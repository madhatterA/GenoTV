#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
work="${TMPDIR:-/tmp}/cast-remux-ios-$(id -u)"
mkdir -p "$work" "$root/ios/libs"
frameworks=()
for sdk in iphoneos iphonesimulator; do
  prefix="$root/native/ffmpeg/ios-arm64-$sdk"
  if [[ ! -f "$prefix/lib/libavformat.a" ]] ||
     ! cmp -s "$root/tool/build_ffmpeg.sh" "$prefix/share/ffmpeg/build_ffmpeg.sh"; then
    CAST_IOS_SDK="$sdk" bash "$root/tool/build_ffmpeg.sh" ios arm64
  fi
  framework="$work/$sdk/cast_remux.framework"
  mkdir -p "$framework"
  triple=arm64-apple-ios15.0
  [[ "$sdk" != iphonesimulator ]] || triple="$triple-simulator"
  xcrun --sdk "$sdk" clang -std=c11 -Wall -Wextra -Werror -O2 -dynamiclib \
    -target "$triple" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -fvisibility=hidden -I"$prefix/include" "$root/native/remux/remux.c" \
    -Wl,-hidden-lavformat -Wl,-hidden-lavcodec -Wl,-hidden-lavutil \
    -L"$prefix/lib" -lm -pthread \
    -Wl,-install_name,@rpath/cast_remux.framework/cast_remux \
    -o "$framework/cast_remux"
  cat > "$framework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>cast_remux</string>
<key>CFBundleIdentifier</key><string>com.genotv.cast-remux</string>
<key>CFBundleName</key><string>cast_remux</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST
  frameworks+=(-framework "$framework")
done
rm -rf "$root/ios/libs/cast_remux.xcframework"
xcrun xcodebuild -create-xcframework "${frameworks[@]}" \
  -output "$root/ios/libs/cast_remux.xcframework"
