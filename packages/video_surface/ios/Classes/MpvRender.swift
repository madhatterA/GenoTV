import Foundation

/// Symbols from the pinned libmpv already loaded by media_kit, including the iOS Vulkan context.
final class MpvRenderApi {
  typealias SetPropertyString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
  typealias GetPropertyString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
  typealias MpvFree = @convention(c) (UnsafeMutableRawPointer?) -> Void
  typealias FrameCount = @convention(c) (UnsafeMutableRawPointer?) -> UInt64
  typealias SetActive = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
  typealias Status = @convention(c) (UnsafeMutableRawPointer?) -> Int32
  typealias Unregister = @convention(c) (UnsafeMutableRawPointer?) -> Void
  typealias LiveCount = @convention(c) () -> Int32

  private let library: UnsafeMutableRawPointer
  let setPropertyString: SetPropertyString
  private let getProperty: GetPropertyString
  private let mpvFree: MpvFree
  let frameCount: FrameCount
  let setActive: SetActive
  let status: Status
  let unregister: Unregister
  let liveCount: LiveCount

  init() throws {
    guard let lib = dlopen("Mpv.framework/Mpv", RTLD_LAZY) else {
      throw SurfaceError.mpvSymbolMissing("Mpv.framework")
    }
    library = lib
    func sym<T>(_ name: String, _ type: T.Type) throws -> T {
      guard let p = dlsym(lib, name) else { throw SurfaceError.mpvSymbolMissing(name) }
      return unsafeBitCast(p, to: type)
    }
    do {
      setPropertyString = try sym("mpv_set_property_string", SetPropertyString.self)
      getProperty = try sym("mpv_get_property_string", GetPropertyString.self)
      mpvFree = try sym("mpv_free", MpvFree.self)
      frameCount = try sym("mpv_ios_surface_frame_count", FrameCount.self)
      setActive = try sym("mpv_ios_surface_set_active", SetActive.self)
      status = try sym("mpv_ios_surface_status", Status.self)
      unregister = try sym("mpv_ios_surface_unregister", Unregister.self)
      liveCount = try sym("mpv_ios_surface_live_count", LiveCount.self)
    } catch {
      dlclose(lib)
      throw error
    }
  }

  deinit { dlclose(library) }

  func getPropertyString(_ handle: OpaquePointer?, _ name: String) -> String {
    propertyString(handle, name) ?? ""
  }

  func propertyString(_ handle: OpaquePointer?, _ name: String) -> String? {
    guard let p = getProperty(handle, name) else { return nil }
    defer { mpvFree(p) }
    return String(cString: p)
  }
}

enum SurfaceError: Error, CustomStringConvertible {
  case mpvSymbolMissing(String)
  case mpv(String, Int32)
  case metal(String)

  var description: String {
    switch self {
    case .mpvSymbolMissing(let n): return "libmpv symbol \(n) not found in process"
    case .mpv(let what, let code): return "\(what) failed with mpv error \(code)"
    case .metal(let message): return "Metal: \(message)"
    }
  }
}
