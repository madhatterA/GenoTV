#!/usr/bin/env bash
set -euo pipefail
abi=${ANDROID_ABI:-arm64-v8a}
case "$abi" in
  arm64-v8a) triple=aarch64-linux-android; host_triple=$triple; openssl_target=android-arm64 ;;
  armeabi-v7a) triple=armv7a-linux-androideabi; host_triple=arm-linux-androideabi; openssl_target=android-arm ;;
  x86_64) triple=x86_64-linux-android; host_triple=$triple; openssl_target=android-x86_64 ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 2 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd -P)"
ndk="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) echo 'Unsupported build host' >&2; exit 2 ;; esac
bin="$ndk/toolchains/llvm/prebuilt/$host/bin"
api="${ANDROID_API:-24}"
work="${ARIA2_ANDROID_CACHE:-/tmp/transport-aria2-android-$(id -u)}"
if [[ "$abi" != arm64-v8a ]]; then work="$work-$abi"; fi
mkdir -p "$work"
export PATH="$bin:$PATH" ANDROID_NDK_ROOT="$ndk"
archive="$work/openssl.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 2 https://codeload.github.com/openssl/openssl/tar.gz/d3c1b1169b3569ff3069e5b399f47b2b28e03d79 -o "$archive"
fi
[[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == f4e3080732a86b21e2220cf31c3c60026e923d6193bf371ba872e71fb13bb7c7 ]]
if [[ ! -f "$work/openssl/lib/libssl.a" ]]; then
  mkdir -p "$work/openssl-src"
  tar -xf "$archive" -C "$work/openssl-src" --strip-components=1
  (cd "$work/openssl-src"
    ./Configure "$openssl_target" no-shared no-tests no-module no-dso -fPIC -D__ANDROID_API__="$api" --prefix="$work/openssl" --libdir=lib
    make -j2
    make install_sw)
fi
aria2_ref=${ARIA2_REF:-9e7273583f83}
source_dir="${ARIA2_SOURCE:-${XDG_CACHE_HOME:-$HOME/.cache}/aria2-src-${aria2_ref}}"
if [[ -z "${ARIA2_SOURCE:-}" && ! -f "$source_dir/configure.ac" ]]; then
  # No local checkout: fetch the pinned upstream commit once into a cache dir.
  source_dir="${XDG_CACHE_HOME:-$HOME/.cache}/aria2-src-${aria2_ref}"
  if [[ ! -f "$source_dir/configure.ac" ]]; then
    git init -q "$source_dir"
    git -C "$source_dir" fetch -q --depth 1 https://github.com/aria2/aria2 "$aria2_ref" 2>/dev/null \
      || git -C "$source_dir" fetch -q https://github.com/aria2/aria2
    git -C "$source_dir" checkout -q "$(git -C "$source_dir" rev-parse --verify "${aria2_ref}^{commit}" 2>/dev/null || echo FETCH_HEAD)"
  fi
fi
test "$(git -C "$source_dir" rev-parse --short=12 HEAD)" = "$aria2_ref"
if [[ ! -f "$work/src/configure.ac" ]]; then
  mkdir -p "$work/src"
  rsync -a --exclude .git --exclude .libs --exclude .deps --exclude '*.o' --exclude '*.lo' --exclude '*.la' --exclude '*.a' --exclude Makefile --exclude config.status --exclude config.log --exclude config.h --exclude libtool --exclude stamp-h1 "$source_dir/" "$work/src/"
  patch -p1 -d "$work/src" < "$root/tool/aria2_resume_wakeup.patch"
fi
cd "$work/src"
test -x configure || autoreconf -i
if [[ ! -f config.status ]]; then
  CC="$bin/${triple}$api-clang" CXX="$bin/${triple}$api-clang++" AR="$bin/llvm-ar" RANLIB="$bin/llvm-ranlib" \
  ./configure --host="$host_triple" --enable-libaria2 --disable-shared --enable-static \
    --disable-bittorrent --disable-metalink --disable-sftp --disable-xmlrpc --disable-websocket \
    --without-libxml2 --without-libexpat --without-libcares --without-libssh2 \
    --without-gnutls --without-appletls --without-sqlite3 --without-libgmp \
    --with-openssl --with-ca-bundle=/system/etc/security/cacerts \
    CFLAGS=-fPIC CXXFLAGS=-fPIC CPPFLAGS="-I$work/openssl/include" LDFLAGS="-L$work/openssl/lib" PKG_CONFIG_LIBDIR="$work/openssl/lib/pkgconfig"
fi
make -C src -j2 libaria2.la
out="$root/android/src/main/jniLibs/$abi"
mkdir -p "$out"
"$bin/${triple}$api-clang++" -shared -std=c++17 -x c++ -fPIC \
  -I"$work/src/src/includes" -I"$root/ios/Classes" "$root/ios/Classes/aria2_shim.mm" \
  -x none "$work/src/src/.libs/libaria2.a" "$work/openssl/lib/libssl.a" "$work/openssl/lib/libcrypto.a" \
  -static-libstdc++ -lz -ldl -pthread -Wl,-soname,libtransport_aria2_shim.so -Wl,--exclude-libs,ALL -o "$out/libtransport_aria2_shim.so"
"$bin/llvm-strip" --strip-debug "$out/libtransport_aria2_shim.so"
"$bin/llvm-readelf" -h -d "$out/libtransport_aria2_shim.so"
shasum -a 256 "$out/libtransport_aria2_shim.so"
