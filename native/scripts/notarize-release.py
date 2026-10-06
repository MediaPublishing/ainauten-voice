#!/usr/bin/env python3
"""Submit a Developer-ID app using an existing named notary Keychain profile.

No account, certificate, password or profile is created by this command.
Only Accepted submissions may be stapled and enter the public package path.
"""
import argparse
import json
from pathlib import Path
import subprocess
from distribution_security import verify_distribution_app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--keychain-profile', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    verify_distribution_app(args.app, notarized=False)
    args.output.mkdir(parents=True, exist_ok=False)
    archive = args.output / 'notarization-input.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                    str(args.app), str(archive)], check=True, timeout=120)
    completed = subprocess.run(['xcrun', 'notarytool', 'submit', str(archive),
                                '--keychain-profile', args.keychain_profile,
                                '--wait', '--timeout', '20m', '--output-format', 'json'],
                               capture_output=True, check=True, timeout=1260)
    receipt = json.loads(completed.stdout)
    (args.output / 'submission.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('status') != 'Accepted':
        raise SystemExit('Apple did not accept this app; inspect submission.json. No release allowed.')
    subprocess.run(['xcrun', 'stapler', 'staple', str(args.app)], check=True, timeout=120)
    verified = verify_distribution_app(args.app)
    (args.output / 'verification.json').write_text(json.dumps(verified, indent=2) + '\n')
    print('Apple Accepted; app ticket and distribution checks verified.')


if __name__ == '__main__':
    main()
