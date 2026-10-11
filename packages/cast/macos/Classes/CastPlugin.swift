import AVKit
import FlutterMacOS

/// Hosts AirPlayEngine for Dart: method channel `cast/airplay`, state events
/// on `cast/airplay/events`, and the system route picker as platform view
/// `cast/airplay-route-picker`.
public final class CastPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let engine = AirPlayEngine()
  private var sink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CastPlugin()
    let channel = FlutterMethodChannel(name: "cast/airplay", binaryMessenger: registrar.messenger)
    let events = FlutterEventChannel(name: "cast/airplay/events", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
    events.setStreamHandler(instance)
    instance.engine.onSnapshot = { [weak instance] s in instance?.sink?(s) }
    registrar.register(
      RoutePickerFactory(engine: instance.engine), withId: "cast/airplay-route-picker")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "prepare":
      guard let s = args?["url"] as? String, let url = URL(string: s) else {
        result(FlutterError(code: "bad_url", message: "prepare needs a url", details: nil))
        return
      }
      engine.prepare(url: url, startMs: args?["startMs"] as? Int ?? 0)
      result(nil)
    case "play": engine.play(); result(nil)
    case "pause": engine.pause(); result(nil)
    case "seek": engine.seek(ms: args?["positionMs"] as? Int ?? 0); result(nil)
    case "stop": engine.stop(); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

private final class RoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  let engine: AirPlayEngine
  init(engine: AirPlayEngine) { self.engine = engine }
  func create(withViewIdentifier viewId: Int64, arguments: Any?) -> NSView {
    engine.makeRoutePicker()
  }
}
