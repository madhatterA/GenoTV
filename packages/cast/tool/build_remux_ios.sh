#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
# CAST_REMUX_PLATFORM=tvos builds the same remuxer for tvOS (device + simulator, minimum tvOS 15.0).
platform="${CAST_REMUX_PLATFORM:-ios}"
if [[ "$platform" == tvos ]]; then sdks=(appletvos appletvsimulator) os=tvos; else sdks=(iphoneos iphonesimulator) os=ios; fi
work="${TMPDIR:-/tmp}/cast-remux-$platform-$(id -u)"
mkdir -p "$work" "$root/$platform/libs"
frameworks=()
for sdk in "${sdks[@]}"; do
  prefix="$root/native/ffmpeg/$os-arm64-$sdk"
  if [[ ! -f "$prefix/lib/libavformat.a" ]] ||
     ! cmp -s "$root/tool/build_ffmpeg.sh" "$prefix/share/ffmpeg/build_ffmpeg.sh"; then
    CAST_IOS_SDK="$sdk" bash "$root/tool/build_ffmpeg.sh" "$os" arm64
  fi
  framework="$work/$sdk/cast_remux.framework"
  mkdir -p "$framework"
  triple=arm64-apple-${os}15.0
  [[ "$sdk" != *simulator ]] || triple="$triple-simulator"
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
rm -rf "$root/$platform/libs/cast_remux.xcframework"
xcrun xcodebuild -create-xcframework "${frameworks[@]}" \
  -output "$root/$platform/libs/cast_remux.xcframework"
