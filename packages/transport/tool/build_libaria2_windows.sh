#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
export PATH="/mingw64/bin:$PATH"
work="${ARIA2_WINDOWS_CACHE:-/c/transport-native/aria2}"
case "$work" in *' '*) echo 'Build cache must have no spaces' >&2; exit 2 ;; esac
mkdir -p "$work"
zlib="$work/zlib-1.3.1.tar.gz"
if [[ ! -f "$zlib" ]]; then
  curl --fail --location --connect-timeout 15 --max-time 120 https://zlib.net/fossils/zlib-1.3.1.tar.gz -o "$zlib"
fi
[[ "$(sha256sum "$zlib" | cut -d ' ' -f 1)" == 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23 ]]
if [[ ! -d "$work/zlib-1.3.1" ]]; then tar -xf "$zlib" -C "$work"; fi
make -C "$work/zlib-1.3.1" -f win32/Makefile.gcc -j2 libz.a
if [[ ! -f "$work/src/configure.ac" ]]; then
  archive="$work/aria2.tar.gz"
  curl --fail --location --connect-timeout 15 --max-time 120 \
    https://codeload.github.com/aria2/aria2/tar.gz/9e7273583f83 -o "$archive"
  [[ "$(sha256sum "$archive" | cut -d ' ' -f 1)" == 78c902dce711d8fe0a847fffa633dcd665ee7d0b0267ab1c3f33ca2fa6daf8a7 ]]
  mkdir -p "$work/src"
  tar -xf "$archive" -C "$work/src" --strip-components=1
fi
if [[ ! -f "$work/src/.resume-wakeup-patched" ]]; then
  patch -p1 -d "$work/src" < "$root/tool/aria2_resume_wakeup.patch"
  touch "$work/src/.resume-wakeup-patched"
fi
cd "$work/src"
test -x configure || autoreconf -i
if [[ ! -f config.status ]]; then
  ./configure --host=x86_64-w64-mingw32 --enable-libaria2 --disable-shared --enable-static --disable-nls \
    --disable-bittorrent --disable-metalink --disable-sftp --disable-xmlrpc --disable-websocket \
    --without-libxml2 --without-libexpat --without-libcares --without-libssh2 \
    --without-gnutls --without-openssl --without-appletls --without-sqlite3 --without-libgmp \
    --with-wintls --with-libz \
    CPPFLAGS="-I$work/zlib-1.3.1" LDFLAGS="-L$work/zlib-1.3.1" PKG_CONFIG_LIBDIR="$work/empty"
fi
make -C src -j2 libaria2.la
out="$root/windows/native"
mkdir -p "$out"
{ echo EXPORTS; grep -Eo 'transport_aria2_[A-Za-z0-9_]+[[:space:]]*\(' "$root/ios/Classes/aria2_shim.h" | sed 's/[[:space:]]*(//' | sort -u; } > "$work/shim.def"
x86_64-w64-mingw32-g++ -shared -static -std=c++17 -x c++ \
  -I"$work/src/src/includes" -I"$root/ios/Classes" "$root/ios/Classes/aria2_shim.mm" \
  -x none "$work/src/src/.libs/libaria2.a" "$work/shim.def" "$work/zlib-1.3.1/libz.a" \
  -lws2_32 -lcrypt32 -lsecur32 -ladvapi32 -liphlpapi -lshlwapi \
  -o "$out/transport_aria2_shim.dll"
objdump -p "$out/transport_aria2_shim.dll" | grep -E 'DLL Name|transport_aria2_'
sha256sum "$out/transport_aria2_shim.dll"
