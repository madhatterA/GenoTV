#!/usr/bin/env bash
set -euo pipefail

# Pinned, static iOS slices for the torrent ABI. iOS uses aria2's AppleTLS
# backend for HTTP; the libtorrent slice intentionally disables its OpenSSL
# backend so it has no hidden host crypto dependency.
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cache="${LIBTORRENT_IOS_CACHE:-/tmp/transport-ios-native-$(id -u)}"
source_dir="${LIBTORRENT_SOURCE:-$cache/libtorrent-2.1.1}"
prefix="${LIBTORRENT_IOS_PREFIX:-$root/packages/transport/ios/libs/libtorrent}"
ref="56ae8caba38bf154ffc210403cb23f91d0ecaa49"
try_signal_ref="105cce59972f925a33aa6b1c3109e4cd3caf583d"
boost_sha=5c1d40cb8e19adbf740a4ec2da35b3e58f3f5804b1dce44deb53df72193cbc6c
mkdir -p "$cache"
boost_archive="$cache/boost_1_92_0.tar.bz2"
if [[ ! -f "$boost_archive" ]]; then
  curl --fail --location --retry 2 \
    https://archives.boost.io/release/1.92.0/source/boost_1_92_0.tar.bz2 \
    -o "$boost_archive"
fi
[[ "$(shasum -a 256 "$boost_archive" | cut -d ' ' -f1)" == "$boost_sha" ]] || {
  echo 'Boost source checksum mismatch' >&2; exit 2;
}
if [[ ! -d "$cache/boost_1_92_0/boost" ]]; then
  tar -xf "$boost_archive" -C "$cache" boost_1_92_0/boost
fi
boost_include="$cache/boost_1_92_0"
deployment="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone --branch v2.1.1 --depth 1 https://github.com/arvidn/libtorrent.git "$source_dir"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$ref" ]] || { echo "unexpected libtorrent revision" >&2; exit 2; }
git -C "$source_dir" submodule update --init --depth 1 deps/try_signal
[[ "$(git -C "$source_dir/deps/try_signal" rev-parse HEAD)" == "$try_signal_ref" ]] || { echo "unexpected try_signal revision" >&2; exit 2; }

build_slice() {
  local sdk="$1" name="$2"
  local build
  build="$cache/build-$name"
  cmake -S "$source_dir" -B "$build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -Dencryption=OFF -Dwebtorrent=OFF -Ddht=ON \
    -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF -Dpython-bindings=OFF \
    -DBoost_NO_BOOST_CMAKE=ON -DBoost_INCLUDE_DIR="$boost_include" >&2
  cmake --build "$build" --target torrent-rasterbar --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-2}" >&2
  printf '%s\n' "$build/libtorrent-rasterbar.a"
}

device_archive="$(build_slice iphoneos device)"
sim_archive="$(build_slice iphonesimulator simulator)"
mkdir -p "$prefix"
mkdir -p "$prefix/boost/include"
cp -R "$boost_include/boost" "$prefix/boost/include/"
rm -rf "$prefix/libtorrent.xcframework"
xcrun xcodebuild -create-xcframework \
  -library "$device_archive" -headers "$source_dir/include" \
  -library "$sim_archive" -headers "$source_dir/include" \
  -output "$prefix/libtorrent.xcframework"
shasum -a 256 "$prefix/libtorrent.xcframework"/*/*.a
