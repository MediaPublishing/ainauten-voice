#!/usr/bin/env python3
"""Exercise packaged and missing language resources without a developer fallback.

Only the real localization source and Foundation/Combine are compiled. The
module accessor deliberately traps if called: an .app must never use it. These
small native fixtures do not load AppModel, models, settings or permissions.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sdk', type=pathlib.Path)
p.add_argument('--source', type=pathlib.Path, help='Explicit historical localization source for a controlled baseline reproduction')
args = p.parse_args()
out = root/'artifacts'/('bundled-localization-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
out.mkdir(parents=True)
source = args.source or root/'Sources/VoiceWisprCore/InterfaceLanguage.swift'
frozen = out/'InterfaceLanguage.swift'
shutil.copy2(source, frozen)
driver = out/'BundledLocalizationChecks.swift'
shutil.copy2(root/'Tests/Native/BundledLocalizationChecks.swift', driver)
accessor = out/'UnavailableModule.swift'
accessor.write_text('import Foundation\nextension Bundle { static let module: Bundle = { fatalError("Developer resource fallback is unavailable") }() }\n')
binary = out/'ResourceProbe'
cmd = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O', '-target', 'arm64-apple-macosx14.0']
if args.sdk: cmd += ['-sdk', str(args.sdk)]
cmd += [str(frozen), str(accessor), str(driver), '-o', str(binary)]
(out/'compile-command.json').write_text(json.dumps(cmd, indent=2)+'\n')
with (out/'compile.log').open('w') as log:
    compiled = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compiled.returncode: raise SystemExit(compiled.returncode)
results = []
for mode in ['packaged', 'missing']:
    app = out/mode/'ResourceProbe.app'
    contents = app/'Contents'
    (contents/'MacOS').mkdir(parents=True)
    (contents/'Resources').mkdir()
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ResourceProbe', 'CFBundleIdentifier':'com.mediapublishing.bundled-localization-check', 'CFBundlePackageType':'APPL'}))
    shutil.copy2(binary, contents/'MacOS/ResourceProbe')
    if mode == 'packaged':
        bundle = contents/'Resources/VoiceWispr_VoiceWisprCore.bundle'
        shutil.copytree(root/'Sources/VoiceWisprCore/Localization', bundle)
        (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleDevelopmentRegion':'en'}))
    invocation = [str(contents/'MacOS/ResourceProbe')] + (['--missing'] if mode == 'missing' else [])
    run = subprocess.run(invocation, cwd=out, capture_output=True, text=True, timeout=30)
    (out/f'{mode}.stdout.log').write_text(run.stdout)
    (out/f'{mode}.stderr.log').write_text(run.stderr)
    results.append({'mode':mode, 'command':invocation, 'exitCode':run.returncode})
receipt = {'sourceSHA256':hashlib.sha256(frozen.read_bytes()).hexdigest(), 'binarySHA256':hashlib.sha256(binary.read_bytes()).hexdigest(), 'compileExit':compiled.returncode, 'runs':results, 'models':False, 'settings':False}
(out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print('BUNDLED LOCALIZATION RECEIPT', out)
if any(r['exitCode'] != 0 for r in results): raise SystemExit(1)
print('PASS: packaged translations and controlled missing-resource fallback; no developer module accessor')
