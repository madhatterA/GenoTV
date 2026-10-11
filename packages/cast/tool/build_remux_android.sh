#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
ndk="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) echo 'Unsupported build host' >&2; exit 2 ;; esac
prefix="$root/native/ffmpeg/android-arm64"
if [[ ! -f "$prefix/lib/libavformat.a" ]] || ! cmp -s "$root/tool/build_ffmpeg.sh" "$prefix/share/ffmpeg/build_ffmpeg.sh"; then
  ANDROID_NDK_HOME="$ndk" bash "$root/tool/build_ffmpeg.sh" android arm64
fi
out="$root/android/src/main/jniLibs/arm64-v8a"
mkdir -p "$out"
"$ndk/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android${ANDROID_API:-24}-clang" \
  -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC -fvisibility=hidden \
  -I"$prefix/include" "$root/native/remux/remux.c" \
  -Wl,--exclude-libs,ALL -L"$prefix/lib" -lavformat -lavcodec -lavutil -lm -lz \
  -Wl,-soname,libcast_remux.so -o "$out/libcast_remux.so"
"$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-readelf" -h -d "$out/libcast_remux.so"
shasum -a 256 "$out/libcast_remux.so"
