#!/usr/bin/env bash
# Public entry builds Metal for both iOS slices; explicit BUILD_ONLY is internal preparation.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
if [ -z "${LIBMPV_IOS_SIM_BUILD_ONLY+x}" ]; then
  exec bash "$root/packages/playback/tool/build_libmpv_ios_metal.sh"
fi
cache=${LIBMPV_IOS_SIM_CACHE:-/tmp/vp-libmpv-ios-recipe-v0.6.0}
pin=4286f5557bdccc0747030e3c376ce5cd160a96a0
for tool in git meson ninja cmake nasm pkg-config python3 timeout; do command -v "$tool" >/dev/null; done
if [ ! -d "$cache/.git" ]; then
  git init "$cache"
  git -C "$cache" remote add origin https://github.com/media-kit/libmpv-darwin-build.git
  git -C "$cache" fetch --depth 1 origin "$pin"
  git -C "$cache" checkout --detach "$pin"
fi
test "$(git -C "$cache" rev-parse HEAD)" = "$pin"
export VP_IOS_CACHE="$cache" VP_IOS_ROOT="$root"
python3 - <<'PY'
import hashlib
import os
from pathlib import Path
import subprocess
import shutil
import re

cache = Path(os.environ['VP_IOS_CACHE'])
root = Path(os.environ['VP_IOS_ROOT'])
subprocess.run(['git', '-C', str(cache), 'checkout', '--', 'Makefile', 'scripts', 'cross-files'], check=True)
lock = root / 'packages/playback/native/ios-simulator/downloads.lock'
assert lock.read_bytes() == (cache / 'downloads.lock').read_bytes()
entries = {}
for line in lock.read_text().splitlines():
    if not line.startswith(' '):
        name = line.rstrip(':')
        entries[name] = {}
    else:
        key, value = line.strip().split(': ', 1)
        entries[name][key] = value.strip('"')
downloads = cache / 'build/intermediate/downloads'
downloads.mkdir(parents=True, exist_ok=True)
needed = ['dav1d', 'ffmpeg', 'freetype', 'fribidi', 'harfbuzz', 'libass',
          'libxml2', 'mbedtls', 'mpv', 'pkg-config', 'uchardet']
for name in needed:
    entry = entries[name]
    suffix = '.tar.' + entry['url'].split('.tar.')[-1]
    dest = downloads / (name + '-' + entry['version'] + suffix)
    if not dest.exists():
        subprocess.run(['curl', '--fail', '-L', '--max-time', '90', entry['url'],
                        '-o', str(dest)], check=True)
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == entry['sha256'], name
    print(name, entry['version'], entry['sha256'], flush=True)
# Serialize dependency builds. Bound every compiler batch to four jobs.
p = cache / 'Makefile'
p.write_text(p.read_text().replace('MAKEFLAGS += "-j -l $(shell sysctl -n hw.ncpu) "',
                                 'MAKEFLAGS += -j1\n.SECONDARY:'))
for p in (cache / 'scripts').rglob('build.sh'):
    p.write_text(p.read_text().replace('meson compile -C', 'meson compile -j4 -C'))
# Current Meson requires CMake to be named explicitly for cross subprojects.
for p in (cache / 'cross-files').glob('*.ini'):
    text = p.read_text().replace("pkgconfig = ['pkg-config']",
                                "pkgconfig = ['pkg-config']\ncmake = ['cmake']")
    if p.name.startswith('iossimulator-'):
        text = text.replace('-miphoneos-version-min=12.0', '-mios-simulator-version-min=12.0')
    p.write_text(text)
# tvOS (LIBMPV_PLATFORM=tvos): same recipe, cross files derived from the iOS ones with the tvOS SDK and minimum.
tv = {'tvos': ('ios-arm64', 'iPhoneOS', 'AppleTVOS', '-miphoneos-version-min=9.0', '-mtvos-version-min=15.0'),
      'tvossimulator': ('iossimulator-arm64', 'iPhoneSimulator', 'AppleTVSimulator',
                        '-mios-simulator-version-min=12.0', '-mtvos-simulator-version-min=15.0')}
for name, (base, old_sdk, new_sdk, old_min, new_min) in tv.items():
    text = (cache / 'cross-files' / (base + '.ini')).read_text()
    assert old_min in text and old_sdk + '.platform' in text, name
    (cache / 'cross-files' / (name + '-arm64.ini')).write_text(
        text.replace(old_sdk, new_sdk).replace(old_min, new_min))
# Invalidate artifacts emitted with the old device target flag on first migration.
marker = cache / 'build/.vp-simulator-target-v1'
if not marker.exists():
    for p in (cache / 'build/intermediate').glob('*iossimulator*'):
        shutil.rmtree(p)
    marker.touch()
for name in ['mbedtls', 'uchardet']:
    p = cache / ('scripts/' + name + '/meson.build')
    p.write_text(p.read_text().replace('options.add_cmake_defines({',
        "options.add_cmake_defines({\n    'CMAKE_POLICY_VERSION_MINIMUM': '3.5',\n    'CMAKE_BUILD_TYPE': 'Release',"))
p = cache / 'scripts/uchardet/build.sh'
p.write_text(p.read_text().replace('cmake ./subprojects/uchardet',
    'cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release ./subprojects/uchardet'))
# libpng's classic-Mac fp.h branch misdetects modern Xcode TargetConditionals.
# Use the standard math header; no libpng feature or recipe option changes.
p = cache / 'scripts/freetype/build.sh'
p.write_text(p.read_text().replace('meson compile -j4 -C build',
    "sed -i '' 's/<fp.h>/<math.h>/' subprojects/libpng-*/pngpriv.h\nmeson compile -j4 -C build"))
# New Meson CMake import emits versioned files; restore upstream -l lookup names.
p = cache / 'scripts/mbedtls/build.sh'
p.write_text(p.read_text() + '''
for name in mbedtls mbedcrypto mbedx509; do
    cd "${OUTPUT_DIR}/lib"
    for file in lib${name}.*.dylib; do ln -sf "$file" "lib${name}.dylib"; done
done
''')
lib = cache / 'build/intermediate/mbedtls_iossimulator-arm64/lib'
for name in ['mbedtls', 'mbedcrypto', 'mbedx509']:
    for file in lib.glob('lib' + name + '.*.dylib'):
        alias = lib / ('lib' + name + '.dylib')
        if not alias.exists():
            alias.symlink_to(file.name)
# pkg-config is a host build tool; upstream's bundled GLib predates current Clang.
host = 'arm64' if os.uname().machine == 'arm64' else 'amd64'
tools = cache / ('build/intermediate/pkg-config_macos-' + host) / 'bin'
tools.mkdir(parents=True, exist_ok=True)
pc = tools / 'pkg-config'
if pc.is_symlink():
    pc.unlink()
sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip())
sdk_pc = cache / 'build/sdk-pc'
sdk_pc.mkdir(exist_ok=True)
version = re.search(r'#define ZLIB_VERSION "([^"]+)"', (sdk / 'usr/include/zlib.h').read_text())[1]
(sdk_pc / 'zlib.pc').write_text('Name: zlib\nDescription: Apple simulator SDK zlib\nVersion: ' +
    version + '\nLibs: -lz\nCflags:\n')
pc.write_text('#!/bin/sh\nexport PKG_CONFIG_LIBDIR=' + str(sdk_pc) + '\nexec ' +
              shutil.which('pkg-config') + ' "$@"\n')
pc.chmod(0o755)
alias = tools / 'pkgconfig'
if not alias.exists():
    alias.symlink_to('pkg-config')
# The default flavour enables only overlay/equalizer filters; mpv's lavfi chain
# (Kodi stereo upmix `pan`) needs these audio filters, the yadif/bwdif/scale video filters and the TrueHD/MLP decoders. Rebuild FFmpeg and everything
# downstream once when this list changes.
p = cache / 'scripts/ffmpeg/meson.build'
p.write_text(p.read_text().replace("    '--enable-filter=equalizer',\n",
    "    '--enable-filter=equalizer',\n" + ''.join(
        "    '--enable-filter=" + f + "',\n"
        for f in ['abuffer', 'abuffersink', 'pan', 'aformat', 'aresample',
                  'yadif', 'bwdif', 'scale', 'format', 'buffer', 'buffersink']) + ''.join(
        "    '--enable-" + f + "',\n"
        for f in ['decoder=truehd', 'decoder=mlp', 'parser=mlp', 'demuxer=mlp']), 1))
marker = cache / 'build/.vp-ffmpeg-audio-filters-v2'
if not marker.exists():
    for prefix in ['ffmpeg_', 'mpv_', 'libs-arch_', 'libs_', 'frameworks_']:
        for p in (cache / 'build/intermediate').glob(prefix + 'iossimulator*'):
            shutil.rmtree(p)
    marker.touch()
# harfbuzz 7.2.0 calls sincosf, which the Xcode 27 SDK no longer declares; __sincosf is the same function.
p = cache / 'scripts/harfbuzz/build.sh'
p.write_text(p.read_text().replace('cd ${SRC_DIR}\n',
    'cd ${SRC_DIR}\nsed -i "" "s/sincosf (/__sincosf (/" src/OT/glyf/VarCompositeGlyph.hh\n', 1))
# Metal needs original NV12/P010 VideoToolbox output, not the old GLES BGRA8 override.
patch = root / 'packages/playback/tool/ios_metal_ffmpeg.patch'
shutil.copyfile(patch, cache / 'patches/vp-ios-metal-ffmpeg.patch')
p = cache / 'scripts/ffmpeg/build.sh'
p.write_text(p.read_text().replace(
    'patch -p1 <${PROJECT_DIR}/patches/ffmpeg-fix-ios-hdr-texture.patch\n', '').replace(
    'cd ${SRC_DIR}', 'cd ${SRC_DIR}\npatch -p1 <${PROJECT_DIR}/patches/vp-ios-metal-ffmpeg.patch'))
marker = cache / ('build/.vp-ios-metal-decoder-' + hashlib.sha256(patch.read_bytes()).hexdigest())
if not marker.exists():
    for prefix in ['ffmpeg_', 'mpv_', 'libs-arch_', 'libs_', 'frameworks_']:
        for p in (cache / 'build/intermediate').glob(prefix + 'ios*'):
            shutil.rmtree(p)
    marker.touch()
# The simulator needs the same ios-gl VideoToolbox interop as the device slice
# (IOS_VIDEO_OPTIONS applies to iossimulator now); rebuild mpv and downstream once.
marker = cache / 'build/.vp-mpv-ios-gl-v1'
if not marker.exists():
    for prefix in ['mpv_', 'libs-arch_', 'libs_', 'frameworks_']:
        for p in (cache / 'build/intermediate').glob(prefix + 'iossimulator*'):
            shutil.rmtree(p)
    marker.touch()
# Rebuild the pinned engine when our simulator IOSurface upload patch changes.
patch = root / 'packages/playback/tool/ios_sim_gl_upload.patch'
marker = cache / ('build/.vp-mpv-sim-upload-' + hashlib.sha256(patch.read_bytes()).hexdigest())
if not marker.exists():
    for prefix in ['mpv_', 'libs-arch_', 'libs_', 'frameworks_']:
        for p in (cache / 'build/intermediate').glob(prefix + 'iossimulator*'):
            shutil.rmtree(p)
    marker.touch()
shutil.copyfile(patch, cache / 'patches/vp-ios-sim-gl-upload.patch')
# Meson's external_project otherwise starts make -j(cpu_count), ignoring -j4.
links = cache / 'build/intermediate/links/bin'
links.mkdir(parents=True, exist_ok=True)
for name in ['meson', 'ninja', 'cmake', 'nasm']:
    p = links / name
    if not p.exists():
        p.symlink_to(shutil.which(name))
make = links / 'make'
make.write_text('#!/bin/sh\nexec /usr/bin/make "$@" -j4\n')
make.chmod(0o755)
p = cache / 'scripts/mpv/build.sh'
p.write_text(p.read_text().replace('cd ${SRC_DIR}',
    'cd ${SRC_DIR}\nif [ "${OS}" == "iossimulator" ]; then\n'
    '    patch -p1 <${PROJECT_DIR}/patches/vp-ios-sim-gl-upload.patch\nfi\n'
    # tvOS forbids fork/execve: build mpv's no-op subprocess source instead of the posix one (no run/ytdl subprocess on tvOS).
    'if [[ "${OS}" == tvos* ]]; then\n'
    '    sed -i "" "s|subprocess_source = files(.osdep/subprocess-posix.c.)|subprocess_source = files(cc.get_define(\'TARGET_OS_TV\', prefix: \'#include <TargetConditionals.h>\') == \'1\' ? \'osdep/subprocess-dummy.c\' : \'osdep/subprocess-posix.c\')|" meson.build\n'
    'fi')
    .replace('elif [ "${OS}" == "ios" ]; then',
    'elif [[ "${OS}" == ios* || "${OS}" == tvos* ]]; then')
)
p = cache / 'scripts/frameworks/build.sh'
p.write_text(p.read_text().replace('elif [ "${OS}" == "ios" ] || [ "${OS}" == "iossimulator" ]; then',
    'elif [ "${OS}" == "ios" ] || [ "${OS}" == "iossimulator" ] || [ "${OS}" == "tvos" ] || [ "${OS}" == "tvossimulator" ]; then'))
# Keep the host pkg-config wrapper newer than downloads/ and links/, or make rebuilds the bundled GLib (fails on current Clang).
os.utime(tools.parent)
PY
cd "$cache"
if [ "${LIBMPV_PLATFORM:-ios}" = tvos ]; then
  timeout "${LIBMPV_MAKE_TIMEOUT:-900}" make -j1 build/intermediate/frameworks_tvossimulator-arm64-video-default build/intermediate/frameworks_tvos-arm64-video-default
  exit 0
fi
timeout "${LIBMPV_MAKE_TIMEOUT:-900}" make -j1 build/intermediate/frameworks_iossimulator-arm64-video-default
if [ "${LIBMPV_IOS_SIM_BUILD_ONLY:-0}" = 1 ]; then exit 0; fi
plugin="$root/packages/media_kit_libs_ios_video/ios"
mkdir -p "$plugin/.cache"
archive="$plugin/.cache/upstream-v0.6.0.tar.gz"
if [ ! -f "$archive" ]; then
  curl --fail -L --max-time 90 https://github.com/media-kit/libmpv-darwin-build/releases/download/v0.6.0/libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz -o "$archive"
fi
echo "a95bc18508af26136b8a408341c05b5585d644ec013f00ac07db09d2e28d36ae  $archive" | shasum -a 256 -c -
rm -rf "$plugin/Frameworks"
mkdir -p "$plugin/Frameworks"
tar -xf "$archive" --strip-components 1 -C "$plugin/Frameworks"
# Only Mpv's simulator variant is replaced. Device and dependency bytes stay upstream.
mpv="$plugin/Frameworks/Mpv.xcframework"
rm -rf "$mpv/ios-arm64_x86_64-simulator"
mkdir -p "$mpv/ios-arm64-simulator"
cp -R build/intermediate/frameworks_iossimulator-arm64-video-default/Mpv.framework "$mpv/ios-arm64-simulator/"
python3 - "$mpv/Info.plist" <<'PY'
import plistlib
from pathlib import Path
import sys
p = Path(sys.argv[1])
info = plistlib.loads(p.read_bytes())
for variant in info['AvailableLibraries']:
    if variant.get('SupportedPlatformVariant') == 'simulator':
        variant['LibraryIdentifier'] = 'ios-arm64-simulator'
        variant['SupportedArchitectures'] = ['arm64']
p.write_bytes(plistlib.dumps(info))
PY
# Avfilter's simulator variant is also ours: upstream's has no audio filters (pan etc.).
built=build/intermediate/frameworks_iossimulator-arm64-video-default/Avfilter.framework
avf="$plugin/Frameworks/Avfilter.xcframework"
rm -rf "$avf/ios-arm64_x86_64-simulator"
mkdir -p "$avf/ios-arm64-simulator/Avfilter.framework"
cp "$built/Avfilter" "$avf/ios-arm64-simulator/Avfilter.framework/Avfilter"
install_name_tool -id @rpath/Avfilter.framework/Avfilter "$avf/ios-arm64-simulator/Avfilter.framework/Avfilter"
cp "$plugin/Frameworks/Avutil.xcframework/ios-arm64_x86_64-simulator/Avutil.framework/Info.plist" "$avf/ios-arm64-simulator/Avfilter.framework/Info.plist"
plutil -replace CFBundleExecutable -string Avfilter "$avf/ios-arm64-simulator/Avfilter.framework/Info.plist"
plutil -replace CFBundleIdentifier -string com.github.media-kit.Avfilter "$avf/ios-arm64-simulator/Avfilter.framework/Info.plist"
python3 - "$avf/Info.plist" <<'PY'
import plistlib
from pathlib import Path
import sys
p = Path(sys.argv[1])
info = plistlib.loads(p.read_bytes())
for variant in info['AvailableLibraries']:
    if variant.get('SupportedPlatformVariant') == 'simulator':
        variant['LibraryIdentifier'] = 'ios-arm64-simulator'
        variant['SupportedArchitectures'] = ['arm64']
p.write_bytes(plistlib.dumps(info))
PY
cd "$plugin"
rm -rf Frameworks/.symlinks
mkdir -p Frameworks/.symlinks/mpv
sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
strings Frameworks/Mpv.xcframework/ios-arm64-simulator/Mpv.framework/Mpv | grep -F -- '-Daudiounit=enabled'
