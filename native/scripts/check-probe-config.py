#!/usr/bin/env python3
"""Check the native suite configuration without loading speech/formatting models."""
import argparse
import json
import subprocess
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe', type=Path, default=root / '.build/release/VoiceWisprProbe')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cases = [
        ([], {'encoderPrecision': 'int8', 'dualDecodeArbitration': False, 'sdkWorkers': 2,
              'vadSilenceSeconds': 0.5, 'trimTrailingSilence': False}),
        (['--dual-decode'], {'encoderPrecision': 'int8', 'dualDecodeArbitration': True}),
        (['--encoder-v2'], {'encoderPrecision': 'int8-v2', 'dualDecodeArbitration': False}),
        (['--encoder-v2', '--dual-decode', '--sdk-workers=1', '--vad-silence=0.25', '--trim-tail'],
         {'encoderPrecision': 'int8-v2', 'dualDecodeArbitration': True, 'sdkWorkers': 1,
          'vadSilenceSeconds': 0.25, 'trimTrailingSilence': True}),
    ]
    results = []
    for flags, expected in cases:
        command = [str(args.probe.resolve()), 'speech-config-check', *flags]
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=20)
            actual = json.loads(run.stdout) if run.returncode == 0 else None
            passed = (isinstance(actual, dict) and actual.get('event') == 'speech-config-check'
                      and actual.get('loadsModels') is False
                      and all(actual.get(key) == value for key, value in expected.items()))
            results.append({'flags': flags, 'expected': expected, 'actual': actual,
                            'exitCode': run.returncode, 'passed': passed})
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            results.append({'flags': flags, 'passed': False, 'error': str(error)})
    report = {'allPassed': all(case['passed'] for case in results), 'cases': results,
              'scope': 'native shared suite configuration only; no inference, microphone or insertion',
              'humanAcceptance': False}
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'allPassed': report['allPassed'], 'cases': len(results),
                      'passed': sum(case['passed'] for case in results)}))
    return 0 if report['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
