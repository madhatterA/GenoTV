import Foundation
import UIKit
import OpenGLES

@main
struct GLESRegression {
  static func main() {
    let context = OpenGLESHelpers.createContext()
    let cache = OpenGLESHelpers.createTextureCache(context)
    for size in [CGSize(width: 7, height: 3), CGSize(width: 320, height: 180)] {
      let target = TextureGLESContext(context: context, textureCache: cache, size: size)
      precondition(EAGLContext.setCurrent(context))
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), target.frameBuffer)
      precondition(glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GL_FRAMEBUFFER_COMPLETE)
      glClearColor(1, 0.5, 0.25, 1)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
      target.prepareForPresentation()
      var restoredFramebuffer: GLint = -1
      glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &restoredFramebuffer)
      precondition(restoredFramebuffer == 0)
      precondition(CVPixelBufferLockBaseAddress(target.pixelBuffer, .readOnly) == kCVReturnSuccess)
      let pixels = CVPixelBufferGetBaseAddress(target.pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
      let stride = CVPixelBufferGetBytesPerRow(target.pixelBuffer)
      for y in 0..<Int(size.height) {
        for x in 0..<Int(size.width) {
          let offset = y * stride + x * 4
          precondition(abs(Int(pixels[offset]) - 64) <= 1)
          precondition(abs(Int(pixels[offset + 1]) - 128) <= 1)
          precondition(pixels[offset + 2] == 255 && pixels[offset + 3] == 255)
        }
      }
      CVPixelBufferUnlockBaseAddress(target.pixelBuffer, .readOnly)
      precondition(glGetError() == GL_NO_ERROR)
      EAGLContext.setCurrent(nil)
    }
    NSLog("PASS GLES render targets: 2 sizes, 0 skipped")
  }
}
