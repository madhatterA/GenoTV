#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
: "${1:?usage: build_libtorrent_macos.sh <build-directory>}"
# Homebrew supplies build tools only; every linked dependency is built below.
export PATH="/opt/homebrew/bin:$PATH"
[[ "$(uname -m)" == arm64 ]] || { echo 'macOS native baseline requires arm64' >&2; exit 2; }
# OpenSSL makefiles require space-free paths. Keep CMake/Ninja's real build cache,
# isolated by source checkout, toolchain, source pins and build instructions.
deps_key="$(
  {
    printf '%s\n' "$root" "$(uname -m)" "${SDKROOT:-}" "${DEVELOPER_DIR:-}" \
      "${CFLAGS:-}" "${CXXFLAGS:-}" "${CPPFLAGS:-}" "${LDFLAGS:-}"
    /usr/bin/clang++ --version
    xcrun --sdk macosx --show-sdk-path
    xcrun --sdk macosx --show-sdk-version
    cmake --version
    ninja --version
    (cd "$root" && shasum -a 256 tool/build_libtorrent_macos.sh tool/macos_deps/CMakeLists.txt)
  } | shasum -a 256 | cut -d ' ' -f 1
)"
build="/tmp/transport-macos-native-$(id -u)/$deps_key"
shim_key="$(
  (cd "$root" && shasum -a 256 src/lt_shim/CMakeLists.txt src/lt_shim/lt_shim.{cpp,h} src/lt_shim/fs_shim.c tool/check_lt_abi.sh) \
    | shasum -a 256 | cut -d ' ' -f 1
)"
shim="$build/shim-$shim_key"
echo "Native dependency cache: $build/deps"
echo "Native shim cache: $shim"
cmake -S "$root/tool/macos_deps" -B "$build/deps" -G Ninja
cmake --build "$build/deps" --parallel 4
prefix="$build/deps/prefix"
boost="$build/deps/boost"
[[ "$(git -C "$build/deps/libtorrent-prefix/src/libtorrent/deps/try_signal" rev-parse HEAD)" == 105cce59972f925a33aa6b1c3109e4cd3caf583d ]]
cmake -S "$root/src/lt_shim" -B "$shim" -G Ninja \
  -DTRANSPORT_LT_LIBRARY_TYPE=SHARED -DTRANSPORT_LIBTORRENT_ROOT="$prefix" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DBoost_NO_BOOST_CMAKE=ON -DBoost_INCLUDE_DIR="$boost" \
  -DOPENSSL_ROOT_DIR="$prefix" -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DOPENSSL_INCLUDE_DIR="$prefix/include" \
  -DOPENSSL_SSL_LIBRARY="$prefix/lib/libssl.a" \
  -DOPENSSL_CRYPTO_LIBRARY="$prefix/lib/libcrypto.a"
cmake --build "$shim" --parallel 4
artifact="$root/macos/libs/libtransport_lt_shim.dylib"
cp -f "$shim/libtransport_lt_shim.dylib" "$artifact"
install_name_tool -id @rpath/libtransport_lt_shim.dylib "$artifact"
codesign --force --sign - "$artifact"
bash "$root/tool/check_lt_abi.sh" "$artifact"
if otool -L "$artifact" | grep -q /opt/homebrew; then
  echo 'unexpected Homebrew runtime dependency' >&2; exit 1
fi
