import Flutter
import UIKit

public class VideoSurfacePlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var instances: [Int: SurfaceInstance] = [:]
  private var nextId = 1

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "video_surface", binaryMessenger: registrar.messenger())
    let plugin = VideoSurfacePlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(SurfaceViewFactory(plugin: plugin), withId: "video_surface/view")
  }

  func view(for id: Int) -> UIView? { instances[id]?.view }

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
        inst.onError = { [weak self] message in
          self?.channel.invokeMethod("failed", arguments: ["id": id, "message": message])
        }
        inst.onScreenChange = { [weak self, weak inst] in
          guard let self, let inst else { return }
          self.channel.invokeMethod("screen", arguments: self.screen(id, inst))
        }
        result(screen(id, inst))
      } catch {
        result(FlutterError(code: "create_failed", message: "\(error)", details: nil))
      }
    case "dispose":
      guard let id = args["id"] as? Int, let inst = instances.removeValue(forKey: id) else {
        return result(FlutterError(code: "unknown_surface", message: "no such surface", details: nil))
      }
      do {
        try inst.dispose()
        result(nil)
      } catch {
        result(FlutterError(code: "dispose_failed", message: "\(error)", details: nil))
      }
    case "source":
      guard let id = args["id"] as? Int, let inst = instances[id], let hdr = args["hdr"] as? Bool else {
        return result(FlutterError(code: "bad_args", message: "id and hdr required", details: nil))
      }
      do {
        try inst.setHdrSource(hdr)
        result(nil)
      } catch {
        result(FlutterError(code: "source_failed", message: "\(error)", details: nil))
      }
    case "probe":
      guard let id = args["id"] as? Int, let inst = instances[id] else {
        return result(FlutterError(code: "unknown_surface", message: "no such surface", details: nil))
      }
      var s = screen(id, inst)
      let t = inst.target
      s["frames"] = inst.frames
      s["suspended"] = inst.isSuspended
      s["rendererStatus"] = inst.rendererStatus
      s["layerEdr"] = inst.edrEnabled
      s["layerClass"] = String(describing: type(of: inst.view.layer))
      s["colorspace"] = inst.view.metal.colorspace?.name as String? ?? ""
      s["pixelFormat"] = inst.view.metal.pixelFormat == .rgba16Float ? "rgba16Float" : "\(inst.view.metal.pixelFormat.rawValue)"
      s["drawableW"] = t.width
      s["drawableH"] = t.height
      s["hwdec"] = t.hwdec
      s["copyPath"] = "Vulkan direct"
      s["cpuReadback"] = false
      s["readbackBytes"] = 0
      let subtitle = inst.subtitle
      s["subtitleText"] = subtitle.text
      s["subtitleVisible"] = subtitle.visible
      s["inWindow"] = inst.view.window != nil
      result(s)
    case "screenEdr":
      var e = (1.0, 1.0)
      #if !os(tvOS) // tvOS has no EDR headroom API (HDR is display-criteria matching, ch03 p02)
      if #available(iOS 16.0, *) {
        e = (Double(UIScreen.main.currentEDRHeadroom), Double(UIScreen.main.potentialEDRHeadroom))
      }
      #endif
      result(["edr": e.0, "potential": e.1])
    case "counters":
      do {
        result(SurfaceCounters.snapshot.merging(["rendererContexts": Int(try MpvRenderApi().liveCount())]) { _, new in new })
      } catch {
        result(FlutterError(code: "probe_failed", message: "\(error)", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

extension VideoSurfacePlugin {
  fileprivate func screen(_ id: Int, _ inst: SurfaceInstance) -> [String: Any] {
    let e = inst.view.edr
    return ["id": id, "edr": e.current, "potential": e.potential, "headroom": e.headroom]
  }
}

final class SurfaceViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: VideoSurfacePlugin?
  init(plugin: VideoSurfacePlugin) { self.plugin = plugin }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let id = (args as? [String: Any])?["id"] as? Int ?? -1
    return HostedView(plugin?.view(for: id) ?? UIView())
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class HostedView: NSObject, FlutterPlatformView {
  private let v: UIView
  init(_ v: UIView) { self.v = v }
  func view() -> UIView { v }
}
