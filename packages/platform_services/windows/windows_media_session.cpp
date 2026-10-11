#include "windows_media_session.h"

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <chrono>
#include <mutex>
#include <utility>

namespace platform_services::media {

namespace wm = winrt::Windows::Media;

namespace {
std::chrono::duration<int64_t, std::ratio<1, 10000000>> Seconds(double value) {
  return std::chrono::duration<int64_t, std::ratio<1, 10000000>>(
      static_cast<int64_t>(value * 10000000.0));
}
}  // namespace

struct Session::Impl {
  wm::SystemMediaTransportControls smtc{nullptr};
  wm::SystemMediaTransportControls::ButtonPressed_revoker button;
  wm::SystemMediaTransportControls::PlaybackPositionChangeRequested_revoker seek;
  std::function<void()> notify;
  std::mutex mutex;
  std::vector<Command> pending;
  bool active = false;
  std::wstring title;
  std::wstring subtitle;
  bool has_metadata = false;

  void Push(Command command) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      pending.push_back(std::move(command));
    }
    notify();
  }
};

Session::Session(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}

Session::~Session() {
  if (impl_ == nullptr) return;
  impl_->button.revoke();
  impl_->seek.revoke();
  std::string ignored;  // destructor cannot report; Clear() already surfaced errors
  Clear(&ignored);
}

std::unique_ptr<Session> Session::Create(HWND window, std::function<void()> notify,
                                         std::string* error) {
  try {
    auto impl = std::make_unique<Impl>();
    impl->notify = std::move(notify);
    auto interop = winrt::get_activation_factory<wm::SystemMediaTransportControls,
                                                 ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<wm::SystemMediaTransportControls>(), winrt::put_abi(impl->smtc)));
    auto* raw = impl.get();
    impl->button = impl->smtc.ButtonPressed(
        winrt::auto_revoke,
        [raw](wm::SystemMediaTransportControls const&,
              wm::SystemMediaTransportControlsButtonPressedEventArgs const& args) {
          switch (args.Button()) {
            case wm::SystemMediaTransportControlsButton::Play: raw->Push({"play", std::nullopt}); break;
            case wm::SystemMediaTransportControlsButton::Pause: raw->Push({"pause", std::nullopt}); break;
            case wm::SystemMediaTransportControlsButton::Stop: raw->Push({"stop", std::nullopt}); break;
            case wm::SystemMediaTransportControlsButton::Next:
            case wm::SystemMediaTransportControlsButton::FastForward:
              raw->Push({"skipForward", std::nullopt});
              break;
            case wm::SystemMediaTransportControlsButton::Previous:
            case wm::SystemMediaTransportControlsButton::Rewind:
              raw->Push({"skipBackward", std::nullopt});
              break;
            default: break;
          }
        });
    impl->seek = impl->smtc.PlaybackPositionChangeRequested(
        winrt::auto_revoke,
        [raw](wm::SystemMediaTransportControls const&,
              wm::PlaybackPositionChangeRequestedEventArgs const& args) {
          const auto position =
              std::chrono::duration<double>(args.RequestedPlaybackPosition()).count();
          raw->Push({"seekTo", position});
        });
    return std::unique_ptr<Session>(new Session(std::move(impl)));
  } catch (const winrt::hresult_error& failure) {
    if (error != nullptr) *error = "SMTC unavailable: " + winrt::to_string(failure.message());
    return nullptr;
  }
}

bool Session::Update(const Info& info, std::string* error) {
  try {
    auto& smtc = impl_->smtc;
    if (!impl_->active) {
      smtc.IsEnabled(true);
      smtc.IsPlayEnabled(true);
      smtc.IsPauseEnabled(true);
      smtc.IsStopEnabled(true);
      smtc.IsNextEnabled(true);
      smtc.IsPreviousEnabled(true);
      smtc.IsFastForwardEnabled(true);
      smtc.IsRewindEnabled(true);
      impl_->active = true;
    }
    if (!impl_->has_metadata || impl_->title != info.title || impl_->subtitle != info.subtitle) {
      auto updater = smtc.DisplayUpdater();
      updater.Type(wm::MediaPlaybackType::Video);
      auto video = updater.VideoProperties();
      video.Title(winrt::hstring(info.title));
      video.Subtitle(winrt::hstring(info.subtitle));
      updater.Update();
      impl_->title = info.title;
      impl_->subtitle = info.subtitle;
      impl_->has_metadata = true;
    }
    smtc.PlaybackStatus(info.playing ? wm::MediaPlaybackStatus::Playing
                                     : wm::MediaPlaybackStatus::Paused);
    if (info.duration_seconds >= 0) {
      wm::SystemMediaTransportControlsTimelineProperties timeline;
      timeline.StartTime(Seconds(0));
      timeline.MinSeekTime(Seconds(0));
      timeline.EndTime(Seconds(info.duration_seconds));
      timeline.MaxSeekTime(Seconds(info.duration_seconds));
      timeline.Position(Seconds(info.position_seconds < 0 ? 0 : info.position_seconds));
      smtc.UpdateTimelineProperties(timeline);
    }
    return true;
  } catch (const winrt::hresult_error& failure) {
    if (error != nullptr) *error = "SMTC update failed: " + winrt::to_string(failure.message());
    return false;
  }
}

bool Session::Clear(std::string* error) {
  if (!impl_->active) return true;
  impl_->active = false;
  impl_->has_metadata = false;
  try {
    impl_->smtc.PlaybackStatus(wm::MediaPlaybackStatus::Closed);
    impl_->smtc.DisplayUpdater().ClearAll();
    impl_->smtc.DisplayUpdater().Update();
    impl_->smtc.IsEnabled(false);
    return true;
  } catch (const winrt::hresult_error& failure) {
    if (error != nullptr) *error = "SMTC clear failed: " + winrt::to_string(failure.message());
    return false;
  }
}

bool Session::active() const { return impl_->active; }

std::vector<Command> Session::TakeCommands() {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return std::exchange(impl_->pending, {});
}

}  // namespace platform_services::media
