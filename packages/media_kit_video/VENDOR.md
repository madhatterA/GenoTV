# Local media_kit_video 2.0.1

MIT upstream package from the pinned pub.dev 2.0.1 archive; LICENSE retained.
Selected through app/pubspec.yaml's dependency override (phase05 ruling,
2026-10-08). All non-iOS platform implementations stay upstream.

The iOS Simulator supports GLES3, but CoreVideo's IOSurface-to-GLES binding
returns -6683 for BGRA and NV12. Removing the simulator software-renderer
switch alone traps on the null CVOpenGLESTexture. The iOS GLES target instead
uses an RGBA8 renderbuffer and reads the GL shader output into the Metal-compatible
BGRA pixel buffer consumed by Flutter, respecting padded row strides. Device
rendering keeps the upstream zero-copy CoreVideo target. The pinned simulator
mpv engine's matching NV12 plane-upload patch lives in
../playback/tool/ios_sim_gl_upload.patch; VideoToolbox decode and GL tone mapping
remain active, without vo/ao/hwdec test overrides. That simulator-only patch also
refreshes pinned mpv's hardware-decoder-name cache after non-threaded decoding;
otherwise software fallback clears the borrowed name and hwdec-current is empty
until the graph returns.

Native regression: test/ios_gles_regression.swift renders two sizes (including
padded rows), checks every BGRA pixel and GL framebuffer/error state. Full
playback/HDR/seek/settings proof is app/integration_test/ios_video_display_test.dart.
Generated headers and dependency caches are excluded from version control.
