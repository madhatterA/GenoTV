#!/usr/bin/env bash
# media_kit v1.1.7 default recipe, with EGL, AudioTrack, audio-filter and H.264 framing fixes.
set -euo pipefail
abi=${ANDROID_ABI:-arm64-v8a}
case "$abi" in
  arm64-v8a) arch=arm64; triple=aarch64-linux-android ;;
  armeabi-v7a) arch=armv7l; triple=armv7a-linux-androideabi ;;
  x86_64) arch=x86_64; triple=x86_64-linux-android ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 2 ;;
esac
root=$(cd "$(dirname "$0")/../../.." && pwd)
cache=${LIBMPV_ANDROID_CACHE:-/tmp/vp-libmpv-android-recipe-v1.1.7}
if [ "$abi" != arm64-v8a ]; then cache="$cache-$abi"; fi
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
ndk="$sdk/ndk/25.2.9519653"
pin=fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768
jobs=${LIBMPV_ANDROID_JOBS:-2}
case "$jobs" in 2|3|4) ;; *) echo 'Use 2–4 build jobs' >&2; exit 1;; esac
case $(uname -s) in Darwin) host=darwin-x86_64;; Linux) host=linux-x86_64;; *) exit 1;; esac
toolchain="$ndk/toolchains/llvm/prebuilt/$host"
test -x "$toolchain/bin/${triple}21-clang"
for tool in git meson ninja cmake pkg-config python3 make autoreconf automake; do command -v "$tool" >/dev/null; done
if [ "$host" = darwin-x86_64 ]; then
  for tool in gsed ginstall glibtoolize; do command -v "$tool" >/dev/null; done
fi
if [ ! -d "$cache/.git" ]; then
  git init "$cache"
  git -C "$cache" remote add origin https://github.com/media-kit/libmpv-android-video-build.git
  git -C "$cache" fetch --depth 1 origin "$pin"
  git -C "$cache" checkout --detach "$pin"
fi
test "$(git -C "$cache" rev-parse HEAD)" = "$pin"
cd "$cache/buildscripts"
export VP_ANDROID_NDK="$ndk" VP_ANDROID_TOOLCHAIN="$toolchain" cores="$jobs" NOCONFIGURE=1
# Host adaptation only: SDK tools are already installed; target recipe unchanged.
git -C "$cache" checkout -- buildscripts/include/path.sh buildscripts/build.sh
git -C "$cache" checkout -- buildscripts/scripts
python3 - <<'PY'
from pathlib import Path
p = Path('include/path.sh')
s = p.read_text()
s = s.replace('toolchain=$(echo "$DIR/sdk/android-sdk-linux/ndk/$v_ndk/toolchains/llvm/prebuilt/"*)',
              'toolchain="$VP_ANDROID_TOOLCHAIN"')
p.write_text(s)
p = Path('build.sh')
p.write_text(p.read_text().replace('sudo chmod', 'chmod'))
for p in Path('scripts').glob('*.sh'):
    p.write_text(p.read_text().replace('meson setup $build',
        'meson setup --reconfigure $build --prefix=/usr/local --libdir=lib'))
PY
fetch() {
  local name=$1 url=$2 ref=$3
  local expected
  expected=$(awk -v name="$name" '$1 == name {print $2}' "$root/packages/playback/native/android/source-pins.txt")
  test -n "$expected"
  if [ ! -d "deps/$name/.git" ]; then
    git init "deps/$name"
    git -C "deps/$name" remote add origin "$url"
    git -C "deps/$name" fetch --depth 1 origin "$expected"
    git -C "deps/$name" checkout --detach FETCH_HEAD
  fi
  test "$(git -C "deps/$name" rev-parse HEAD)" = "$expected" || {
    echo "Wrong cached revision for $name (recipe ref $ref): expected $expected" >&2; exit 1;
  }
  # These are owned build-cache checkouts; pins must govern source bytes as well
  # as commit labels. Keep ignored build products, reset tracked source edits.
  git -C "deps/$name" reset --hard "$expected"
}
# These are precisely dep_mpv and its transitive default dependencies in depinfo.sh.
export ENCODERS_GPL=
. include/depinfo.sh
fetch mbedtls https://github.com/Mbed-TLS/mbedtls.git "v$v_mbedtls"
fetch dav1d https://code.videolan.org/videolan/dav1d.git "$v_dav1d"
fetch libxml2 https://gitlab.gnome.org/GNOME/libxml2.git "v$v_libxml2"
fetch ffmpeg https://github.com/FFmpeg/FFmpeg.git "n$v_ffmpeg"
fetch freetype https://gitlab.freedesktop.org/freetype/freetype.git "VER-$v_freetype"
fetch fribidi https://github.com/fribidi/fribidi.git "v$v_fribidi"
fetch harfbuzz https://github.com/harfbuzz/harfbuzz.git "$v_harfbuzz"
fetch libass https://github.com/libass/libass.git "$v_libass"
fetch mpv https://github.com/mpv-player/mpv.git "$v_mpv"
test "$(git -C deps/mpv rev-parse HEAD)" = "$v_mpv"
./patch.sh
git -C deps/mpv apply "$root/packages/playback/native/android/patches/egl-zero-context-flags.patch"
git -C deps/mpv apply "$root/packages/playback/native/android/patches/audiotrack-sink-rate.patch"
git -C deps/ffmpeg apply "$root/packages/playback/native/android/patches/h264-annexb-four-byte-startcodes.patch"
# mpv's runtime version uses git describe, not Meson's VERSION project file.
version=$(git -C deps/mpv show HEAD:VERSION | tr -d '\n')
git -C deps/mpv tag -f "v$version-vp-egl-zero-flags-1-audio-rates-1" "$v_mpv"
cp flavors/default.sh scripts/ffmpeg.sh
python3 - <<'PY'
from pathlib import Path
p = Path('scripts/ffmpeg.sh')
# The default flavour disables every filter; mpv's lavfi chain (Kodi stereo upmix `pan`) needs these.
p.write_text(p.read_text().replace('--ranlib=$RANLIB', '--ranlib=$RANLIB --nm=llvm-nm')
    .replace('--enable-filter=overlay \\',
             '--enable-filter=overlay --enable-filter=abuffer --enable-filter=abuffersink '
             '--enable-filter=pan --enable-filter=aformat --enable-filter=aresample \\'))
PY
bash -e build.sh --arch "$arch"
fetch media-kit-android-helper https://github.com/media-kit/media-kit-android-helper.git 42054e5d479f39ccbb0ae604862e2bcaf59b74c2
test "$(git -C deps/media-kit-android-helper rev-parse HEAD)" = 42054e5d479f39ccbb0ae604862e2bcaf59b74c2
cmake -S deps/media-kit-android-helper/app/src/main/cpp -B helper-$abi -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-21 -DCMAKE_BUILD_TYPE=Release
cmake --build helper-$abi --parallel "$jobs"
dest="$root/packages/media_kit_libs_android_video/android/src/main/jniLibs/$abi"
mkdir -p "$dest"
cp -L prefix/$abi/lib/libmpv.so "$dest/libmpv.so"
cp helper-$abi/libmediakitandroidhelper.so "$dest/"
"$toolchain/bin/llvm-strip" --strip-debug "$dest"/*.so
{
  echo "recipe=$pin ndk=$v_ndk flavour=default abi=$abi jobs=$jobs"
  for dep in mbedtls dav1d libxml2 ffmpeg freetype fribidi harfbuzz libass mpv media-kit-android-helper; do
    echo "$dep=$(git -C "deps/$dep" rev-parse HEAD)"
  done
  shasum -a 256 "$root/packages/playback/native/android/patches/"*.patch "$dest"/*.so
} | tee "$dest/BUILD.txt"
"$toolchain/bin/llvm-strings" "$dest/libmpv.so" | grep 'vp-egl-zero-flags-1'
