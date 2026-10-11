#ifndef PLATFORM_SERVICES_AUDIO_CAPS_H_
#define PLATFORM_SERVICES_AUDIO_CAPS_H_

// Kodi Windows WASAPI capability detection (windows_reference.md 1.4, 1.5.8).
// Pure logic: the caller supplies the IsFormatSupported(EXCLUSIVE) answer.

#include <algorithm>
#include <functional>
#include <string>
#include <vector>

namespace platform_services::audio {

enum class Iec { DtsHdHra, DtsHdMa, TrueHd, Eac3, Dts, Ac3 };

struct Candidate {
  bool iec = false;  // false = PCM probe
  Iec format = Iec::Ac3;
  int channels = 2;
  int rate = 48000;
};

using Probe = std::function<bool(const Candidate&)>;

struct Caps {
  std::vector<std::string> formats;  // Dart names: ac3 eac3 dts dtsHd trueHd
  std::vector<int> rates;            // descending, as Kodi probes them
  int maxChannels = 2;
  std::vector<std::string> log;      // one line per probe
};

inline const char* Name(Iec f) {
  switch (f) {
    case Iec::DtsHdHra: return "dts-hd-hra";
    case Iec::DtsHdMa: return "dts-hd-ma";
    case Iec::TrueHd: return "truehd";
    case Iec::Eac3: return "eac3";
    case Iec::Dts: return "dts";
    default: return "ac3";
  }
}

// Kodi order: DTS-HD HRA, DTS-HD MA, TrueHD, E-AC3, DTS, AC3 (AESinkWASAPI.cpp).
// [hdmi]: every format is advertised even if the probe failed (1.5.8 step 3).
// [passthroughType]: false for PCM-only endpoints (speakers...): never offered.
inline Caps Detect(bool hdmi, bool passthroughType, const Probe& probe) {
  Caps caps;
  const int kRates[] = {384000, 192000, 176400, 96000, 88200,
                        48000,  44100,  32000,  22050, 11025};
  for (int rate : kRates) {
    const bool ok = probe({false, Iec::Ac3, 2, rate});
    caps.log.push_back("pcm.rate." + std::to_string(rate) + "=" + (ok ? "ok" : "rejected"));
    if (ok) caps.rates.push_back(rate);
  }
  for (int channels : {2, 4, 6, 8}) {
    const bool ok = probe({false, Iec::Ac3, channels, 48000});
    caps.log.push_back("pcm.channels." + std::to_string(channels) + "=" + (ok ? "ok" : "rejected"));
    if (ok) caps.maxChannels = (std::max)(caps.maxChannels, channels);
  }
  struct Row { Iec f; int ch; int rate; };
  const Row rows[] = {{Iec::DtsHdHra, 2, 192000}, {Iec::DtsHdMa, 8, 192000},
                      {Iec::TrueHd, 8, 192000},   {Iec::Eac3, 2, 192000},
                      {Iec::Dts, 6, 48000},       {Iec::Ac3, 6, 48000}};
  bool hd = false, add192 = false, add48 = false;
  auto add = [&](const char* n) {
    if (std::find(caps.formats.begin(), caps.formats.end(), n) == caps.formats.end())
      caps.formats.push_back(n);
  };
  for (const Row& r : rows) {
    const bool ok = probe({true, r.f, r.ch, r.rate});
    const bool accepted = passthroughType && (ok || hdmi);
    caps.log.push_back(std::string("iec.") + Name(r.f) + "=" + (ok ? "ok" : "rejected") +
                       (accepted && !ok ? " (hdmi assumed, Kodi 1.5.8)" : "") +
                       (!passthroughType ? " (pcm-only endpoint, not offered)" : ""));
    if (!accepted) continue;
    (r.rate == 192000 ? add192 : add48) = true;
    switch (r.f) {
      case Iec::DtsHdHra: case Iec::DtsHdMa: add("dtsHd"); hd = true; break;
      case Iec::TrueHd: add("trueHd"); break;
      case Iec::Eac3: add("eac3"); break;
      case Iec::Dts: add("dts"); break;
      default: add("ac3");
    }
  }
  (void)hd;
  auto force = [&](int rate) {
    if (std::find(caps.rates.begin(), caps.rates.end(), rate) == caps.rates.end()) {
      caps.rates.push_back(rate);
      std::sort(caps.rates.rbegin(), caps.rates.rend());
    }
  };
  if (add192) force(192000);
  if (add48) force(48000);
  return caps;
}

}  // namespace platform_services::audio

#endif
