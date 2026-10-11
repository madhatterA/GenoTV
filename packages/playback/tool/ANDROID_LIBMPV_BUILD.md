# Android libmpv

Run `timeout 900 packages/playback/tool/build_libmpv_android.sh` from the repo
root (`gtimeout` on macOS). Install the SDK NDK **25.2.9519653** first.
Build tools: Git, Meson, Ninja, CMake, pkg-config, Python, make, autotools;
macOS also needs GNU sed/install and GNU libtool. Tools may come from Homebrew;
target libraries always come from pinned source. Jobs default to two (maximum four).

The recipe is media-kit/libmpv-android-video-build v1.1.7 at
`fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768`, its `default` FFmpeg flavour,
and its source revisions in `native/android/source-pins.txt`. The only engine
patch omits zero-valued EGL context flags; nonzero debug flags remain intact.
This fixes gfxstream's EGL_BAD_ATTRIBUTE with the production GPU renderer.
The build suffix `vp-egl-zero-flags-1` identifies the packaged binary.

Build cache defaults to `/tmp/vp-libmpv-android-recipe-v1.1.7`.
`LIBMPV_ANDROID_CACHE`, `LIBMPV_ANDROID_JOBS`, and `ANDROID_HOME` can override
cache, bounded parallelism, and SDK location. Existing caches must have the exact
pinned revisions. Target flags/features remain upstream's; host adaptations
select the installed NDK, `/usr/local` staged Meson install directories,
LLVM nm, and configure generation without trying to run Android binaries.

The local MIT media_kit_libs_android_video 1.3.8 plugin supplies built
`libmpv.so` and `libmediakitandroidhelper.so` in its arm64 jniLibs directory.
Gradle does not download the upstream arm64 jar and fails if our library is
missing. Other ABIs retain the upstream URLs and MD5s. App and playback
dependency overrides select the local plugin; Dart/Java APIs are unchanged.
`BUILD.txt` records source revisions and artifact hashes. The engine retains
upstream's LGPL build configuration (GPL disabled); preserve source/patches
and upstream dependency notices when distributing it.
