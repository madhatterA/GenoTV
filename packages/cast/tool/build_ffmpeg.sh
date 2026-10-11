#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
platform="${1:?usage: build_ffmpeg.sh <macos|android|ios|windows> [architecture]}"
arch="${2:-$(uname -m)}"
version=8.0.1
sha256=05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41
case "$platform" in macos|android|ios|windows) ;; *) echo 'Unsupported platform' >&2; exit 2 ;; esac
case "$arch" in arm64|aarch64|x86_64|armeabi-v7a|armv7|x86|i686) ;; *) echo 'Unsupported architecture' >&2; exit 2 ;; esac
cache="${CAST_FFMPEG_CACHE:-${TMPDIR:-/tmp}/cast-ffmpeg-$(id -u)}"
# Upstream makefiles need space-free paths; publish into the repo only after install.
case "$cache" in *' '*) echo 'CAST_FFMPEG_CACHE must have no spaces' >&2; exit 2 ;; esac
mkdir -p "$cache"
archive="$cache/ffmpeg-$version.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 2 --connect-timeout 15 --max-time 120 \
    "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "$archive" | cut -d ' ' -f 1)"
else
  actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
fi
[[ "$actual" == "$sha256" ]] || { echo 'FFmpeg source checksum mismatch' >&2; exit 1; }
echo "FFmpeg $version SHA256 $actual"
source_dir="$cache/ffmpeg-$version"
if [[ ! -d "$source_dir" ]]; then tar -xf "$archive" -C "$cache"; fi
if [[ "$platform" == windows && "${CAST_WINDOWS_TOOLCHAIN:-mingw}" == msvc && ! -f "$source_dir/.msvc-empty-cbs-patched" ]]; then
  patch -p1 -d "$source_dir" < "$root/tool/ffmpeg_msvc_empty_cbs.patch"
  touch "$source_dir/.msvc-empty-cbs-patched"
fi
target=()
host_flags=(--host-cc="${HOST_CC:-cc}")
if [[ "$(uname -s)" == Darwin ]]; then
  host_sdk="$(xcrun --sdk macosx --show-sdk-path)"
  host_flags=(--host-cc="$(xcrun --sdk macosx -f clang)"
    --host-cflags="-isysroot $host_sdk" --host-ldflags="-isysroot $host_sdk")
fi
case "$platform" in
  macos)
    [[ "$(uname -s)" == Darwin ]] || { echo 'macOS requires an Apple SDK host' >&2; exit 2; }
    case "$arch" in arm64|aarch64) arch=arm64; cpu=aarch64 ;; x86_64) cpu=x86_64 ;; *) echo 'Invalid macOS architecture' >&2; exit 2 ;; esac
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
    target=(--target-os=darwin --arch="$cpu" --cc="$(xcrun -f clang)"
      --sysroot="$sdk" --extra-cflags="-arch $arch -mmacosx-version-min=12.0"
      --extra-ldflags="-arch $arch -mmacosx-version-min=12.0")
    ;;
  ios)
    sdk_name="${CAST_IOS_SDK:-iphoneos}"
    case "$sdk_name" in iphoneos|iphonesimulator) ;; *) echo 'Invalid iOS SDK' >&2; exit 2 ;; esac
    sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
    case "$arch" in arm64|aarch64) arch=arm64; cpu=aarch64 ;; x86_64) cpu=x86_64 ;; *) echo 'Invalid iOS architecture' >&2; exit 2 ;; esac
    triple="$arch-apple-ios13.0"
    if [[ "$sdk_name" == iphonesimulator ]]; then triple="$triple-simulator"; fi
    target=(--enable-cross-compile --target-os=darwin --arch="$cpu"
      --cc="$(xcrun --sdk "$sdk_name" -f clang)" --sysroot="$sdk"
      --extra-cflags="-target $triple" --extra-ldflags="-target $triple")
    ;;
  android)
    : "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the Android NDK}"
    case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) host=windows-x86_64 ;; esac
    bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host/bin"
    case "$arch" in
      arm64|aarch64) cpu=aarch64; triple=aarch64-linux-android ;;
      armeabi-v7a|armv7) cpu=arm; triple=armv7a-linux-androideabi ;;
      x86_64) cpu=x86_64; triple=x86_64-linux-android ;;
      x86|i686) cpu=x86; triple=i686-linux-android ;;
    esac
    target=(--enable-cross-compile --target-os=android --arch="$cpu"
      --cc="$bin/$triple${ANDROID_API:-24}-clang" --ar="$bin/llvm-ar"
      --ranlib="$bin/llvm-ranlib" --strip="$bin/llvm-strip")
    ;;
  windows)
    case "$arch" in x86_64) cpu=x86_64 ;; x86|i686) cpu=x86 ;; *) echo 'Windows build requires x86 or x86_64' >&2; exit 2 ;; esac
    if [[ "${CAST_WINDOWS_TOOLCHAIN:-mingw}" == msvc ]]; then
      target=(--toolchain=msvc --target-os=win32 --arch="$cpu")
      host_flags=(--host-cc=cl)
    else
      : "${CAST_WINDOWS_CROSS_PREFIX:?Set CAST_WINDOWS_CROSS_PREFIX (e.g. x86_64-w64-mingw32-)}"
      target=(--enable-cross-compile --target-os=mingw32 --arch="$cpu"
        --cross-prefix="$CAST_WINDOWS_CROSS_PREFIX")
    fi
    ;;
esac
work="$cache/$platform-$arch-${CAST_IOS_SDK:-default}"
mkdir -p "$work"
cd "$work"
"$source_dir/configure" --prefix="$work/install" \
  --disable-everything --disable-autodetect --disable-programs --disable-doc \
  --disable-debug --enable-network --disable-shared --enable-static --enable-pic \
  --disable-encoders --disable-decoders --disable-filters --disable-avfilter \
  --disable-avdevice --disable-swresample --disable-swscale --disable-x86asm \
  --enable-demuxer=matroska,mov,mpegts,hls,srt,webvtt \
  --enable-muxer=matroska,mov,mp4,mpegts,hls \
  --enable-parser=h264,hevc,aac,ac3,mpegaudio,mpegvideo \
  --enable-decoder=h264,hevc,aac,ac3,eac3 \
  --enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb,extract_extradata \
  --enable-protocol=file,pipe,http,tcp "${host_flags[@]}" "${target[@]}"
if grep -Eq '^#define CONFIG_.*_(ENCODER|FILTER) 1$' config_components.h; then
  echo 'Unexpected encoder/filter enabled' >&2; exit 1
fi
# Two workers bound normal compilation load; this is not a stress run.
make -j2
make install
mkdir -p "$work/install/share/ffmpeg"
cp config.h config_components.h "$work/install/share/ffmpeg/"
cp "$root/tool/build_ffmpeg.sh" "$work/install/share/ffmpeg/build_ffmpeg.sh"
cp "$source_dir/COPYING.LGPLv2.1" "$work/install/share/ffmpeg/"
"$source_dir/configure" --help > "$work/install/share/ffmpeg/configure-help.txt"
printf '%s\n%s\n' "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" "$sha256" \
  > "$work/install/share/ffmpeg/source.txt"
output="$root/native/ffmpeg/$platform-$arch"
if [[ "$platform" == ios ]]; then output="$output-${CAST_IOS_SDK:-iphoneos}"; fi
mkdir -p "$output"
cp -R "$work/install/." "$output/"
echo "Installed FFmpeg: $output"
