# Minimal FFmpeg source build

Build dependencies: Bash, curl, tar with xz support, SHA-256 tool, make and a C
toolchain/target SDK. No package-manager libraries are linked. Release tarball:
https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz, SHA256
`05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`.
FFmpeg's LGPLv2.1 license is copied alongside the installed build metadata.

```sh
packages/cast/tool/build_remux.sh
cd packages/cast
flutter test --no-pub --reporter=json
```

The artifact test discovers the default host install directory automatically; no
environment variable is required. Missing artifacts fail the test, never skip.

Produces PIC static `libavformat.a`, `libavcodec.a`, `libavutil.a` plus headers
under `native/ffmpeg/<platform>-<arch>/` (ignored). This phase does not embed or
link them into the app; the later remux phase owns that integration. Source,
build and install cache uses a space-free temporary directory because upstream
makefiles cannot handle repository paths containing spaces. Override with
`CAST_FFMPEG_CACHE`; deleting it forces a fresh build. Default compilation uses
two workers. macOS deployment target12.0 matches the transport precedent.

No encoders, filters, programs or autodetected external libraries.
Networking is limited to HTTP/TCP for existing loopback cast-proxy input.
The 2026-10-05 p02 ruling enables H264/HEVC/AAC/AC3/EAC3 decoders for stream-info
probing so MKV B-frame decode timestamps are correct; packet copying never
decodes or encodes frames. Includes MKV/MOV/MP4/MPEG-TS/HLS, H264/HEVC/AAC/AC3/MPEG parsers,
file/pipe/http/tcp, SRT/WebVTT demuxers for external subtitle inputs, and packet bitstream
filters for AAC/Annex-B remuxing. Upstream enables
dependent AAC/AC3/EAC3 demuxers, ADTS/LATM muxers and packet bitstream filters;
these are container/packet operations, not encoding or frame filtering.
Fragmented MP4 uses the same MP4 muxer, not a separate component.

`nm` retains mandatory generic encode/lookup API symbols even with no encoder
implementations. Acceptance checks zero `ff_*_encoder` implementation symbols,
zero enabled encoder/filter config entries and zero encoders in the linked codec
registry. `check_ffmpeg.c` checks those encoders, the approved probe decoder
lookups and MP4 fragment option acceptance;
it is a proof executable only, never an app helper or shipped program.

`build_remux.sh` compares the installed FFmpeg recipe with the current script;
it rebuilds stale/missing archives before linking the wrapper. This catches the
Phase01-to-Phase02 probe-decoder change without an environment variable.
It also publishes the generated dylib to ignored `macos/libs/` for CocoaPods;
vendored file patterns cannot traverse outside the macOS pod root. Run this
native build before the first `flutter build macos`/`pod install` on a checkout.
The pod's before-compile phase refreshes the library on subsequent app builds.

Other platform recipes reuse the same source pin and component flags:

- Android: `ANDROID_NDK_HOME=... tool/build_ffmpeg.sh android arm64` (also
  `armeabi-v7a`, `x86_64`, `x86`), optional `ANDROID_API` (default24).
- iOS: `tool/build_ffmpeg.sh ios arm64`, `CAST_IOS_SDK=iphonesimulator` for
  simulator; deployment target13.0, Apple SDK host required.
- Windows: `CAST_WINDOWS_CROSS_PREFIX=x86_64-w64-mingw32- tool/build_ffmpeg.sh windows x86_64`
  using a MinGW toolchain (Bash/MSYS2 or cross host); x86 also accepted.

Those builds and device runs are NOT RUN — deferred by owner: macOS-only baseline.

Phase03 transport delta: HTTP and TCP protocols are enabled for loopback cast-proxy input. HTTPS/authentication stay in the existing Dart proxy; no TLS library, encoder, filter, or executable is added. HLS writes one exclusively owned directory, atomically publishing complete segments/playlists using `hls_flags=temp_file`, `hls_time=1`, and `hls_list_size=0`. Cancellation/failure removes only this created directory. Single-file MP4 retains its fragmentation flags and flushes AVIO after packet writes. Native reads/probing use a five-second interruption deadline; successful reads reset the deadline.
