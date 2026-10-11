#include "windows_audio.h"

#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <audioclient.h>
#include <propsys.h>
#include <ks.h>
#include <ksmedia.h>

#include <algorithm>

namespace platform_services::audio {
namespace {

std::string Utf8(const wchar_t* v) {
  if (v == nullptr) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, v, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return {};
  std::string s(static_cast<size_t>(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, v, -1, s.data(), n, nullptr, nullptr);
  return s;
}

DWORD Mask(int channels) {
  switch (channels) {
    case 4: return KSAUDIO_SPEAKER_QUAD;
    case 6: return KSAUDIO_SPEAKER_5POINT1;
    case 8: return KSAUDIO_SPEAKER_7POINT1_SURROUND;
    default: return KSAUDIO_SPEAKER_STEREO;
  }
}

WAVEFORMATEXTENSIBLE Format(int channels, int rate, int bits, int valid, const GUID& subtype) {
  WAVEFORMATEXTENSIBLE f{};
  f.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
  f.Format.nChannels = static_cast<WORD>(channels);
  f.Format.nSamplesPerSec = static_cast<DWORD>(rate);
  f.Format.wBitsPerSample = static_cast<WORD>(bits);
  f.Format.nBlockAlign = static_cast<WORD>(channels * bits / 8);
  f.Format.nAvgBytesPerSec = f.Format.nSamplesPerSec * f.Format.nBlockAlign;
  f.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
  f.Samples.wValidBitsPerSample = static_cast<WORD>(valid);
  f.dwChannelMask = Mask(channels);
  f.SubFormat = subtype;
  return f;
}

const GUID& IecSubtype(Iec f) {
  switch (f) {
    case Iec::DtsHdHra: case Iec::DtsHdMa: return KSDATAFORMAT_SUBTYPE_IEC61937_DTS_HD;
    case Iec::TrueHd: return KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_MLP;
    case Iec::Eac3: return KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_DIGITAL_PLUS;
    case Iec::Dts: return KSDATAFORMAT_SUBTYPE_IEC61937_DTS;
    default: return KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_DIGITAL;
  }
}

HRESULT ExclusiveHr(IAudioClient* client, const WAVEFORMATEXTENSIBLE& f) {
  return client->IsFormatSupported(AUDCLNT_SHAREMODE_EXCLUSIVE,
                                   reinterpret_cast<const WAVEFORMATEX*>(&f), nullptr);
}
bool Exclusive(IAudioClient* client, const WAVEFORMATEXTENSIBLE& f) {
  return ExclusiveHr(client, f) == S_OK;
}

// Kodi testFormats order: float32, 24-in-32, 32, 16.
bool PcmSupported(IAudioClient* c, int channels, int rate) {
  return Exclusive(c, Format(channels, rate, 32, 32, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)) ||
         Exclusive(c, Format(channels, rate, 32, 24, KSDATAFORMAT_SUBTYPE_PCM)) ||
         Exclusive(c, Format(channels, rate, 32, 32, KSDATAFORMAT_SUBTYPE_PCM)) ||
         Exclusive(c, Format(channels, rate, 16, 16, KSDATAFORMAT_SUBTYPE_PCM));
}

}  // namespace

std::vector<Endpoint> ProbeEndpoints(std::vector<std::string>* log, std::string* error) {
  std::vector<Endpoint> out;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool uninit = SUCCEEDED(com);
  IMMDeviceEnumerator* en = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&en)))) {
    *error = "WASAPI device enumerator unavailable";
    if (uninit) CoUninitialize();
    return out;
  }
  std::string defaultId;
  IMMDevice* def = nullptr;
  if (SUCCEEDED(en->GetDefaultAudioEndpoint(eRender, eConsole, &def)) && def) {
    LPWSTR id = nullptr;
    if (SUCCEEDED(def->GetId(&id)) && id) { defaultId = Utf8(id); CoTaskMemFree(id); }
    def->Release();
  }
  IMMDeviceCollection* list = nullptr;
  if (FAILED(en->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &list)) || !list) {
    *error = "WASAPI render endpoint enumeration failed";
    en->Release();
    if (uninit) CoUninitialize();
    return out;
  }
  UINT count = 0;
  list->GetCount(&count);
  for (UINT i = 0; i < count; ++i) {
    IMMDevice* dev = nullptr;
    if (FAILED(list->Item(i, &dev)) || !dev) continue;
    Endpoint e;
    LPWSTR id = nullptr;
    if (SUCCEEDED(dev->GetId(&id)) && id) { e.id = Utf8(id); CoTaskMemFree(id); }
    e.isDefault = e.id == defaultId;
    e.name = "unknown";
    int form = 10;  // UnknownFormFactor
    bool bluetooth = false;
    IPropertyStore* store = nullptr;
    if (SUCCEEDED(dev->OpenPropertyStore(STGM_READ, &store)) && store) {
      PROPVARIANT v;
      PropVariantInit(&v);
      if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &v)) && v.vt == VT_LPWSTR) e.name = Utf8(v.pwszVal);
      PropVariantClear(&v);
      PropVariantInit(&v);
      if (SUCCEEDED(store->GetValue(PKEY_AudioEndpoint_FormFactor, &v)) && v.vt == VT_UI4) form = static_cast<int>(v.ulVal);
      PropVariantClear(&v);
      PropVariantInit(&v);
      if (SUCCEEDED(store->GetValue(PKEY_Device_EnumeratorName, &v)) && v.vt == VT_LPWSTR) {
        std::wstring n(v.pwszVal);
        for (auto& ch : n) ch = static_cast<wchar_t>(::towupper(ch));
        bluetooth = n.find(L"BTHENUM") != std::wstring::npos;
      }
      PropVariantClear(&v);
      store->Release();
    }
    // Kodi winEndpoints[]: 7 digital passthrough and 8 SPDIF = IEC958, 9 HDMI.
    e.hdmi = form == 9;
    e.passthroughType = form == 7 || form == 8 || form == 9;
    e.kind = e.hdmi ? "hdmi" : bluetooth ? "bluetooth" : form == 1 ? "speaker"
             : (form == 3 || form == 5) ? "headphones" : "unknown";
    IAudioClient* client = nullptr;
    if (FAILED(dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&client))) || !client) {
      log->push_back(e.name + ": IAudioClient activation failed");
      dev->Release();
      continue;
    }
    WAVEFORMATEX* mix = nullptr;
    if (SUCCEEDED(client->GetMixFormat(&mix)) && mix) {
      e.mixChannels = (std::min)(8, (std::max)(2, static_cast<int>(mix->nChannels)));
      e.mixRate = static_cast<int>(mix->nSamplesPerSec);
      CoTaskMemFree(mix);
    }
    const HRESULT first = ExclusiveHr(client, Format(2, 48000, 16, 16, KSDATAFORMAT_SUBTYPE_PCM));
    if (first == AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED) {
      log->push_back(e.name + ": exclusive mode not allowed, device hidden (Kodi 1.1)");
      client->Release();
      dev->Release();
      continue;
    }
    e.caps = Detect(e.hdmi, e.passthroughType, [&](const Candidate& c) {
      if (!c.iec) return PcmSupported(client, c.channels, c.rate);
      return Exclusive(client, Format(c.channels, c.rate, 16, 16, IecSubtype(c.format)));
    });
    log->push_back(e.name + ": formFactor=" + std::to_string(form) + " kind=" + e.kind +
                   " mix=" + std::to_string(e.mixChannels) + "ch/" + std::to_string(e.mixRate));
    for (const auto& line : e.caps.log) log->push_back(e.name + ": " + line);
    client->Release();
    dev->Release();
    out.push_back(std::move(e));
  }
  list->Release();
  en->Release();
  if (uninit) CoUninitialize();
  return out;
}

struct RouteWatcher::Impl final : IMMNotificationClient {
  explicit Impl(std::function<void()> f) : notify(std::move(f)) {}
  std::function<void()> notify;
  IMMDeviceEnumerator* en = nullptr;
  LONG refs = 1;

  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override { return InterlockedDecrement(&refs); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID r, void** o) override {
    if (r == __uuidof(IUnknown) || r == __uuidof(IMMNotificationClient)) {
      *o = static_cast<IMMNotificationClient*>(this);
      AddRef();
      return S_OK;
    }
    *o = nullptr;
    return E_NOINTERFACE;
  }
  // Fired once per role; Kodi reacts to eRender + eCommunications only.
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR) override {
    if (flow == eRender && role == eCommunications) notify();
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR) override { notify(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR) override { notify(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR, DWORD) override { notify(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override { return S_OK; }
};

RouteWatcher::RouteWatcher(std::function<void()> onChange) : impl_(new Impl(std::move(onChange))) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                 __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&impl_->en))) &&
      impl_->en) {
    impl_->en->RegisterEndpointNotificationCallback(impl_.get());
  }
}

RouteWatcher::~RouteWatcher() {
  if (impl_->en) {
    impl_->en->UnregisterEndpointNotificationCallback(impl_.get());
    impl_->en->Release();
  }
}

}  // namespace platform_services::audio
