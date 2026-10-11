# Native torrent build — pinned source, macOS12 baseline

Owner decision (2026-10-01): cross-OS compatibility matters, not macOS version. Build every native dependency from pinned source; Homebrew supplies build tools only. App deployment stays12.0. Android/iOS/Windows/device execution is NOT RUN — deferred by owner: macOS-only baseline.

## Source/dependency pins

| Dependency | Pinned source | Components built |
| --- | --- | --- |
| libtorrent2.1.1 | `https://github.com/arvidn/libtorrent.git`, commit `56ae8caba38bf154ffc210403cb23f91d0ecaa49` | static torrent-rasterbar; DHT and encryption enabled; WebTorrent disabled |
| try_signal | libtorrent submodule, commit `105cce59972f925a33aa6b1c3109e4cd3caf583d` | included in static torrent-rasterbar |
| Boost1.92.0 | `https://archives.boost.io/release/1.92.0/source/boost_1_92_0.tar.bz2`, SHA256 `5c1d40cb8e19adbf740a4ec2da35b3e58f3f5804b1dce44deb53df72193cbc6c` | headers only (`Boost::headers`), no compiled Boost components |
| OpenSSL3.6.4 | `https://codeload.github.com/openssl/openssl/tar.gz/d3c1b1169b3569ff3069e5b399f47b2b28e03d79`, SHA256 `f4e3080732a86b21e2220cf31c3c60026e923d6193bf371ba872e71fb13bb7c7` | static libssl/libcrypto; no shared libraries/tests/modules/DSO |

Libtorrent and try_signal pins mirror `build_libtorrent_android.sh` and the existing iOS source script. Android has no pinned Boost source or OpenSSL version: it takes host Boost headers and disables encryption; those platforms were not edited or executed in this phase. The source pins here can be reused when their owner resumes those native builds.

## Native build wiring

`macos/transport.podspec` runs `tool/build_libtorrent_macos.sh` before compile, declares source/CMake/script inputs and the shim output, and embeds only `libs/libtransport_lt_shim.dylib`. The prebuilt-only SwiftPM manifest/XCFramework and obsolete sibling libtorrent/OpenSSL dylibs have been removed. Flutter uses CocoaPods for this plugin; unrelated plugins can continue using SwiftPM.

`tool/macos_deps/CMakeLists.txt` uses CMake ExternalProject to download/hash-check Boost and OpenSSL, clone the exact libtorrent commit/submodule, run OpenSSL's supported Configure/make through CMake, and build/install libtorrent through CMake. OpenSSL does not provide an upstream CMake build. All linked C/C++ code is source-built for arm64, deployment12.0; Apple system libraries/frameworks and C++ runtime remain platform dependencies. The script then builds the existing shim CMake target against that private static prefix, signs the resulting self-contained image, and checks the complete C ABI. Homebrew library prefixes are excluded from CMake discovery; dependency headers and archives are explicitly selected from the source build.

The standalone shim's rpath-removal step is now limited to shared libtorrent imports; a static libtorrent does not introduce the dependency rpath to remove.

OpenSSL's generated makefiles cannot escape spaces in their source/build path. The script keeps a space-free CMake/Ninja build cache under `/tmp/transport-macos-native-<uid>/`. Its dependency key hashes the canonical checkout path, architecture, compiler/SDK/build-tool identities, build flags, build script and pinned dependency CMake file. A separate shim key hashes its CMake/source/header and ABI-check script, so shim changes reuse the pinned dependency archives. Every invocation still configures/builds through CMake/Ninja and runs packaging/ABI/dependency checks; unchanged inputs produce `ninja: no work to do.`, while touched shim inputs rebuild normally. No success stamp or timer bypasses compilation. Removing the cache (or OS temporary-directory cleanup) causes a fresh source build. The existing build-directory argument remains accepted for pod callers; native builds use the keyed cache for both spaced and unspaced paths.

## Rebuild

Build tools: Xcode/Apple clang, CMake>=3.24, Ninja, make, Perl and Git; network access for pinned source downloads. Homebrew can install CMake/Ninja, but no Homebrew headers or libraries are used.

```sh
bash packages/transport/tool/build_libtorrent_macos.sh /tmp/transport-macos-source
cd app
flutter build macos --release -v
```

Fresh proof runner: `flutter clean`, `flutter pub get`, `flutter build macos --release -v` passed (exit0). It embeds a14,155,424-byte arm64 shim with minos12.0,27 transport ABI symbols, and no Homebrew runtime dependency. `codesign --verify --deep --strict` passed. The original Phase01 C ABI harness was compiled against this exact packaged artifact, passed40 session create/destroy cycles (20 warmup+20 measured), invalid-magnet mapping, real magnet metadata, forced C++ exception mapping and teardown, exit0. `DYLD_PRINT_LIBRARIES=1` confirms the loaded app-owned shim and no `/opt/homebrew` image. Full transport tests:75 passed,0 failed,0 skipped.

Actual repo app release build also passed (exit0), with the same14,155,424-byte/minos12.0/system-only shim, deep strict signature verification,27 symbols, and a second Phase01 packaged harness run (exit0). Its proof is recorded separately in `evidence/part-03/ch03-p04/REPORT.md`. An initial repo app build found the spaces-in-path OpenSSL defect described above; its failure log is retained. No app deployment/source change or commit is authorized.

## Evidence and limitations

Current evidence: `evidence/part-03/ch03-p04/REPORT.md`, `build_macos.log` (fresh runner), `packaged_macos.txt`, `harness_packaged_macos.log`, `transport_tests.jsonl` and `transport_test_counts.txt`. Source/compiler flags and archive verification output are in the full native Flutter build log. Older Homebrew/Android logs are history, not current acceptance evidence.

Only macOSarm64 is built and executed. Actual runtime on macOS12.0 or Intel hardware is NOT RUN (current host is Apple Silicon); minos12.0 is an artifact/build fact, not a device-runtime claim. Other OS builds and device confirmation remain owner-deferred.

## Reproduce the packaged harness

Use a Python interpreter that has the existing fixture's `libtorrent` module installed (the fixture is a test peer; the app's shim is built from pinned source). No prestarted tracker/peer service or fixed-port configuration is required.

```sh
python3 packages/transport/tool/run_packaged_macos_harness.py \
  app/build/macos/Build/Products/Release/video_player.app
```

The single script compiles the original Phase01 C ABI harness directly against the app-owned shim, starts the existing local multifile fixture on OS-assigned loopback ports, runs with a90s deadline and dyld image tracing, and terminates/reaps the fixture even on failure. Missing app, fixture readiness, compile, runtime or teardown failure exits nonzero. Output: `evidence/part-03/ch03-p04/packaged_harness_reproducible.log`.
