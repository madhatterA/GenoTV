#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ "$(uname -s)" == Darwin ]] || { echo 'This build requires the macOS SDK' >&2; exit 2; }
arch="${1:-$(uname -m)}"
case "$arch" in arm64|x86_64) ;; *) echo 'Invalid macOS architecture' >&2; exit 2 ;; esac
prefix="$root/native/ffmpeg/macos-$arch"
if [[ ! -f "$prefix/lib/libavformat.a" ]] ||
   ! cmp -s "$root/tool/build_ffmpeg.sh" "$prefix/share/ffmpeg/build_ffmpeg.sh"; then
  "$root/tool/build_ffmpeg.sh" macos "$arch"
fi
output="$prefix/lib/libcast_remux.dylib"
temporary="$output.tmp"
trap 'rm -f "$temporary"' EXIT
xcrun clang -std=c11 -Wall -Wextra -Werror -O2 -dynamiclib -arch "$arch" \
  -mmacosx-version-min=12.0 -fvisibility=hidden -I"$prefix/include" \
  "$root/native/remux/remux.c" -Wl,-hidden-lavformat -Wl,-hidden-lavcodec \
  -Wl,-hidden-lavutil -L"$prefix/lib" -lm -pthread \
  -Wl,-install_name,@rpath/libcast_remux.dylib -o "$temporary"
mv "$temporary" "$output"
mkdir -p "$root/macos/libs"
cp "$output" "$root/macos/libs/libcast_remux.dylib"
echo "Built $output"
