import Cocoa
import Metal
import QuartzCore

/// Live-object counters so teardown can be proven from outside (Phase proof, 50 cycles).
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

/// NSView whose backing layer is the EDR CAMetalLayer mpv presents on (wid). Flutter controls sit above it.
final class SurfaceView: NSView {
  var onGeometryChange: (() -> Void)?
  var onScreenChange: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    SurfaceCounters.add("views", 1)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  deinit { SurfaceCounters.add("views", -1) }

  var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

  override func makeBackingLayer() -> CALayer {
    let l = CAMetalLayer()
    l.device = MTLCreateSystemDefaultDevice()
    l.pixelFormat = .rgba16Float
    l.wantsExtendedDynamicRangeContent = true
    l.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    l.isOpaque = true
    l.backgroundColor = NSColor.black.cgColor
    l.presentsWithTransaction = false
    return l
  }

  private func updateDrawableSize() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = CGSize(
      width: max((bounds.width * scale).rounded(), 1), height: max((bounds.height * scale).rounded(), 1))
  }

  override func layout() {
    super.layout()
    updateDrawableSize()
    onGeometryChange?()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateDrawableSize()
    onGeometryChange?()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    if let w = window {
      NotificationCenter.default.addObserver(
        self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: w)
      NotificationCenter.default.addObserver(
        self, selector: #selector(screenChanged), name: NSWindow.didChangeOcclusionStateNotification, object: w)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification,
      object: nil)
    updateDrawableSize()
    onGeometryChange?()
    onScreenChange?()
  }

  @objc private func screenChanged() { onScreenChange?() }

  /// EDR headroom of the screen this view is on. `headroom` is what the display can show now
  /// (current once EDR is active, else the potential); 1.0 means SDR only.
  var edr: (current: Double, potential: Double, headroom: Double) {
    guard let s = window?.screen ?? NSScreen.main else { return (1, 1, 1) }
    let c = Double(s.maximumExtendedDynamicRangeColorComponentValue)
    let p = Double(s.maximumPotentialExtendedDynamicRangeColorComponentValue)
    return (c, p, c > 1 ? c : p)
  }
}

/// mpv owns the decoder, libplacebo renderer and MoltenVK swapchain; no frame crosses the CPU or Flutter.
final class SurfaceInstance {
  let view = SurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
  private let api: MpvRenderApi
  private let mpvHandle: OpaquePointer?
  private var layerPointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(view.metalLayer).toOpaque() }
  private var hdrSource = false
  private var appliedHeadroom: Double?
  private var headroomTimer: Timer?
  private var disposed = false
  private var failed = false
  private var savedOptions: [(String, String)] = []
  var onScreenChange: (() -> Void)?
  /// Runtime failure after creation (renderer or mpv property); the owner reports it to Dart.
  var onError: ((String) -> Void)?

  init(handle: Int) throws {
    guard handle != 0 else { throw SurfaceError.metal("null player handle") }
    api = try MpvRenderApi()
    mpvHandle = OpaquePointer(bitPattern: handle)
    guard view.metalLayer.device != nil else { throw SurfaceError.metal("no system default device") }
    view.layoutSubtreeIfNeeded()
    let options = [
      ("wid", String(UInt(bitPattern: layerPointer))),
      ("gpu-api", "vulkan"), ("gpu-context", "iosvk"),
      ("vulkan-async-compute", "no"), ("vulkan-async-transfer", "no"),
      ("target-colorspace-hint", "yes"), ("target-trc", "linear"), ("target-prim", "display-p3"),
      ("target-peak", "auto"), ("target-contrast", "1750"),
      ("hwdec", "videotoolbox"), ("vid", "auto"), ("vo", "gpu-next"),
    ]
    savedOptions = try options.map { name, _ in
      guard let value = api.propertyString(mpvHandle, "options/\(name)") else {
        throw SurfaceError.metal("required engine option \(name) unavailable")
      }
      return (name, value)
    }
    guard api.setActive(layerPointer, 1) != 0 else {
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
    view.onScreenChange = { [weak self] in self?.screenChanged() }
    // ponytail: NSScreen posts nothing when EDR headroom changes (EDR activating, brightness),
    // so poll on the main run loop; replace if AppKit grows a notification.
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
    let headroom = hdrSource ? view.edr.headroom : 1
    if appliedHeadroom != headroom {
      do {
        try setProperty("target-peak", String(Int((headroom * 203).rounded())))
        appliedHeadroom = headroom
      } catch { fail(error); return }
    }
    onScreenChange?()
  }

  /// Falls back to the texture path: stop the native renderer, put the saved engine options back.
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
  var rendererStatus: Int32 { failed ? -1 : api.status(layerPointer) }
  var subtitle: (text: String, visible: String) {
    (api.getPropertyString(mpvHandle, "sub-text"), api.getPropertyString(mpvHandle, "sub-visibility"))
  }
  var target: (width: Int, height: Int, hwdec: String) {
    let size = view.metalLayer.drawableSize
    return (Int(size.width), Int(size.height), api.getPropertyString(mpvHandle, "hwdec-current"))
  }

  /// Cancel pending VO initialization before changing vo, and stop GPU work before releasing the view.
  func dispose() throws {
    guard !disposed else { return }
    disposed = true
    headroomTimer?.invalidate()
    headroomTimer = nil
    api.unregister(layerPointer)
    defer {
      SurfaceCounters.add("instances", -1)
      view.onGeometryChange = nil
      view.onScreenChange = nil
      onScreenChange = nil
      onError = nil
      view.removeFromSuperview()
      NotificationCenter.default.removeObserver(view)
    }
    if !failed { try setProperty("vo", "null") }
  }
}
