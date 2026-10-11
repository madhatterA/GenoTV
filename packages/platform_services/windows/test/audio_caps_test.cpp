// Standalone (no gtest): cl /EHsc /std:c++17 audio_caps_test.cpp
#include "../audio_caps.h"
#include <cstdio>
#include <cstdlib>
using namespace platform_services::audio;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); std::exit(1); } } while (0)
static bool Has(const Caps& c, const char* n) {
  for (auto& f : c.formats) if (f == n) return true;
  return false;
}
int main() {
  // PCM-only endpoint (speakers): no passthrough even if the driver lied.
  Caps speakers = Detect(false, false, [](const Candidate& c) { return !c.iec && c.channels == 2 && c.rate <= 96000; });
  CHECK(speakers.formats.empty());
  CHECK(speakers.maxChannels == 2);
  CHECK(!speakers.rates.empty() && speakers.rates.front() == 96000);
  // S/PDIF: only what the driver accepted (AC3 + DTS core @48k).
  Caps spdif = Detect(false, true, [](const Candidate& c) { return c.iec && c.rate == 48000; });
  CHECK(Has(spdif, "ac3") && Has(spdif, "dts") && !Has(spdif, "eac3") && !Has(spdif, "trueHd") && !Has(spdif, "dtsHd"));
  CHECK(spdif.rates.size() == 1 && spdif.rates[0] == 48000);  // forced 48000
  // HDMI: all six advertised even when every probe fails; 192000+48000 forced.
  Caps hdmi = Detect(true, true, [](const Candidate&) { return false; });
  CHECK(Has(hdmi, "ac3") && Has(hdmi, "eac3") && Has(hdmi, "dts") && Has(hdmi, "dtsHd") && Has(hdmi, "trueHd"));
  CHECK(hdmi.rates.size() == 2 && hdmi.rates[0] == 192000 && hdmi.rates[1] == 48000);
  // Multichannel PCM maximum from exclusive probes.
  Caps multi = Detect(false, false, [](const Candidate& c) { return !c.iec && c.channels <= 6; });
  CHECK(multi.maxChannels == 6);
  std::puts("audio_caps_test OK");
  return 0;
}
