import AVFoundation
import AVKit

/// The only AVPlayer in the app: it plays the cast proxy URL to an AirPlay
/// device, never locally (mpv stays the local engine). The system route
/// picker is bound to [player]; picking an AirPlay route there switches this
/// player to external playback.
public final class AirPlayEngine: NSObject {
  public let player = AVPlayer()
  /// Called with a snapshot on every state, position, duration or route change.
  public var onSnapshot: (([String: Any]) -> Void)?

  private var observations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var ended = false

  public override init() {
    super.init()
    player.allowsExternalPlayback = true
    observations = [
      player.observe(\.timeControlStatus) { [weak self] _, _ in self?.emit() },
      player.observe(\.isExternalPlaybackActive) { [weak self] _, _ in self?.emit() },
    ]
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 2), queue: .main
    ) { [weak self] _ in self?.emit() }
  }

  deinit {
    if let timeObserver { player.removeTimeObserver(timeObserver) }
  }

  public static func state(
    hasItem: Bool, itemStatus: AVPlayerItem.Status,
    timeControl: AVPlayer.TimeControlStatus, ended: Bool
  ) -> String {
    if !hasItem || ended { return "idle" }
    if itemStatus == .failed { return "error" }
    switch timeControl {
    case .playing: return "playing"
    case .waitingToPlayAtSpecifiedRate: return "buffering"
    case .paused: return itemStatus == .unknown ? "loading" : "paused"
    @unknown default: return "idle"
    }
  }

  public func snapshot() -> [String: Any] {
    let item = player.currentItem
    func ms(_ t: CMTime?) -> Int {
      guard let t, t.isNumeric, t.seconds.isFinite else { return 0 }
      return max(0, Int(t.seconds * 1000))
    }
    var s: [String: Any] = [
      "state": AirPlayEngine.state(
        hasItem: item != nil, itemStatus: item?.status ?? .unknown,
        timeControl: player.timeControlStatus, ended: ended),
      "external": player.isExternalPlaybackActive,
      "positionMs": ms(player.currentTime()),
      "durationMs": ms(item?.duration),
    ]
    if let e = item?.error { s["error"] = e.localizedDescription }
    return s
  }

  private func emit() { onSnapshot?(snapshot()) }

  /// Loads [url] paused at [startMs]; nothing is sent to a TV until the user
  /// picks an AirPlay route in the route picker.
  public func prepare(url: URL, startMs: Int) {
    clearItem()
    ended = false
    let item = AVPlayerItem(url: url)
    itemObservations = [
      item.observe(\.status) { [weak self] _, _ in self?.emit() },
      item.observe(\.duration) { [weak self] _, _ in self?.emit() },
    ]
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      self?.ended = true
      self?.emit()
    }
    player.replaceCurrentItem(with: item)
    player.pause()
    seek(ms: startMs)
    emit()
  }

  public func play() { ended = false; player.play() }
  public func pause() { player.pause() }

  public func seek(ms: Int) {
    ended = false
    player.seek(
      to: CMTime(value: CMTimeValue(ms), timescale: 1000),
      toleranceBefore: .zero, toleranceAfter: .zero
    ) { [weak self] _ in self?.emit() }
  }

  /// Ends the session; with no item the AirPlay device is released.
  public func stop() {
    player.pause()
    clearItem()
    player.replaceCurrentItem(with: nil)
    emit()
  }

  private func clearItem() {
    itemObservations.removeAll()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
  }

  public func makeRoutePicker() -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.player = player
    picker.isRoutePickerButtonBordered = false
    return picker
  }
}
