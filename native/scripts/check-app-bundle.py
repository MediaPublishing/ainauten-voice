#!/usr/bin/env python3
"""Retained, isolated Mach-O fixtures for the missing-library launch regression."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from app_bundle import verify_runtime
from package_dmg import create_dmg

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = args.output or root / 'artifacts/receipts' / ('app-bundle-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
out = out.resolve()
out.mkdir(parents=True, exist_ok=False)
app = out / 'valid/AInauten Voice.app'
macos = app / 'Contents/MacOS'; frameworks = app / 'Contents/Frameworks'
macos.mkdir(parents=True); frameworks.mkdir()
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable': 'Fixture', 'CFBundleIdentifier': 'com.mediapublishing.VoiceWispr',
    'CFBundleShortVersionString': '0.0.0'}))
sources = {'leaf.c': 'int leaf(void) { return 0; }\n',
           'library.c': 'extern int leaf(void); int fixture(void) { return leaf(); }\n',
           'main.c': 'extern int fixture(void); int main(void) { return fixture(); }\n'}
for name, text in sources.items():
    (out / name).write_text(text)
cc = ['xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=14.0']
subprocess.run(cc + ['-dynamiclib', str(out / 'leaf.c'), '-install_name', '@rpath/libleaf.dylib',
                    '-o', str(frameworks / 'libleaf.dylib')], check=True)
subprocess.run(cc + ['-dynamiclib', str(out / 'library.c'), '-L', str(frameworks), '-lleaf',
                    '-install_name', '@rpath/libfixture.dylib', '-o', str(frameworks / 'libfixture.dylib')], check=True)
subprocess.run(cc + [str(out / 'main.c'), '-L', str(frameworks), '-lfixture',
                    '-Wl,-rpath,@executable_path/../Frameworks', '-Wl,-headerpad_max_install_names',
                    '-o', str(macos / 'Fixture')], check=True)
assert verify_runtime(app) == 3
checks = ['bundled transitive dependencies resolve']
relocated = out / 'moved directory/AInauten Voice.app'
shutil.copytree(app, relocated, symlinks=True)
assert verify_runtime(relocated) == 3
checks.append('bundle relocation preserves relative library lookup')

def reject(label, mutate, expected):
    fixture = out / label / 'AInauten Voice.app'
    shutil.copytree(app, fixture, symlinks=True)
    mutate(fixture)
    try:
        verify_runtime(fixture)
    except ValueError as error:
        assert expected in str(error), error
    else:
        raise AssertionError(label + ' was accepted')
    checks.append(label + ' rejected')
    return fixture

bad = reject('missing-rpath', lambda a: subprocess.run(
    ['install_name_tool', '-delete_rpath', '@executable_path/../Frameworks', str(a / 'Contents/MacOS/Fixture')], check=True),
    '@rpath/libfixture.dylib')
reject('missing-transitive-library', lambda a: (a / 'Contents/Frameworks/libleaf.dylib').rename(
    a / 'Contents/Frameworks/libleaf.disabled'), '@rpath/libleaf.dylib')
reject('external-development-library', lambda a: subprocess.run(
    ['install_name_tool', '-change', '@rpath/libfixture.dylib', str(frameworks / 'libfixture.dylib'),
     str(a / 'Contents/MacOS/Fixture')], check=True), str(frameworks / 'libfixture.dylib'))
rejected_dmg = out / 'rejected-dmg'
try:
    create_dmg(bad, rejected_dmg)
except ValueError as error:
    assert '@rpath/libfixture.dylib' in str(error), error
else:
    raise AssertionError('DMG packaging accepted broken runtime')
assert not rejected_dmg.exists()
checks.append('DMG creation stops before producing an invalid installer')
(out / 'receipt.json').write_text(json.dumps({'status': 'pass', 'checks': checks, 'fixture_apps_launched': False}, indent=2) + '\n')
print(f'BUNDLE REGRESSION PASS: {len(checks)} checks; receipt {out / "receipt.json"}')
