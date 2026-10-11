import Cocoa
import FlutterMacOS

public class VideoSurfacePlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var instances: [Int: SurfaceInstance] = [:]
  private var nextId = 1

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "video_surface", binaryMessenger: registrar.messenger)
    let plugin = VideoSurfacePlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(SurfaceViewFactory(plugin: plugin), withId: "video_surface/view")
  }

  func view(for id: Int) -> NSView? { instances[id]?.view }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "create":
      guard let handle = args["handle"] as? Int else {
        return result(FlutterError(code: "bad_args", message: "handle required", details: nil))
      }
      do {
        let inst = try SurfaceInstance(handle: handle)
        let id = nextId
        nextId += 1
        instances[id] = inst
        inst.onScreenChange = { [weak self, weak inst] in
          guard let self, let inst else { return }
          self.channel.invokeMethod("screen", arguments: self.screen(id, inst))
        }
        inst.onError = { [weak self] message in
          self?.channel.invokeMethod("failed", arguments: ["id": id, "message": message])
        }
        result(screen(id, inst))
      } catch {
        result(FlutterError(code: "create_failed", message: "\(error)", details: nil))
      }
    case "dispose":
      guard let id = args["id"] as? Int, let inst = instances.removeValue(forKey: id) else {
        return result(FlutterError(code: "unknown_surface", message: "no such surface", details: nil))
      }
      inst.dispose()
      result(nil)
    case "source":
      guard let id = args["id"] as? Int, let inst = instances[id], let hdr = args["hdr"] as? Bool else {
        return result(FlutterError(code: "bad_args", message: "id and hdr required", details: nil))
      }
      inst.setHdrSource(hdr)
      result(nil)
    case "probe":
      guard let id = args["id"] as? Int, let inst = instances[id] else {
        return result(FlutterError(code: "unknown_surface", message: "no such surface", details: nil))
      }
      var s = screen(id, inst)
      s["peak"] = inst.peakValue()
      s["frames"] = inst.frames
      s["layerEdr"] = inst.view.metalLayer.wantsExtendedDynamicRangeContent
      result(s)
    case "screenEdr":
      let s = NSScreen.main
      result([
        "edr": Double(s?.maximumExtendedDynamicRangeColorComponentValue ?? 1),
        "potential": Double(s?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1),
      ])
    case "counters":
      result(SurfaceCounters.snapshot)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func screen(_ id: Int, _ inst: SurfaceInstance) -> [String: Any] {
    let e = inst.view.edr
    return ["id": id, "edr": e.current, "potential": e.potential, "headroom": e.headroom]
  }
}

final class SurfaceViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: VideoSurfacePlugin?
  init(plugin: VideoSurfacePlugin) { self.plugin = plugin }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let id = (args as? [String: Any])?["id"] as? Int ?? -1
    // The view is created by the "create" call; an unknown id gets an empty black view.
    return plugin?.view(for: id) ?? NSView()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
