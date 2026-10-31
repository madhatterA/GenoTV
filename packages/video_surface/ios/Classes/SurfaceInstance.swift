import Metal
import QuartzCore
import UIKit

/// Live-object counters for the open/close proof; engine contexts have their own counter.
enum SurfaceCounters {
  static let lock = NSLock()
  private static var counts: [String: Int] = [:]
  static func add(_ key: String, _ delta: Int) {
    lock.lock(); counts[key, default: 0] += delta; lock.unlock()
  }
  static var snapshot: [String: Int] {
    lock.lock(); defer { lock.unlock() }
    return counts
  }
}

/// Native Vulkan/Metal presentation. Flutter controls are composited above this view.
final class SurfaceView: UIView {
  override class var layerClass: AnyClass { CAMetalLayer.self }
  var metal: CAMetalLayer { layer as! CAMetalLayer }
  var onGeometryChange: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    metal.device = MTLCreateSystemDefaultDevice()
    metal.pixelFormat = .rgba16Float
    metal.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    #if !os(tvOS)
    if #available(iOS 16.0, *) { metal.wantsExtendedDynamicRangeContent = true }
    #endif
    metal.isOpaque = true
    metal.presentsWithTransaction = false
    backgroundColor = .black
    SurfaceCounters.add("views", 1)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
  deinit { SurfaceCounters.add("views", -1) }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let scale = window?.screen.scale ?? UIScreen.main.scale
    var drawableScale = scale
    #if os(tvOS)
    // The TV UI is drawn on a 960-wide canvas scaled up by Flutter (TvScale): size the
    // drawable by the pixels this view really covers, not by its unscaled bounds.
    if let window = window, bounds.width > 0 {
      drawableScale *= convert(bounds, to: window).width / bounds.width
    }
    #endif
    metal.contentsScale = scale
    metal.drawableSize = CGSize(width: bounds.width * drawableScale, height: bounds.height * drawableScale)
    onGeometryChange?()
  }

  var edr: (current: Double, potential: Double, headroom: Double) {
    #if os(tvOS)
    return (1, 1, 1)
    #else
    guard #available(iOS 16.0, *) else { return (1, 1, 1) }
    let screen = window?.screen ?? UIScreen.main
    let current = Double(screen.currentEDRHeadroom)
    let potential = Double(screen.potentialEDRHeadroom)
    return (current, potential, current > 1 ? current : potential)
    #endif
  }
}

/// mpv owns the decoder, libplacebo renderer and MoltenVK swapchain; no frame crosses the CPU or Flutter.
final class SurfaceInstance {
  let view = SurfaceView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
  private let api: MpvRenderApi
  private let mpvHandle: OpaquePointer?
  private var layerPointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(view.metal).toOpaque() }
  private var hdrSource = false
  private var appliedHeadroom: Double?
  private var headroomTimer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var disposed = false
  private var failed = false
  private var savedOptions: [(String, String)] = []
  private var suspended = false
  var onScreenChange: (() -> Void)?
  var onError: ((String) -> Void)?

  init(handle: Int) throws {
    guard handle != 0 else { throw SurfaceError.metal("null player handle") }
    api = try MpvRenderApi()
    mpvHandle = OpaquePointer(bitPattern: handle)
    guard view.metal.device != nil else { throw SurfaceError.metal("no system default device") }
    view.layoutSubviews()
    suspended = UIApplication.shared.applicationState != .active
    #if os(tvOS)
    // No EDR on tvOS: libplacebo picks the normal SDR swapchain and mpv matches it (the fp16 linear P3 path looked washed out).
    let (hint, trc, prim) = ("no", "auto", "auto")
    #else
    let (hint, trc, prim) = ("yes", "linear", "display-p3")
    #endif
    let options = [
        ("wid", String(UInt(bitPattern: layerPointer))),
        ("gpu-api", "vulkan"), ("gpu-context", "iosvk"),
        ("vulkan-async-compute", "no"), ("vulkan-async-transfer", "no"),
        ("target-colorspace-hint", hint), ("target-trc", trc), ("target-prim", prim), ("target-peak", "auto"),
        ("hwdec", "videotoolbox"), ("vid", "auto"), ("vo", "gpu-next"),
      ]
    savedOptions = try options.map { name, _ in
      guard let value = api.propertyString(mpvHandle, "options/\(name)") else {
        throw SurfaceError.metal("required engine option \(name) unavailable")
      }
      return (name, value)
    }
    guard api.setActive(layerPointer, suspended ? 0 : 1) != 0 else {
      throw SurfaceError.metal("surface registration failed")
    }
    do {
      for (name, value) in options { try setProperty(name, value) }
    } catch {
      api.unregister(layerPointer)
      do { try restoreOptions() } catch let restoreError {
        throw SurfaceError.metal("native setup: \(error); restore: \(restoreError)")
      }
      throw error
    }
    SurfaceCounters.add("instances", 1)
    view.onGeometryChange = { [weak self] in self?.screenChanged() }
    let center = NotificationCenter.default
    for (name, stop) in [
      (UIApplication.willResignActiveNotification, true), (UIApplication.didBecomeActiveNotification, false),
    ] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.setSuspended(stop)
      })
    }
    // shortcut: UIScreen has no EDR headroom notification; replace polling when UIKit adds one.
    headroomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.screenChanged()
    }
  }

  private func setProperty(_ name: String, _ value: String) throws {
    let rc = api.setPropertyString(mpvHandle, name, value)
    guard rc >= 0 else { throw SurfaceError.mpv("set \(name)=\(value)", rc) }
  }

  func setHdrSource(_ hdr: Bool) throws {
    guard !failed, !disposed else { throw SurfaceError.metal("native output unavailable") }
    hdrSource = hdr
    appliedHeadroom = nil
    screenChanged()
    if failed { throw SurfaceError.metal("native source configuration failed") }
  }

  private func screenChanged() {
    guard !disposed, !failed else { return }
    if api.status(layerPointer) < 0 {
      fail(SurfaceError.metal("native Vulkan renderer failed; see mpv log"))
      return
    }
    #if !os(tvOS)
    if !suspended {
      let headroom = hdrSource ? view.edr.headroom : 1
      if appliedHeadroom != headroom {
        do {
          try setProperty("target-peak", String(Int((headroom * 203).rounded())))
          appliedHeadroom = headroom
        } catch { fail(error); return }
      }
    }
    #endif
    onScreenChange?()
  }

  private func setSuspended(_ value: Bool) {
    guard !disposed, !failed else { return }
    // Engine mutex drains the entire draw+flip section before UIKit may enter the background.
    _ = api.setActive(layerPointer, value ? 0 : 1)
    suspended = value
    if !value { screenChanged() }
  }

  private func fail(_ error: Error) {
    failed = true
    api.unregister(layerPointer)
    do {
      try restoreOptions()
      onError?("\(error)")
    } catch let restoreError {
      onError?("\(error); restoring texture output: \(restoreError)")
    }
  }

  private func restoreOptions() throws {
    try setProperty("vo", "null")
    for (name, value) in savedOptions where name != "vo" { try setProperty(name, value) }
    if let vo = savedOptions.first(where: { $0.0 == "vo" }) { try setProperty(vo.0, vo.1) }
  }

  var frames: Int { Int(api.frameCount(layerPointer)) }
  var isSuspended: Bool { suspended }
  var rendererStatus: Int32 { failed ? -1 : api.status(layerPointer) }
  var subtitle: (text: String, visible: String) {
    (api.getPropertyString(mpvHandle, "sub-text"), api.getPropertyString(mpvHandle, "sub-visibility"))
  }
  var edrEnabled: Bool {
    #if os(tvOS)
    return false
    #else
    if #available(iOS 16.0, *) { return view.metal.wantsExtendedDynamicRangeContent }
    return false
    #endif
  }
  var target: (width: Int, height: Int, hwdec: String) {
    let size = view.metal.drawableSize
    return (Int(size.width), Int(size.height), api.getPropertyString(mpvHandle, "hwdec-current"))
  }

  /// Cancel pending VO initialization before changing vo, and stop GPU work before releasing the view.
  func dispose() throws {
    guard !disposed else { return }
    disposed = true
    headroomTimer?.invalidate()
    headroomTimer = nil
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    api.unregister(layerPointer)
    defer {
      SurfaceCounters.add("instances", -1)
      view.onGeometryChange = nil
      onScreenChange = nil
      onError = nil
      view.removeFromSuperview()
    }
    if !failed { try setProperty("vo", "null") }
  }
}
