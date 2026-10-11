# Windows libmpv

Run from an MSYS2 MINGW64 shell, bounded:

```sh
timeout -k 10 7200 bash packages/playback/tool/build_libmpv_windows.sh
```

Tools: GCC/MinGW-w64, NASM, CMake, Meson, Ninja, pkg-config, autotools,
curl, tar, patch and make. Package managers supply these tools only. Every linked
engine dependency is built from the exact source commits recorded in
`native/windows/source-pins.txt`, matching the Android recipe's versions. GNU libiconv1.17 is additionally
built from its official release-source archive pinned by SHA256 in the same file.
No FFmpeg, font or TLS libraries from the tool installation are linked.

For an interrupted build where all dependencies and FFmpeg have finished
compiling, `--resume` verifies the cached source pins, installs FFmpeg, and
builds/packages mpv without repeating dependency compilation/configuration.
It fails if the source-built static iconv archive is absent. The default
command builds every dependency from source.

The cache defaults to `/tmp/vp-libmpv-windows`; override
`LIBMPV_WINDOWS_CACHE` in MSYS path syntax. `LIBMPV_WINDOWS_JOBS` defaults
to eight and is limited to sixteen. FFmpeg retains its built-in codecs,
demuxers, filters, D3D11VA/DXVA2 hardware acceleration, and the AC3 encoder.
mpv retains WASAPI, native OpenGL, libmpv's plain OpenGL render API,
and D3D11/DXVA2 ANGLE hardware-decoding interop. Only pinned EGL/KHR
header declarations are used at compile time; ANGLE is loaded dynamically.
The app rendering boundary is `VideoOutput::VideoOutput` in
`packages/media_kit_video/windows/video_output.cc`: it calls
`mpv_render_context_create` with `MPV_RENDER_API_TYPE_OPENGL` and ANGLE's
`eglGetProcAddress`. The `d3d11` Meson feature is a separate standalone VO
backend (pinned mpv `meson.build` lines984–992), requiring both shaderc and
SPIRV-Cross. It is disabled for this verified app rendering boundary;
the app's `plain-gl`, `egl-angle`, `d3d-hwaccel` and `d3d9-hwaccel` paths stay
enabled. No standalone shader compiler is added for that unused VO.

The runtime version suffix is `vp-windows-audio-1`.
The exact upstream FFmpeg compatibility patch
[effadce6](https://github.com/FFmpeg/FFmpeg/commit/effadce6c756247ea8bae32dc13bb3e6f464f0eb)
clips inline x86 shift constants for binutils ≥2.41; no assembler/codec is disabled.
Its SHA256 is recorded alongside the source and artifact hashes.

The local `media_kit_libs_windows_video` override retains the upstream plugin
API and pinned ANGLE packaging, replacing only its libmpv archive download.
ANGLE is the existing companion renderer; the local plugin keeps its
upstream packaging, following the Android/iOS override precedent.
The source-built DLL, import archive and public headers are copied to the
upstream CMake location used by `media_kit_video`. Missing outputs fail the
build instead of falling back to a prebuilt download.

`windows/libmpv/BUILD.txt` records source pins, source-archive, compatibility-patch and artifact
SHA256s, compiler versions, mpv feature configuration, FFmpeg configuration/filter/encoder lists, and DLL imports. The
recipe also performs a 0.1-second PCM → pan/aformat/aresample → AC3 encode.
Only that build-time check launches FFmpeg; the application remains one
process and ships only the engine DLL.

Context7: `/mpv-player/mpv`, queried 2026-10-09. Upstream
[compile-windows.md](https://github.com/mpv-player/mpv/blob/master/DOCS/compile-windows.md)
documents `-Dlibmpv=true -Ddefault_library=shared` and `ninja -C build
libmpv-2.dll`, and notes static subproject linkage when producing libmpv.
FFmpeg requires LGPLv3 (`--enable-version3`) because the pinned mbedTLS is
version 3; GPL remains disabled (`gpl=false`). Distribute dependency notices
and source as required.
