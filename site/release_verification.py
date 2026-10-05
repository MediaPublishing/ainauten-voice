"""Authenticate the exact mounted installer against the reviewed signed bundle.

The fingerprint is public; no private signing material is read here. Local
signing is explicitly not Apple Developer ID signing or notarization.
"""
import hashlib
import plistlib
import re
import subprocess
import tempfile
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError('Release verification: ' + message)


def bundle_manifest(app):
    app = app.resolve()
    result = {}
    for item in sorted(app.rglob('*')):
        relative = str(item.relative_to(app))
        if item.is_symlink():
            require(item.resolve().is_relative_to(app), 'bundle link escapes app')
            result[relative] = ['link', item.readlink().as_posix()]
        elif item.is_file():
            result[relative] = ['file', hashlib.sha256(item.read_bytes()).hexdigest(), item.stat().st_mode & 0o777]
        else:
            require(item.is_dir(), 'nonregular bundle entry')
    return result


def verify_app(app):
    require(app.is_dir() and not app.is_symlink(), 'regular app required')
    fingerprint = (ROOT / 'native/Resources/release-signing-fingerprint.txt').read_text().strip()
    require(bool(re.fullmatch('[0-9A-F]{40}', fingerprint)), 'missing publisher pin')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '-R',
                    '=certificate leaf = H"' + fingerprint + '"', str(app)], check=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == 'com.mediapublishing.VoiceWispr', 'wrong app identity')
    require(info.get('SUPublicEDKey') == (ROOT / 'native/Resources/update-public-key.txt').read_text().strip(), 'wrong update identity')
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    sparkle = plistlib.loads((framework / 'Resources/Info.plist').read_bytes())
    version = tuple(int(part) for part in sparkle['CFBundleShortVersionString'].split('.'))
    require(version >= (2, 9, 6), 'Sparkle below security floor 2.9.6')
    # Validate every actual nested code object against the same publisher pin.
    nested = [app / 'Contents/Frameworks/llama.framework', framework,
              app / 'Contents/Resources/LipReading/uv']
    nested += list((framework / 'Versions/B/XPCServices').glob('*.xpc'))
    nested += [framework / 'Versions/B/Autoupdate', framework / 'Versions/B/Updater.app']
    for item in nested:
        subprocess.run(['codesign', '--verify', '--strict', '-R',
                        '=certificate leaf = H"' + fingerprint + '"', str(item)], check=True)
    # Includes loading the lazy diagnostics catalog that caused the 0.1.7
    # clean-machine startup trap; reads only bundled resources, never a profile.
    if int(info.get('CFBundleVersion', '0')) >= 12:
        subprocess.run([str(app/'Contents/MacOS'/info['CFBundleExecutable']),
                        '--check-bundled-resources'], check=True, timeout=30)
    return info, bundle_manifest(app)


def verify_release(app, dmg):
    require(dmg.is_file() and not dmg.is_symlink(), 'regular installer required')
    before = hashlib.sha256(dmg.read_bytes()).hexdigest()
    info, reviewed = verify_app(app)
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix='ainauten-installer-check-') as mount:
        attached = False
        try:
            subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, str(dmg)],
                           check=True, stdout=subprocess.DEVNULL)
            attached = True
            apps = list(Path(mount).glob('*.app'))
            require(len(apps) == 1 and apps[0].name == 'AInauten Voice.app', 'unexpected installer apps')
            embedded, manifest = verify_app(apps[0])
            require(embedded == info, 'installer metadata differs from reviewed app')
            require(manifest == reviewed, 'installer contents differ from reviewed signed app')
        finally:
            if attached:
                subprocess.run(['hdiutil', 'detach', mount], check=True, stdout=subprocess.DEVNULL)
    require(hashlib.sha256(dmg.read_bytes()).hexdigest() == before, 'installer changed during verification')
    return {'sha256': before, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'entries': len(reviewed), 'signing': 'pinned-local-certificate', 'notarized': False}


def verify_archive(app, archive):
    """Extract only a bounded, path-safe signed archive and compare its app."""
    require(archive.is_file() and not archive.is_symlink(), 'regular update archive required')
    info, reviewed = verify_app(app)
    with zipfile.ZipFile(archive) as zipped:
        names = set()
        require(sum(item.file_size for item in zipped.infolist()) <= 300 * 1024 * 1024, 'expanded archive too large')
        for item in zipped.infolist():
            name = item.filename
            parts = Path(name).parts
            require(name not in names and parts and parts[0] in {app.name, '__MACOSX'} and
                    not name.startswith('/') and '..' not in parts and '\\' not in name, 'unsafe archive path')
            names.add(name)
            if stat.S_ISLNK(item.external_attr >> 16):
                target = zipped.read(item).decode('utf-8')
                require(parts[0] == app.name and not Path(target).is_absolute(), 'unsafe archive link')
                base = Path('/bundle-check')
                resolved = (base / Path(name).parent / target).resolve()
                require(resolved.is_relative_to(base / app.name), 'archive link escapes app')
    with tempfile.TemporaryDirectory(prefix='ainauten-update-check-') as directory:
        subprocess.run(['ditto', '-x', '-k', str(archive), directory], check=True)
        candidate = Path(directory) / app.name
        embedded, actual = verify_app(candidate)
        require(embedded == info and actual == reviewed, 'update contents differ from reviewed signed app')
    return {'entries': len(reviewed), 'matchesReviewedApp': True}
