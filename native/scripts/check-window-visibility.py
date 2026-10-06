#!/usr/bin/env python3
"""Observe the installed app's windows after explicit UI preparation.

No application activation, input synthesis, clipboard, preference, content or
permission access. Never launches or restarts the app. Raw samples are retained.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=['foreground', 'background', 'closed'], required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    args = parser.parse_args()
    out = args.output_dir.resolve()
    if not out.is_relative_to((root / 'artifacts/receipts').resolve()):
        parser.error('output-dir must be inside native/artifacts/receipts')
    out.mkdir(parents=True, exist_ok=True)
    result_path = out / (args.stage + '-RESULT.json')
    if result_path.exists():
        parser.error('preserve existing stage result; use a new output directory for a justified retry')
    source = root / 'Tests/Native/WindowVisibilityChecks.swift'
    binary = out / 'WindowVisibilityChecks'
    compile_command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                       '-target', 'arm64-apple-macosx14.0']
    if args.sdk:
        compile_command += ['-sdk', str(args.sdk)]
    compile_command += ['-framework', 'AppKit', '-framework', 'CoreGraphics',
                        '-framework', 'ApplicationServices', str(source), '-o', str(binary)]
    compile_run = subprocess.run(compile_command, capture_output=True, text=True, timeout=90)
    (out / (args.stage + '-compile.log')).write_text(compile_run.stdout + compile_run.stderr)
    if compile_run.returncode:
        print(json.dumps({'passed': False, 'compileExit': compile_run.returncode}))
        return compile_run.returncode
    command = [str(binary), '/Applications/AInauten Voice.app', '3']
    started = datetime.now(timezone.utc).isoformat()
    run = subprocess.run(command, capture_output=True, text=True, timeout=15)
    (out / (args.stage + '-raw.json')).write_text(run.stdout)
    (out / (args.stage + '-stderr.log')).write_text(run.stderr)
    observed = None
    try:
        observed = json.loads(run.stdout) if run.returncode == 0 else None
    except ValueError:
        pass
    checks = {}
    if observed:
        samples = observed['samples']
        exposed = lambda sample: [window for window in sample['windows']
                                 if window['onScreen'] and window['alpha'] > 0]
        checks['duration'] = observed['sampleDuration'] >= 3 and len(samples) >= 2
        checks['processLive'] = observed['processRemainedLive']
        checks['noPill'] = all(not any(w['pillNamed'] or w['pillFrame'] for w in exposed(s)) for s in samples)
        checks['activation'] = all(s['processActive'] == (args.stage == 'foreground')
                                   and s['frontmostMatches'] == (args.stage == 'foreground') for s in samples)
        checks['mainWindow'] = all(any(w['mainSized'] for w in exposed(s)) == (args.stage != 'closed') for s in samples)
    passed = bool(checks) and all(checks.values())
    report = {'stage': args.stage, 'startedAtUTC': started,
              'endedAtUTC': datetime.now(timezone.utc).isoformat(),
              'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'compileCommand': compile_command, 'command': command, 'exitCode': run.returncode,
              'checks': checks, 'passed': passed,
              'rawEvidence': args.stage + '-raw.json',
              'limits': 'Observed surfaces in prepared resting UI condition only. No post-dictation transition, microphone, p95, multi-display/fullscreen or future-state acceptance.'}
    result_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'stage': args.stage, 'passed': passed, 'checks': checks}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
