"""Build the two native iOS (or, LIBMPV_PLATFORM=tvos, tvOS) engine slices; iOS stages only after both compile."""
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(os.environ['VP_IOS_ROOT'])
CACHE = Path(os.environ['VP_IOS_CACHE'])
METAL = CACHE / 'metal'
METAL.mkdir(exist_ok=True)
MOLTEN_PIN = '02a8c011a8ca077dfaa09f3b7ebf68be869dc26f'
TVOS = os.environ.get('LIBMPV_PLATFORM', 'ios') == 'tvos'
PLATFORM = 'tvos' if TVOS else 'ios'
PLACEBO_PIN = 'ed29e541a55acf28022738440b2a925386292551'


def variant_dir(base, simulator):
    # tvOS device slices are named tvos-arm64_arm64e; iOS keeps its original names.
    names = [PLATFORM + '-arm64_x86_64-simulator'] if simulator else [PLATFORM + '-arm64', PLATFORM + '-arm64_arm64e']
    return next((n for n in names if (base / n).is_dir()), names[0])


def run(args, *, cwd=None, env=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


def checkout(name, url, pin):
    path = METAL / name
    if not (path / '.git').exists():
        run(['git', 'init', path])
        run(['git', 'remote', 'add', 'origin', url], cwd=path)
        run(['git', 'fetch', '--depth', '1', 'origin', pin], cwd=path)
        run(['git', 'checkout', '--detach', pin], cwd=path)
    assert subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip() == pin
    return path


# tvOS gets its own MoltenVK checkout so its external-dependency xcframeworks never replace the iOS ones.
molten = checkout('MoltenVK-tvos' if TVOS else 'MoltenVK', 'https://github.com/KhronosGroup/MoltenVK.git', MOLTEN_PIN)
placebo = checkout('libplacebo', 'https://github.com/haasn/libplacebo.git', PLACEBO_PIN)
run(['git', 'submodule', 'update', '--init', '--recursive'], cwd=placebo)
# The pinned generator's ElementTree input predates Python 3.14's type check.
run(['git', 'checkout', '--', 'src/vulkan/utils_gen.py', 'src/glsl/meson.build', 'src/glsl/glslang.cc', 'src/vulkan/swapchain.c'], cwd=placebo)
p = placebo / 'src/vulkan/utils_gen.py'
p.write_text(p.read_text().replace('VkXML(ET.parse(xmlfile))', 'VkXML(ET.parse(xmlfile).getroot())'))
p = placebo / 'src/glsl/glslang.cc'
s = p.read_text().replace('#if (GLSLANG_VERSION_MAJOR * 1000 + GLSLANG_VERSION_MINOR) >= 11013\n#include <glslang/Public/ResourceLimits.h>\n#define DefaultTBuiltInResource *GetDefaultResources()\n#endif\n', '')
p.write_text(s)
# iOS pins the fp16 display-P3 linear swapchain (EDR); tvOS has no EDR, so libplacebo picks its normal SDR format.
if not TVOS:
    p = placebo / 'src/vulkan/swapchain.c'
    s = p.read_text().replace('    for (int i = 0; i < p->formats.num; i++) {',
        '    for (int i = 0; i < p->formats.num; i++) {\n'
        '        if (p->formats.elem[i].format != VK_FORMAT_R16G16B16A16_SFLOAT ||\n'
        '            p->formats.elem[i].colorSpace != VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT)\n'
        '            continue;')
    p.write_text(s)
run(['git', 'checkout', '--', 'MoltenVK/MoltenVK/Utility/MVKSmallVector.h', 'MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm', 'Common/MVKOSExtensions.mm'], cwd=molten)
run(['git', 'apply', '--unidiff-zero', '--ignore-whitespace', ROOT / 'packages/playback/tool/ios_moltenvk_libcxx.patch'], cwd=molten)
# MoltenVK reports 0 bytes of system memory on tvOS, so libplacebo's max_buf_size is 0 and every vertex buffer fails (no picture).
if TVOS:
    run(['git', 'apply', '--unidiff-zero', '--ignore-whitespace', ROOT / 'packages/playback/tool/ios_moltenvk_tvos_memsize.patch'], cwd=molten)
# Xcode's Python 3.9 has the distutils needed by the pinned dependency downloader.
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
run(['./fetchDependencies'] + (['--tvos', '--tvossim'] if TVOS else ['--ios', '--iossim']), cwd=molten, env=fetch_env)
for platform in [PLATFORM, PLATFORM + 'sim']:
    lift_deployment_targets()
    run(['make', platform], cwd=molten)
    xcf = molten / 'Package/Release/MoltenVK/MoltenVK.xcframework'
    variant = variant_dir(xcf, platform.endswith('sim'))
    shutil.copyfile(xcf / variant / 'libMoltenVK.a', METAL / ('MoltenVK-' + platform + '.a'))
header = molten / 'External/glslang/glslang/SPIRV'
if not header.exists():
    header.symlink_to('../SPIRV')

engines = {}
for target, platform in [(PLATFORM + 'simulator', PLATFORM + 'sim'), (PLATFORM, PLATFORM)]:
    if target == 'ios':
        run(['make', '-j1', 'PROJECT_DIR=' + str(CACHE), 'build/intermediate/frameworks_ios-arm64-video-default'], cwd=CACHE)
    prefix = METAL / ('prefix-' + target)
    lib = prefix / 'lib'
    pc = lib / 'pkgconfig'
    pc.mkdir(parents=True, exist_ok=True)
    external = molten / 'External/build/Release'
    variant = variant_dir(external / 'glslang.xcframework', target.endswith('simulator'))
    libraries = {'MoltenVK': METAL / ('MoltenVK-' + platform + '.a')}
    for name in ['SPIRV', 'MachineIndependent', 'OSDependent', 'OGLCompiler', 'GenericCodeGen']:
        libraries[name] = external / 'glslang.xcframework' / variant / 'libglslang.a'
    libraries['SPIRV-Tools'] = external / 'SPIRVTools.xcframework' / variant / 'libSPIRVTools.a'
    for name, source in libraries.items():
        assert source.is_file(), source
        alias = lib / ('lib' + name + '.a')
        alias.unlink(missing_ok=True)
        alias.symlink_to(source)
    (pc / 'vulkan.pc').write_text(
        'Name: Vulkan\nDescription: Pinned MoltenVK\nVersion: 1.3.250\n'
        f'Cflags: -I{molten}/External/Vulkan-Headers/include\n'
        f'Libs: -L{lib} -lMoltenVK -framework Metal -framework Foundation -framework QuartzCore -framework IOSurface -lc++\n')
    cross = METAL / ('cross-' + target + '.ini')
    s = (CACHE / 'cross-files' / (target + '-arm64.ini')).read_text()
    minimum = {'iossimulator': '-mios-simulator-version-min=12.0', 'ios': '-miphoneos-version-min=12.0',
               'tvossimulator': '-mtvos-simulator-version-min=15.0', 'tvos': '-mtvos-version-min=15.0'}[target]
    additions = [f'-I{molten}/External/glslang', f'-I{molten}/External/glslang/build/include', f'-L{lib}']
    s = s.replace(repr(minimum), ', '.join(map(repr, [minimum] + additions)))
    cross.write_text(s)
    p = placebo / 'src/glsl/meson.build'
    run(['git', 'checkout', '--', 'src/glsl/meson.build'], cwd=placebo)
    s = p.read_text()
    s = re.sub(r'(cxx\.find_library\([^\n]*?)(required:)', r'\1dirs: ' + repr(str(lib)) + r', \2', s)
    p.write_text(s)
    deps = [str(path) for path in (CACHE / 'build/intermediate').glob('*_' + target + '-arm64*/lib/pkgconfig')]
    env = dict(os.environ, PKG_CONFIG_PATH=':'.join(deps + [str(pc)]), PKG_CONFIG_LIBDIR=str(CACHE / 'build/sdk-pc'))
    build = METAL / ('placebo-' + target)
    setup = ['meson', 'setup', build, placebo, '--cross-file', cross, '--prefix', prefix,
             '-Ddefault_library=static', '-Dvulkan=enabled', '-Dglslang=enabled', '-Dshaderc=disabled',
             '-Dopengl=disabled', '-Dd3d11=disabled', '-Dlcms=disabled', '-Ddovi=enabled',
             '-Dlibdovi=disabled', '-Ddemos=false', '-Dtests=false', '-Dbench=false', '-Dunwind=disabled',
             '-Dvulkan-registry=' + str(molten / 'External/Vulkan-Headers/registry/vk.xml')]
    if build.exists():
        setup.append('--wipe')
    run(setup, env=env)
    run(['meson', 'compile', '-j4', '-C', build], env=env)
    run(['meson', 'install', '-C', build], env=env)
    source = METAL / ('mpv-' + target)
    if source.exists():
        shutil.rmtree(source)
    source.mkdir()
    run(['tar', '-xf', CACHE / 'build/intermediate/downloads/mpv-0.36.0.tar.gz', '--strip-components', '1', '-C', source])
    script = (CACHE / 'scripts/mpv/build.sh').read_text()
    script = script.replace('meson setup build \\',
        'patch -p1 <"' + str(ROOT / 'packages/playback/tool/ios_metal_mpv.patch') + '"\n'
        'OPTIONS+=(-Dlibplacebo=enabled -Dvulkan=enabled)\nmeson setup build \\')
    build_script = METAL / ('mpv-build-' + target + '.sh')
    build_script.write_text(script)
    output = METAL / ('engine-' + target)
    env.update(PROJECT_DIR=str(CACHE), SRC_DIR=str(source), OUTPUT_DIR=str(output), OS=target, ARCH='arm64', VARIANT='video')
    run(['bash', build_script], env=env)
    binary = output / 'lib/libmpv.2.dylib'
    names = {'ass': 'Ass', 'avcodec': 'Avcodec', 'avfilter': 'Avfilter', 'avformat': 'Avformat',
             'avutil': 'Avutil', 'swresample': 'Swresample', 'swscale': 'Swscale', 'uchardet': 'Uchardet'}
    for line in subprocess.check_output(['otool', '-L', str(binary)], text=True).splitlines()[1:]:
        dep = line.strip().split(' (')[0]
        match = re.search(r'/lib([a-z]+)\.[0-9]+\.dylib$', dep)
        if match and match[1] in names:
            name = names[match[1]]
            run(['install_name_tool', '-change', dep, '@rpath/' + name + '.framework/' + name, binary])
    run(['install_name_tool', '-id', '@rpath/Mpv.framework/Mpv', binary])
    symbols = subprocess.check_output(['nm', '-g', str(binary)], text=True)
    for name in ['frame_count', 'set_active', 'status', 'live_count', 'unregister']:
        assert '_mpv_ios_surface_' + name in symbols, name
    undefined = subprocess.check_output(['nm', '-u', str(binary)], text=True)
    assert 'GetDefaultResources' not in undefined and 'glslang' not in undefined, undefined
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    assert all(str(CACHE) not in line for line in linked.splitlines()[1:]), linked
    engines[target] = binary

if TVOS:
    print('tvOS engines built: ' + ', '.join(f'{t}={b}' for t, b in engines.items()), flush=True)
    raise SystemExit(0)
frameworks = ROOT / 'packages/media_kit_libs_ios_video/ios/Frameworks'
assert frameworks.is_dir(), 'Run the baseline packaging script once to stage the pinned dependency frameworks.'
from ios_framework_packaging import package_frameworks
backup = package_frameworks(frameworks, CACHE, engines)
print(f'Previous frameworks retained at {backup}; list in TO_DELETE.md after review.', flush=True)
print('iOS Metal engines: device+simulator built; 5 C symbols each; no cache dependency paths; skipped=0', flush=True)
