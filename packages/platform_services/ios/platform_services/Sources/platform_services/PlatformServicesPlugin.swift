import Flutter
import AVFoundation
import VideoToolbox
import UIKit
import MediaPlayer

// The host manifest registers this role so UIKit creates an external UIWindowScene.
@objc(PlatformServicesExternalSceneDelegate)
public class PlatformServicesExternalSceneDelegate: NSObject, UIWindowSceneDelegate {
  public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    PlatformServicesPlugin.activeInstance?.screensChanged()
  }

  public func sceneDidDisconnect(_ scene: UIScene) {
    PlatformServicesPlugin.activeInstance?.screensChanged(disconnected: (scene as? UIWindowScene)?.screen)
  }
}

#if DEBUG
// MediaPlayer's event initialisers raise; the system allocates events uninitialised, so do the same.
private final class ProofPositionEvent: MPChangePlaybackPositionCommandEvent {
  static var seconds: Double = 0
  override var positionTime: TimeInterval { ProofPositionEvent.seconds }
}
#endif

public class PlatformServicesPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var notificationTokens: [NSObjectProtocol] = []
  private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
  private weak var rootController: UIViewController?
  private var resolveController: (() -> UIViewController?)?
  private var touchscreenWindow: UIWindow?
  private var externalWindow: UIWindow?
  private var selectedDisplay = ""
  private var interruptedPlaying = false
  static weak var activeInstance: PlatformServicesPlugin?
  #if DEBUG
  private var proofCommandHandlers: [String: (MPRemoteCommand, (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = [:]
  #endif

  override init() {
    super.init()
    let center = NotificationCenter.default
    notificationTokens = [
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
        self?.handleInterruption(note)
      },
      center.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] _ in self?.screensChanged() },
      center.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in self?.screensChanged(disconnected: note.object as? UIScreen) },
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
        // Re-detect on every route change (ios_reference.md 1.5.8 / 1.6 decision) and log it.
        let max = AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
        NSLog("platform_services: audio route changed: %@ maxOutputChannels=%d", PlatformServicesPlugin.routeDescription(), max)
        self?.eventSink?(["event": "audioRouteChanged", "maxOutputChannels": max])
      },
    ]
  }

  deinit {
    _ = clearMediaSession()
    notificationTokens.forEach(NotificationCenter.default.removeObserver)
  }
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "platform_services", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "platform_services/events", binaryMessenger: registrar.messenger())
    let instance = PlatformServicesPlugin()
    instance.rootController = registrar.viewController
    instance.resolveController = { [weak registrar] in registrar?.viewController }
    activeInstance = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities.version":
      result(["os": "iOS " + UIDevice.current.systemVersion, "plugin": "0.0.1"])
    case "capabilities.probe":
      var headroom = 1.0
      if #available(iOS 16.0, *) { headroom = UIScreen.main.potentialEDRHeadroom }
      let formats: [String] = headroom > 1.0 ? ["edr"] : []
      let decoders = hardwareDecoders()
      let session = AVAudioSession.sharedInstance()
      var diagnostics: [String: String] = ["os": "ios", "edrHeadroom": String(headroom), "hardwareDecode": "VideoToolbox codec support probe"]
      // Kodi iOS has no EDR/refresh handling (ios_reference 4.3-4.7): report what UIScreen says.
      var currentHeadroom = 1.0
      if #available(iOS 16.0, *) { currentHeadroom = UIScreen.main.currentEDRHeadroom }
      diagnostics["display.potentialEdrHeadroom"] = String(headroom)
      diagnostics["display.currentEdrHeadroom"] = String(currentHeadroom)
      diagnostics["display.isHdr"] = String(headroom > 1.0)
      diagnostics["display.maxFramesPerSecond"] = String(UIScreen.main.maximumFramesPerSecond)
      diagnostics["display.modeCount"] = String(UIScreen.main.availableModes.count)
      diagnostics["audioProbe.method"] = "AVAudioSession.currentRoute + maximumOutputNumberOfChannels"
      diagnostics["audioRoute"] = PlatformServicesPlugin.routeDescription()
      diagnostics["audioMaxOutputChannels"] = String(session.maximumOutputNumberOfChannels)
      diagnostics["audioOutputChannels"] = String(session.outputNumberOfChannels)
      diagnostics["audioSessionSampleRate"] = String(session.sampleRate)
      diagnostics["audioPassthrough"] = "unsupported: iOS has no bitstream sink (Kodi iOS: not handled)"
      let report: [String: Any] = ["hardwareDecode": !decoders.isEmpty, "decoders": decoders, "hdrOutput": headroom > 1.0, "hdrFormats": formats, "displayModeSwitching": !UIScreen.main.availableModes.isEmpty, "audioPassthrough": false, "passthroughFormats": [], "diagnostics": diagnostics]
      result(report)
    case "display.modes":
      result(displayModes())
    case "display.apply", "display.restore":
      result(applyDisplayMode(call.arguments))
    case "display.screens":
      result(displayScreens())
    case "display.select":
      guard let values = call.arguments as? [String: Any], let id = values["id"] as? String,
            ["", "Touchscreen", "External"].contains(id) else {
        result(FlutterError(code: "platform.display.invalid", message: "Unknown display", details: nil)); return
      }
      completeDisplaySelection(id, result: result, deadline: Date().addingTimeInterval(2))
    #if DEBUG
    case "proof.mediaSession.read":
      let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      result(["title": info[MPMediaItemPropertyTitle] ?? NSNull(),
              "duration": info[MPMediaItemPropertyPlaybackDuration] ?? NSNull(),
              "elapsed": info[MPNowPlayingInfoPropertyElapsedPlaybackTime] ?? NSNull(),
              "rate": info[MPNowPlayingInfoPropertyPlaybackRate] ?? NSNull(), "cleared": info.isEmpty])
    case "proof.mediaSession.command":
      let values = call.arguments as? [String: Any] ?? [:]
      guard let name = values["command"] as? String,
            let (command, handler) = proofCommandHandlers[name], command.isEnabled else {
        result(FlutterError(code: "proof.command.missing", message: "No registered system target", details: nil)); return
      }
      ProofPositionEvent.seconds = values["positionSeconds"] as? Double ?? 0
      let event = class_createInstance(name == "seekTo" ? ProofPositionEvent.self : MPRemoteCommandEvent.self, 0) as! MPRemoteCommandEvent
      result(["status": handler(event).rawValue])
    case "proof.audioSession.interruption":
      let values = call.arguments as? [String: Any] ?? [:]
      let began = values["began"] as? Bool ?? true
      NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(), userInfo: [
          AVAudioSessionInterruptionTypeKey: began ? AVAudioSession.InterruptionType.began.rawValue : AVAudioSession.InterruptionType.ended.rawValue,
          AVAudioSessionInterruptionOptionKey: (values["shouldResume"] as? Bool ?? false) ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0,
        ])
      result(["posted": true])
    case "proof.display.disconnect":
      // Exercise the real notification observer, with the real connected screens.
      NotificationCenter.default.post(name: UIScreen.didDisconnectNotification, object: UIScreen.main)
      result(displayScreens())
    #endif
    case "audio.devices":
      let session = AVAudioSession.sharedInstance()
      // Kodi iOS advertises 44100 and 48000 Hz; CoreAudio resamples the rest.
      let devices: [[String: Any]] = session.currentRoute.outputs.map { output in
        ["id": output.uid, "name": output.portName, "kind": output.portType.rawValue, "isCurrent": true, "channels": output.channels?.count ?? 0, "sampleRate": session.sampleRate, "supportedSampleRates": [44100, 48000]]
      }
      result(["supported": true, "os": "ios", "maxOutputChannels": session.maximumOutputNumberOfChannels, "devices": devices])
    case "audio.negotiate":
      result(["passthrough": false, "fallbackReason": "platform does not support bitstream output", "deviceId": "unknown"])
    case "media.probe":
      result(probeMedia(call.arguments))
    case "lifecycle.mediaSession.update":
      result(updateMediaSession(call.arguments))
    case "lifecycle.mediaSession.clear":
      result(clearMediaSession())
    case "lifecycle.keepAwake":
      UIApplication.shared.isIdleTimerDisabled = true
      result(["supported": true])
    case "lifecycle.releaseKeepAwake":
      UIApplication.shared.isIdleTimerDisabled = false
      result(["supported": true])
    default:
      result(FlutterError(code: "platform.unsupported", message: "platform.unsupported: \(call.method)", details: nil))
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      // Active session so maximumOutputNumberOfChannels describes the live route.
      try session.setActive(true)
    } catch {
      return FlutterError(code: "platform.probe.failed", message: "Unable to configure AVAudioSession", details: nil)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func updateMediaSession(_ arguments: Any?) -> [String: Any] {
    guard let values = arguments as? [String: Any], let title = values["title"] as? String else {
      return ["supported": false, "reason": "media session title is required"]
    }
    configureRemoteCommands()
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyPlaybackRate: (values["playing"] as? Bool ?? false) ? 1.0 : 0.0,
    ]
    if let subtitle = values["subtitle"] as? String { info[MPMediaItemPropertyArtist] = subtitle }
    if let duration = values["durationSeconds"] as? NSNumber { info[MPMediaItemPropertyPlaybackDuration] = duration.doubleValue }
    if let position = values["positionSeconds"] as? NSNumber { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.doubleValue }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    return ["supported": true, "nowPlaying": true]
  }

  private func clearMediaSession() -> [String: Any] {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    remoteCommandTokens.forEach { $0.0.isEnabled = false; $0.0.removeTarget($0.1) }
    remoteCommandTokens.removeAll()
    #if DEBUG
    proofCommandHandlers.removeAll()
    #endif
    return ["supported": true, "cleared": true]
  }

  private func configureRemoteCommands() {
    guard remoteCommandTokens.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    center.skipForwardCommand.preferredIntervals = [30]
    center.skipBackwardCommand.preferredIntervals = [10]
    let handlers: [(MPRemoteCommand, (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = [
      (center.playCommand, { [weak self] _ in self?.emitMediaCommand("play"); return .success }),
      (center.pauseCommand, { [weak self] _ in self?.emitMediaCommand("pause"); return .success }),
      (center.togglePlayPauseCommand, { [weak self] _ in self?.emitMediaCommand("togglePlay"); return .success }),
      (center.stopCommand, { [weak self] _ in self?.emitMediaCommand("stop"); return .success }),
      (center.skipForwardCommand, { [weak self] _ in self?.emitMediaCommand("skipForward"); return .success }),
      (center.skipBackwardCommand, { [weak self] _ in self?.emitMediaCommand("skipBackward"); return .success }),
      (center.changePlaybackPositionCommand, { [weak self] event in
        guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
        self?.emitMediaCommand("seekTo", positionSeconds: event.positionTime)
        return .success
      }),
    ]
    let names = ["play", "pause", "togglePlay", "stop", "skipForward", "skipBackward", "seekTo"]
    for (index, entry) in handlers.enumerated() {
      let (command, handler) = entry
      command.isEnabled = true
      remoteCommandTokens.append((command, command.addTarget(handler: handler)))
      #if DEBUG
      proofCommandHandlers[names[index]] = (command, handler)
      #endif
    }
  }

  private func handleInterruption(_ note: Notification) {
    let info = note.userInfo ?? [:]
    guard let raw = info[AVAudioSessionInterruptionTypeKey] as? NSNumber,
          let type = AVAudioSession.InterruptionType(rawValue: raw.uintValue) else { return }
    if type == .began {
      // Kodi preserves whether playback was active before becoming inactive.
      interruptedPlaying = (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 1
      eventSink?(["event": "audioInterruptionBegan", "lossKind": "transient", "shouldResume": false])
    } else {
      let options = (info[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
      var resume = interruptedPlaying && (options & AVAudioSession.InterruptionOptions.shouldResume.rawValue) != 0
      interruptedPlaying = false
      if resume {
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { NSLog("platform_services: cannot reactivate interrupted audio: %@", error.localizedDescription); resume = false }
      }
      eventSink?(["event": "audioInterruptionEnded", "shouldResume": resume])
    }
  }

  // Kodi ios_reference 4.5: one mode per UIScreen.availableModes entry, refresh unknown (0.0),
  // applied by size (the built-in screen also matches width/height swapped).
  private func modeScreen() -> UIScreen {
    if rootController == nil { rootController = resolveController?() }
    return rootController?.view.window?.screen ?? UIScreen.main
  }

  private func displayModes() -> [String: Any] {
    let screen = modeScreen()
    let modes = screen.availableModes.map { mode -> [String: Any] in
      ["width": Int(mode.size.width), "height": Int(mode.size.height), "refreshHz": 0.0,
       "isCurrent": mode == screen.currentMode]
    }
    return ["supported": !modes.isEmpty, "modes": modes]
  }

  private func applyDisplayMode(_ arguments: Any?) -> [String: Any] {
    let screen = modeScreen()
    guard let values = arguments as? [String: Any], let width = (values["width"] as? NSNumber)?.intValue,
          let height = (values["height"] as? NSNumber)?.intValue else {
      return ["supported": false, "reason": "display mode arguments missing"]
    }
    let swap = screen === UIScreen.main
    guard let mode = screen.availableModes.first(where: {
      (Int($0.size.width) == width && Int($0.size.height) == height) ||
        (swap && Int($0.size.width) == height && Int($0.size.height) == width)
    }) else {
      NSLog("platform_services: No matching mode found for %dx%d", width, height)
      return ["supported": false, "reason": "no matching UIScreenMode for \(width)x\(height)"]
    }
    if screen.currentMode == mode { return ["supported": true, "switched": false, "reason": "mode already active"] }
    screen.currentMode = mode
    if screen.currentMode != mode {
      return ["supported": false, "reason": "UIScreen.currentMode did not take the requested mode"]
    }
    return ["supported": true, "switched": true]
  }

  private func displayScreens() -> [String: Any] {
    if rootController == nil { rootController = resolveController?() }
    var choices = ["": "Default", "Touchscreen": "Touchscreen"]
    if UIScreen.screens.count > 1 { choices["External"] = "External" }
    return ["supported": true, "choices": choices, "selected": selectedDisplay,
            "screenCount": UIScreen.screens.count,
            "windowOnTouchscreen": (rootController?.view.window?.screen ?? UIScreen.main) === UIScreen.main]
  }

  private func selectDisplay(_ id: String) -> Any {
    if rootController == nil { rootController = resolveController?() }
    let selected = id == "External" && UIScreen.screens.count < 2 ? "Touchscreen" : id
    if selected == "External" {
      guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.screen === UIScreen.screens[1] }),
        let controller = rootController, let main = controller.view.window else {
        return FlutterError(code: "platform.display.notReady", message: "External display is not ready", details: nil)
      }
      if externalWindow == nil {
        touchscreenWindow = main
        let window = UIWindow(windowScene: scene)
        main.rootViewController = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        externalWindow = window
      }
    } else if let window = externalWindow, let main = touchscreenWindow {
      let controller = window.rootViewController
      window.rootViewController = nil
      window.isHidden = true
      main.rootViewController = controller
      main.makeKeyAndVisible()
      externalWindow = nil
      touchscreenWindow = nil
    }
    selectedDisplay = selected
    return displayScreens()
  }

  private func completeDisplaySelection(_ id: String, result: @escaping FlutterResult, deadline: Date) {
    let value = selectDisplay(id)
    // UIScreen can connect before UIKit has attached its UIWindowScene.
    if let error = value as? FlutterError, error.code == "platform.display.notReady", Date() < deadline {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self else {
          result(FlutterError(code: "platform.display.disposed", message: "Display service closed", details: nil)); return
        }
        self.completeDisplaySelection(id, result: result, deadline: deadline)
      }
    } else { result(value) }
  }

  func screensChanged(disconnected: UIScreen? = nil) {
    if selectedDisplay == "External" && (UIScreen.screens.count < 2 || disconnected === externalWindow?.screen) {
      _ = selectDisplay("Touchscreen")
    }
    eventSink?(displayScreens().merging(["event": "displayScreensChanged"]) { _, new in new })
  }

  private func emitMediaCommand(_ command: String, positionSeconds: Double? = nil) {
    var payload: [String: Any] = ["event": "mediaCommand", "command": command]
    if let positionSeconds { payload["positionSeconds"] = positionSeconds }
    eventSink?(payload)
  }

  private func probeMedia(_ arguments: Any?) -> [String: Any] {
    guard let path = arguments as? String else {
      return ["supported": false, "reason": "media path is required"]
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let video = asset.tracks(withMediaType: .video).first
    let audio = asset.tracks(withMediaType: .audio).first
    let audioDescription: CMAudioFormatDescription? = audio?.formatDescriptions.first.map { $0 as! CMAudioFormatDescription }
    let asbd = audioDescription.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
    return [
      "supported": true,
      "durationMs": Int(asset.duration.seconds * 1000),
      "videoWidth": video.map { Int($0.naturalSize.width) } ?? 0,
      "videoHeight": video.map { Int($0.naturalSize.height) } ?? 0,
      "videoFrameRate": video?.nominalFrameRate ?? 0,
      "audioChannels": asbd.map { Int($0.mChannelsPerFrame) } ?? 0,
      "audioSampleRate": asbd.map { $0.mSampleRate } ?? 0,
      "audioFormats": asbd == nil ? [] : [["codec": "aac", "channels": Int(asbd!.mChannelsPerFrame), "sampleRate": asbd!.mSampleRate]],
      "codecs": video == nil ? [] : ["h264"],
    ]
  }

  private static func routeDescription() -> String {
    AVAudioSession.sharedInstance().currentRoute.outputs
      .map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
  }

  private func hardwareDecoders() -> [String] {
    var result: [String] = []
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) { result.append("h264") }
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) { result.append("hevc") }
    return result
  }
}
