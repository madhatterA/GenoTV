#ifndef PLATFORM_SERVICES_WINDOWS_AUDIO_H_
#define PLATFORM_SERVICES_WINDOWS_AUDIO_H_

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "audio_caps.h"

namespace platform_services::audio {

struct Endpoint {
  std::string id;    // IMMDevice id; mpv names it "wasapi/<id>"
  std::string name;  // PKEY_Device_FriendlyName
  std::string kind;  // AudioDeviceKind name
  bool isDefault = false;
  bool hdmi = false;
  bool passthroughType = false;  // Kodi AE_DEVTYPE_IEC958 / HDMI
  int mixChannels = 2;           // shared-mode mix format, clamped 2..8
  int mixRate = 48000;
  Caps caps;
};

// Kodi GetRendererDetails + WASAPI probes. Endpoints with exclusive mode
// disallowed are dropped and named in [log]. [error] set when COM fails.
std::vector<Endpoint> ProbeEndpoints(std::vector<std::string>* log, std::string* error);

// IMMNotificationClient (Kodi IMMNotificationClient.h): [onChange] runs on an
// MMDevice thread for default-render-communications changes and add/remove/state.
class RouteWatcher {
 public:
  explicit RouteWatcher(std::function<void()> onChange);
  ~RouteWatcher();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace platform_services::audio

#endif
