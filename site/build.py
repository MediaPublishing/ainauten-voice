#!/usr/bin/env python3
"""Package only public site assets and a verified release DMG."""
import argparse
import datetime
import hashlib
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--package', type=Path, required=True)
parser.add_argument('--promo-video', type=Path, help='User-provided original MP4; never copied into Git')
parser.add_argument('--updates', type=Path, help='Signed update directory prepared by native/scripts/package-update.py')
args = parser.parse_args()
package = args.package.resolve()
promo = (args.promo_video or root / 'assets/video/ainauten-voice-promo-de.mp4').resolve()
assert promo.is_file(), 'Provide the promo video with --promo-video'
assert promo.stat().st_size < 25 * 1024 * 1024, 'Video exceeds Pages asset size limit'
app = package / 'AInauten Voice.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
dmg = package / f'AInauten-Voice-{version}-arm64.dmg'
assert dmg.is_file(), 'Release DMG missing'
assert dmg.stat().st_size < 25 * 1024 * 1024, 'Exceeds Pages asset size limit'
assert info['CFBundleIdentifier'] == 'com.mediapublishing.VoiceWispr'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run(['hdiutil', 'verify', str(dmg)], check=True, stdout=subprocess.DEVNULL)
update_receipt = None
update_assets = {}
if args.updates is None:
    existing_channel = root/'dist/updates'
    if (existing_channel/'appcast.xml').is_file():
        args.updates = existing_channel
    elif (root.parent/'native/Resources/update-public-key.txt').is_file():
        parser.error('Provide the signed update channel with --updates; never remove an initialized channel silently')
if args.updates:
    import importlib.util
    module_spec = importlib.util.spec_from_file_location('voice_update_packager', root.parent/'native/scripts/package-update.py')
    updater = importlib.util.module_from_spec(module_spec); module_spec.loader.exec_module(updater)
    channel = args.updates.resolve()
    items = updater.xml_feed(channel/'appcast.xml').findall('./channel/item')
    update_receipt = updater.verify_signatures(channel, app) if items else updater.verify_empty_channel(channel)
    for name in ['appcast.xml'] + ([update_receipt['filename']] if update_receipt['filename'] else []):
        assert (channel/name).stat().st_size < 25*1024*1024, 'Update exceeds Pages asset size limit'
        update_assets[name] = (channel/name).read_bytes()
dist = root / 'dist'
if dist.exists():
    archived = root.parent / 'native/artifacts' / ('site-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    dist.rename(archived)
dist.mkdir()
for name in ['index.html', 'styles.css', 'app.js', '_headers', 'robots.txt', 'sitemap.xml']:
    shutil.copy2(root / name, dist / name)
# A changed stylesheet must also reach visitors with a cached previous version.
style_version = hashlib.sha256((dist / 'styles.css').read_bytes()).hexdigest()[:12]
index = dist / 'index.html'
html = index.read_text()
assert 'href="/styles.css"' in html, 'Main stylesheet reference missing'
index.write_text(html.replace('href="/styles.css"', f'href="/styles.css?v={style_version}"'))
guide = root.parent / 'native/Resources/InstallerGuide'
for name in ['installation.html', 'installation.css']:
    shutil.copy2(guide / name, dist / name)
shutil.copytree(root / 'assets', dist / 'assets', ignore=shutil.ignore_patterns('*.mp4'))
video = dist / 'assets/video/ainauten-voice-promo-de.mp4'
shutil.copy2(promo, video)
video_digest = hashlib.sha256(video.read_bytes()).hexdigest()
(video.parent / 'media.json').write_text(json.dumps({'filename': video.name, 'sha256': video_digest, 'size': video.stat().st_size, 'youtube': 'https://youtu.be/UBhxxBohiMU'}, indent=2) + '\n')
downloads = dist / 'downloads'
downloads.mkdir()
shutil.copy2(dmg, downloads / dmg.name)
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
(downloads / 'SHA256SUMS.txt').write_text(f'{digest}  {dmg.name}\n')
(downloads / 'release.json').write_text(json.dumps({'name': 'AInauten Voice', 'version': version, 'architecture': 'arm64', 'sha256': digest, 'filename': dmg.name, 'size': dmg.stat().st_size, 'notarized': False}, indent=2) + '\n')
print(f'RELEASE {version} {dmg.stat().st_size} bytes SHA256 {digest}')
print(f'PROMO {video.stat().st_size} bytes SHA256 {video_digest}')
if args.updates:
    # Only the exact verified assets; never publish staging or key files.
    (dist/'updates').mkdir()
    for name, content in update_assets.items():
        (dist/'updates'/name).write_bytes(content)
    print('UPDATE CHANNEL verified and copied')
