#!/usr/bin/env python3
"""Open synthetic fixture documents in TextEdit and check current Core delivery.
Uses existing Accessibility permission; never requests or changes permissions.
Saves/closes only its own documents and restores the preceding foreground app.
Clipboard bytes stay in RAM. No microphone, models, user settings or cloud calls.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import uuid


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--include-fullscreen', action='store_true', help='Also test and exit fullscreen in an own fixture window.')
    parser.add_argument('--output', type=Path, default=root / 'artifacts/receipts/textedit-delivery-current.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out = root / 'artifacts/textedit-delivery-checks'
    out.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    # Use the native debug object layout already used by portable-checks.py.
    # Do not rebuild or replace a possibly running release speech Probe.
    build_run = subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '--jobs', '4'],
                               cwd=root, capture_output=True, text=True)
    (out / 'build.log').write_text(build_run.stdout + build_run.stderr)
    if build_run.returncode:
        raise SystemExit(build_run.returncode)
    build = root / '.build/arm64-apple-macosx/debug'
    command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0',
               '-I', str(build / 'Modules'), '-I', str(root / 'Sources/CSQLite'),
               '-I', str(build / 'FastClusterWrapper.build'), '-I', str(build / 'MachTaskSelfWrapper.build'),
               '-F', str(build), '-L', str(build)]
    for framework in ['llama', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
        command += ['-framework', framework]
    command += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
    for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
        include = root / '.build/checkouts/FluidAudio/Sources' / target / 'include'
        command += ['-Xcc', '-fmodule-map-file=' + str(include / 'module.modulemap'), '-Xcc', '-I' + str(include)]
    for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
        command += [str(p) for p in sorted((build / target).glob('*.o'))]
    binary = out / 'TextEditDeliveryChecks'
    command += [str(root / 'Tests/Native/TextEditDeliveryChecks.swift'), '-o', str(binary)]
    compile_run = subprocess.run(command, cwd=root, capture_output=True, text=True)
    (out / 'compile.log').write_text(compile_run.stdout + compile_run.stderr)
    if compile_run.returncode:
        raise SystemExit(compile_run.returncode)
    cases = []
    modes = ['selection', 'caret', 'long', 'focus'] + (['fullscreen'] if args.include_fullscreen else [])
    for mode in modes:
        file = out / ('AInauten-Voice-Delivery-' + mode + '-' + str(uuid.uuid4()) + '.txt')
        case_started = datetime.now(timezone.utc).isoformat()
        run = subprocess.run([str(binary), str(file), mode], cwd=root, capture_output=True, text=True, timeout=30)
        (out / (mode + '.stdout')).write_text(run.stdout)
        (out / (mode + '.stderr')).write_text(run.stderr)
        try:
            native = json.loads(run.stdout) if run.returncode == 0 else None
        except ValueError:
            native = None
        case = {'mode': mode, 'startedAt': case_started, 'endedAt': datetime.now(timezone.utc).isoformat(),
                'exitCode': run.returncode, 'native': native}
        cases.append(case)
        # Never keep opening new documents after a failed/unsafe UI preparation.
        if not isinstance(native, dict) or not native.get('passed'):
            break
    report = {'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
              'expectedCases': len(modes), 'allPassed': len(cases) == len(modes) and all(isinstance(case['native'], dict) and case['native'].get('passed') for case in cases),
              'cases': cases, 'productionChanged': False, 'clipboardContentsLogged': False,
              'microphoneUsed': False, 'modelsLoaded': False,
              'scope': 'Requested real TextEdit Core delivery cases, with explicit optional fullscreen. No physical hotkey, microphone, ASR, installed Pill/recovery UI, multi-display or full OS matrix/p95 acceptance.'}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'allPassed': report['allPassed'], 'cases': len(cases),
                      'passed': sum(bool(case['native'] and case['native'].get('passed')) for case in cases)}))
    return 0 if report['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
