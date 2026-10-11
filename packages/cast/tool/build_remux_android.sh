#!/usr/bin/env bash
set -euo pipefail
abi=${ANDROID_ABI:-arm64-v8a}
case "$abi" in
  arm64-v8a) arch=arm64; triple=aarch64-linux-android ;;
  armeabi-v7a) arch=armeabi-v7a; triple=armv7a-linux-androideabi ;;
  x86_64) arch=x86_64; triple=x86_64-linux-android ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 2 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd -P)"
ndk="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) echo 'Unsupported build host' >&2; exit 2 ;; esac
prefix="$root/native/ffmpeg/android-$arch"
if [[ ! -f "$prefix/lib/libavformat.a" ]] || ! cmp -s "$root/tool/build_ffmpeg.sh" "$prefix/share/ffmpeg/build_ffmpeg.sh"; then
  ANDROID_NDK_HOME="$ndk" bash "$root/tool/build_ffmpeg.sh" android "$arch"
fi
out="$root/android/src/main/jniLibs/$abi"
mkdir -p "$out"
"$ndk/toolchains/llvm/prebuilt/$host/bin/${triple}${ANDROID_API:-24}-clang" \
  -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC -fvisibility=hidden \
  -I"$prefix/include" "$root/native/remux/remux.c" \
  -Wl,--exclude-libs,ALL -L"$prefix/lib" -lavformat -lavcodec -lavutil -lm -lz \
  -Wl,-soname,libcast_remux.so -o "$out/libcast_remux.so"
"$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-strip" --strip-debug "$out/libcast_remux.so"
"$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-readelf" -h -d "$out/libcast_remux.so"
shasum -a 256 "$out/libcast_remux.so"
