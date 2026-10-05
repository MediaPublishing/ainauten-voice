#!/usr/bin/env python3
"""Package only public site assets and a verified release DMG."""
import argparse
import datetime
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

def require(condition, message):
    if not condition: raise ValueError(message)

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
input_group = parser.add_mutually_exclusive_group(required=True)
input_group.add_argument('--package', type=Path)
input_group.add_argument('--existing-site', type=Path, help='Refresh only frontend assets in an existing public site; preserve release, video, installation guide and update feed')
parser.add_argument('--promo-video', type=Path, help='User-provided original MP4; never copied into Git')
parser.add_argument('--updates', type=Path, help='Signed update directory prepared by native/scripts/package-update.py')
parser.add_argument('--github-release', action='store_true', help='Host assets exceeding the Pages limit in the matching public GitHub release')
args = parser.parse_args()
subprocess.run(['node', str(root / 'scripts/build-shell.mjs')], cwd=root, check=True)
subprocess.run(['node', str(root / 'scripts/check-shell.mjs')], cwd=root, check=True)
if args.existing_site:
    parser.error('--existing-site was retired: regenerate from tracked source with --package and --updates; arbitrary deployment trees are never copied')
package = args.package.resolve()
promo = (args.promo_video or root / 'assets/video/ainauten-voice-promo-de.mp4').resolve()
require(promo.is_file(), 'Provide the promo video with --promo-video')
require(promo.stat().st_size < 25 * 1024 * 1024, 'Video exceeds Pages asset size limit')
app = package / 'AInauten Voice.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
dmg = package / f'AInauten-Voice-{version}-arm64.dmg'
require(dmg.is_file(), 'Release DMG missing')
asset_limit = 25 * 1024 * 1024
require(info['CFBundleIdentifier'] == 'com.mediapublishing.VoiceWispr', 'invalid release input')
from release_verification import verify_release, verify_archive
verified_release = verify_release(app, dmg)
dmg_data = dmg.read_bytes()
require(hashlib.sha256(dmg_data).hexdigest() == verified_release['sha256'], 'Installer changed after verification')
require(verified_release['version'] == version and verified_release['build'] == info['CFBundleVersion'], 'Reviewed app metadata changed')
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
        update_assets[name] = (channel/name).read_bytes()
    if update_receipt['filename']:
        require(hashlib.sha256(update_assets[update_receipt['filename']]).hexdigest() == update_receipt['sha256'], 'Update changed after verification')
        # Authenticate the immutable bytes that will actually be published.
        with tempfile.TemporaryDirectory(prefix='ainauten-channel-check-') as saved:
            captured = Path(saved)
            for name, data in update_assets.items(): (captured/name).write_bytes(data)
            updater.verify_signatures(captured, app)
            verify_archive(app, captured/update_receipt['filename'])
dist = root / 'dist'
if dist.exists():
    archived = root.parent / 'native/artifacts' / ('site-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    dist.rename(archived)
dist.mkdir()
for name in ['index.html', 'styles.css', 'app.js', '_headers', 'robots.txt', 'sitemap.xml', 'help.html', 'help.css', 'help.mjs', 'report-schema.mjs', '_routes.json', '404.html']:
    shutil.copy2(root / name, dist / name)
shutil.copy2(root/'pages-worker.mjs', dist/'_worker.js')
# A changed stylesheet must also reach visitors with a cached previous version.
style_version = hashlib.sha256((dist / 'styles.css').read_bytes()).hexdigest()[:12]
index = dist / 'index.html'
html = index.read_text()
require('href="/styles.css"' in html, 'Main stylesheet reference missing')
index.write_text(html.replace('href="/styles.css"', f'href="/styles.css?v={style_version}"'))
guide = root.parent / 'native/Resources/InstallerGuide'
for name in ['installation.html', 'installation.css']:
    shutil.copy2(guide / name, dist / name)
shutil.copytree(guide/'installation-images', dist/'installation-images', ignore=shutil.ignore_patterns('*.md'))
shutil.copytree(root / 'assets', dist / 'assets', ignore=shutil.ignore_patterns('*.mp4'))
video = dist / 'assets/video/ainauten-voice-promo-de.mp4'
shutil.copy2(promo, video)
video_digest = hashlib.sha256(video.read_bytes()).hexdigest()
(video.parent / 'media.json').write_text(json.dumps({'filename': video.name, 'sha256': video_digest, 'size': video.stat().st_size, 'youtube': 'https://youtu.be/UBhxxBohiMU'}, indent=2) + '\n')
downloads = dist / 'downloads'
downloads.mkdir()
redirects = []
release_base = f'https://github.com/MediaPublishing/ainauten-voice/releases/download/v{version}/'

def write_release_asset(name, data, directory):
    if len(data) < asset_limit:
        (directory/name).write_bytes(data)
    else:
        require(args.github_release, f'{name} exceeds the Pages asset limit; upload the verified asset to the matching GitHub release and use --github-release')
        route = '/' + str(directory.relative_to(dist) / name)
        redirects.append(f'{route} {release_base}{name} 302')
        print(f'GITHUB RELEASE ASSET required: {release_base}{name}')

write_release_asset(dmg.name, dmg_data, downloads)
digest = hashlib.sha256(dmg_data).hexdigest()
html = index.read_text()
if "{{DOWNLOAD_SHA256}}" in html:
    index.write_text(html.replace("{{DOWNLOAD_SHA256}}", digest))
(downloads / 'SHA256SUMS.txt').write_text(f'{digest}  {dmg.name}\n')
(downloads / 'release.json').write_text(json.dumps({'name': 'AInauten Voice', 'version': version, 'build': int(info['CFBundleVersion']), 'updaterIncluded': bool(info.get('SUPublicEDKey') and (app/'Contents/Frameworks/Sparkle.framework').exists()), 'automaticUpdatesByDefault': bool(info.get('SUEnableAutomaticChecks') and info.get('SUAutomaticallyUpdate')), 'reportDeliveryEnabled': info.get('AInautenReportDeliveryEnabled') is True, 'architecture': 'arm64', 'sha256': digest, 'filename': dmg.name, 'size': len(dmg_data), 'notarized': False}, indent=2) + '\n')
print(f'RELEASE {version} {len(dmg_data)} bytes SHA256 {digest}')
print(f'PROMO {video.stat().st_size} bytes SHA256 {video_digest}')
if args.updates:
    # Only the exact verified assets; never publish staging or key files.
    (dist/'updates').mkdir()
    for name, content in update_assets.items():
        write_release_asset(name, content, dist/'updates')
    print('UPDATE CHANNEL verified and copied')
if redirects:
    (dist/'_redirects').write_text('\n'.join(redirects)+'\n')

subprocess.run(['python3', str(root/'check.py'), '--root', str(dist)], cwd=root, check=True)
