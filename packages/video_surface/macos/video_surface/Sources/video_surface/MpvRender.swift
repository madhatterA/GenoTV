import Foundation

// mpv render-API surface used by this plugin, resolved from the libmpv media_kit has already loaded (Mpv.framework, mpv 0.36). Layouts mirror mpv/render.h and
// mpv/render_gl.h; resolving by symbol avoids linking or vendoring a second libmpv.

struct MpvRenderParam {
  var type: Int32
  var data: UnsafeMutableRawPointer?
}

struct MpvOpenGLInitParams {
  var getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
  var getProcAddressCtx: UnsafeMutableRawPointer?
}

struct MpvOpenGLFbo {
  var fbo: Int32
  var w: Int32
  var h: Int32
  var internalFormat: Int32
}

enum MpvRenderParamType {
  static let apiType: Int32 = 1
  static let openGLInitParams: Int32 = 2
  static let openGLFbo: Int32 = 3
}

let mpvRenderUpdateFrame: UInt64 = 1

struct MpvRenderApi {
  typealias Create = @convention(c) (
    UnsafeMutablePointer<OpaquePointer?>, OpaquePointer?, UnsafeMutableRawPointer
  ) -> Int32
  typealias SetUpdateCallback = @convention(c) (
    OpaquePointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?
  ) -> Void
  typealias Update = @convention(c) (OpaquePointer?) -> UInt64
  typealias Render = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer) -> Int32
  typealias ReportSwap = @convention(c) (OpaquePointer?) -> Void
  typealias Free = @convention(c) (OpaquePointer?) -> Void
  typealias SetPropertyString = @convention(c) (
    OpaquePointer?, UnsafePointer<CChar>, UnsafePointer<CChar>
  ) -> Int32

  let create: Create
  let setUpdateCallback: SetUpdateCallback
  let update: Update
  let render: Render
  let reportSwap: ReportSwap
  let free: Free
  let setPropertyString: SetPropertyString

  init() throws {
    // Same path media_kit opens; dlopen returns the already-loaded image.
    guard let lib = dlopen("Mpv.framework/Mpv", RTLD_LAZY) else {
      throw SurfaceError.mpvSymbolMissing("Mpv.framework")
    }
    func sym<T>(_ name: String, _ type: T.Type) throws -> T {
      guard let p = dlsym(lib, name) else {
        throw SurfaceError.mpvSymbolMissing(name)
      }
      return unsafeBitCast(p, to: type)
    }
    create = try sym("mpv_render_context_create", Create.self)
    setUpdateCallback = try sym("mpv_render_context_set_update_callback", SetUpdateCallback.self)
    update = try sym("mpv_render_context_update", Update.self)
    render = try sym("mpv_render_context_render", Render.self)
    reportSwap = try sym("mpv_render_context_report_swap", ReportSwap.self)
    free = try sym("mpv_render_context_free", Free.self)
    setPropertyString = try sym("mpv_set_property_string", SetPropertyString.self)
  }
}

enum SurfaceError: Error, CustomStringConvertible {
  case mpvSymbolMissing(String)
  case mpv(String, Int32)
  case gl(String)
  case metal(String)

  var description: String {
    switch self {
    case .mpvSymbolMissing(let n): return "libmpv symbol \(n) not found in process"
    case .mpv(let what, let code): return "\(what) failed with mpv error \(code)"
    case .gl(let m): return "OpenGL: \(m)"
    case .metal(let m): return "Metal: \(m)"
    }
  }
}
