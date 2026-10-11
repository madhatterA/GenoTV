#!/usr/bin/env bash
# Run inside MSYS2 MINGW64; only build tools may come from its package manager.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
cache=${LIBMPV_WINDOWS_CACHE:-/tmp/vp-libmpv-windows}
jobs=${LIBMPV_WINDOWS_JOBS:-8}
resume=${1:-}
[[ -z "$resume" || "$resume" = --resume ]]
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] && (( jobs <= 16 ))
export PATH=/mingw64/bin:/usr/bin:$PATH
mkdir -p "$cache/src" "$cache/prefix"
prefix=$(cygpath -m "$cache/prefix")
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export CFLAGS='-O2 -std=gnu11 -Wno-error=incompatible-pointer-types'
export CXXFLAGS='-O2'
export CPPFLAGS="-I$prefix/include"
export LDFLAGS="-L$prefix/lib -static-libgcc -static-libstdc++ -Wl,-Bstatic -lwinpthread -Wl,-Bdynamic"
fetch() {
  local name=$1 repo=$2 pin
  pin=$(awk -v n="$name" '$1==n {print $2}' "$root/packages/playback/native/windows/source-pins.txt")
  test -n "$pin"
  if [[ ! -f "$cache/src/$name/.vp-pin" ]]; then
    curl --fail --location --retry 2 --max-time 180 "https://codeload.github.com/$repo/tar.gz/$pin" -o "$cache/$name.tgz"
    mkdir -p "$cache/src/$name"
    tar --anchored --exclude="${repo##*/}-$pin/README" --exclude="${repo##*/}-$pin/test/relaxng/ambig_name-class.rng" -xzf "$cache/$name.tgz" --strip-components=1 -C "$cache/src/$name"
    # Newer CMake's CPack requires freetype's README (excluded above for the others).
    if [[ "$name" == freetype ]]; then : > "$cache/src/$name/README"; fi
    printf '%s\n' "$pin" > "$cache/src/$name/.vp-pin"
  fi
  test "$(cat "$cache/src/$name/.vp-pin")" = "$pin"
}
fetch mbedtls Mbed-TLS/mbedtls
fetch freetype freetype/freetype
fetch fribidi fribidi/fribidi
fetch harfbuzz harfbuzz/harfbuzz
fetch libass libass/libass
fetch dav1d videolan/dav1d
fetch libxml2 GNOME/libxml2
fetch ffmpeg FFmpeg/FFmpeg
fetch mpv mpv-player/mpv
fetch zlib madler/zlib
cd "$cache/src/mpv"
patch_file="$root/packages/playback/native/windows/mpv-wasapi-mmreg.patch"
if patch --dry-run -p1 < "$patch_file" >/dev/null 2>&1; then
  patch -p1 < "$patch_file"
else
  patch --dry-run -R -p1 < "$patch_file" >/dev/null
fi
# zlib from pinned source, static: libmpv must not import the MSYS zlib1.dll.
if [[ ! -s "$cache/prefix/lib/libz.a" ]]; then
  rm -rf "$cache/zlib" && cp -r "$cache/src/zlib" "$cache/zlib"
  (cd "$cache/zlib" && CHOST=x86_64-w64-mingw32 ./configure --static --prefix="$prefix" && make -j "$jobs" && make install)
fi
cd "$cache/src"
if [[ "$resume" != --resume ]]; then
cmake -S mbedtls -B "$cache/mbedtls" -G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
cmake --build "$cache/mbedtls" -j "$jobs"
cmake --install "$cache/mbedtls"
cmake -S freetype -B "$cache/freetype" -G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON
cmake --build "$cache/freetype" -j "$jobs"
cmake --install "$cache/freetype"
meson setup --reconfigure "$cache/fribidi" fribidi --prefix="$prefix" --libdir=lib --default-library=static --buildtype=release -Ddocs=false -Dtests=false -Dbin=false
ninja -C "$cache/fribidi" -j "$jobs" install
meson setup --reconfigure "$cache/harfbuzz" harfbuzz --prefix="$prefix" --libdir=lib --default-library=static --buildtype=release -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dfreetype=enabled -Dtests=disabled -Dutilities=disabled
ninja -C "$cache/harfbuzz" -j "$jobs" install
# The C-only mpv project needs the static C++ compiler runtime for HarfBuzz.
printf '\nLibs.private: -l:libstdc++.a -l:libwinpthread.a\n' >> "$cache/prefix/lib/pkgconfig/harfbuzz.pc"
iconv_sha=$(awk '$1=="libiconv" {print $2}' "$root/packages/playback/native/windows/source-pins.txt")
if [[ ! -f "$cache/libiconv-release.tgz" ]]; then
  curl --fail --location --retry 2 --max-time 180 https://ftp.gnu.org/gnu/libiconv/libiconv-1.17.tar.gz -o "$cache/libiconv-release.tgz"
fi
printf '%s  %s\n' "$iconv_sha" "$cache/libiconv-release.tgz" | sha256sum -c -
mkdir -p "$cache/src/libiconv-1.17"
tar -xzf "$cache/libiconv-release.tgz" --strip-components=1 -C "$cache/src/libiconv-1.17"
cd libiconv-1.17
./configure --prefix="$prefix" --disable-shared --enable-static --disable-nls
make -j "$jobs"
make install
cd ../libass
./autogen.sh
PKG_CONFIG="/mingw64/bin/pkg-config --static" ./configure --prefix="$prefix" --disable-shared --enable-static --disable-fontconfig --disable-libunibreak --enable-directwrite
make -j "$jobs"
make install
cd ..
meson setup --reconfigure "$cache/dav1d" dav1d --prefix="$prefix" --libdir=lib --default-library=static --buildtype=release -Denable_tools=false -Denable_tests=false
ninja -C "$cache/dav1d" -j "$jobs" install
cmake -S libxml2 -B "$cache/libxml2" -G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ICONV=OFF
cmake --build "$cache/libxml2" -j "$jobs"
cmake --install "$cache/libxml2"
fi
cd "$cache/src/ffmpeg"
patch_file="$root/packages/playback/native/windows/ffmpeg-binutils-shifts.patch"
if patch --dry-run -p1 < "$patch_file" >/dev/null 2>&1; then
  patch -p1 < "$patch_file"
else
  patch --dry-run -R -p1 < "$patch_file" >/dev/null
fi
# Keep all built-in decoders/demuxers/HW acceleration and filters, plus AC3.
# Disable autodetection so tool-installation libraries never enter the engine.
if [[ "$resume" != --resume ]]; then
./configure --prefix="$prefix" --target-os=mingw32 --arch=x86_64 --disable-autodetect --pkg-config-flags=--static --disable-shared --enable-static --disable-doc --disable-debug --disable-ffplay --disable-ffprobe --enable-ffmpeg --enable-version3 --enable-mbedtls --enable-libdav1d --enable-libxml2 --enable-d3d11va --enable-dxva2 --extra-cflags="$CPPFLAGS $CFLAGS" --extra-ldflags="$LDFLAGS"
make -j "$jobs"
fi
if [[ "$resume" != --resume || ! -s "$cache/prefix/lib/libavfilter.a" ]]; then
  make install
fi
# GCC's atomics runtime is part of the compiler; link its static archive.
sed -i 's/-latomic/-l:libatomic.a/g' "$cache/prefix/lib/pkgconfig/"lib*.pc
test -s "$cache/prefix/lib/libiconv.a"
iconv_sha=$(awk '$1=="libiconv" {print $2}' "$root/packages/playback/native/windows/source-pins.txt")
printf '%s  %s\n' "$iconv_sha" "$cache/libiconv-release.tgz" | sha256sum -c -
cd ../mpv
printf '%s\n' '0.36.0-vp-windows-audio-1' > VERSION
# mpv's pkg-config dependencies must include each static library's private links.
pkg_config_native=$(cygpath -w "$(command -v pkg-config)")
printf '@"%s" --static %%*\r\n' "$pkg_config_native" > "$cache/pkg-config-static.bat"
export PKG_CONFIG="$(cygpath -m "$cache/pkg-config-static.bat")"
# mpv 0.36 relies on `union m_option_value val = {0}` zeroing the whole union; GCC 15+ only zeroes the first member.
export CFLAGS="$CFLAGS -fzero-init-padding-bits=unions -I$(cygpath -m "$root/packages/media_kit_libs_windows_video/windows/angle_headers")"
rm -rf "$cache/mpv"
meson setup "$cache/mpv" . --prefix="$prefix" --libdir=lib --buildtype=release --default-library=shared -Dlibmpv=true -Dcplayer=false -Dgpl=false -Dlua=disabled -Dlibplacebo=disabled -Dwasapi=enabled -Dd3d11=disabled -Dgl=enabled -Dgl-win32=enabled -Dplain-gl=enabled -Degl-angle=enabled -Degl-angle-win32=enabled -Degl-angle-lib=disabled -Dd3d-hwaccel=enabled -Dd3d9-hwaccel=enabled -Dtests=false
ninja -C "$cache/mpv" -j "$jobs"
dest="$root/packages/media_kit_libs_windows_video/windows/libmpv"
mkdir -p "$dest/include"
cp "$cache/mpv/libmpv-2.dll" "$dest/"
cp "$cache/mpv/libmpv.dll.a" "$dest/"
cp "$cache/src/mpv/libmpv/"*.h "$dest/include/"
{
  echo 'Windows x86_64 source-built libmpv; vp-windows-audio-1'
  cat "$root/packages/playback/native/windows/source-pins.txt"
  sha256sum "$root/packages/playback/native/windows/"*.patch "$cache/"*.tgz "$dest/libmpv-2.dll" "$dest/libmpv.dll.a"
  gcc --version
  nasm -v
  cat "$cache/mpv/config.h"
  "$cache/prefix/bin/ffmpeg.exe" -version
  "$cache/prefix/bin/ffmpeg.exe" -filters
  "$cache/prefix/bin/ffmpeg.exe" -encoders
  objdump -p "$dest/libmpv-2.dll" | grep 'DLL Name'
} > "$dest/BUILD.txt" 2>&1
if grep -qi 'DLL Name: zlib1' "$dest/BUILD.txt"; then echo 'libmpv imports zlib1.dll' >&2; exit 1; fi
# A tiny real encode exercises the filters and encoder, without an audio override.
"$cache/prefix/bin/ffmpeg.exe" -y -f lavfi -i 'sine=duration=0.1:sample_rate=48000' -af 'pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0,aformat=sample_fmts=fltp,aresample=48000' -c:a ac3 "$cache/ac3-selfcheck.ac3"
test -s "$cache/ac3-selfcheck.ac3"
