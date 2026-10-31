"""Normalize pinned FFmpeg frameworks and publish only a complete signed engine set."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def run_command(args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def source_framework(directory, name):
    candidates = sorted(path for path in directory.glob(name + '*.framework')
                        if re.fullmatch(re.escape(name) + r'(?:\.[0-9]+)*\.framework', path.name))
    if len(candidates) != 1:
        raise ValueError(f'{directory}: expected one {name} framework, found {candidates}')
    folder = candidates[0]
    info = plistlib.loads((folder / 'Info.plist').read_bytes())
    executable = info['CFBundleExecutable']
    if executable != folder.stem:
        raise ValueError(f'{folder}: unexpected executable {executable}')
    binary = folder / executable
    if not binary.is_file():
        raise FileNotFoundError(binary)
    return binary, info


def package_frameworks(frameworks, cache, engines, *, command=run_command):
    frameworks, cache = Path(frameworks), Path(cache)
    if set(engines) != {'ios', 'iossimulator'}:
        raise ValueError('Both device and simulator engines are required')
    replacements = []
    metadata = {}
    for target, engine in engines.items():
        variant = 'ios-arm64-simulator' if target == 'iossimulator' else 'ios-arm64'
        for name in ['Mpv', 'Avcodec', 'Avutil', 'Avfilter']:
            xc = frameworks / (name + '.xcframework')
            info = plistlib.loads((xc / 'Info.plist').read_bytes())
            items = [item for item in info['AvailableLibraries']
                     if item.get('SupportedPlatform') == 'ios' and
                     (item.get('SupportedPlatformVariant') == 'simulator') == (target == 'iossimulator')]
            if len(items) != 1:
                raise ValueError(f'{xc}: expected exactly one {target} slice')
            item = items[0]
            if item['LibraryPath'] != name + '.framework':
                raise ValueError(f'{xc}: unexpected framework path')
            if name == 'Mpv':
                binary = Path(engine)
                bundle = plistlib.loads((xc / item['LibraryIdentifier'] / item['LibraryPath'] / 'Info.plist').read_bytes())
                if not binary.is_file():
                    raise FileNotFoundError(binary)
            else:
                built = cache / ('build/intermediate/frameworks_' + target + '-arm64-video-default')
                binary, bundle = source_framework(built, name)
            replacements.append((name, variant, binary, dict(bundle, CFBundleExecutable=name,
                                CFBundleIdentifier='com.github.media-kit.' + name)))
            # Apply both platform changes to one copy of each XCFramework manifest.
            updated = metadata.setdefault(name, info)
            matching = next(entry for entry in updated['AvailableLibraries']
                            if entry['LibraryIdentifier'] == item['LibraryIdentifier'])
            matching.update(LibraryIdentifier=variant, SupportedArchitectures=['arm64'])

    # Retain staging/backup trees: no deletion, including failures before publication.
    staging = Path(tempfile.mkdtemp(prefix='.ios-framework-stage-', dir=frameworks.parent)) / 'Frameworks'
    shutil.copytree(frameworks, staging, symlinks=True)
    for name, variant, binary, bundle in replacements:
        folder = staging / (name + '.xcframework') / variant / (name + '.framework')
        folder.mkdir(parents=True, exist_ok=True)
        output = folder / name
        shutil.copyfile(binary, output)
        (folder / 'Info.plist').write_bytes(plistlib.dumps(bundle))
        # Modern install_name_tool requires a complete LINKEDIT layout on old unsigned dylibs.
        command(['codesign', '--force', '--sign', '-', output])
        for line in command(['otool', '-L', output]).splitlines()[1:]:
            dep = line.strip().split(' (')[0]
            match = re.fullmatch(r'@rpath/([A-Za-z0-9]+)(?:\.[0-9]+)+\.framework/\1(?:\.[0-9]+)+', dep)
            if match:
                normalized = '@rpath/' + match[1] + '.framework/' + match[1]
                command(['install_name_tool', '-change', dep, normalized, output])
        command(['install_name_tool', '-id', '@rpath/' + name + '.framework/' + name, output])
        command(['codesign', '--force', '--sign', '-', folder])
        command(['codesign', '--verify', '--strict', folder])
    for name, info in metadata.items():
        (staging / (name + '.xcframework') / 'Info.plist').write_bytes(plistlib.dumps(info))
    backup = Path(tempfile.mkdtemp(prefix='.ios-framework-backup-', dir=frameworks.parent)) / 'Frameworks'
    frameworks.rename(backup)
    try:
        staging.rename(frameworks)
    except OSError:
        backup.rename(frameworks)
        raise
    return backup
