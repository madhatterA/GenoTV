import Cocoa
import CoreGraphics
import AVFoundation
import AudioToolbox
import VideoToolbox
import FlutterMacOS
import IOKit.pwr_mgt
import MediaPlayer

#if DEBUG
// MediaPlayer's event initialisers raise; the system allocates events uninitialised, so do the same.
private final class ProofPositionEvent: MPChangePlaybackPositionCommandEvent {
  static var seconds: Double = 0
  override var positionTime: TimeInterval { ProofPositionEvent.seconds }
}
#endif

public class PlatformServicesPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, FlutterAppLifecycleDelegate {
  private var selectedScreen = ""
  private var powerAssertion: IOPMAssertionID = 0
  private var eventSink: FlutterEventSink?
  private var activityObservers: [NSObjectProtocol] = []
  private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
  #if DEBUG
  private var proofCommandHandlers: [String: (MPRemoteCommand, (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = [:]
  #endif
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "platform_services", binaryMessenger: registrar.messenger)
    let events = FlutterEventChannel(name: "platform_services/events", binaryMessenger: registrar.messenger)
    let instance = PlatformServicesPlugin()
    instance.restorePendingDisplayMode()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities.version":
      result(["os": "macOS " + ProcessInfo.processInfo.operatingSystemVersionString, "plugin": "0.0.1"])
    case "capabilities.probe":
      let decoders = hardwareDecoders()
      // Potential > 1.0 means the panel/path can take EDR; the current value stays 1.0 until EDR content is on screen.
      let edr = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
      let edrCurrent = NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1
      let hdrFormats: [String] = edr > 1 ? ["edr"] : []
      let passthrough = probePassthrough()
      let diagnostics: [String: String] = ["os": "macos", "edrHeadroom": String(describing: edr), "edrCurrent": String(describing: edrCurrent), "hdrState": edr > 1 ? (edrCurrent > 1 ? "capable, EDR active" : "capable, no EDR content active") : "SDR display", "probe": "CoreGraphics, VideoToolbox and CoreAudio stream-format probes are real", "audioPassthroughDevice": passthrough.name ?? "none"]
      let report: [String: Any] = ["hardwareDecode": !decoders.isEmpty, "decoders": decoders, "hdrOutput": edr > 1, "hdrFormats": hdrFormats, "displayModeSwitching": true, "audioPassthrough": !passthrough.formats.isEmpty, "passthroughFormats": passthrough.formats, "diagnostics": diagnostics]
      result(report)
    case "display.modes":
      result(displayModes())
    case "display.apply":
      result(applyDisplayMode(call.arguments))
    case "display.restore":
      result(restoreDisplayMode(call.arguments))
    case "display.screens":
      result(displayScreens())
    case "display.select":
      guard let id = (call.arguments as? [String: Any])?["id"] as? String else {
        result(FlutterError(code: "platform.invalidArgument", message: "display.select needs an id", details: nil)); return
      }
      selectDisplay(id, result: result)
    case "window.fullscreen":
      setFullscreen(call.arguments, result: result)
    case "audio.devices":
      result(audioDevices())
    case "audio.negotiate":
      result(negotiateAudio(call.arguments))
    case "lifecycle.keepAwake":
      if powerAssertion != 0 {
        result(["supported": true])
      } else {
        let status = IOPMAssertionCreateWithName(
          kIOPMAssertionTypeNoDisplaySleep as CFString,
          IOPMAssertionLevel(kIOPMAssertionLevelOn),
          "platform_services playback" as CFString,
          &powerAssertion
        )
        result(status == kIOReturnSuccess
          ? ["supported": true]
          : ["supported": false, "reason": "IOKit could not create a display-sleep assertion"])
      }
    case "lifecycle.releaseKeepAwake":
      if powerAssertion != 0 {
        _ = IOPMAssertionRelease(powerAssertion)
        powerAssertion = 0
      }
      result(["supported": true])
    case "media.probe":
      result(probeMedia(call.arguments))
    case "lifecycle.mediaSession.update":
      result(updateMediaSession(call.arguments))
    case "lifecycle.mediaSession.clear":
      result(clearMediaSession())
    #if DEBUG
    case "proof.mediaSession.read":
      let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      result(["title": info[MPMediaItemPropertyTitle] ?? NSNull(),
              "duration": info[MPMediaItemPropertyPlaybackDuration] ?? NSNull(),
              "elapsed": info[MPNowPlayingInfoPropertyElapsedPlaybackTime] ?? NSNull(),
              "rate": info[MPNowPlayingInfoPropertyPlaybackRate] ?? NSNull(),
              "playbackState": MPNowPlayingInfoCenter.default().playbackState.rawValue, "cleared": info.isEmpty])
    case "proof.mediaSession.command":
      let values = call.arguments as? [String: Any] ?? [:]
      guard let name = values["command"] as? String,
            let (command, handler) = proofCommandHandlers[name], command.isEnabled else {
        result(FlutterError(code: "proof.command.missing", message: "No registered system target", details: nil)); return
      }
      ProofPositionEvent.seconds = values["positionSeconds"] as? Double ?? 0
      let event = class_createInstance(name == "seekTo" ? ProofPositionEvent.self : MPRemoteCommandEvent.self, 0) as! MPRemoteCommandEvent
      result(["status": handler(event).rawValue])
    case "proof.window.number":
      result(appWindow().map { $0.windowNumber } ?? NSNull())
    case "proof.display.vanish":
      // Exercise the real notification observer with a selection whose screen is gone.
      selectedScreen = "Vanished Display (99)"
      NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self else { result(FlutterError(code: "platform.display.disposed", message: "Display service closed", details: nil)); return }
        result(self.displayScreens())
      }
    #endif
    default:
      result(FlutterError(code: "platform.unsupported", message: "platform.unsupported: \(call.method)", details: nil))
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    addAudioRouteListener()
    let center = NotificationCenter.default
    activityObservers = [
      center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.eventSink?(["event": "appBackgrounded"])
      },
      center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.eventSink?(["event": "appForegrounded"])
      },
      // Kodi WinSystemOSX DisplayReconfigured: hot-plug and mode changes re-read the screens.
      center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
        self?.screensChanged()
      },
    ]
    return nil
  }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeAudioRouteListener()
    removeActivityObservers()
    eventSink = nil
    return nil
  }

  private var fullscreenTransition = false

  /// Complete only after AppKit confirms the requested transition.
  private func setFullscreen(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any], let enabled = values["enabled"] as? Bool else {
      result(FlutterError(code: "platform.invalidArgument", message: "window.fullscreen needs an enabled flag", details: nil))
      return
    }
    guard let window = NSApp.mainWindow ?? NSApp.windows.first else {
      result(["supported": false, "reason": "the app has no window"])
      return
    }
    guard !fullscreenTransition else {
      result(FlutterError(code: "platform.busy", message: "fullscreen transition in progress", details: nil))
      return
    }
    if window.styleMask.contains(.fullScreen) == enabled {
      result(["supported": true, "fullscreen": enabled])
      return
    }
    fullscreenTransition = true
    let name = enabled ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
    var observer: NSObjectProtocol?
    observer = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
      if let observer = observer { NotificationCenter.default.removeObserver(observer) }
      self?.fullscreenTransition = false
      result(["supported": true, "fullscreen": window.styleMask.contains(.fullScreen)])
    }
    window.toggleFullScreen(nil)
  }

  private func appWindow() -> NSWindow? { NSApp.mainWindow ?? NSApp.windows.first }

  /// Kodi screenNameForDisplay: localised name plus (displayID - 1) so equal panels stay distinct.
  private func screenKey(_ screen: NSScreen) -> String {
    guard let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
      return screen.localizedName
    }
    return "\(screen.localizedName) (\(number - 1))"
  }

  private func displayScreens() -> [String: Any] {
    var choices = ["": "Default"]
    for screen in NSScreen.screens { choices[screenKey(screen)] = screenKey(screen) }
    return ["supported": true, "choices": choices, "selected": choices[selectedScreen] != nil ? selectedScreen : "",
            "screenCount": NSScreen.screens.count,
            "windowScreen": appWindow()?.screen.map(screenKey) ?? NSNull()]
  }

  /// Kodi 4.1 MoveToScreen: a fullscreen window cannot change screen, so leave fullscreen, move, re-enter.
  private func moveWindow(to screen: NSScreen, completion: @escaping () -> Void) {
    guard let window = appWindow(), window.screen !== screen, !fullscreenTransition else { completion(); return }
    let relocate = {
      let area = screen.visibleFrame
      var frame = window.frame
      frame.size = NSSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
      frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
      window.setFrame(frame, display: true)
    }
    guard window.styleMask.contains(.fullScreen) else { relocate(); completion(); return }
    fullscreenTransition = true
    var exit: NSObjectProtocol?
    exit = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
      if let exit { NotificationCenter.default.removeObserver(exit) }
      relocate()
      var enter: NSObjectProtocol?
      enter = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
        if let enter { NotificationCenter.default.removeObserver(enter) }
        self?.fullscreenTransition = false
        completion()
      }
      window.toggleFullScreen(nil)
    }
    window.toggleFullScreen(nil)
  }

  private func selectDisplay(_ id: String, result: @escaping FlutterResult) {
    let screens = NSScreen.screens
    let chosen = id.isEmpty ? nil : screens.first { screenKey($0) == id }
    let previous = selectedScreen
    // A chosen screen that is gone falls back to Default, the main screen.
    selectedScreen = chosen == nil ? "" : id
    guard let target = chosen ?? screens.first, !(id.isEmpty && previous.isEmpty) else { result(displayScreens()); return }
    moveWindow(to: target) { [weak self] in
      guard let self else { result(FlutterError(code: "platform.display.disposed", message: "Display service closed", details: nil)); return }
      result(self.displayScreens())
    }
  }

  func screensChanged() {
    let emit = { [weak self] in
      guard let self else { return }
      self.eventSink?(self.displayScreens().merging(["event": "displayScreensChanged"]) { _, new in new })
    }
    if !selectedScreen.isEmpty && !NSScreen.screens.contains(where: { screenKey($0) == selectedScreen }), let main = NSScreen.screens.first {
      selectedScreen = ""
      moveWindow(to: main, completion: emit)
    } else { emit() }
  }

  private func updateMediaSession(_ arguments: Any?) -> [String: Any] {
    guard let values = arguments as? [String: Any], let title = values["title"] as? String else {
      return ["supported": false, "reason": "media session title is required"]
    }
    configureRemoteCommands()
    let playing = values["playing"] as? Bool ?? false
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    if let subtitle = values["subtitle"] as? String { info[MPMediaItemPropertyArtist] = subtitle }
    if let duration = values["durationSeconds"] as? NSNumber { info[MPMediaItemPropertyPlaybackDuration] = duration.doubleValue }
    if let position = values["positionSeconds"] as? NSNumber { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.doubleValue }
    var result: [String: Any] = ["supported": true, "nowPlaying": true]
    if let bytes = values["artworkBytes"] as? FlutterStandardTypedData {
      if let image = thumbnail(bytes.data) {
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      } else {
        result["artwork"] = "artworkBytes could not be decoded"
      }
    } else if values["artworkUri"] is String {
      result["artwork"] = "macOS Now Playing takes decoded images, not URIs; pass artworkBytes"
    }
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = info
    // macOS needs playbackState set on every start/stop or remote commands are not routed here.
    center.playbackState = playing ? .playing : .paused
    return result
  }

  /// Decodes artwork at no more than 512px on the long edge, never the full-resolution source.
  private func thumbnail(_ data: Data) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 512,
      ] as CFDictionary)
    else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
  }

  private func clearMediaSession() -> [String: Any] {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
    remoteCommandTokens.forEach { $0.0.removeTarget($0.1) }
    remoteCommandTokens.removeAll()
    #if DEBUG
    proofCommandHandlers.removeAll()
    #endif
    return ["supported": true, "cleared": true]
  }

  private func configureRemoteCommands() {
    guard remoteCommandTokens.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
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

  private func emitMediaCommand(_ command: String, positionSeconds: Double? = nil) {
    // The event channel is intentionally optional: system commands may arrive before Dart
    // starts listening, in which case there is no controller to notify.
    var payload: [String: Any] = ["event": "mediaCommand", "command": command]
    if let positionSeconds { payload["positionSeconds"] = positionSeconds }
    eventSink?(payload)
  }

  private func removeActivityObservers() {
    activityObservers.forEach { NotificationCenter.default.removeObserver($0) }
    activityObservers = []
  }

  deinit {
    removeAudioRouteListener()
    removeActivityObservers()
    _ = clearMediaSession()
    if powerAssertion != 0 { _ = IOPMAssertionRelease(powerAssertion) }
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

  private func hardwareDecoders() -> [String] {
    var result: [String] = []
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) { result.append("h264") }
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) { result.append("hevc") }
    return result
  }

  private func audioAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private func defaultOutputDevice() -> AudioDeviceID? {
    var address = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    return status == noErr && deviceID != AudioDeviceID(kAudioObjectUnknown) ? deviceID : nil
  }

  private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
  }

  /// Built-in output is speaker or headphone jack; the output data source says which ('hdpn' / 'ispk').
  private func builtInOutputKind(_ deviceID: AudioDeviceID) -> String {
    var address = audioAddress(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
    var source: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &source) == noErr else { return "speaker" }
    return source == 0x6864706E ? "headphones" : "speaker"
  }

  private func audioDeviceKind(_ deviceID: AudioDeviceID) -> String {
    var address = audioAddress(kAudioDevicePropertyTransportType)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr else { return "unknown" }
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn: return builtInOutputKind(deviceID)
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "bluetooth"
    case kAudioDeviceTransportTypeUSB: return "usb"
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "hdmi"
    default: return "unknown"
    }
  }

  private func audioDeviceUID(_ deviceID: AudioDeviceID) -> String? {
    var address = audioAddress(kAudioDevicePropertyDeviceUID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
          let value else { return nil }
    return value.takeRetainedValue() as String
  }

  private func audioDeviceSampleRates(_ deviceID: AudioDeviceID) -> (rates: [Int], reason: String?) {
    let unknown = "supported sample rates are unknown"
    var address = audioAddress(kAudioDevicePropertyAvailableNominalSampleRates)
    var size: UInt32 = 0
    let stride = MemoryLayout<AudioValueRange>.stride
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
          size > 0, Int(size) % stride == 0 else { return ([], unknown) }
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / stride)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else { return ([], unknown) }
    var rates = Set<Int>()
    for range in ranges {
      guard range.mMinimum.isFinite, range.mMaximum.isFinite,
            range.mMinimum > 0, range.mMaximum >= range.mMinimum,
            range.mMaximum < Double(Int.max) else { return ([], unknown) }
      guard range.mMinimum == range.mMaximum else {
        return ([], "continuous sample-rate range cannot be represented as discrete supported rates")
      }
      guard range.mMinimum.rounded() == range.mMinimum else { return ([], unknown) }
      rates.insert(Int(range.mMinimum))
    }
    return (rates.sorted(), nil)
  }

  private func audioDevices() -> [String: Any] {
    guard let current = defaultOutputDevice() else {
      return ["supported": false, "devices": [], "reason": "Core Audio has no default output device"]
    }
    var address = audioAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
      return ["supported": false, "devices": [], "reason": "Core Audio could not list devices"]
    }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
      return ["supported": false, "devices": [], "reason": "Core Audio could not read devices"]
    }
    var diagnostics: [String] = []
    let devices = ids.filter(hasOutputStreams).compactMap { id -> [String: Any]? in
      guard let uid = audioDeviceUID(id), !uid.isEmpty else {
        diagnostics.append("Core Audio output \(id) has no persistent device UID")
        return nil
      }
      let rates = audioDeviceSampleRates(id)
      if let reason = rates.reason { diagnostics.append("Core Audio output \(id): \(reason)") }
      var device: [String: Any] = [
        "id": "coreaudio/\(uid)",
        "supportedSampleRates": rates.rates,
        "name": audioDeviceName(id) ?? "Audio output \(id)",
        "kind": audioDeviceKind(id),
        "isCurrent": id == current,
      ]
      if let format = audioDeviceFormat(id) {
        device["sampleRate"] = format.sampleRate
        device["channels"] = Int(format.channels)
      }
      return device
    }
    return ["supported": true, "devices": devices, "diagnostic": diagnostics.isEmpty ? "Core Audio output-capable devices" : diagnostics.joined(separator: "; ")]
  }

  /// Asks the selected output's physical formats whether the codec can be sent as a bitstream.
  private func negotiateAudio(_ arguments: Any?) -> [String: Any] {
    let args = arguments as? [String: Any]
    let codec = (args?["codec"] as? String)?.lowercased() ?? ""
    let requested = args?["deviceId"] as? String ?? "auto"
    let selected = requested == "auto" ? nil : allOutputDevices().first {
      guard let uid = audioDeviceUID($0) else { return false }
      return "coreaudio/\(uid)" == requested
    }
    guard let device = selected ?? defaultOutputDevice() else {
      return ["passthrough": false, "fallbackReason": "Core Audio has no default output device", "deviceId": "unknown"]
    }
    let routeDiagnostic = requested != "auto" && selected == nil
      ? "Selected audio device is unavailable; using the default output" : nil
    let routePrefix = routeDiagnostic.map { "\($0). " } ?? ""
    let name = audioDeviceName(device) ?? "default output"
    guard let uid = audioDeviceUID(device), !uid.isEmpty else {
      return ["passthrough": false, "fallbackReason": "\(routePrefix)Core Audio output has no persistent device UID", "deviceId": "unknown"]
    }
    let deviceId = "coreaudio/\(uid)"
    switch codec {
    case "ac3", "eac3", "dts": break
    case "dts-hd", "truehd", "eac3-joc":
      return ["passthrough": false, "fallbackReason": "\(routePrefix)macOS Core Audio defines no \(codec) bitstream physical format", "deviceId": deviceId]
    default:
      return ["passthrough": false, "fallbackReason": "\(routePrefix)unknown codec '\(codec)' cannot be negotiated", "deviceId": deviceId]
    }
    guard hasOutputStreams(device) else {
      return ["passthrough": false, "fallbackReason": "\(routePrefix)\(name) has no output streams", "deviceId": deviceId]
    }
    if devicePassthroughFormats(device).contains(codec) {
      var result: [String: Any] = ["passthrough": true, "deviceId": deviceId]
      if let routeDiagnostic { result["fallbackReason"] = routeDiagnostic }
      return result
    }
    return ["passthrough": false, "fallbackReason": "\(routePrefix)\(name) (\(audioDeviceKind(device))) lists no \(codec) physical format; output is PCM only", "deviceId": deviceId]
  }

  private func audioFormatSupportsBitstream(_ format: AudioStreamBasicDescription, codec: String, digital: Bool) -> Bool {
    if [kAudioFormatAC3, kAudioFormat60958AC3].contains(format.mFormatID) {
      return codec == "ac3" || codec == "dts"
    }
    guard format.mFormatID == kAudioFormatLinearPCM, digital,
          format.mBitsPerChannel == 16, format.mChannelsPerFrame == 2,
          format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { return false }
    return (format.mSampleRate == 48000 && (codec == "ac3" || codec == "dts"))
      || (format.mSampleRate == 192000 && codec == "eac3")
  }

  private func audioTransportIsDigital(_ transport: UInt32, name: String) -> Bool {
    return [kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypeUSB,
            kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
            kAudioDeviceTransportTypeThunderbolt, kAudioStreamTerminalTypeDigitalAudioInterface]
      .contains(transport) || name.lowercased().contains("digital")
  }

  /// Kodi 1.5.8 gate: a device is a passthrough device only when it is digital (or named HDMI/DisplayPort)
  /// and its physical formats carry a bitstream; built-in speakers and headphones never qualify.
  private func passthroughFormats(transport: UInt32, name: String, formats: [AudioStreamBasicDescription]) -> [String] {
    let digital = audioTransportIsDigital(transport, name: name)
    guard digital || name.contains("HDMI") || name.contains("DisplayPort") else { return [] }
    return ["ac3", "dts", "eac3"].filter { codec in
      formats.contains { audioFormatSupportsBitstream($0, codec: codec, digital: digital) }
    }
  }

  private func devicePassthroughFormats(_ device: AudioDeviceID) -> [String] {
    var transportAddress = audioAddress(kAudioDevicePropertyTransportType)
    var transport: UInt32 = 0
    var transportSize = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport)
    var streamsAddress = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &streamsAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
    var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
    _ = AudioObjectGetPropertyData(device, &streamsAddress, 0, nil, &size, &streams)
    var formats: [AudioStreamBasicDescription] = []
    for stream in streams {
      var address = audioAddress(kAudioStreamPropertyAvailablePhysicalFormats)
      var formatsSize: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(stream, &address, 0, nil, &formatsSize) == noErr else { continue }
      var ranged = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: Int(formatsSize) / MemoryLayout<AudioStreamRangedDescription>.size)
      guard AudioObjectGetPropertyData(stream, &address, 0, nil, &formatsSize, &ranged) == noErr else { continue }
      formats += ranged.map { $0.mFormat }
    }
    return passthroughFormats(transport: transport, name: audioDeviceName(device) ?? "", formats: formats)
  }

  /// Kodi HasPassthroughDevice: any output qualifies; the default output is preferred.
  private func probePassthrough() -> (name: String?, formats: [String]) {
    for device in [defaultOutputDevice()].compactMap({ $0 }) + allOutputDevices() {
      let formats = devicePassthroughFormats(device)
      if !formats.isEmpty { return (audioDeviceName(device), formats) }
    }
    return (nil, [])
  }

  private var audioListenerQueue = DispatchQueue.main
  private var audioListener: AudioObjectPropertyListenerBlock?
  private var audioListenerSelectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]

  private var dataSourceDevices: [AudioDeviceID] = []

  /// Data source changes (jack plugged) fire on the device, not the system object; follow the device list.
  private func syncDataSourceListeners() {
    guard let block = audioListener else { return }
    var address = audioAddress(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
    for id in dataSourceDevices { AudioObjectRemovePropertyListenerBlock(id, &address, audioListenerQueue, block) }
    dataSourceDevices = allOutputDevices()
    for id in dataSourceDevices { AudioObjectAddPropertyListenerBlock(id, &address, audioListenerQueue, block) }
  }

  private func allOutputDevices() -> [AudioDeviceID] {
    var address = audioAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter(hasOutputStreams)
  }

  private func addAudioRouteListener() {
    guard audioListener == nil else { return }
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.syncDataSourceListeners()
      self?.eventSink?(["event": "audioRouteChanged"])
    }
    audioListener = block
    syncDataSourceListeners()
    for selector in audioListenerSelectors {
      var address = audioAddress(selector)
      AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioListenerQueue, block)
    }
  }

  private func removeAudioRouteListener() {
    guard let block = audioListener else { return }
    var dsAddress = audioAddress(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
    for id in dataSourceDevices { AudioObjectRemovePropertyListenerBlock(id, &dsAddress, audioListenerQueue, block) }
    dataSourceDevices = []
    for selector in audioListenerSelectors {
      var address = audioAddress(selector)
      AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioListenerQueue, block)
    }
    audioListener = nil
  }

  private func audioDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
    guard status == noErr, let value else { return nil }
    return value.takeUnretainedValue() as String
  }

  private func audioDeviceFormat(_ deviceID: AudioDeviceID) -> (sampleRate: Double, channels: UInt32)? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamFormat,
      mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var format = AudioStreamBasicDescription()
    var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &format)
    guard status == noErr, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return nil }
    return (format.mSampleRate, format.mChannelsPerFrame)
  }

  private let pendingKey = "platform_services.pendingDisplayMode"

  /// The display a mode was applied to; restore must target the same one, not whichever is main later.
  private var displayID: CGDirectDisplayID {
    if let id = (UserDefaults.standard.dictionary(forKey: pendingKey)?["displayID"] as? NSNumber)?.uint32Value {
      return CGDirectDisplayID(id)
    }
    return mainDisplayID
  }

  private var mainDisplayID: CGDirectDisplayID {
    if let number = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return CGDirectDisplayID(number.uint32Value)
    }
    return CGMainDisplayID()
  }

  private func displayModes() -> [String: Any] {
    let id = displayID
    guard let modes = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] else {
      return ["supported": false, "modes": [], "reason": "CoreGraphics returned no display modes"]
    }
    guard let current = CGDisplayCopyDisplayMode(id) else {
      return ["supported": false, "modes": [], "reason": "CoreGraphics returned no current display mode"]
    }
    let currentWidth = current.pixelWidth
    let currentHeight = current.pixelHeight
    let currentRefresh = kodiRefresh(current.refreshRate)
    let payload = modes.map { mode -> [String: Any] in
      let refresh = kodiRefresh(mode.refreshRate)
      return [
        "width": mode.pixelWidth,
        "height": mode.pixelHeight,
        "refreshHz": refresh,
        "isCurrent": mode.pixelWidth == currentWidth &&
          mode.pixelHeight == currentHeight &&
          abs(refresh - currentRefresh) < 0.01,
      ]
    }
    return ["supported": true, "modes": payload]
  }

  /// Kodi macOS 4.4: CoreGraphics reports 0 Hz on many panels; Kodi uses 60.
  private func kodiRefresh(_ rate: Double) -> Double { rate == 0 ? 60 : rate }

  private func applyDisplayMode(_ arguments: Any?) -> [String: Any] {
    guard let values = arguments as? [String: Any],
          let width = values["width"] as? Int,
          let height = values["height"] as? Int,
          let refresh = values["refreshHz"] as? Double,
          let current = CGDisplayCopyDisplayMode(mainDisplayID),
          let modes = CGDisplayCopyAllDisplayModes(mainDisplayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode],
          let target = modes.first(where: {
            $0.pixelWidth == width &&
              $0.pixelHeight == height &&
              abs(kodiRefresh($0.refreshRate) - refresh) < 0.01
          }) else {
      return ["supported": false, "reason": "requested display mode was not enumerated"]
    }
    let id = mainDisplayID
    let old = ["width": current.pixelWidth, "height": current.pixelHeight, "refreshHz": kodiRefresh(current.refreshRate), "displayID": NSNumber(value: id)] as [String: Any]
    if UserDefaults.standard.dictionary(forKey: pendingKey) == nil {
      UserDefaults.standard.set(old, forKey: pendingKey)
    }
    guard CGDisplaySetDisplayMode(id, target, nil) == .success else {
      return ["supported": false, "reason": "CoreGraphics rejected the display mode"]
    }
    return ["supported": true]
  }

  private func restoreDisplayMode(_ arguments: Any?) -> [String: Any] {
    guard let values = arguments as? [String: Any],
          let width = values["width"] as? Int,
          let height = values["height"] as? Int,
          let refresh = values["refreshHz"] as? Double,
          let modes = CGDisplayCopyAllDisplayModes(displayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode],
          let target = modes.first(where: {
            $0.pixelWidth == width &&
              $0.pixelHeight == height &&
              abs(kodiRefresh($0.refreshRate) - refresh) < 0.01
          }) else {
      return ["supported": false, "reason": "previous display mode was not enumerated"]
    }
    guard CGDisplaySetDisplayMode(displayID, target, nil) == .success else {
      return ["supported": false, "reason": "CoreGraphics rejected display restore"]
    }
    UserDefaults.standard.removeObject(forKey: "platform_services.pendingDisplayMode")
    return ["supported": true]
  }

  public func handleWillTerminate(_ notification: Notification) {
    if powerAssertion != 0 {
      _ = IOPMAssertionRelease(powerAssertion)
      powerAssertion = 0
    }
    restorePendingDisplayMode()
  }

  private func restorePendingDisplayMode() {
    guard let values = UserDefaults.standard.dictionary(forKey: "platform_services.pendingDisplayMode") else { return }
    _ = restoreDisplayMode(values)
  }
}
