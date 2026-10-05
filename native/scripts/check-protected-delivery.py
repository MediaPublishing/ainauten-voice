#!/usr/bin/env python3
"""Real Core guards in owned Comet controls, using synthetic public data only.

No microphone/models, actual passwords, user profiles or permission changes.
The secure-input case briefly enables and balances its own OS secure-input
counter; a pre-existing secure-input owner is never disabled.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


def page(marker, _editor, mode):
    control = '<input id="target" type="password" aria-label="Eigenes synthetisches Passwort">' if mode == 'secure' else '<textarea id="target" aria-label="Eigener Testtext" ' + ('readonly' if mode == 'readonly' else 'disabled' if mode == 'disabled' else '') + '></textarea>'
    return ('''<!doctype html><meta charset="utf-8"><title>MARKER</title>
<h1>Eigene synthetische Schutzprüfung</h1><form>CONTROL<button type="button" id="other">Eigener Testknopf</button></form>
<script>
const target=document.getElementById('target'),other=document.getElementById('other'),initial='Anfang ERSETZEN Ende',mode=MODE;
target.value=initial;let inputs=0,pastes=0,submits=0,sequence=0;
function report(){fetch(location.pathname+'/status',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sequence:++sequence,expectedMatches:target.value===initial,initialMatches:target.value===initial,inputEvents:inputs,pasteEvents:pastes,submitEvents:submits,otherEmpty:other.value==='',activeTarget:document.activeElement===target,activeOther:document.activeElement===other})});}
target.addEventListener('input',()=>{inputs++;report()});target.addEventListener('paste',()=>{pastes++;report()});document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();submits++;report()});
window.addEventListener('load',()=>{if(mode==='disabled')other.focus();else{target.focus();target.setSelectionRange(7,15)}report()});
</script>'''.replace('MARKER', marker).replace('CONTROL', control).replace('MODE', json.dumps(mode))).encode()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--existing-binary', type=Path, help='Use a frozen candidate native artifact; record its hash.')
    parser.add_argument('--output', type=Path, default=root / 'artifacts/receipts/protected-delivery-current.json')
    parser.add_argument('--artifacts-dir', type=Path, default=root / 'artifacts/protected-delivery-checks')
    args = parser.parse_args()
    out = args.artifacts_dir.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        parser.error('artifacts-dir must be inside native/artifacts')
    out.mkdir(parents=True, exist_ok=True); args.output.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    if args.existing_binary:
        binary = args.existing_binary.resolve()
        if not binary.is_file():
            parser.error('existing native artifact unavailable')
    else:
        run = subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '--jobs', '4'], cwd=root, capture_output=True, text=True)
        (out / 'build.log').write_text(run.stdout + run.stderr)
        if run.returncode:
            return run.returncode
        build = root / '.build/arm64-apple-macosx/debug'
        command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-I', str(build / 'Modules'), '-I', str(root / 'Sources/CSQLite'), '-I', str(build / 'FastClusterWrapper.build'), '-I', str(build / 'MachTaskSelfWrapper.build'), '-F', str(build), '-L', str(build)]
        for framework in ['llama', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
            command += ['-framework', framework]
        command += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
        for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
            include = root / '.build/checkouts/FluidAudio/Sources' / target / 'include'
            command += ['-Xcc', '-fmodule-map-file=' + str(include / 'module.modulemap'), '-Xcc', '-I' + str(include)]
        for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
            command += [str(p) for p in sorted((build / target).glob('*.o'))]
        binary = out / 'ProtectedDeliveryChecks'
        command += [str(root / 'Tests/Native/ProtectedDeliveryChecks.swift'), '-o', str(binary)]
        run = subprocess.run(command, cwd=root, capture_output=True, text=True)
        (out / 'compile.log').write_text(run.stdout + run.stderr)
        if run.returncode:
            print(run.stderr); return run.returncode
    # Reuse the established owned-tab HTTP lifecycle and metadata-only schema.
    spec = importlib.util.spec_from_file_location('owned_comet', root / 'scripts/check-comet-delivery.py')
    owner = importlib.util.module_from_spec(spec); spec.loader.exec_module(owner)
    owner.page = page
    cases = []
    modes = ['editable-control', 'secure-input', 'secure', 'readonly', 'disabled']
    for mode in modes:
        case = owner.run_case(binary, out, 'textarea', mode); cases.append(case)
        (out / (mode + '.case.json')).write_text(json.dumps(case, ensure_ascii=False, indent=2) + '\n')
        # Keep an honest rejected test, but never keep opening tabs after an
        # unobserved cleanup or failed preparation.
        native = case['native']
        if not native or not native.get('closedOwnTab') or not native.get('foregroundAppRestored'):
            break
    report = {'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
              'allPassed': len(cases) == len(modes) and all(c['native'] and c['native'].get('passed') for c in cases),
              'expectedCases': len(modes), 'cases': cases, 'nativeBinarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'coreDeliverySHA256': hashlib.sha256((root / 'Sources/VoiceWisprCore/Delivery.swift').read_bytes()).hexdigest(),
              'microphoneUsed': False, 'modelsLoaded': False, 'clipboardContentsLogged': False,
              'scope': 'Actual owned controls and Core no-paste guard only; not installed hotkey/capture, general OS/p95 or hardware acceptance.'}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'allPassed': report['allPassed'], 'cases': len(cases), 'passed': sum(bool(c['native'] and c['native'].get('passed')) for c in cases)}))
    return 0 if report['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
