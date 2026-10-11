#!/usr/bin/env bash
# Builds libaria2 (static, AppleTLS) from pinned source and links it with the shared aria2 C shim
# into macos/libs/libtransport_aria2_shim.dylib. No Homebrew runtime dependency; Homebrew only
# supplies build tools (autoconf/automake).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir=${ARIA2_SOURCE:-"$root/../../research/technical/downloading/aria2"}
aria2_ref=${ARIA2_REF:-9e7273583f83}
deployment_target=${MACOSX_DEPLOYMENT_TARGET:-12.0}
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
export PATH="/opt/homebrew/bin:$PATH"
[[ "$(uname -m)" == arm64 ]] || { echo 'macOS native baseline requires arm64' >&2; exit 2; }
test -f "$source_dir/configure.ac" || { echo "not an aria2 source checkout: $source_dir" >&2; exit 1; }
if test -d "$source_dir/.git"; then
  actual_ref=$(git -C "$source_dir" rev-parse HEAD)
  case "$actual_ref" in
    "$aria2_ref"*) ;;
    *) echo "aria2 checkout $actual_ref does not match pinned ref $aria2_ref" >&2; exit 1;;
  esac
fi
command -v autoreconf >/dev/null || { echo 'autoreconf (Homebrew autoconf/automake) is required' >&2; exit 1; }

# Build in a space-free scratch copy: the source checkout stays untouched (research/ is read-only).
work="$(mktemp -d /tmp/transport-aria2-macos.XXXXXX)"
trap 'rm -rf "$work"' EXIT
rsync -a --exclude .git --exclude "*.o" --exclude "*.lo" --exclude "*.a" --exclude "*.la" --exclude .libs --exclude .deps --exclude config.status --exclude config.log --exclude config.h --exclude Makefile --exclude stamp-h1 --exclude libtool "$source_dir/" "$work/src/"
patch -p1 -d "$work/src" < "$root/tool/aria2_resume_wakeup.patch"
cd "$work/src"
make distclean >/dev/null 2>&1 || true
test -x configure || autoreconf -i
flags="-arch arm64 -mmacosx-version-min=$deployment_target -isysroot $(xcrun --sdk macosx --show-sdk-path)"
CC=/usr/bin/clang CXX=/usr/bin/clang++ ./configure \
  --enable-libaria2 --disable-shared --enable-static \
  --disable-bittorrent --disable-metalink --disable-sftp \
  --disable-xmlrpc --disable-websocket \
  --without-libxml2 --without-libexpat --without-libcares --without-libssh2 \
  --without-openssl --without-gnutls \
  CFLAGS="$flags" CXXFLAGS="$flags" LDFLAGS="$flags"
make -C src -j"$(sysctl -n hw.ncpu)" libaria2.la

artifact="$root/macos/libs/libtransport_aria2_shim.dylib"
mkdir -p "$root/macos/libs"
/usr/bin/clang++ -dynamiclib -std=gnu++17 -x objective-c++ $flags \
  -I"$work/src/src/includes" -I"$root/ios/Classes" \
  "$root/ios/Classes/aria2_shim.mm" \
  -Wl,-force_load,"$work/src/src/.libs/libaria2.a" \
  -framework Security -framework CoreFoundation -framework SystemConfiguration \
  -lz -lsqlite3 -install_name @rpath/libtransport_aria2_shim.dylib -o "$artifact"
codesign --force --sign - "$artifact"
if otool -L "$artifact" | grep -qE '/opt/homebrew|/usr/local'; then
  echo 'unexpected Homebrew runtime dependency' >&2; exit 1
fi
echo "Built $artifact"
