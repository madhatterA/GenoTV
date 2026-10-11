#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

source_dir=${ARIA2_SOURCE:?Set ARIA2_SOURCE to the pinned aria2 checkout}
aria2_ref=${ARIA2_REF:-9e7273583f83}
sdk=${IOS_SDK:-$(xcrun --sdk iphoneos --show-sdk-path)}
sim_sdk=${IOS_SIMULATOR_SDK:-$(xcrun --sdk iphonesimulator --show-sdk-path)}
deployment_target=${IPHONEOS_DEPLOYMENT_TARGET:-13.0}
prefix=${ARIA2_PREFIX:-"$(pwd)/ios/libs/libaria2"}

test -f "$source_dir/configure.ac" || { echo "not an aria2 source checkout: $source_dir" >&2; exit 1; }
if test -d "$source_dir/.git"; then
  actual_ref=$(git -C "$source_dir" rev-parse HEAD)
  case "$actual_ref" in
    "$aria2_ref"*) ;;
    *) echo "aria2 checkout $actual_ref does not match pinned ref $aria2_ref" >&2; exit 1;;
  esac
fi
command -v xcrun >/dev/null || { echo 'Xcode xcrun is required' >&2; exit 1; }
command -v make >/dev/null || { echo 'make is required' >&2; exit 1; }

# Apply the portable API fix to a scratch copy; the pinned checkout is read-only.
work="$(mktemp -d /tmp/transport-aria2-ios.XXXXXX)"
trap 'rm -rf "$work"' EXIT
rsync -a --exclude .git "$source_dir/" "$work/src/"
patch -p1 -d "$work/src" < "$root/tool/aria2_resume_wakeup.patch"
cd "$work/src"
if test ! -x configure; then
  autoreconf -i
fi
make distclean >/dev/null 2>&1 || true
make -C src clean >/dev/null 2>&1 || true
device_cc=$(xcrun --sdk iphoneos -f clang)
device_cxx=$(xcrun --sdk iphoneos -f clang++)
CC="$device_cc" CXX="$device_cxx" ./configure \
  --enable-libaria2 --disable-shared --enable-static \
  --disable-bittorrent --disable-metalink --disable-sftp \
  --disable-xmlrpc --disable-websocket \
  --without-libxml2 --without-libexpat --without-libcares --without-libssh2 \
  --without-openssl --without-gnutls \
  --host=arm-apple-darwin \
  CFLAGS="-DCIPHER_NO_DHPARAM -target arm64-apple-ios${deployment_target} -isysroot $sdk -miphoneos-version-min=$deployment_target" \
  CXXFLAGS="-DCIPHER_NO_DHPARAM -target arm64-apple-ios${deployment_target} -isysroot $sdk -miphoneos-version-min=$deployment_target" \
  LDFLAGS="-isysroot $sdk -miphoneos-version-min=$deployment_target"
make -C src -j"$(sysctl -n hw.ncpu)" libaria2.la
mkdir -p "$prefix"
cp src/.libs/libaria2.a "$prefix/libaria2-iphoneos.a"
mkdir -p "$prefix/include/aria2"
cp src/includes/aria2/aria2.h "$prefix/include/aria2/aria2.h"

# Build a separate simulator slice and package both archives. A missing
# simulator build is a hard failure; no fallback ABI is emitted.
make distclean >/dev/null 2>&1 || true
make -C src clean >/dev/null 2>&1 || true
rm -f config.cache
sim_cc=$(xcrun --sdk iphonesimulator -f clang)
sim_cxx=$(xcrun --sdk iphonesimulator -f clang++)
rm -f config.cache
CC="$sim_cc" CXX="$sim_cxx" ./configure \
  --enable-libaria2 --disable-shared --enable-static \
  --disable-bittorrent --disable-metalink --disable-sftp \
  --disable-xmlrpc --disable-websocket \
  --without-libxml2 --without-libexpat --without-libcares --without-libssh2 \
  --without-openssl --without-gnutls \
  --host=arm-apple-darwin \
  CFLAGS="-DCIPHER_NO_DHPARAM -target arm64-apple-ios${deployment_target}-simulator -isysroot $sim_sdk -mios-simulator-version-min=$deployment_target" \
  CXXFLAGS="-DCIPHER_NO_DHPARAM -target arm64-apple-ios${deployment_target}-simulator -isysroot $sim_sdk -mios-simulator-version-min=$deployment_target" \
  LDFLAGS="-isysroot $sim_sdk -mios-simulator-version-min=$deployment_target"
make -C src -j"$(sysctl -n hw.ncpu)" libaria2.la
cp src/.libs/libaria2.a "$prefix/libaria2-iphonesimulator.a"
xcframework_prefix="$prefix/.xcframework-slices"
rm -rf "$xcframework_prefix"
mkdir -p "$xcframework_prefix/ios-arm64" "$xcframework_prefix/ios-arm64-simulator"
cp "$prefix/libaria2-iphoneos.a" "$xcframework_prefix/ios-arm64/libaria2.a"
cp "$prefix/libaria2-iphonesimulator.a" "$xcframework_prefix/ios-arm64-simulator/libaria2.a"
xcrun xcodebuild -create-xcframework \
  -library "$xcframework_prefix/ios-arm64/libaria2.a" -headers "$prefix/include" \
  -library "$xcframework_prefix/ios-arm64-simulator/libaria2.a" -headers "$prefix/include" \
  -output "$prefix/libaria2.xcframework"
rm -rf "$xcframework_prefix"
echo "Built device, simulator, and $prefix/libaria2.xcframework"
