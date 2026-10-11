import Cocoa
import CoreVideo
import IOSurface
import Metal
import OpenGL.GL3
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

/// NSView whose backing layer is the EDR CAMetalLayer mpv's output is presented on.
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
    l.framebufferOnly = false
    l.isOpaque = true
    l.backgroundColor = NSColor.black.cgColor
    l.presentsWithTransaction = false
    return l
  }

  override func layout() {
    super.layout()
    onGeometryChange?()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
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

/// One mpv render context drawing into an IOSurface-backed half-float texture that is blitted
/// to the view's CAMetalLayer. All GL, mpv and Metal work runs on `queue`.
final class SurfaceInstance {
  let view = SurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
  private let api: MpvRenderApi
  private let queue = DispatchQueue(label: "video_surface.render")
  private let cgl: CGLContextObj
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let mpvHandle: OpaquePointer?
  private var scale: Float = 1
  private var decodeSrgb: Float = 1
  private var hdrSource = false
  private var applied: (hdr: Bool, headroom: Double)?
  private var headroomTimer: Timer?
  private var renderContext: OpaquePointer?
  private var surface: IOSurface?
  private var glTexture: GLuint = 0
  private var glFramebuffer: GLuint = 0
  private var metalTexture: MTLTexture?
  private var width = 0
  private var height = 0
  private(set) var framesRendered = 0
  var onScreenChange: (() -> Void)?
  /// Runtime failure after creation (resize, mpv property); the owner reports it to Dart.
  var onError: ((String) -> Void)?

  init(handle: Int) throws {
    api = try MpvRenderApi()
    guard let device = MTLCreateSystemDefaultDevice(), let cq = device.makeCommandQueue() else {
      throw SurfaceError.metal("no system default device")
    }
    commandQueue = cq
    pipeline = try SurfaceInstance.makePipeline(device)
    mpvHandle = OpaquePointer(bitPattern: handle)
    cgl = try SurfaceInstance.makeGLContext()
    SurfaceCounters.add("instances", 1)
    do {
      try setStaticProperties()
      applyOutput()
      try queue.sync { try createRenderContext(handle: mpvHandle) }
    } catch {
      SurfaceCounters.add("instances", -1)
      CGLDestroyContext(cgl)
      throw error
    }
    view.onGeometryChange = { [weak self] in self?.geometryChanged() }
    view.onScreenChange = { [weak self] in self?.screenChanged() }
    // ponytail: NSScreen posts nothing when EDR headroom changes (EDR activating, brightness),
    // so poll on the main run loop; replace if AppKit grows a notification.
    headroomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.screenChanged()
    }
  }

  private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    struct Params { float scale; float decodeSrgb; };
    vertex V vs(uint i [[vertex_id]]) {
      float2 p = float2((i << 1) & 2, i & 2);
      V o; o.pos = float4(p * 2 - 1, 0, 1); o.uv = float2(p.x, 1 - p.y); return o;
    }
    fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]],
                       constant Params &u [[buffer(0)]]) {
      constexpr sampler s(filter::nearest);
      float3 c = t.sample(s, in.uv).rgb;
      if (u.decodeSrgb > 0.5) {
        // Match the texture path's UNORM framebuffer clipping before decoding.
        c = clamp(c, 0.0, 1.0);
        c = select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
        // Linear sRGB -> linear Display P3 (D65), composed from CSS Color 4's XYZ matrices.
        c = float3x3(float3(0.822461969, 0.033194199, 0.017082631),
                     float3(0.177538031, 0.966805801, 0.072397441),
                     float3(0.0, 0.0, 0.910519929)) * c;
      }
      return float4(c * u.scale, 1);
    }
    """

  /// The extended-linear layer wants linear light with 1.0 = SDR white. HDR frames arrive linear
  /// relative to target-peak and are rescaled; SDR keeps the texture path's encoded output,
  /// interpreted as sRGB by Flutter, then decoded and converted to the layer's P3 primaries.
  private static func makePipeline(_ device: MTLDevice) throws -> MTLRenderPipelineState {
    let lib = try device.makeLibrary(source: shaderSource, options: nil)
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = lib.makeFunction(name: "vs")
    d.fragmentFunction = lib.makeFunction(name: "fs")
    d.colorAttachments[0].pixelFormat = .rgba16Float
    return try device.makeRenderPipelineState(descriptor: d)
  }

  private func setProperty(_ name: String, _ value: String) throws {
    let rc = api.setPropertyString(mpvHandle, name, value)
    guard rc >= 0 else { throw SurfaceError.mpv("set \(name)=\(value)", rc) }
  }

  private func setStaticProperties() throws {
    for (k, v) in [
      ("vo", "libmpv"), ("hwdec", "auto"), ("vid", "auto"),
    ] { try setProperty(k, v) }
  }

  /// Chooses HDR (linear, sized to the display headroom) or SDR (texture-compatible) output and the matching
  /// shader parameters.
  private func applyOutput() {
    let headroom = view.edr.headroom
    let hdr = hdrSource && headroom > 1
    if let a = applied, a.hdr == hdr, a.headroom == headroom { return }
    applied = (hdr, headroom)
    let peak = hdr ? String(Int((headroom * SurfaceInstance.referenceWhiteNits).rounded())) : "auto"
    do {
      // Preserve the texture renderer's SDR codes; explicit srgb converts BT.1886 first.
      try setProperty("target-trc", hdr ? "linear" : "auto")
      try setProperty("target-prim", hdr ? "display-p3" : "auto")
      try setProperty("target-peak", peak)
    } catch {
      fail(error)
    }
    queue.async { [self] in
      scale = Float(hdr ? headroom : 1)
      decodeSrgb = hdr ? 0 : 1
      renderFrame()
    }
  }

  /// Tells the surface whether the playing source is HDR (PQ/HLG).
  func setHdrSource(_ hdr: Bool) {
    hdrSource = hdr
    applyOutput()
  }

  private static let referenceWhiteNits = 203.0

  private func screenChanged() {
    applyOutput()
    onScreenChange?()
  }

  deinit {
    SurfaceCounters.add("instances", -1)
  }

  private static func makeGLContext() throws -> CGLContextObj {
    let attrs: [CGLPixelFormatAttribute] = [
      kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers,
      _CGLPixelFormatAttribute(rawValue: 0),
    ]
    var pf: CGLPixelFormatObj?
    var n: GLint = 0
    guard CGLChoosePixelFormat(attrs, &pf, &n) == kCGLNoError, let pixelFormat = pf else {
      throw SurfaceError.gl("no 3.2 core pixel format")
    }
    defer { CGLDestroyPixelFormat(pixelFormat) }
    var ctx: CGLContextObj?
    guard CGLCreateContext(pixelFormat, nil, &ctx) == kCGLNoError, let c = ctx else {
      throw SurfaceError.gl("CGLCreateContext failed")
    }
    SurfaceCounters.add("glContexts", 1)
    return c
  }

  private func createRenderContext(handle: OpaquePointer?) throws {
    CGLSetCurrentContext(cgl)
    defer { CGLSetCurrentContext(nil) }
    var apiName = Array("opengl".utf8CString)
    var initParams = MpvOpenGLInitParams(
      getProcAddress: { _, name in
        guard let name,
          let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
        else { return nil }
        return CFBundleGetFunctionPointerForName(
          bundle, CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue))
      },
      getProcAddressCtx: nil)
    var ctx: OpaquePointer?
    let rc = try withUnsafeMutablePointer(to: &initParams) { initPtr -> Int32 in
      try apiName.withUnsafeMutableBytes { apiPtr -> Int32 in
        var params = [
          MpvRenderParam(type: MpvRenderParamType.apiType, data: apiPtr.baseAddress),
          MpvRenderParam(type: MpvRenderParamType.openGLInitParams, data: UnsafeMutableRawPointer(initPtr)),
          MpvRenderParam(type: 0, data: nil),
        ]
        return params.withUnsafeMutableBytes { api.create(&ctx, handle, $0.baseAddress!) }
      }
    }
    guard rc >= 0 else { throw SurfaceError.mpv("mpv_render_context_create", rc) }
    renderContext = ctx
    api.setUpdateCallback(
      ctx,
      { p in
        let me = Unmanaged<SurfaceInstance>.fromOpaque(p!).takeUnretainedValue()
        me.queue.async { me.onUpdate() }
      }, Unmanaged.passUnretained(self).toOpaque())
  }

  private func fail(_ error: Error) {
    DispatchQueue.main.async { [self] in onError?("\(error)") }
  }

  private func geometryChanged() {
    let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let w = max(Int((view.bounds.width * scale).rounded()), 0)
    let h = max(Int((view.bounds.height * scale).rounded()), 0)
    view.metalLayer.contentsScale = scale
    queue.async { [self] in
      guard w > 0, h > 0, w != width || h != height else { return }
      do {
        try resizeTarget(w, h)
        renderFrame()
      } catch {
        fail(error)
      }
    }
  }

  private func releaseTarget() {
    CGLSetCurrentContext(cgl)
    if glFramebuffer != 0 { glDeleteFramebuffers(1, &glFramebuffer); glFramebuffer = 0 }
    if glTexture != 0 { glDeleteTextures(1, &glTexture); glTexture = 0 }
    CGLSetCurrentContext(nil)
    metalTexture = nil
    if surface != nil { SurfaceCounters.add("ioSurfaces", -1) }
    surface = nil
  }

  private func resizeTarget(_ w: Int, _ h: Int) throws {
    releaseTarget()
    guard let device = view.metalLayer.device else { throw SurfaceError.metal("layer has no device") }
    let rowBytes = (w * 8 + 63) / 64 * 64
    guard
      let s = IOSurface(properties: [
        .width: w, .height: h, .bytesPerElement: 8, .bytesPerRow: rowBytes,
        .pixelFormat: kCVPixelFormatType_64RGBAHalf,
      ])
    else { throw SurfaceError.metal("IOSurface \(w)x\(h) allocation failed") }
    surface = s
    SurfaceCounters.add("ioSurfaces", 1)

    CGLSetCurrentContext(cgl)
    defer { CGLSetCurrentContext(nil) }
    glGenTextures(1, &glTexture)
    glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), glTexture)
    let err = CGLTexImageIOSurface2D(
      cgl, GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_RGBA16F), GLsizei(w), GLsizei(h),
      GLenum(GL_RGBA), GLenum(GL_HALF_FLOAT), s, 0)
    guard err == kCGLNoError else { throw SurfaceError.gl("CGLTexImageIOSurface2D: \(err.rawValue)") }
    glGenFramebuffers(1, &glFramebuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), glFramebuffer)
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE), glTexture, 0)
    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    guard status == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
      throw SurfaceError.gl("framebuffer incomplete: \(status)")
    }

    let d = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
    d.usage = [.shaderRead]
    guard let t = device.makeTexture(descriptor: d, iosurface: s, plane: 0) else {
      throw SurfaceError.metal("makeTexture from IOSurface failed")
    }
    metalTexture = t
    width = w
    height = h
    view.metalLayer.drawableSize = CGSize(width: w, height: h)
  }

  private func onUpdate() {
    guard let ctx = renderContext else { return }
    if api.update(ctx) & mpvRenderUpdateFrame != 0 { renderFrame() }
  }

  private func renderFrame() {
    guard let ctx = renderContext, glFramebuffer != 0, let src = metalTexture else { return }
    CGLSetCurrentContext(cgl)
    var fbo = MpvOpenGLFbo(
      fbo: Int32(glFramebuffer), w: Int32(width), h: Int32(height), internalFormat: Int32(GL_RGBA16F))
    withUnsafeMutablePointer(to: &fbo) { fboPtr in
      var params = [
        MpvRenderParam(type: MpvRenderParamType.openGLFbo, data: UnsafeMutableRawPointer(fboPtr)),
        MpvRenderParam(type: 0, data: nil),
      ]
      _ = params.withUnsafeMutableBytes { api.render(ctx, $0.baseAddress!) }
    }
    glFinish()
    CGLSetCurrentContext(nil)

    guard let drawable = view.metalLayer.nextDrawable(), let cmd = commandQueue.makeCommandBuffer()
    else { return }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
    var params = [scale, decodeSrgb]
    enc.setRenderPipelineState(pipeline)
    enc.setFragmentTexture(src, index: 0)
    enc.setFragmentBytes(&params, length: MemoryLayout<Float>.size * 2, index: 0)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
    cmd.waitUntilCompleted()
    api.reportSwap(ctx)
    framesRendered += 1
  }

  /// Sampled presented linear peak for HDR/grayscale SDR (1.0 = SDR white).
  /// For colored SDR this is an upper bound: sampling omits the shader's sRGB-to-P3 matrix.
  func peakValue() -> Double {
    var peak = 0.0
    queue.sync { peak = scanPeak() }
    return peak
  }

  /// IEEE half to float; Float16 is unavailable in the x86_64 macOS slice.
  private static func halfToFloat(_ h: UInt16) -> Float {
    let sign: Float = h & 0x8000 != 0 ? -1 : 1
    let exp = Int((h >> 10) & 0x1F)
    let man = Float(h & 0x3FF)
    if exp == 0 { return sign * man * 0x1p-24 }
    if exp == 31 { return man == 0 ? sign * .infinity : .nan }
    return sign * (1 + man / 1024) * Float(sign: .plus, exponent: exp - 15, significand: 1)
  }

  private func scanPeak() -> Double {
    guard let s = surface else { return 0 }
    s.lock(options: .readOnly, seed: nil)
    defer { s.unlock(options: .readOnly, seed: nil) }
    let base: UnsafeMutableRawPointer = s.baseAddress
    let rowBytes: Int = s.bytesPerRow
    var peak: Float = 0
    for y in stride(from: 0, to: height, by: 4) {
      let row = (base + y * rowBytes).assumingMemoryBound(to: UInt16.self)
      for x in stride(from: 0, to: width, by: 4) {
        for c in 0..<3 {
          let v = SurfaceInstance.halfToFloat(row[x * 4 + c])
          if v > peak { peak = v }
        }
      }
    }
    if decodeSrgb > 0.5 {
      peak = min(max(peak, 0), 1)
      return Double(peak <= 0.04045 ? peak / 12.92 : powf((peak + 0.055) / 1.055, 2.4))
    }
    return Double(peak * scale)
  }

  var frames: Int {
    var n = 0
    queue.sync { n = framesRendered }
    return n
  }

  /// Frees the mpv render context (must precede Player.dispose) and every GL/Metal resource.
  func dispose() {
    headroomTimer?.invalidate()
    headroomTimer = nil
    queue.sync {
      if let ctx = renderContext {
        api.setUpdateCallback(ctx, nil, nil)
        CGLSetCurrentContext(cgl)
        api.free(ctx)
        CGLSetCurrentContext(nil)
        renderContext = nil
      }
      releaseTarget()
      CGLDestroyContext(cgl)
      SurfaceCounters.add("glContexts", -1)
    }
    view.onGeometryChange = nil
    view.onScreenChange = nil
    onScreenChange = nil
    onError = nil
    DispatchQueue.main.async { [view] in
      view.removeFromSuperview()
      NotificationCenter.default.removeObserver(view)
    }
  }
}
