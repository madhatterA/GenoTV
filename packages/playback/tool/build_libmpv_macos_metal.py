"""Build a pinned macOS (MACOS_ARCH=arm64 default, or amd64 cross-compiled) gpu-next engine without changing the installed engine.

Prepare the pinned recipe with build_libmpv_ios_sim.sh BUILD_ONLY=1 first. Output
is staged in the recipe cache for surface acceptance before packaging.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess

CACHE = Path(os.environ.get('LIBMPV_IOS_SIM_CACHE', '/tmp/vp-libmpv-ios-recipe-v0.6.0'))
METAL = CACHE / 'metal'
ARCH = os.environ.get('MACOS_ARCH', 'arm64')
assert ARCH in ('arm64', 'amd64'), ARCH
SUFFIX = '' if ARCH == 'arm64' else '-' + ARCH
ROOT = Path(__file__).resolve().parents[3]
PATCH = ROOT / 'packages/playback/tool/macos_metal_mpv.patch'


def run(args, *, cwd=None, env=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


for source, pin in [(CACHE, '4286f5557bdccc0747030e3c376ce5cd160a96a0'),
                    (METAL / 'MoltenVK', '02a8c011a8ca077dfaa09f3b7ebf68be869dc26f'),
                    (METAL / 'libplacebo', 'ed29e541a55acf28022738440b2a925386292551')]:
    assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == pin
molten = METAL / 'MoltenVK'
placebo = METAL / 'libplacebo'
fetch_env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin:' + os.environ['PATH'])
# Xcode 27 rejects deployment targets below iOS/tvOS 15 and macOS 12; raise MoltenVK's external-dependency project to the SDK minimum.
def lift_deployment_targets():
    for pbx in molten.rglob('project.pbxproj'):
        text = pbx.read_text()
        fixed = re.sub(r'(IPHONEOS|TVOS)_DEPLOYMENT_TARGET = 1[0-4]\.\d+', r'\1_DEPLOYMENT_TARGET = 15.0',
                       re.sub(r'MACOSX_DEPLOYMENT_TARGET = 1[01]\.\d+', 'MACOSX_DEPLOYMENT_TARGET = 12.0', text))
        if fixed != text:
            pbx.write_text(fixed)


lift_deployment_targets()
run(['./fetchDependencies', '--macos'], cwd=molten, env=fetch_env)
lift_deployment_targets()
run(['make', 'macos'], cwd=molten)
baseline_cross = CACHE / f'cross-files/macos-{ARCH}.ini'
baseline_cross.write_text(baseline_cross.read_text().replace('-mmacosx-version-min=10.9', '-mmacosx-version-min=11.0'))
run(['make', 'PROJECT_DIR=' + str(CACHE), 'build/intermediate/mpv_macos-' + ARCH + '-video'], cwd=CACHE)
prefix = METAL / f'prefix-macos{SUFFIX}'
lib = prefix / 'lib'
pc = lib / 'pkgconfig'
pc.mkdir(parents=True, exist_ok=True)
variant = 'macos-arm64_x86_64'
external = molten / 'External/build/Release'
libraries = {'MoltenVK': molten / 'Package/Release/MoltenVK/MoltenVK.xcframework' / variant / 'libMoltenVK.a'}
for name in ['SPIRV', 'MachineIndependent', 'OSDependent', 'OGLCompiler', 'GenericCodeGen']:
    libraries[name] = external / 'glslang.xcframework' / variant / 'libglslang.a'
libraries['SPIRV-Tools'] = external / 'SPIRVTools.xcframework' / variant / 'libSPIRVTools.a'
for name, source in libraries.items():
    assert source.is_file(), source
    alias = lib / ('lib' + name + '.a')
    if not alias.exists():
        alias.symlink_to(source)
(pc / 'vulkan.pc').write_text(
    'Name: Vulkan\nDescription: Pinned MoltenVK\nVersion: 1.3.250\n'
    f'Cflags: -I{molten}/External/Vulkan-Headers/include\n'
    f'Libs: -L{lib} -lMoltenVK -framework Metal -framework Foundation -framework QuartzCore -framework IOSurface -lc++\n')
cross = METAL / f'cross-macos{SUFFIX}.ini'
s = (CACHE / f'cross-files/macos-{ARCH}.ini').read_text()
s = s.replace("'-mmacosx-version-min=11.0'", ', '.join(map(repr, [
    '-mmacosx-version-min=11.0', f'-I{molten}/External/glslang',
    f'-I{molten}/External/glslang/build/include', f'-L{lib}'])))
cross.write_text(s)
p = placebo / 'src/glsl/meson.build'
run(['git', 'checkout', '--', 'src/glsl/meson.build', 'src/vulkan/swapchain.c'], cwd=placebo)
p.write_text(re.sub(r'(cxx\.find_library\([^\n]*?)(required:)',
                    r'\1dirs: ' + repr(str(lib)) + r', \2', p.read_text()))
swapchain = placebo / 'src/vulkan/swapchain.c'
swapchain.write_text(swapchain.read_text().replace(
    '    for (int i = 0; i < p->formats.num; i++) {',
    '    for (int i = 0; i < p->formats.num; i++) {\n'
    '        if (p->formats.elem[i].format != VK_FORMAT_R16G16B16A16_SFLOAT ||\n'
    '            p->formats.elem[i].colorSpace != VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT)\n'
    '            continue;'))
deps = [str(path) for path in (CACHE / 'build/intermediate').glob('*_macos-' + ARCH + '*/lib/pkgconfig')
        if 'failed-' not in str(path)]
env = dict(os.environ, PKG_CONFIG_PATH=':'.join(deps + [str(pc)]), PKG_CONFIG_LIBDIR=str(CACHE / 'build/sdk-pc'))
build = METAL / f'placebo-macos{SUFFIX}'
setup = ['meson', 'setup', build, placebo, '--cross-file', cross, '--prefix', prefix,
         '-Ddefault_library=static', '-Dvulkan=enabled', '-Dglslang=enabled', '-Dshaderc=disabled',
         '-Dopengl=disabled', '-Dd3d11=disabled', '-Dlcms=disabled', '-Ddovi=enabled',
         '-Dlibdovi=disabled', '-Ddemos=false', '-Dtests=false', '-Dbench=false', '-Dunwind=disabled',
         '-Dvulkan-registry=' + str(molten / 'External/Vulkan-Headers/registry/vk.xml')]
if build.exists():
    setup.append('--reconfigure')
run(setup, env=env)
run(['meson', 'compile', '-j4', '-C', build], env=env)
run(['meson', 'install', '-C', build], env=env)
source = METAL / ('mpv-macos-metal' + SUFFIX + '-' + hashlib.sha256(PATCH.read_bytes()).hexdigest()[:16])
source.mkdir(exist_ok=True)
if not (source / 'meson.build').exists():
    run(['tar', '-xf', CACHE / 'build/intermediate/downloads/mpv-0.36.0.tar.gz', '--strip-components', '1', '-C', source])
script = (CACHE / 'scripts/mpv/build.sh').read_text().replace(
    'meson setup build \\',
    'patch -p1 <"' + str(PATCH) + '"\n'
    'OPTIONS+=(-Dlibplacebo=enabled -Dvulkan=enabled)\nmeson setup build \\')
script = script.replace('--cross-file ${PROJECT_DIR}/cross-files/${OS}-${ARCH}.ini', '--cross-file ' + str(cross))
# mpv uses Swift for Cocoa. The pinned recipe predates Xcode's executable lookup.
script = script.replace('patch -p1 <${PROJECT_DIR}/patches/mpv-fix-missing-objc.patch',
                        'patch --forward -p1 <${PROJECT_DIR}/patches/mpv-fix-missing-objc.patch')
build_script = METAL / f'mpv-build-macos{SUFFIX}.sh'
build_script.write_text(script)
output = METAL / f'engine-macos-metal{SUFFIX}'
env.update(PROJECT_DIR=str(CACHE), SRC_DIR=str(source), OUTPUT_DIR=str(output), OS='macos', ARCH=ARCH, VARIANT='video')
if (source / 'build/build.ninja').exists():
    run(['meson', 'compile', '-j4', '-C', source / 'build'], env=env)
    run(['meson', 'install', '-C', source / 'build'], env=env)
else:
    run(['bash', build_script], env=env)
binary = output / 'lib/libmpv.2.dylib'
symbols = subprocess.check_output(['nm', '-g', str(binary)], text=True)
assert '_pl_shader_dovi_reshape' in symbols
for name in ['frame_count', 'set_active', 'status', 'live_count', 'unregister']:
    assert '_mpv_ios_surface_' + name in symbols, name
linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
assert '/opt/homebrew' not in linked and '/usr/local' not in linked, linked
print(ARCH + ' macOS pinned gpu-next + DOVI engine built; original packaged engine unchanged; skipped=0')
