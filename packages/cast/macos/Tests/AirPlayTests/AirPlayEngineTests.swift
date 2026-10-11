import AVFoundation
import AVKit
import XCTest
@testable import AirPlayCore

final class AirPlayEngineTests: XCTestCase {
  let proxy = URL(string: "http://192.168.1.20:8080/stream/abc.mp4")!

  func testExternalPlaybackAllowed() {
    XCTAssertTrue(AirPlayEngine().player.allowsExternalPlayback)
  }

  func testRoutePickerIsBoundToThePlayer() {
    let engine = AirPlayEngine()
    let picker = engine.makeRoutePicker()
    XCTAssertTrue(picker.player === engine.player)
  }

  func testPrepareGivesPlayerTheProxyUrlPaused() {
    let engine = AirPlayEngine()
    engine.prepare(url: proxy, startMs: 5000)
    let asset = engine.player.currentItem?.asset as? AVURLAsset
    XCTAssertEqual(asset?.url, proxy)
    XCTAssertEqual(engine.player.timeControlStatus, .paused)
    XCTAssertEqual(engine.snapshot()["external"] as? Bool, false)
  }

  func testStopReleasesTheItem() {
    let engine = AirPlayEngine()
    engine.prepare(url: proxy, startMs: 0)
    engine.stop()
    XCTAssertNil(engine.player.currentItem)
    XCTAssertEqual(engine.snapshot()["state"] as? String, "idle")
  }

  func testSnapshotsAreEmitted() {
    let engine = AirPlayEngine()
    var seen: [[String: Any]] = []
    engine.onSnapshot = { seen.append($0) }
    engine.prepare(url: proxy, startMs: 0)
    XCTAssertFalse(seen.isEmpty)
  }

  func testStateMapping() {
    func s(_ item: Bool, _ st: AVPlayerItem.Status, _ tc: AVPlayer.TimeControlStatus, _ ended: Bool = false) -> String {
      AirPlayEngine.state(hasItem: item, itemStatus: st, timeControl: tc, ended: ended)
    }
    XCTAssertEqual(s(false, .unknown, .paused), "idle")
    XCTAssertEqual(s(true, .unknown, .paused), "loading")
    XCTAssertEqual(s(true, .readyToPlay, .paused), "paused")
    XCTAssertEqual(s(true, .readyToPlay, .playing), "playing")
    XCTAssertEqual(s(true, .readyToPlay, .waitingToPlayAtSpecifiedRate), "buffering")
    XCTAssertEqual(s(true, .failed, .paused), "error")
    XCTAssertEqual(s(true, .readyToPlay, .paused, true), "idle")
  }
}
