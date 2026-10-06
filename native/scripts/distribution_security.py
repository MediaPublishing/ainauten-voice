"""Fail-closed Apple distribution checks. Never provisions credentials or keys."""
import plistlib
import re
import subprocess
from pathlib import Path

DEVELOPER_ID = ('anchor apple generic and '
                'certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
                'certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
FORBIDDEN = {
    'com.apple.security.cs.disable-library-validation',
    'com.apple.security.cs.allow-dyld-environment-variables',
    'com.apple.security.cs.allow-unsigned-executable-memory',
    'com.apple.security.cs.disable-executable-page-protection',
    'com.apple.security.get-task-allow',
}
MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
         b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
         b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def require(condition, message):
    if not condition:
        raise ValueError('Apple distribution check: ' + message)


def run(command):
    return subprocess.run(list(map(str, command)), check=True, capture_output=True,
                          timeout=60)


def validate_metadata(metadata, entitlements, expected_team=None):
    match = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', metadata, re.MULTILINE)
    require(match is not None, 'Developer ID Team ID missing; local signing cannot be distributed')
    team = match[1]
    require(expected_team is None or team == expected_team, 'nested code has a different Team ID')
    require(re.search(r'^Authority=Developer ID Application:', metadata, re.MULTILINE),
            'Developer ID Application signing required')
    require(re.search(r'^CodeDirectory .*flags=.*\bruntime\b', metadata, re.MULTILINE),
            'hardened runtime missing')
    require(re.search(r'^Timestamp=.+$', metadata, re.MULTILINE), 'secure signing timestamp missing')
    require(isinstance(entitlements, dict), 'invalid entitlements')
    require(not any(entitlements.get(key) for key in FORBIDDEN),
            'library validation or code-injection protection disabled')
    return team


def verify_code(path, expected_team=None):
    run(['codesign', '--verify', '--strict', '-R', '=' + DEVELOPER_ID, path])
    metadata = run(['codesign', '-dv', '--verbose=4', path]).stderr.decode()
    payload = run(['codesign', '-d', '--entitlements', '-', '--xml', path]).stdout
    entitlements = plistlib.loads(payload) if payload.strip() else {}
    return validate_metadata(metadata, entitlements, expected_team)


def verify_ticket(path):
    run(['xcrun', 'stapler', 'validate', path])


def verify_distribution_app(app, *, notarized=True):
    app = Path(app)
    require(app.is_dir() and not app.is_symlink(), 'regular app required')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == 'com.mediapublishing.VoiceWispr',
            'wrong application identity')
    run(['codesign', '--verify', '--deep', '--strict', app])
    team = verify_code(app)
    # Enumerate actual executable code, rather than trusting a fixed framework list.
    count = 0
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), 'bundle link escapes app')
        elif path.is_file():
            with path.open('rb') as stream:
                is_code = stream.read(4) in MACHO
            if is_code:
                verify_code(path, team)
                count += 1
    require(count > 0, 'no executable code found')
    if notarized:
        verify_ticket(app)
        run(['spctl', '--assess', '--type', 'execute', app])
    return {'signing': 'apple-developer-id', 'teamID': team,
            'libraryValidation': True, 'notarized': notarized, 'codeObjects': count}


def verify_local_beta_app(app):
    """Explicit non-notarized beta only; never substitutes for the Apple gate."""
    app = Path(app)
    require(app.is_dir() and not app.is_symlink(), 'regular beta app required')
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    require(info.get('AInautenDistributionMode') == 'local-beta', 'explicit local-beta marker required')
    require(info.get('CFBundleIdentifier') == 'com.mediapublishing.VoiceWispr', 'wrong beta identity')
    fingerprint = (Path(__file__).resolve().parents[1]/'Resources/release-signing-fingerprint.txt').read_text().strip()
    require(re.fullmatch(r'[0-9A-F]{40}', fingerprint), 'reviewed publisher pin required')
    run(['codesign', '--verify', '--deep', '--strict', app])
    main = (app/'Contents/MacOS'/info['CFBundleExecutable']).resolve()
    require(main.is_relative_to(app.resolve()), 'executable escapes beta bundle')
    count = 0
    paths = [app]
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), 'beta link escapes app')
        elif path.is_file():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    paths.append(path); count += 1
    require(count > 0, 'no beta executable code found')
    for path in paths:
        run(['codesign', '--verify', '--strict', '-R', '=certificate leaf = H"'+fingerprint+'"', path])
        metadata = run(['codesign', '-dv', '--verbose=4', path]).stderr.decode()
        require('TeamIdentifier=not set' in metadata, 'local-beta must use the existing local identity')
        require(re.search(r'^CodeDirectory .*flags=.*\bruntime\b', metadata, re.MULTILINE), 'beta hardened runtime missing')
        payload = run(['codesign', '-d', '--entitlements', '-', '--xml', path]).stdout
        entitlements = plistlib.loads(payload) if payload.strip() else {}
        require(isinstance(entitlements, dict), 'invalid beta entitlements')
        exceptions = FORBIDDEN - {'com.apple.security.cs.disable-library-validation'}
        require(not any(entitlements.get(key) for key in exceptions), 'beta adds code-injection exception')
        if path != app and path.resolve() != main:
            require(not entitlements.get('com.apple.security.cs.disable-library-validation'), 'nested beta code disables library validation')
    return {'signing':'pinned-local-beta', 'teamID':None, 'libraryValidation':False,
            'notarized':False, 'codeObjects':count}
