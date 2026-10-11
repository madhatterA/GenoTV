#ifndef PLATFORM_SERVICES_WINDOWS_MEDIA_SESSION_H_
#define PLATFORM_SERVICES_WINDOWS_MEDIA_SESSION_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace platform_services::media {

struct Command {
  std::string name;
  std::optional<double> position_seconds;
};

struct Info {
  std::wstring title;
  std::wstring subtitle;
  double duration_seconds = -1;  // < 0: unknown
  double position_seconds = -1;
  bool playing = false;
};

// System Media Transport Controls for one top-level window.
class Session {
 public:
  // `notify` may run on any thread; it must make the platform thread call
  // TakeCommands(). Returns null and fills `error` when SMTC is unavailable.
  static std::unique_ptr<Session> Create(HWND window, std::function<void()> notify,
                                         std::string* error);
  ~Session();

  bool Update(const Info& info, std::string* error);
  bool Clear(std::string* error);
  bool active() const;
  std::vector<Command> TakeCommands();

 private:
  struct Impl;
  explicit Session(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};

}  // namespace platform_services::media

#endif  // PLATFORM_SERVICES_WINDOWS_MEDIA_SESSION_H_
