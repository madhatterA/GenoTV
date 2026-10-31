"""Publish the source-built arm64 macOS engine into the local media_kit_libs_macos_video package.

Each upstream universal framework has both slices replaced by the pinned builds (arm64 and cross-compiled amd64), re-identified as @rpath/<Name>.framework/Versions/A/<Name> and ad-hoc signed.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

CACHE = Path(os.environ.get('LIBMPV_IOS_SIM_CACHE', '/tmp/vp-libmpv-ios-recipe-v0.6.0'))
ROOT = Path(__file__).resolve().parents[3]
UPSTREAM = Path(os.environ.get('MEDIA_KIT_MACOS_UPSTREAM', Path.home() / '.pub-cache/hosted/pub.dev/media_kit_libs_macos_video-1.1.4/macos/Frameworks'))
OUT = ROOT / 'packages/media_kit_libs_macos_video/macos/Frameworks'
INTER = CACHE / 'build/intermediate'


def sources(arch, suffix):
    ffmpeg = INTER / f'ffmpeg_macos-{arch}-video-default/lib'
    lib = lambda pkg, name: INTER / f'{pkg}_macos-{arch}/lib/{name}'
    return {
        'Mpv': CACHE / f'metal/engine-macos-metal{suffix}/lib/libmpv.2.dylib',
        'Ass': lib('libass', 'libass.9.dylib'),
        'Avcodec': ffmpeg / 'libavcodec.60.3.100.dylib', 'Avfilter': ffmpeg / 'libavfilter.9.3.100.dylib',
        'Avformat': ffmpeg / 'libavformat.60.3.100.dylib', 'Avutil': ffmpeg / 'libavutil.58.2.100.dylib',
        'Swresample': ffmpeg / 'libswresample.4.10.100.dylib', 'Swscale': ffmpeg / 'libswscale.7.1.100.dylib',
        'Uchardet': lib('uchardet', 'libuchardet.0.0.8.dylib'), 'Dav1d': lib('dav1d', 'libdav1d.6.dylib'),
        'Freetype': lib('freetype', 'libfreetype.6.dylib'), 'Fribidi': lib('fribidi', 'libfribidi.0.dylib'),
        'Harfbuzz': lib('harfbuzz', 'libharfbuzz.0.dylib'),
        'Mbedcrypto': lib('mbedtls', 'libmbedcrypto.14.dylib'), 'Mbedtls': lib('mbedtls', 'libmbedtls.19.dylib'),
        'Mbedx509': lib('mbedtls', 'libmbedx509.5.dylib'), 'Png16': lib('freetype', 'libpng16.16.dylib'),
        'Xml2': lib('libxml2', 'libxml2.2.dylib'),
    }


ARCHES = {'arm64': sources('arm64', ''), 'x86_64': sources('amd64', '-amd64')}


def out(*args):
    return subprocess.check_output([str(a) for a in args], text=True)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def deps(binary):
    return [line.strip().split(' (')[0] for line in out('otool', '-L', binary).splitlines()[1:]]


assert (UPSTREAM / 'Mpv.xcframework').is_dir(), UPSTREAM
stage = Path(tempfile.mkdtemp(prefix='.macos-framework-stage-', dir=OUT.parent.parent)) / 'Frameworks'
shutil.copytree(UPSTREAM, stage, symlinks=True)
work = Path(tempfile.mkdtemp(prefix='macos-engine-'))
for name in ARCHES['arm64']:
    framework = stage / (name + '.xcframework/macos-arm64_x86_64') / (name + '.framework')
    binary = framework / 'Versions/A' / name
    slices = []
    for arch, table in ARCHES.items():
        # install-name basename -> framework (ffmpeg ids use the short soname, e.g. libavcodec.60.dylib)
        by_id = {}
        for n, path in table.items():
            assert path.is_file(), path
            by_id[Path(out('otool', '-D', path).splitlines()[1].strip()).name] = n
            by_id[path.name] = n
        thin = work / f'{name}.{arch}'
        shutil.copyfile(table[name], thin)
        run('install_name_tool', '-id', f'@rpath/{name}.framework/Versions/A/{name}', thin)
        for dep in deps(thin)[1:]:
            match = by_id.get(Path(dep).name)
            if match:
                run('install_name_tool', '-change', dep, f'@rpath/{match}.framework/Versions/A/{match}', thin)
            else:
                assert dep.startswith(('/System/', '/usr/lib/')), f'{name} {arch}: unexpected dependency {dep}'
        slices.append(thin)
    binary.unlink()
    run('lipo', '-create', *slices, '-output', binary)
    run('codesign', '--force', '--sign', '-', binary)
    assert '/tmp/' not in out('otool', '-L', '-arch', 'all', binary), name
for arch in ARCHES:
    symbols = out('nm', '-g', '-arch', arch, stage / 'Mpv.xcframework/macos-arm64_x86_64/Mpv.framework/Versions/A/Mpv')
    for symbol in ['_pl_shader_dovi_reshape', '_mpv_ios_surface_frame_count', '_mpv_ios_surface_status']:
        assert symbol in symbols, (arch, symbol)
if OUT.exists():
    OUT.rename(OUT.with_name('Frameworks.previous-' + os.urandom(3).hex()))  # retained, never deleted
stage.rename(OUT)
print('macOS engine published to', OUT)
