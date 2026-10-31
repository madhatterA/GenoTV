#include "video_surface_plugin.h"

#include <dxgi1_6.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include <string>

namespace video_surface {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr wchar_t kClass[] = L"VpVideoSurface";
// DXGI reports SDR white as 80 nits; headroom is the panel peak over that.
constexpr double kSdrWhiteNits = 80.0;

// libmpv is already loaded by media_kit; resolve the few entry points we need.
struct Mpv {
  using SetProperty = int (*)(void*, const char*, const char*);
  using GetProperty = char* (*)(void*, const char*);
  using Free = void (*)(void*);
  SetProperty set = nullptr;
  GetProperty get = nullptr;
  Free free = nullptr;

  static const Mpv& Get() {
    static const Mpv mpv = [] {
      Mpv m;
      HMODULE lib = GetModuleHandleW(L"libmpv-2.dll");
      if (!lib) lib = LoadLibraryW(L"libmpv-2.dll");
      if (lib) {
        m.set = reinterpret_cast<SetProperty>(GetProcAddress(lib, "mpv_set_property_string"));
        m.get = reinterpret_cast<GetProperty>(GetProcAddress(lib, "mpv_get_property_string"));
        m.free = reinterpret_cast<Free>(GetProcAddress(lib, "mpv_free"));
      }
      return m;
    }();
    return mpv;
  }
  bool ok() const { return set && get && free; }
};

std::string Set(void* mpv, const char* name, const std::string& value) {
  const int code = Mpv::Get().set(mpv, name, value.c_str());
  return code < 0 ? std::string(name) + "=" + value + " failed (" + std::to_string(code) + ")"
                  : std::string();
}

std::string Get(void* mpv, const char* name) {
  char* raw = Mpv::Get().get(mpv, name);
  if (!raw) return "";
  std::string value(raw);
  Mpv::Get().free(raw);
  return value;
}

LRESULT CALLBACK SurfaceProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void RegisterClassOnce() {
  static const bool registered = [] {
    WNDCLASSW wc{};
    wc.lpfnWndProc = SurfaceProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClass;
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    return RegisterClassW(&wc) != 0;
  }();
  (void)registered;
}

// Peak/headroom of the monitor under `window`: > 1 only while Windows HDR is on for it.
bool DisplayHdr(HWND window, double* headroom) {
  *headroom = 1.0;
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return false;
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT a = 0; factory->EnumAdapters1(a, &adapter) == S_OK; ++a, adapter.Reset()) {
    ComPtr<IDXGIOutput> output;
    for (UINT o = 0; adapter->EnumOutputs(o, &output) == S_OK; ++o, output.Reset()) {
      ComPtr<IDXGIOutput6> output6;
      DXGI_OUTPUT_DESC1 desc{};
      if (FAILED(output.As(&output6)) || FAILED(output6->GetDesc1(&desc))) continue;
      if (desc.Monitor != monitor) continue;
      if (desc.ColorSpace != DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020) return false;
      *headroom = desc.MaxLuminance / kSdrWhiteNits;
      return *headroom > 1.0;
    }
  }
  return false;
}

// PQ swapchain only when both the source and the display are HDR; otherwise mpv tone-maps.
std::string ApplyColor(Instance& inst) {
  if (!inst.pq_output) return "";
  return Set(inst.mpv, "target-colorspace-hint", inst.hdr_display && inst.hdr_source ? "yes" : "no");
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

int64_t Int(const EncodableMap& map, const char* key, int64_t fallback = -1) {
  const auto* v = Find(map, key);
  if (!v) return fallback;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* l = std::get_if<int64_t>(v)) return *l;
  return fallback;
}

}  // namespace

void VideoSurfacePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<VideoSurfacePlugin>(registrar));
}

VideoSurfacePlugin::VideoSurfacePlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "video_surface", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
  delegate_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
        switch (message) {
          case WM_DISPLAYCHANGE:
          case WM_DPICHANGED:
          case WM_SETTINGCHANGE:
          case WM_EXITSIZEMOVE:
          case WM_MOVE:
            RefreshScreens();
            break;
        }
        return std::nullopt;
      });
}

VideoSurfacePlugin::~VideoSurfacePlugin() {
  registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
  for (auto& [id, inst] : instances_) DestroyWindow(inst.hwnd);
}

EncodableMap VideoSurfacePlugin::Screen(int id, Instance& inst) {
  // Only a PQ-capable output can show HDR; otherwise mpv tone-maps and the display counts as SDR.
  const double usable = inst.pq_output && inst.hdr_display ? inst.headroom : 1.0;
  return {{EncodableValue("id"), EncodableValue(id)},
          {EncodableValue("edr"), EncodableValue(usable)},
          {EncodableValue("potential"), EncodableValue(inst.pq_output ? inst.headroom : 1.0)},
          {EncodableValue("headroom"), EncodableValue(usable)},
          {EncodableValue("displayHdr"), EncodableValue(inst.hdr_display)},
          {EncodableValue("pqOutput"), EncodableValue(inst.pq_output)}};
}

// Window moved to another monitor (HDR <-> SDR) or Windows HDR toggled: re-read, re-apply, tell Dart.
void VideoSurfacePlugin::RefreshScreens() {
  for (auto& [id, inst] : instances_) {
    double headroom = 1.0;
    const bool hdr = DisplayHdr(inst.hwnd, &headroom);
    if (hdr == inst.hdr_display && headroom == inst.headroom) continue;
    inst.hdr_display = hdr;
    inst.headroom = headroom;
    const std::string error = ApplyColor(inst);
    if (!error.empty()) {
      channel_->InvokeMethod("failed", std::make_unique<EncodableValue>(EncodableMap{
                                           {EncodableValue("id"), EncodableValue(id)},
                                           {EncodableValue("message"), EncodableValue(error)}}));
      continue;
    }
    channel_->InvokeMethod("screen", std::make_unique<EncodableValue>(Screen(id, inst)));
  }
}

void VideoSurfacePlugin::Handle(const flutter::MethodCall<EncodableValue>& call,
                                std::unique_ptr<Result> result) {
  static const EncodableMap none;
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const EncodableMap& a = args ? *args : none;
  const std::string& method = call.method_name();

  if (method == "create") {
    const int64_t handle = Int(a, "handle");
    if (handle <= 0) return result->Error("bad_args", "handle required");
    if (!Mpv::Get().ok()) return result->Error("create_failed", "libmpv-2.dll entry points not found");
    HWND flutter_view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
    HWND top = flutter_view ? GetAncestor(flutter_view, GA_ROOT) : nullptr;
    if (!top) return result->Error("create_failed", "no Flutter top-level window");
    RegisterClassOnce();
    // Flutter paints this exact colour over the video rect; the key makes it see-through.
    SetWindowLongPtrW(flutter_view, GWL_EXSTYLE, GetWindowLongPtrW(flutter_view, GWL_EXSTYLE) | WS_EX_LAYERED);
    SetLayeredWindowAttributes(flutter_view, RGB(1, 2, 3), 0, LWA_COLORKEY);
    // Hidden and tiny until Dart reports the video rect.
    HWND hwnd = CreateWindowExW(0, kClass, L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0,
                                1, 1, top, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!hwnd) return result->Error("create_failed", "CreateWindowEx failed");
    Instance inst;
    inst.hwnd = hwnd;
    inst.mpv = reinterpret_cast<void*>(static_cast<intptr_t>(handle));
    inst.hdr_display = DisplayHdr(top, &inst.headroom);
    // Zero-copy d3d11va: decoded frames stay on the GPU and go straight to the swapchain.
    // Preferred: libplacebo + Direct3D 11 (PQ swapchain for HDR10). A libmpv built without
    // them rejects `gpu-api=d3d11`; then it renders through its own ANGLE (D3D11 flip) context.
    const std::string wid = std::to_string(reinterpret_cast<intptr_t>(hwnd));
    std::string error = Set(inst.mpv, "gpu-api", "d3d11");
    if (error.empty()) {
      inst.pq_output = true;
      for (const auto& [name, value] :
           {std::pair<const char*, std::string>{"gpu-context", "d3d11"},
            {"vo", "gpu-next"},
            {"hwdec", "d3d11va"},
            {"wid", wid},
            {"vid", "auto"}}) {
        error = Set(inst.mpv, name, value);
        if (!error.empty()) break;
      }
    } else {
      for (const auto& [name, value] :
           {std::pair<const char*, std::string>{"gpu-api", "opengl"},
            {"gpu-context", "angle"},
            {"vo", "gpu"},
            {"hwdec", "d3d11va-copy"},
            {"wid", wid},
            {"vid", "auto"}}) {
        error = Set(inst.mpv, name, value);
        if (!error.empty()) break;
      }
    }
    if (error.empty()) error = ApplyColor(inst);
    if (!error.empty()) {
      DestroyWindow(hwnd);
      return result->Error("create_failed", error);
    }
    const int id = next_id_++;
    auto reply = Screen(id, inst);
    reply[EncodableValue("hwnd")] = EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd)));
    instances_[id] = inst;
    return result->Success(EncodableValue(reply));
  }
  if (method == "screenEdr") {
    double headroom = 1.0;
    HWND view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
    const bool hdr = DisplayHdr(view, &headroom);
    return result->Success(EncodableValue(EncodableMap{
        {EncodableValue("edr"), EncodableValue(hdr ? headroom : 1.0)},
        {EncodableValue("potential"), EncodableValue(headroom)}}));
  }
  if (method == "counters") {
    int windows = 0;
    HWND view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
    if (HWND top = view ? GetAncestor(view, GA_ROOT) : nullptr) {
      EnumChildWindows(
          top,
          [](HWND child, LPARAM count) -> BOOL {
            wchar_t name[32] = {};
            GetClassNameW(child, name, 32);
            if (wcscmp(name, kClass) == 0) ++*reinterpret_cast<int*>(count);
            return TRUE;
          },
          reinterpret_cast<LPARAM>(&windows));
    }
    return result->Success(EncodableValue(EncodableMap{
        {EncodableValue("instances"), EncodableValue(static_cast<int>(instances_.size()))},
        {EncodableValue("windows"), EncodableValue(windows)}}));
  }

  const int id = static_cast<int>(Int(a, "id"));
  auto it = instances_.find(id);
  if (it == instances_.end()) return result->Error("unknown_surface", "no such surface");
  Instance& inst = it->second;

  if (method == "rect") {
    // Physical pixels in the top-level client area (where Flutter's view sits).
    const bool visible = Int(a, "visible", 1) != 0;
    inst.req[0] = static_cast<int>(Int(a, "x", 0));
    inst.req[1] = static_cast<int>(Int(a, "y", 0));
    inst.req[2] = static_cast<int>(Int(a, "w", 1));
    inst.req[3] = static_cast<int>(Int(a, "h", 1));
    SetWindowPos(inst.hwnd, HWND_BOTTOM, static_cast<int>(Int(a, "x", 0)),
                 static_cast<int>(Int(a, "y", 0)), static_cast<int>(Int(a, "w", 1)),
                 static_cast<int>(Int(a, "h", 1)),
                 SWP_NOACTIVATE | (visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW));
    return result->Success();
  }
  if (method == "geometry") {
    // Where the child window really is (parent client pixels) vs. what Dart asked for, plus the
    // window DPI and the monitor list, for the monitor/DPI proof.
    HWND view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
    HWND top = view ? GetAncestor(view, GA_ROOT) : nullptr;
    RECT child{}, client{};
    GetWindowRect(inst.hwnd, &child);
    MapWindowPoints(nullptr, GetParent(inst.hwnd), reinterpret_cast<POINT*>(&child), 2);
    GetClientRect(GetParent(inst.hwnd), &client);
    EncodableList monitors;
    EnumDisplayMonitors(
        nullptr, nullptr,
        [](HMONITOR m, HDC, LPRECT r, LPARAM list) -> BOOL {
          MONITORINFO info{sizeof(info)};
          GetMonitorInfoW(m, &info);
          reinterpret_cast<EncodableList*>(list)->push_back(EncodableValue(EncodableMap{
              {EncodableValue("rect"),
               EncodableValue(EncodableList{EncodableValue(static_cast<int>(r->left)),
                                            EncodableValue(static_cast<int>(r->top)),
                                            EncodableValue(static_cast<int>(r->right)),
                                            EncodableValue(static_cast<int>(r->bottom))})},
              {EncodableValue("primary"),
               EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0)}}));
          return TRUE;
        },
        reinterpret_cast<LPARAM>(&monitors));
    auto rect = [](int a, int b, int c, int d) {
      return EncodableValue(EncodableList{EncodableValue(a), EncodableValue(b), EncodableValue(c),
                                          EncodableValue(d)});
    };
    return result->Success(EncodableValue(EncodableMap{
        {EncodableValue("actual"), rect(child.left, child.top, child.right - child.left,
                                        child.bottom - child.top)},
        {EncodableValue("requested"), rect(inst.req[0], inst.req[1], inst.req[2], inst.req[3])},
        {EncodableValue("client"), rect(0, 0, client.right, client.bottom)},
        {EncodableValue("visible"), EncodableValue(IsWindowVisible(inst.hwnd) != 0)},
        {EncodableValue("dpi"), EncodableValue(static_cast<int>(top ? GetDpiForWindow(top) : 0))},
        {EncodableValue("monitors"), EncodableValue(monitors)}}));
  }
  if (method == "source") {
    const auto* hdr = Find(a, "hdr");
    const bool* flag = hdr ? std::get_if<bool>(hdr) : nullptr;
    if (!flag) return result->Error("bad_args", "id and hdr required");
    inst.hdr_source = *flag;
    const std::string error = ApplyColor(inst);
    if (!error.empty()) return result->Error("source_failed", error);
    return result->Success();
  }
  if (method == "probe") {
    auto reply = Screen(id, inst);
    reply[EncodableValue("hwnd")] = EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(inst.hwnd)));
    for (const char* name : {"current-vo", "hwdec-current", "gpu-api", "target-colorspace-hint",
                             "d3d11-output-format", "d3d11-output-csp", "video-out-params/gamma"}) {
      reply[EncodableValue(name)] = EncodableValue(Get(inst.mpv, name));
    }
    const std::string frames = Get(inst.mpv, "estimated-frame-number");
    reply[EncodableValue("frames")] = EncodableValue(frames.empty() ? 0 : std::atoi(frames.c_str()));
    return result->Success(EncodableValue(reply));
  }
  if (method == "dispose") {
    // Tear the VO down while the window still exists, then hand the player back as media_kit
    // expects it (vo=libmpv) so a texture fallback can attach.
    Set(inst.mpv, "vid", "no");
    Set(inst.mpv, "wid", "0");
    Set(inst.mpv, "vo", "libmpv");

    DestroyWindow(inst.hwnd);
    instances_.erase(it);
    return result->Success();
  }
  return result->NotImplemented();
}

}  // namespace video_surface
