#!/usr/bin/env bash
set -euo pipefail

# Reproducible Android bundle: libtorrent v2.1.1 with its pinned try_signal
# submodule, WebTorrent disabled (the product uses native BitTorrent), and the
# thin transport C ABI built against the same NDK toolchain.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ABI="${ANDROID_ABI:-arm64-v8a}"
case "$ABI" in arm64-v8a|armeabi-v7a|x86_64) ;; *) echo "Unsupported Android ABI: $ABI" >&2; exit 2 ;; esac
API="${ANDROID_PLATFORM:-24}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/28.2.13676358}}"
BOOST_INCLUDE="${BOOST_INCLUDE_DIR:-${TRANSPORT_ANDROID_CACHE:-/tmp/transport-android-native-$(id -u)}/boost_1_92_0}"
OUT="${TRANSPORT_ANDROID_OUT:-$ROOT/packages/transport/android/src/main/jniLibs/$ABI}"
WORK="${TRANSPORT_ANDROID_CACHE:-/tmp/transport-android-native-$(id -u)}"
mkdir -p "$WORK"
if [[ ! -f "$BOOST_INCLUDE/boost/version.hpp" ]]; then
  archive="$WORK/boost_1_92_0.tar.bz2"
  curl --fail --location --retry 5 -C - https://archives.boost.io/release/1.92.0/source/boost_1_92_0.tar.bz2 -o "$archive"
  [[ "$(shasum -a 256 "$archive" | cut -d " " -f 1)" == 5c1d40cb8e19adbf740a4ec2da35b3e58f3f5804b1dce44deb53df72193cbc6c ]]
  tar -xf "$archive" -C "$WORK"
  BOOST_INCLUDE="$WORK/boost_1_92_0"
fi

test -x "$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++" || {
  echo "Android NDK clang++ not found under $NDK" >&2; exit 2;
}
LLVM_READ_ELF="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
test -x "$LLVM_READ_ELF" || { echo "Android NDK llvm-readelf not found under $NDK" >&2; exit 2; }

[[ -d "$WORK/libtorrent/.git" ]] || git clone --depth 1 --branch v2.1.1 https://github.com/arvidn/libtorrent.git "$WORK/libtorrent" >/dev/null
test "$(git -C "$WORK/libtorrent" rev-parse HEAD)" = \
  56ae8caba38bf154ffc210403cb23f91d0ecaa49
git -C "$WORK/libtorrent" submodule update --init --depth 1 deps/try_signal >/dev/null
test "$(git -C "$WORK/libtorrent/deps/try_signal" rev-parse HEAD)" = \
  105cce59972f925a33aa6b1c3109e4cd3caf583d

toolchain="$NDK/build/cmake/android.toolchain.cmake"
lt_build="$WORK/libtorrent-build-$ABI"
lt_prefix="$WORK/prefix-$ABI"
cmake -S "$WORK/libtorrent" -B "$lt_build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -Dwebtorrent=OFF -Ddht=ON \
  -Dencryption=OFF -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF \
  -Dpython-bindings=OFF -DBoost_NO_BOOST_CMAKE=ON -DBoost_INCLUDE_DIR="$BOOST_INCLUDE" \
  -DCMAKE_INSTALL_PREFIX="$lt_prefix"
cmake --build "$lt_build" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"
cmake --install "$lt_build" >/dev/null

shim_build="$WORK/shim-build-$ABI"
cmake -S "$ROOT/packages/transport/src/lt_shim" -B "$shim_build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release -DLibtorrentRasterbar_DIR="$lt_prefix/lib/cmake/LibtorrentRasterbar" \
  -DBoost_INCLUDE_DIR="$BOOST_INCLUDE" -DBOOST_INCLUDEDIR="$BOOST_INCLUDE" -DBoost_NO_BOOST_CMAKE=ON \
  -DTRANSPORT_LT_LIBRARY_TYPE=SHARED -DTRANSPORT_LIBTORRENT_VERSION=2.1.1 \
  -DTRANSPORT_LIBTORRENT_ROOT="$lt_prefix"
cmake --build "$shim_build" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"

mkdir -p "$OUT"
cp "$lt_build/libtorrent-rasterbar.so" "$OUT/libtorrent-rasterbar.so"
cp "$shim_build/libtransport_lt_shim.so" "$OUT/libtransport_lt_shim.so"
"${LLVM_READ_ELF%llvm-readelf}llvm-strip" --strip-debug "$OUT/libtorrent-rasterbar.so" "$OUT/libtransport_lt_shim.so"
"$LLVM_READ_ELF" -h "$OUT/libtransport_lt_shim.so" | grep -E 'Class:|Machine:'
"$LLVM_READ_ELF" -d "$OUT/libtransport_lt_shim.so" | grep 'libtorrent-rasterbar.so'
shasum -a 256 "$OUT"/*.so
