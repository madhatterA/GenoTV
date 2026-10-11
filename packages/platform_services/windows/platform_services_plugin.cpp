#include "platform_services_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <winternl.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <audioclient.h>
#include <propsys.h>
#include <d3d11.h>
#include <d3d11_1.h>
#include <wrl/client.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <optional>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>

#include <cmath>
#include <memory>
#include <string>
#include <vector>
#include <algorithm>

#include "windows_audio.h"

namespace platform_services {

namespace {
constexpr UINT kAudioRouteMessage = WM_APP + 1;
constexpr UINT kMediaCommandMessage = WM_APP + 2;

class SinkStreamHandler final
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit SinkStreamHandler(PlatformServicesPlugin* plugin) : plugin_(plugin) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) override {
    plugin_->SetEventSink(std::move(sink));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    plugin_->SetEventSink(nullptr);
    return nullptr;
  }

 private:
  PlatformServicesPlugin* plugin_;
};

LRESULT CALLBACK AudioWindowProc(HWND window, UINT message, WPARAM w, LPARAM l) {
  if (message == kAudioRouteMessage) {
    auto* plugin = reinterpret_cast<PlatformServicesPlugin*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (plugin != nullptr) plugin->OnAudioRouteChanged();
    return 0;
  }
  if (message == kMediaCommandMessage) {
    auto* plugin = reinterpret_cast<PlatformServicesPlugin*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (plugin != nullptr) plugin->OnMediaCommands();
    return 0;
  }
  return DefWindowProcW(window, message, w, l);
}

std::string WindowsVersion() {
  RTL_OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  using RtlGetVersionFn = LONG(WINAPI *)(PRTL_OSVERSIONINFOW);
  auto get_version = reinterpret_cast<RtlGetVersionFn>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  if (get_version == nullptr || get_version(&info) != 0) return "Windows unknown";
  return "Windows " + std::to_string(info.dwMajorVersion) + "." +
         std::to_string(info.dwMinorVersion) + "." +
         std::to_string(info.dwBuildNumber);
}
flutter::EncodableMap Unsupported(const std::string& reason) {
  flutter::EncodableMap value;
  value[flutter::EncodableValue("supported")] = flutter::EncodableValue(false);
  value[flutter::EncodableValue("reason")] = flutter::EncodableValue(reason);
  return value;
}

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string output(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, output.data(), size, nullptr, nullptr);
  return output;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring output(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), output.data(), size);
  return output;
}

std::string DeviceName(IMMDevice* device) {
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr) return "unknown";
  PROPVARIANT value;
  PropVariantInit(&value);
  std::string name = "unknown";
  if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &value)) && value.vt == VT_LPWSTR) {
    name = WideToUtf8(value.pwszVal);
  }
  PropVariantClear(&value);
  store->Release();
  return name;
}

std::wstring PendingModePath() {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  if (length == 0 || length >= MAX_PATH - 40) return L"platform_services_display_mode.bin";
  std::wstring path(buffer, length);
  CreateDirectoryW((path + L"\\platform_services").c_str(), nullptr);
  return path + L"\\platform_services\\display_mode.bin";
}

// Kodi 4.4 (WinSystemWin32.cpp UpdateResolutions): Windows reports 23.976 Hz as
// 23, 59.94 as 59 ...; (f+1)%24==0 || (f+1)%30==0 means (f+1)/1.001.
double KodiRefreshHz(DWORD frequency) {
  const int f = static_cast<int>(frequency);
  return ((f + 1) % 24 == 0 || (f + 1) % 30 == 0) ? (f + 1) / 1.001 : f;
}

bool Progressive(const DEVMODEW& mode) { return (mode.dmDisplayFlags & DM_INTERLACED) == 0; }

// Kodi 4.1/4.4: only 32 bpp modes, one entry per size and rate, same interlace
// mode as the current one (the desktop is progressive).
std::vector<DEVMODEW> ListedModes(const wchar_t* device) {
  std::vector<DEVMODEW> modes;
  for (DWORD index = 0;; ++index) {
    DEVMODEW mode{};
    mode.dmSize = sizeof(mode);
    if (!EnumDisplaySettingsW(device, index, &mode)) break;
    if (mode.dmBitsPerPel != 32 || !Progressive(mode)) continue;
    bool duplicate = false;
    for (const auto& known : modes)
      duplicate = duplicate || (known.dmPelsWidth == mode.dmPelsWidth && known.dmPelsHeight == mode.dmPelsHeight &&
                                known.dmDisplayFrequency == mode.dmDisplayFrequency);
    if (!duplicate) modes.push_back(mode);
  }
  return modes;
}

// Kodi 4.1 GetConnectedDisplays: attached desktop adapters (no mirroring
// drivers), EDID friendly names (QueryDisplayConfig), " #N" to keep them unique.
struct Monitor {
  std::string name;
  std::wstring device;
  bool primary = false;
  RECT rect{};
};

std::vector<Monitor> ConnectedMonitors() {
  std::vector<DISPLAYCONFIG_PATH_INFO> paths;
  UINT32 pathCount = 0;
  UINT32 modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) == ERROR_SUCCESS) {
    paths.resize(pathCount);
    std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount, modes.data(), nullptr) != ERROR_SUCCESS)
      paths.clear();
    paths.resize(pathCount);
  }
  auto friendly = [&paths](const wchar_t* gdiName) -> std::wstring {
    for (const auto& path : paths) {
      DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
      source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
      source.header.size = sizeof(source);
      source.header.adapterId = path.sourceInfo.adapterId;
      source.header.id = path.sourceInfo.id;
      if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS || wcscmp(source.viewGdiDeviceName, gdiName) != 0) continue;
      DISPLAYCONFIG_TARGET_DEVICE_NAME target{};
      target.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
      target.header.size = sizeof(target);
      target.header.adapterId = path.targetInfo.adapterId;
      target.header.id = path.targetInfo.id;
      if (DisplayConfigGetDeviceInfo(&target.header) == ERROR_SUCCESS && target.flags.friendlyNameFromEdid &&
          target.monitorFriendlyDeviceName[0] != 0)
        return target.monitorFriendlyDeviceName;
    }
    return L"";
  };
  std::vector<Monitor> monitors;
  for (DWORD i = 0;; ++i) {
    DISPLAY_DEVICEW adapter{};
    adapter.cb = sizeof(adapter);
    if (!EnumDisplayDevicesW(nullptr, i, &adapter, 0)) break;
    if ((adapter.StateFlags & DISPLAY_DEVICE_MIRRORING_DRIVER) || !(adapter.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) continue;
    std::wstring label = adapter.DeviceString;
    for (DWORD j = 0;; ++j) {
      DISPLAY_DEVICEW monitor{};
      monitor.cb = sizeof(monitor);
      if (!EnumDisplayDevicesW(adapter.DeviceName, j, &monitor, 0)) break;
      if (monitor.StateFlags & (DISPLAY_DEVICE_ACTIVE | DISPLAY_DEVICE_ATTACHED)) {
        label = monitor.DeviceString;
        break;
      }
    }
    if (const auto name = friendly(adapter.DeviceName); !name.empty()) label = name;
    DEVMODEW mode{};
    mode.dmSize = sizeof(mode);
    if (!EnumDisplaySettingsExW(adapter.DeviceName, ENUM_CURRENT_SETTINGS, &mode, 0)) continue;
    Monitor entry;
    entry.name = WideToUtf8(label.c_str());
    entry.device = adapter.DeviceName;
    entry.primary = (adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
    entry.rect = {mode.dmPosition.x, mode.dmPosition.y, mode.dmPosition.x + static_cast<LONG>(mode.dmPelsWidth),
                  mode.dmPosition.y + static_cast<LONG>(mode.dmPelsHeight)};
    monitors.push_back(entry);
  }
  for (size_t i = 0; i < monitors.size(); ++i) {
    int same = 0;
    for (size_t k = 0; k < i; ++k) same += monitors[k].name.rfind(monitors[i].name, 0) == 0 ? 1 : 0;
    if (same > 0) monitors[i].name += " #" + std::to_string(same + 1);
  }
  return monitors;
}

// Kodi 4.7 CDisplayUtilsWin32::GetDisplayHDRStatus. HDR-capable and HDR-on.
void DisplayHdrStatus(bool* supported, bool* enabled) {
  *supported = *enabled = false;
  using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  OSVERSIONINFOW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  if (const auto rtl = reinterpret_cast<RtlGetVersionFn>(
          GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion")))
    rtl(&version);
  const bool win11_24h2 = version.dwBuildNumber >= 26100;
  UINT32 pathCount = 0;
  UINT32 modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) return;
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount, modes.data(), nullptr) != ERROR_SUCCESS) return;
  for (UINT32 index = 0; index < pathCount; ++index) {
    if (win11_24h2) {
      // SDK 10.0.26100 DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 (type 15), as Kodi's SDK_26100.h.
      struct ColorInfo2 {
        DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        UINT32 flags;  // bit 4 highDynamicRangeSupported
        UINT32 colorEncoding;
        UINT32 bitsPerColorChannel;
        UINT32 activeColorMode;  // 2 = HDR
      } info{};
      info.header.type = static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(15);
      info.header.size = sizeof(info);
      info.header.adapterId = paths[index].targetInfo.adapterId;
      info.header.id = paths[index].targetInfo.id;
      if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
        *supported = *supported || ((info.flags >> 4) & 1) != 0;
        *enabled = *enabled || info.activeColorMode == 2;
      }
    } else {
      DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info{};
      info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
      info.header.size = sizeof(info);
      info.header.adapterId = paths[index].targetInfo.adapterId;
      info.header.id = paths[index].targetInfo.id;
      if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
        // SDR+ACM on Win11 22H2 reports supported=1 with wideColorEnforced=1: not HDR.
        const bool capable = info.advancedColorSupported && !info.wideColorEnforced;
        *supported = *supported || capable;
        *enabled = *enabled || (capable && info.advancedColorEnabled);
      }
    }
  }
}

// Kodi 2.1/2.2: DXVA is available when the GPU's D3D11 video device reports a
// decoder profile (ID3D11VideoDevice::GetVideoDecoderProfile, DXVA.cpp table).
std::vector<std::string> HardwareDecoders() {
  std::vector<std::string> decoders;
  Microsoft::WRL::ComPtr<ID3D11Device> device;
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_VIDEO_SUPPORT, levels,
                               static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, &device, nullptr, nullptr)))
    return decoders;
  Microsoft::WRL::ComPtr<ID3D11VideoDevice> video;
  if (FAILED(device.As(&video))) return decoders;
  bool h264 = false;
  bool hevc = false;
  for (UINT index = 0; index < video->GetVideoDecoderProfileCount(); ++index) {
    GUID profile{};
    if (FAILED(video->GetVideoDecoderProfile(index, &profile))) continue;
    h264 = h264 || profile == D3D11_DECODER_PROFILE_H264_VLD_NOFGT || profile == D3D11_DECODER_PROFILE_H264_VLD_FGT;
    hevc = hevc || profile == D3D11_DECODER_PROFILE_HEVC_VLD_MAIN || profile == D3D11_DECODER_PROFILE_HEVC_VLD_MAIN10;
  }
  if (h264) decoders.emplace_back("h264");
  if (hevc) decoders.emplace_back("hevc");
  return decoders;
}
}  // namespace

// static
void PlatformServicesPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "platform_services",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PlatformServicesPlugin>();
  plugin->SetView(registrar->GetView());
  plugin->SetRegistrar(registrar);
  auto* plugin_pointer_for_events = plugin.get();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  flutter::EventChannel<flutter::EncodableValue> events(
      registrar->messenger(), "platform_services/events",
      &flutter::StandardMethodCodec::GetInstance());
  events.SetStreamHandler(std::make_unique<SinkStreamHandler>(plugin_pointer_for_events));

  registrar->AddPlugin(std::move(plugin));
}

PlatformServicesPlugin::PlatformServicesPlugin() {
  RestorePendingDisplayMode();
  // MMDevice notifications arrive on its own thread; a message-only window
  // hands them to this (platform) thread, the only one allowed to use the sink.
  WNDCLASSW wc{};
  wc.lpfnWndProc = AudioWindowProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"PlatformServicesAudioRoute";
  RegisterClassW(&wc);
  window_ = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
  if (window_ != nullptr) {
    SetWindowLongPtrW(window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    HWND target = window_;
    watcher_ = std::make_unique<audio::RouteWatcher>([target] { PostMessageW(target, kAudioRouteMessage, 0, 0); });
  }
}

void PlatformServicesPlugin::SetView(flutter::FlutterView* view) { view_ = view; }

void PlatformServicesPlugin::SetEventSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  sink_ = std::move(sink);
}

void PlatformServicesPlugin::OnAudioRouteChanged() {
  endpoints_valid_ = false;
  if (sink_ == nullptr) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] = flutter::EncodableValue("audioRouteChanged");
  sink_->Success(flutter::EncodableValue(event));
}

// Kodi WinEventsWin32 WM_DISPLAYCHANGE -> UpdateResolutions: the top-level
// window (not the message-only one) receives the OS display broadcast.
void PlatformServicesPlugin::SetRegistrar(flutter::PluginRegistrarWindows* registrar) {
  registrar_ = registrar;
  display_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND, UINT message, WPARAM, LPARAM l) -> std::optional<LRESULT> {
        if (message == WM_DISPLAYCHANGE) OnDisplayChanged();
        return std::nullopt;  // never consume: Flutter still handles it
      });
}

void PlatformServicesPlugin::OnDisplayChanged() {
  // Re-reads monitors, drops a vanished selection back to Default, and tells
  // Dart so the monitor choices and the mode list refresh live.
  auto event = DisplayScreens(nullptr);
  if (sink_ == nullptr) return;
  event[flutter::EncodableValue("event")] = flutter::EncodableValue("displayScreensChanged");
  sink_->Success(flutter::EncodableValue(event));
}

void PlatformServicesPlugin::EmitMediaCommand(const media::Command& command) {
  if (sink_ == nullptr) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] = flutter::EncodableValue("mediaCommand");
  event[flutter::EncodableValue("command")] = flutter::EncodableValue(command.name);
  if (command.position_seconds)
    event[flutter::EncodableValue("positionSeconds")] = flutter::EncodableValue(*command.position_seconds);
  sink_->Success(flutter::EncodableValue(event));
}

void PlatformServicesPlugin::OnMediaCommands() {
  if (media_ == nullptr) return;
  for (const auto& command : media_->TakeCommands()) EmitMediaCommand(command);
}

flutter::EncodableMap PlatformServicesPlugin::UpdateMediaSession(const flutter::EncodableValue* arguments) {
  const auto* map = arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return Unsupported("media session payload is required");
  const auto text = [map](const char* key) -> std::string {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it == map->end()) return {};
    const auto* value = std::get_if<std::string>(&it->second);
    return value == nullptr ? std::string() : *value;
  };
  const auto number = [map](const char* key) -> double {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it == map->end()) return -1;
    if (const auto* value = std::get_if<double>(&it->second)) return *value;
    if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
    return -1;
  };
  media::Info info;
  info.title = Utf8ToWide(text("title"));
  info.subtitle = Utf8ToWide(text("subtitle"));
  info.duration_seconds = number("durationSeconds");
  info.position_seconds = number("positionSeconds");
  const auto playing = map->find(flutter::EncodableValue("playing"));
  info.playing = playing != map->end() && std::get_if<bool>(&playing->second) != nullptr &&
                 *std::get_if<bool>(&playing->second);
  std::string error;
  if (media_ == nullptr) {
    const HWND child = registrar_ == nullptr || registrar_->GetView() == nullptr
                           ? nullptr
                           : registrar_->GetView()->GetNativeWindow();
    const HWND top = child == nullptr ? nullptr : GetAncestor(child, GA_ROOT);
    if (top == nullptr || window_ == nullptr) return Unsupported("no top-level window for the media session");
    const HWND target = window_;
    media_ = media::Session::Create(
        top, [target] { PostMessageW(target, kMediaCommandMessage, 0, 0); }, &error);
    if (media_ == nullptr) return Unsupported(error);
  }
  if (!media_->Update(info, &error)) return Unsupported(error);
  flutter::EncodableMap value;
  value[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  return value;
}

flutter::EncodableMap PlatformServicesPlugin::ClearMediaSession() {
  std::string error;
  if (media_ != nullptr && !media_->Clear(&error)) return Unsupported(error);
  flutter::EncodableMap value;
  value[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  return value;
}

PlatformServicesPlugin::~PlatformServicesPlugin() {
  if (registrar_ != nullptr && display_proc_id_ != 0)
    registrar_->UnregisterTopLevelWindowProcDelegate(display_proc_id_);
  media_.reset();
  watcher_.reset();
  if (window_ != nullptr) DestroyWindow(window_);
  if (keep_awake_) SetThreadExecutionState(ES_CONTINUOUS);
}

flutter::EncodableMap PlatformServicesPlugin::EnumerateDisplayModes() const {
  flutter::EncodableList modes;
  DEVMODEW current{};
  current.dmSize = sizeof(current);
  EnumDisplaySettingsW(Device(), ENUM_CURRENT_SETTINGS, &current);
  for (const auto& mode : ListedModes(Device())) {
    flutter::EncodableMap value;
    value[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(mode.dmPelsWidth));
    value[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(mode.dmPelsHeight));
    value[flutter::EncodableValue("refreshHz")] = flutter::EncodableValue(KodiRefreshHz(mode.dmDisplayFrequency));
    value[flutter::EncodableValue("isCurrent")] = flutter::EncodableValue(
        mode.dmPelsWidth == current.dmPelsWidth && mode.dmPelsHeight == current.dmPelsHeight &&
        mode.dmDisplayFrequency == current.dmDisplayFrequency);
    modes.emplace_back(value);
  }
  if (modes.empty()) return Unsupported("EnumDisplaySettings returned no 32 bpp progressive display modes");
  flutter::EncodableMap result;
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  result[flutter::EncodableValue("modes")] = flutter::EncodableValue(modes);
  return result;
}

flutter::EncodableMap PlatformServicesPlugin::ApplyDisplayMode(const flutter::EncodableValue* arguments) {
  const auto* values = arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments);
  if (values == nullptr) return Unsupported("display.apply requires a mode map");
  auto number = [&values](const char* key) -> double {
    const auto found = values->find(flutter::EncodableValue(key));
    if (found == values->end()) return 0;
    if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
    if (const auto* value = std::get_if<int64_t>(&found->second)) return static_cast<double>(*value);
    if (const auto* value = std::get_if<double>(&found->second)) return *value;
    return 0;
  };
  const DWORD width = static_cast<DWORD>(number("width"));
  const DWORD height = static_cast<DWORD>(number("height"));
  const double refresh = number("refreshHz");
  if (width == 0 || height == 0 || refresh <= 0) return Unsupported("display.apply requires width, height, and refreshHz");
  DEVMODEW target{};
  bool found = false;
  for (const auto& mode : ListedModes(Device())) {
    if (mode.dmPelsWidth == width && mode.dmPelsHeight == height &&
        std::abs(KodiRefreshHz(mode.dmDisplayFrequency) - refresh) < 0.01) {
      target = mode;
      found = true;
      break;
    }
  }
  if (!found) return Unsupported("requested display mode was not enumerated");
  DEVMODEW current{};
  current.dmSize = sizeof(current);
  if (!EnumDisplaySettingsW(Device(), ENUM_CURRENT_SETTINGS, &current)) return Unsupported("current display mode unavailable");
  if (current.dmPelsWidth == target.dmPelsWidth && current.dmPelsHeight == target.dmPelsHeight &&
      current.dmDisplayFrequency == target.dmDisplayFrequency)
    return flutter::EncodableMap{{flutter::EncodableValue("supported"), flutter::EncodableValue(true)}};
  // A second switch must still restore the mode the user started from.
  const std::wstring path = PendingModePath();
  if (!has_previous_display_mode_) {
    previous_display_mode_ = current;
    previous_device_ = selected_device_;
    has_previous_display_mode_ = true;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      DWORD written = 0;
      WriteFile(file, &current, sizeof(current), &written, nullptr);
      wchar_t name[CCHDEVICENAME] = {};
      wcsncpy_s(name, selected_device_.c_str(), _TRUNCATE);
      WriteFile(file, name, sizeof(name), &written, nullptr);
      CloseHandle(file);
    }
  }
  target.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYFLAGS;
  target.dmDisplayFlags = 0;
  LONG status = DISP_CHANGE_FAILED;
  // Kodi 4.3 "Windows 8 refresh rate workaround": exactly 24, 48 and 60 Hz go
  // through the registry (written without applying), then restore the old values.
  if (target.dmDisplayFrequency == 24 || target.dmDisplayFrequency == 48 || target.dmDisplayFrequency == 60) {
    DEVMODEW registry{};
    registry.dmSize = sizeof(registry);
    if (EnumDisplaySettingsW(Device(), ENUM_REGISTRY_SETTINGS, &registry) &&
        ChangeDisplaySettingsExW(Device(), &target, nullptr, CDS_UPDATEREGISTRY | CDS_NORESET, nullptr) == DISP_CHANGE_SUCCESSFUL) {
      status = ChangeDisplaySettingsExW(Device(), nullptr, nullptr, CDS_FULLSCREEN, nullptr);
      registry.dmFields |= DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
      ChangeDisplaySettingsExW(Device(), &registry, nullptr, CDS_UPDATEREGISTRY | CDS_NORESET, nullptr);
    }
  }
  if (status != DISP_CHANGE_SUCCESSFUL) status = ChangeDisplaySettingsExW(Device(), &target, nullptr, CDS_FULLSCREEN, nullptr);
  if (status != DISP_CHANGE_SUCCESSFUL) {
    has_previous_display_mode_ = false;
    DeleteFileW(path.c_str());
    return Unsupported("ChangeDisplaySettingsEx failed with code " + std::to_string(status));
  }
  flutter::EncodableMap result;
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  return result;
}

// Kodi 4.1: "Default" (= primary monitor, key "") plus every attached monitor.
// An unknown or vanished selection falls back to Default.
flutter::EncodableMap PlatformServicesPlugin::DisplayScreens(const flutter::EncodableValue* select) {
  const auto monitors = ConnectedMonitors();
  std::string wanted = selected_monitor_;
  if (select != nullptr)
    if (const auto* values = std::get_if<flutter::EncodableMap>(select))
      if (const auto found = values->find(flutter::EncodableValue("id")); found != values->end())
        if (const auto* id = std::get_if<std::string>(&found->second)) wanted = *id;
  const Monitor* chosen = nullptr;
  for (const auto& monitor : monitors) if (monitor.name == wanted) chosen = &monitor;
  const bool changed = chosen != nullptr && wanted != selected_monitor_;
  selected_monitor_ = chosen != nullptr ? chosen->name : "";
  selected_device_ = chosen != nullptr ? chosen->device : L"";
  if (changed && view_ != nullptr) {
    // Kodi moves the window onto the chosen monitor (CreateNewWindow/SetMonitor).
    if (const HWND window = GetAncestor(view_->GetNativeWindow(), GA_ROOT))
      SetWindowPos(window, nullptr, chosen->rect.left + 40, chosen->rect.top + 40, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
  }
  flutter::EncodableMap choices;
  choices[flutter::EncodableValue("")] = flutter::EncodableValue("Default");
  for (const auto& monitor : monitors) choices[flutter::EncodableValue(monitor.name)] = flutter::EncodableValue(monitor.name);
  flutter::EncodableMap result;
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  result[flutter::EncodableValue("choices")] = flutter::EncodableValue(choices);
  result[flutter::EncodableValue("selected")] = flutter::EncodableValue(selected_monitor_);
  return result;
}

// Kodi 4.2 "fullscreen window" (videoscreen.fakefullscreen, default true): a
// borderless window covering the monitor the window is on; windowed restores
// the saved style and placement. Exclusive DXGI fullscreen is not offered, the
// Flutter engine owns the swap chain (ENGINE_UNSUPPORTED.md).
flutter::EncodableMap PlatformServicesPlugin::SetFullscreen(const flutter::EncodableValue* arguments) {
  flutter::EncodableMap result;
  bool enabled = false;
  if (const auto* map = arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments)) {
    const auto it = map->find(flutter::EncodableValue("enabled"));
    if (it != map->end())
      if (const auto* flag = std::get_if<bool>(&it->second)) enabled = *flag;
  }
  const HWND window = view_ == nullptr ? nullptr : GetAncestor(view_->GetNativeWindow(), GA_ROOT);
  if (window == nullptr) {
    result[flutter::EncodableValue("supported")] = flutter::EncodableValue(false);
    result[flutter::EncodableValue("reason")] = flutter::EncodableValue("No top-level window to switch");
    return result;
  }
  if (enabled && !fullscreen_) {
    MONITORINFO monitor{sizeof(MONITORINFO)};
    windowed_placement_.length = sizeof(WINDOWPLACEMENT);
    if (GetWindowPlacement(window, &windowed_placement_) &&
        GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
      windowed_style_ = GetWindowLong(window, GWL_STYLE);
      SetWindowLong(window, GWL_STYLE, windowed_style_ & ~WS_OVERLAPPEDWINDOW);
      SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                   monitor.rcMonitor.right - monitor.rcMonitor.left,
                   monitor.rcMonitor.bottom - monitor.rcMonitor.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      fullscreen_ = true;
    }
  } else if (!enabled && fullscreen_) {
    SetWindowLong(window, GWL_STYLE, windowed_style_);
    SetWindowPlacement(window, &windowed_placement_);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = false;
  }
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  result[flutter::EncodableValue("fullscreen")] = flutter::EncodableValue(fullscreen_);
  return result;
}

flutter::EncodableMap PlatformServicesPlugin::RestoreDisplayMode() {
  const std::wstring path = PendingModePath();
  if (!has_previous_display_mode_) {
    DeleteFileW(path.c_str());
    return flutter::EncodableMap{{flutter::EncodableValue("supported"), flutter::EncodableValue(true)}};
  }
  const LONG status = ChangeDisplaySettingsExW(previous_device_.empty() ? nullptr : previous_device_.c_str(), &previous_display_mode_, nullptr, CDS_FULLSCREEN, nullptr);
  if (status != DISP_CHANGE_SUCCESSFUL) return Unsupported("ChangeDisplaySettingsEx restore failed with code " + std::to_string(status));
  has_previous_display_mode_ = false;
  DeleteFileW(path.c_str());
  return flutter::EncodableMap{{flutter::EncodableValue("supported"), flutter::EncodableValue(true)}};
}

const std::vector<audio::Endpoint>& PlatformServicesPlugin::Endpoints() {
  if (!endpoints_valid_) {
    audio_log_.clear();
    audio_error_.clear();
    endpoints_ = audio::ProbeEndpoints(&audio_log_, &audio_error_);
    endpoints_valid_ = audio_error_.empty();
  }
  return endpoints_;
}

namespace {
constexpr char kWasapiPrefix[] = "wasapi/";

std::string StripPrefix(const std::string& id) {
  return id.rfind(kWasapiPrefix, 0) == 0 ? id.substr(sizeof(kWasapiPrefix) - 1) : id;
}

// Kodi ValidateOuputDevice for passthrough (1.1): the requested device if it
// can carry streams, else the default endpoint, else the first that can.
const audio::Endpoint* PassthroughEndpoint(const std::vector<audio::Endpoint>& all, const std::string& requested) {
  auto capable = [](const audio::Endpoint& e) { return e.passthroughType && !e.caps.formats.empty(); };
  for (const auto& e : all) if (e.id == requested && capable(e)) return &e;
  for (const auto& e : all) if (e.isDefault && capable(e)) return &e;
  for (const auto& e : all) if (capable(e)) return &e;
  return nullptr;
}

flutter::EncodableList Strings(const std::vector<std::string>& values) {
  flutter::EncodableList list;
  for (const auto& v : values) list.emplace_back(v);
  return list;
}
}  // namespace

flutter::EncodableMap PlatformServicesPlugin::AudioDevices(const flutter::EncodableValue* arguments) {
  const auto& all = Endpoints();
  if (!audio_error_.empty()) return Unsupported(audio_error_);
  std::string requested, passthroughRequested;
  bool exclusive = false;
  if (const auto* map = arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments)) {
    if (auto it = map->find(flutter::EncodableValue("deviceId")); it != map->end())
      if (const auto* text = std::get_if<std::string>(&it->second)) requested = StripPrefix(*text);
    if (auto it = map->find(flutter::EncodableValue("passthroughDeviceId")); it != map->end())
      if (const auto* text = std::get_if<std::string>(&it->second)) passthroughRequested = StripPrefix(*text);
    if (auto it = map->find(flutter::EncodableValue("exclusive")); it != map->end())
      if (const auto* flag = std::get_if<bool>(&it->second)) exclusive = *flag;
  }
  flutter::EncodableList devices;
  const audio::Endpoint* selected = nullptr;
  for (const auto& e : all) {
    if (e.id == requested || (selected == nullptr && requested.empty() && e.isDefault)) selected = &e;
    flutter::EncodableList rates;
    for (int rate : e.caps.rates) rates.emplace_back(static_cast<int32_t>(rate));
    flutter::EncodableMap value;
    value[flutter::EncodableValue("id")] = flutter::EncodableValue(std::string(kWasapiPrefix) + e.id);
    value[flutter::EncodableValue("name")] = flutter::EncodableValue(e.name);
    value[flutter::EncodableValue("kind")] = flutter::EncodableValue(e.kind);
    value[flutter::EncodableValue("isCurrent")] = flutter::EncodableValue(e.isDefault);
    value[flutter::EncodableValue("supportedSampleRates")] = flutter::EncodableValue(rates);
    devices.emplace_back(value);
  }
  if (selected == nullptr) for (const auto& e : all) if (e.isDefault) selected = &e;
  const auto* pass = PassthroughEndpoint(all, passthroughRequested);
  flutter::EncodableMap result;
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  result[flutter::EncodableValue("os")] = flutter::EncodableValue("windows");
  result[flutter::EncodableValue("devices")] = flutter::EncodableValue(devices);
  if (selected != nullptr) {
    // Exclusive: the driver's probed maximum; shared: the Windows mixer layout.
    result[flutter::EncodableValue("maxOutputChannels")] = flutter::EncodableValue(
        static_cast<int32_t>(exclusive ? selected->caps.maxChannels : selected->mixChannels));
  }
  if (pass != nullptr)
    result[flutter::EncodableValue("passthroughDeviceId")] =
        flutter::EncodableValue(std::string(kWasapiPrefix) + pass->id);
  result[flutter::EncodableValue("diagnostic")] = flutter::EncodableValue("WASAPI endpoints; Kodi exclusive-mode IsFormatSupported probes");
  return result;
}

flutter::EncodableMap PlatformServicesPlugin::NegotiateAudio(const flutter::EncodableValue* arguments) {
  const auto& all = Endpoints();
  flutter::EncodableMap value;
  value[flutter::EncodableValue("passthrough")] = flutter::EncodableValue(false);
  std::string codec, requested;
  if (const auto* map = arguments == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(arguments)) {
    auto text = [&](const char* key) {
      auto it = map->find(flutter::EncodableValue(key));
      const auto* t = it == map->end() ? nullptr : std::get_if<std::string>(&it->second);
      return t == nullptr ? std::string() : *t;
    };
    codec = text("codec");
    requested = StripPrefix(text("deviceId"));
  }
  for (auto& ch : codec) ch = static_cast<char>(::tolower(static_cast<unsigned char>(ch)));
  std::string name = codec == "ac3" ? "ac3" : (codec == "eac3" || codec == "eac3-joc" || codec == "eac3_joc") ? "eac3"
                     : codec == "dts" ? "dts" : (codec == "dts-hd" || codec == "dtshd") ? "dtsHd"
                     : codec == "truehd" ? "trueHd" : "";
  const auto* device = PassthroughEndpoint(all, requested);
  value[flutter::EncodableValue("deviceId")] = flutter::EncodableValue(
      device != nullptr ? std::string(kWasapiPrefix) + device->id : std::string("auto"));
  if (!audio_error_.empty()) {
    value[flutter::EncodableValue("fallbackReason")] = flutter::EncodableValue(audio_error_);
  } else if (name.empty()) {
    value[flutter::EncodableValue("fallbackReason")] = flutter::EncodableValue("codec " + codec + " has no IEC 61937 carrier");
  } else if (device == nullptr) {
    value[flutter::EncodableValue("fallbackReason")] = flutter::EncodableValue("no WASAPI endpoint can carry IEC 61937 streams (Kodi 1.5.8)");
  } else if (std::find(device->caps.formats.begin(), device->caps.formats.end(), name) == device->caps.formats.end()) {
    value[flutter::EncodableValue("fallbackReason")] = flutter::EncodableValue(device->name + " rejected " + name + " in exclusive mode");
  } else {
    value[flutter::EncodableValue("passthrough")] = flutter::EncodableValue(true);
  }
  return value;
}

flutter::EncodableMap PlatformServicesPlugin::ProbeMedia(const flutter::EncodableValue* arguments) const {
  const auto* pathValue = arguments == nullptr ? nullptr : std::get_if<std::string>(arguments);
  if (pathValue == nullptr || pathValue->empty()) return Unsupported("media path is required");
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool shouldUninitialize = SUCCEEDED(com);
  if (FAILED(MFStartup(MF_VERSION))) {
    if (shouldUninitialize) CoUninitialize();
    return Unsupported("Media Foundation startup failed");
  }
  IMFSourceReader* reader = nullptr;
  const std::wstring path = Utf8ToWide(*pathValue);
  HRESULT status = MFCreateSourceReaderFromURL(path.c_str(), nullptr, &reader);
  if (FAILED(status) || reader == nullptr) {
    MFShutdown();
    if (shouldUninitialize) CoUninitialize();
    return Unsupported("Media Foundation could not open the media source");
  }
  flutter::EncodableList codecs;
  int32_t videoWidth = 0;
  int32_t videoHeight = 0;
  double frameRate = 0.0;
  int32_t audioChannels = 0;
  double audioSampleRate = 0.0;
  for (DWORD stream = 0; stream < 2; ++stream) {
    IMFMediaType* type = nullptr;
    if (FAILED(reader->GetNativeMediaType(stream, 0, &type)) || type == nullptr) continue;
    GUID subtype{};
    if (SUCCEEDED(type->GetGUID(MF_MT_SUBTYPE, &subtype))) {
      if (IsEqualGUID(subtype, MFVideoFormat_H264)) codecs.emplace_back("h264");
      else if (IsEqualGUID(subtype, MFVideoFormat_HEVC)) codecs.emplace_back("hevc");
      else if (IsEqualGUID(subtype, MFAudioFormat_AAC)) codecs.emplace_back("aac");
    }
    GUID major{};
    if (SUCCEEDED(type->GetGUID(MF_MT_MAJOR_TYPE, &major)) && IsEqualGUID(major, MFMediaType_Video)) {
      UINT32 width = 0, height = 0;
      if (SUCCEEDED(MFGetAttributeSize(type, MF_MT_FRAME_SIZE, &width, &height))) {
        videoWidth = static_cast<int32_t>(width);
        videoHeight = static_cast<int32_t>(height);
      }
      UINT32 numerator = 0, denominator = 1;
      if (SUCCEEDED(MFGetAttributeRatio(type, MF_MT_FRAME_RATE, &numerator, &denominator)) && denominator != 0) {
        frameRate = static_cast<double>(numerator) / static_cast<double>(denominator);
      }
    } else if (SUCCEEDED(type->GetGUID(MF_MT_MAJOR_TYPE, &major)) && IsEqualGUID(major, MFMediaType_Audio)) {
      UINT32 channels = 0, sampleRate = 0;
      type->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
      type->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
      audioChannels = static_cast<int32_t>(channels);
      audioSampleRate = static_cast<double>(sampleRate);
    }
    type->Release();
  }
  DWORD nativeVideoSamples = 0;
  DWORD nativeAudioSamples = 0;
  for (const DWORD stream : {static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
                             static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM)}) {
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    IMFSample* sample = nullptr;
    for (int attempt = 0; attempt < 4; ++attempt) {
      const HRESULT readStatus = reader->ReadSample(stream, 0, nullptr, &flags, &timestamp, &sample);
      if (FAILED(readStatus) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) break;
      if (sample != nullptr) {
        if (stream == MF_SOURCE_READER_FIRST_VIDEO_STREAM) ++nativeVideoSamples;
        else ++nativeAudioSamples;
        sample->Release();
        sample = nullptr;
      }
    }
  }
  PROPVARIANT duration;
  PropVariantInit(&duration);
  int64_t durationMs = 0;
  if (SUCCEEDED(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION, &duration)) && duration.vt == VT_UI8) {
    durationMs = static_cast<int64_t>(duration.uhVal.QuadPart / 10000);
  }
  PropVariantClear(&duration);
  reader->Release();
  MFShutdown();
  if (shouldUninitialize) CoUninitialize();
  flutter::EncodableMap result;
  result[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
  result[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(durationMs);
  result[flutter::EncodableValue("videoWidth")] = flutter::EncodableValue(videoWidth);
  result[flutter::EncodableValue("videoHeight")] = flutter::EncodableValue(videoHeight);
  result[flutter::EncodableValue("videoFrameRate")] = flutter::EncodableValue(frameRate);
  result[flutter::EncodableValue("audioChannels")] = flutter::EncodableValue(audioChannels);
  result[flutter::EncodableValue("audioSampleRate")] = flutter::EncodableValue(audioSampleRate);
  result[flutter::EncodableValue("audioFormats")] = flutter::EncodableList();
  result[flutter::EncodableValue("codecs")] = flutter::EncodableValue(codecs);
  result[flutter::EncodableValue("nativeVideoSamples")] = flutter::EncodableValue(static_cast<int32_t>(nativeVideoSamples));
  result[flutter::EncodableValue("nativeAudioSamples")] = flutter::EncodableValue(static_cast<int32_t>(nativeAudioSamples));
  return result;
}

void PlatformServicesPlugin::RestorePendingDisplayMode() {
  const std::wstring path = PendingModePath();
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DEVMODEW mode{};
  DWORD read = 0;
  const bool valid = ReadFile(file, &mode, sizeof(mode), &read, nullptr) && read == sizeof(mode);
  wchar_t name[CCHDEVICENAME] = {};
  const bool named = valid && ReadFile(file, name, sizeof(name), &read, nullptr) && read == sizeof(name);
  CloseHandle(file);
  if (valid) ChangeDisplaySettingsExW(named && name[0] != 0 ? name : nullptr, &mode, nullptr, CDS_FULLSCREEN, nullptr);
  DeleteFileW(path.c_str());
}

void PlatformServicesPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("capabilities.version") == 0) {
    flutter::EncodableMap value;
    value[flutter::EncodableValue("os")] = flutter::EncodableValue(WindowsVersion());
    value[flutter::EncodableValue("plugin")] = flutter::EncodableValue("0.0.1");
    result->Success(flutter::EncodableValue(value));
  } else if (method_call.method_name().compare("capabilities.probe") == 0) {
    const auto decoders = HardwareDecoders();
    const auto display = EnumerateDisplayModes();
    const auto audio = AudioDevices(nullptr);
    bool hdrSupported = false;
    bool hdrEnabled = false;
    DisplayHdrStatus(&hdrSupported, &hdrEnabled);
    const bool displaySupported = [&display] {
      const auto it = display.find(flutter::EncodableValue("supported"));
      return it != display.end() && std::get_if<bool>(&it->second) != nullptr &&
             *std::get_if<bool>(&it->second);
    }();
    const bool audioSupported = [&audio] {
      const auto it = audio.find(flutter::EncodableValue("supported"));
      return it != audio.end() && std::get_if<bool>(&it->second) != nullptr &&
             *std::get_if<bool>(&it->second);
    }();
    flutter::EncodableMap value;
    flutter::EncodableList decoderValues;
    for (const auto& decoder : decoders) decoderValues.emplace_back(decoder);
    value[flutter::EncodableValue("hardwareDecode")] = flutter::EncodableValue(!decoders.empty());
    value[flutter::EncodableValue("decoders")] = flutter::EncodableValue(decoderValues);
    // Kodi 4.7: the HDR choice is offered when the display is HDR capable.
    value[flutter::EncodableValue("hdrOutput")] = flutter::EncodableValue(hdrSupported);
    flutter::EncodableList hdrFormats;
    if (hdrSupported) hdrFormats.emplace_back("advanced-color");
    value[flutter::EncodableValue("hdrFormats")] = flutter::EncodableValue(hdrFormats);
    value[flutter::EncodableValue("displayModeSwitching")] = flutter::EncodableValue(displaySupported);
    std::string requestedPassthrough, requestedOutput;
    if (const auto* map = method_call.arguments() == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(method_call.arguments())) {
      const auto it = map->find(flutter::EncodableValue("passthroughDeviceId"));
      if (it != map->end())
        if (const auto* text = std::get_if<std::string>(&it->second)) requestedPassthrough = StripPrefix(*text);
      const auto outputIt = map->find(flutter::EncodableValue("outputDeviceId"));
      if (outputIt != map->end())
        if (const auto* text = std::get_if<std::string>(&outputIt->second)) requestedOutput = StripPrefix(*text);
    }
    const auto* passthroughDevice = PassthroughEndpoint(Endpoints(), requestedPassthrough);
    value[flutter::EncodableValue("audioPassthrough")] = flutter::EncodableValue(passthroughDevice != nullptr);
    value[flutter::EncodableValue("passthroughFormats")] = flutter::EncodableValue(
        passthroughDevice != nullptr ? Strings(passthroughDevice->caps.formats) : flutter::EncodableList());
    flutter::EncodableMap diagnostics;
    diagnostics[flutter::EncodableValue("probe")] = flutter::EncodableValue("D3D11 video decoder profiles, EnumDisplaySettings, and WASAPI probes");
    diagnostics[flutter::EncodableValue("os")] = flutter::EncodableValue("windows");
    diagnostics[flutter::EncodableValue("display.hdrSupported")] = flutter::EncodableValue(hdrSupported ? "true" : "false");
    diagnostics[flutter::EncodableValue("display.hdrEnabled")] = flutter::EncodableValue(hdrEnabled ? "true" : "false");
    diagnostics[flutter::EncodableValue("display.modeCount")] = flutter::EncodableValue(std::to_string(ListedModes(Device()).size()));
    std::string passthroughIds;
    const audio::Endpoint* pcmDevice = nullptr;
    for (const auto& endpoint : Endpoints()) {
      if (endpoint.passthroughType && !endpoint.caps.formats.empty())
        passthroughIds += std::string(kWasapiPrefix) + endpoint.id + "\n";
      if (endpoint.id == requestedOutput) pcmDevice = &endpoint;
    }
    if (pcmDevice == nullptr)
      for (const auto& endpoint : Endpoints()) if (endpoint.isDefault) pcmDevice = &endpoint;
    diagnostics[flutter::EncodableValue("audioPassthroughDevices")] = flutter::EncodableValue(passthroughIds);
    diagnostics[flutter::EncodableValue("audioPcmIsIec958")] = flutter::EncodableValue(
        pcmDevice != nullptr && pcmDevice->passthroughType && !pcmDevice->hdmi ? "true" : "false");
    for (const auto& endpoint : Endpoints()) {
      if (!endpoint.isDefault) continue;
      diagnostics[flutter::EncodableValue("audioRoute")] = flutter::EncodableValue(endpoint.name);
      diagnostics[flutter::EncodableValue("audioMixRate")] = flutter::EncodableValue(std::to_string(endpoint.mixRate));
      diagnostics[flutter::EncodableValue("audioMixChannels")] = flutter::EncodableValue(std::to_string(endpoint.mixChannels));
      diagnostics[flutter::EncodableValue("audioExclusiveMaxChannels")] = flutter::EncodableValue(std::to_string(endpoint.caps.maxChannels));
    }
    {
      std::string joined;
      for (const auto& line : audio_log_) joined += line + "\n";
      diagnostics[flutter::EncodableValue("audioProbe")] = flutter::EncodableValue(joined);
    }
    diagnostics[flutter::EncodableValue("audioEnumeration")] = flutter::EncodableValue(audioSupported ? "WASAPI render endpoints" : "WASAPI unavailable");
    value[flutter::EncodableValue("diagnostics")] = flutter::EncodableValue(diagnostics);
    result->Success(flutter::EncodableValue(value));
  } else if (method_call.method_name().compare("lifecycle.keepAwake") == 0) {
    keep_awake_ = SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED) != 0;
    flutter::EncodableMap value;
    value[flutter::EncodableValue("supported")] = flutter::EncodableValue(keep_awake_);
    if (!keep_awake_) value[flutter::EncodableValue("reason")] = flutter::EncodableValue("SetThreadExecutionState failed");
    result->Success(flutter::EncodableValue(value));
  } else if (method_call.method_name().compare("lifecycle.releaseKeepAwake") == 0) {
    keep_awake_ = false;
    const bool released = SetThreadExecutionState(ES_CONTINUOUS) != 0;
    flutter::EncodableMap value;
    value[flutter::EncodableValue("supported")] = flutter::EncodableValue(released);
    result->Success(flutter::EncodableValue(value));
  } else if (method_call.method_name().compare("display.screens") == 0) {
    result->Success(flutter::EncodableValue(DisplayScreens(nullptr)));
  } else if (method_call.method_name().compare("display.select") == 0) {
    result->Success(flutter::EncodableValue(DisplayScreens(method_call.arguments())));
  } else if (method_call.method_name().compare("display.modes") == 0) {
    result->Success(flutter::EncodableValue(EnumerateDisplayModes()));
  } else if (method_call.method_name().compare("display.apply") == 0) {
    result->Success(flutter::EncodableValue(ApplyDisplayMode(method_call.arguments())));
  } else if (method_call.method_name().compare("display.restore") == 0) {
    result->Success(flutter::EncodableValue(RestoreDisplayMode()));
  } else if (method_call.method_name().compare("window.fullscreen") == 0) {
    result->Success(flutter::EncodableValue(SetFullscreen(method_call.arguments())));
  } else if (method_call.method_name().compare("audio.devices") == 0) {
    result->Success(flutter::EncodableValue(AudioDevices(method_call.arguments())));
  } else if (method_call.method_name().compare("audio.negotiate") == 0) {
    result->Success(flutter::EncodableValue(NegotiateAudio(method_call.arguments())));
  } else if (method_call.method_name().compare("media.probe") == 0) {
    result->Success(flutter::EncodableValue(ProbeMedia(method_call.arguments())));
  } else if (method_call.method_name().compare("lifecycle.mediaSession.update") == 0) {
    result->Success(flutter::EncodableValue(UpdateMediaSession(method_call.arguments())));
  } else if (method_call.method_name().compare("lifecycle.mediaSession.clear") == 0) {
    result->Success(flutter::EncodableValue(ClearMediaSession()));
  } else {
    result->Error("platform.unsupported", "platform.unsupported: " + method_call.method_name());
  }
}

}  // namespace platform_services
