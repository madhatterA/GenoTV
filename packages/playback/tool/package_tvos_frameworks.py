"""Package the built tvOS device+simulator frameworks as xcframeworks in media_kit_libs_tvos_video."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(os.environ.get('VP_IOS_ROOT', Path(__file__).resolve().parents[3]))
CACHE = Path(os.environ.get('VP_IOS_CACHE', '/tmp/vp-libmpv-ios-recipe-v0.6.0'))
OUT = ROOT / 'packages/media_kit_libs_tvos_video/tvos/Frameworks'
if OUT.exists():
    raise SystemExit(f'{OUT} exists; move it aside (no deletes) and rerun')
stage = Path(tempfile.mkdtemp(prefix='vp-tvos-stage-'))


def sh(*args):
    return subprocess.check_output([str(a) for a in args], text=True)


def build(target, name):
    """Return a clean, signed-ad-hoc Name.framework copy for one slice."""
    src = CACHE / ('build/intermediate/frameworks_' + target + '-arm64-video-default')
    found = [d for d in src.glob(name + '*.framework') if re.fullmatch(name + r'(\.[0-9]+)*\.framework', d.name)]
    assert len(found) == 1, (target, name, found)
    binary = found[0] / found[0].stem
    if name == 'Mpv':
        binary = CACHE / ('metal/engine-' + target + '/lib/libmpv.2.dylib')
    info = plistlib.loads((found[0] / 'Info.plist').read_bytes())
    info.update(CFBundleExecutable=name, CFBundleIdentifier='com.github.media-kit.' + name)
    fw = stage / target / (name + '.framework')
    fw.mkdir(parents=True)
    shutil.copyfile(binary, fw / name)
    (fw / 'Info.plist').write_bytes(plistlib.dumps(info))
    sh('codesign', '--force', '--sign', '-', fw / name)
    for line in sh('otool', '-L', fw / name).splitlines()[1:]:
        dep = line.strip().split(' (')[0]
        m = re.fullmatch(r'@rpath/([A-Za-z0-9]+)(?:\.[0-9]+)+\.framework/\1(?:\.[0-9]+)+', dep)
        if m:
            sh('install_name_tool', '-change', dep, '@rpath/%s.framework/%s' % (m[1], m[1]), fw / name)
    sh('install_name_tool', '-id', '@rpath/%s.framework/%s' % (name, name), fw / name)
    sh('codesign', '--force', '--sign', '-', fw)
    return fw


sim = CACHE / 'build/intermediate/frameworks_tvossimulator-arm64-video-default'
names = sorted({re.sub(r'(\.[0-9]+)*\.framework$', '', d.name) for d in sim.glob('*.framework')})
OUT.mkdir(parents=True)
for name in names:
    sh('xcodebuild', '-create-xcframework', '-framework', build('tvos', name),
       '-framework', build('tvossimulator', name), '-output', OUT / (name + '.xcframework'))
    print(name, flush=True)
