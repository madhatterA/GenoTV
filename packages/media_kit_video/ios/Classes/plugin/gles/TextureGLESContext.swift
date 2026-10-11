public class TextureGLESContext {
  private let context: EAGLContext
  public let frameBuffer: GLuint
  #if targetEnvironment(simulator)
    private let renderBuffer: GLuint
  #else
    public let texture: CVOpenGLESTexture
  #endif
  public let pixelBuffer: CVPixelBuffer

  init(
    context: EAGLContext,
    textureCache: CVOpenGLESTextureCache,
    size: CGSize
  ) {
    self.context = context

    #if targetEnvironment(simulator)
      // Simulator CoreVideo cannot bind IOSurfaces to GLES textures (-6683).
      // Render with mpv's GL shaders, then transfer their result for Flutter.
      self.pixelBuffer = OpenGLESHelpers.createPixelBuffer(size)
      precondition(EAGLContext.setCurrent(context))
      defer { EAGLContext.setCurrent(nil) }
      var frameBuffer: GLuint = 0
      var renderBuffer: GLuint = 0
      glGenFramebuffers(1, &frameBuffer)
      glGenRenderbuffers(1, &renderBuffer)
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
      glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
      glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_RGBA8),
                            GLsizei(size.width), GLsizei(size.height))
      glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                GLenum(GL_RENDERBUFFER), renderBuffer)
      precondition(glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GL_FRAMEBUFFER_COMPLETE,
                   "Simulator GLES framebuffer")
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
      glBindRenderbuffer(GLenum(GL_RENDERBUFFER), 0)
      self.frameBuffer = frameBuffer
      self.renderBuffer = renderBuffer
    #else
    // Sometimes the frameBuffer created by `createFrameBuffer` has the status
    // `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`, which makes it unusable.
    // This seems to be because the pixelBuffer created by `createPixelBuffer`
    // appears to be invalid, with no way to prevent or detect this.
    // So we have to try several times to create a frameBuffer valid.
    // This is usually the case after the second attempt.
    for index in 0...3 {
      let pixelBuffer = OpenGLESHelpers.createPixelBuffer(size)

      let texture = OpenGLESHelpers.createTexture(
        textureCache,
        pixelBuffer,
        size
      )

      let frameBuffer = try? OpenGLESHelpers.createFrameBuffer(
        context: context,
        texture: texture,
        size: size
      )
      if frameBuffer != nil {
        self.pixelBuffer = pixelBuffer
        self.texture = texture
        self.frameBuffer = frameBuffer!
        return
      }

      OpenGLESHelpers.deletePixeBuffer(context, pixelBuffer)
      OpenGLESHelpers.deleteTexture(context, texture)
    }

    NSLog("TextureGLESContext: init: unable to create a valid frameBuffer")
    exit(1)
    #endif
  }

  public func prepareForPresentation() {
    #if targetEnvironment(simulator)
      precondition(CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess,
                   "Simulator pixel buffer lock")
      defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
      // libmpv resets GL bindings after rendering, so select this target again.
      var previousFramebuffer: GLint = 0
      glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &previousFramebuffer)
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
      defer { glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(previousFramebuffer)) }
      var previousRowLength: GLint = 0
      glGetIntegerv(GLenum(GL_PACK_ROW_LENGTH), &previousRowLength)
      glPixelStorei(GLenum(GL_PACK_ROW_LENGTH), GLint(CVPixelBufferGetBytesPerRow(pixelBuffer) / 4))
      glReadPixels(0, 0, GLsizei(CVPixelBufferGetWidth(pixelBuffer)),
                   GLsizei(CVPixelBufferGetHeight(pixelBuffer)), GLenum(GL_BGRA),
                   GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(pixelBuffer))
      glPixelStorei(GLenum(GL_PACK_ROW_LENGTH), previousRowLength)
      precondition(glGetError() == GL_NO_ERROR, "Simulator GLES readback")
    #endif
  }

  deinit {
    #if targetEnvironment(simulator)
      EAGLContext.setCurrent(context)
      var renderBuffer = renderBuffer
      glDeleteRenderbuffers(1, &renderBuffer)
      EAGLContext.setCurrent(nil)
    #else
    OpenGLESHelpers.deletePixeBuffer(context, pixelBuffer)
    OpenGLESHelpers.deleteTexture(context, texture)
    #endif
    OpenGLESHelpers.deleteFrameBuffer(context, frameBuffer)
  }
}
