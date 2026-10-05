#!/usr/bin/env python3
"""Wrap a verified app unchanged, with prominent offline first-start guidance."""
import argparse
import base64
import datetime
import pathlib
import plistlib
import re
import shutil
import subprocess
from app_bundle import verify_runtime

ROOT = pathlib.Path(__file__).resolve().parents[1]
GUIDE = ROOT / 'Resources/InstallerGuide'


def write_offline_guide(destination):
    html = (GUIDE / 'installation.html').read_text()
    css = (GUIDE / 'installation.css').read_text()
    link = '<link rel="stylesheet" href="installation.css">'
    if html.count(link) != 1:
        raise ValueError('Guide stylesheet link must appear exactly once')
    def embed_image(match):
        asset = (GUIDE / match[1]).resolve()
        if not asset.is_relative_to((GUIDE / 'installation-images').resolve()) or asset.suffix != '.png':
            raise ValueError('Expected a PNG from the installer guide image directory')
        encoded = base64.b64encode(asset.read_bytes()).decode('ascii')
        return 'src="data:image/png;base64,' + encoded + '"'

    html = re.sub(r'src="(installation-images/[^"]+)"', embed_image, html)
    # One self-contained document opens even without an internet connection.
    (destination / '00 - ZUERST LESEN.html').write_text(
        html.replace(link, '<style>\n' + css + '\n</style>'), encoding='utf-8')
    shutil.copy2(GUIDE / 'installation.txt', destination / '00 - ZUERST LESEN.txt')


def create_dmg(app, output):
    app, output = pathlib.Path(app).resolve(), pathlib.Path(output).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if app.name != 'AInauten Voice.app' or info.get('CFBundleIdentifier') != 'com.mediapublishing.VoiceWispr':
        raise ValueError('Expected the AInauten Voice app bundle')
    version = info['CFBundleShortVersionString']
    verify_runtime(app)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / f'AInauten-Voice-{version}-arm64.dmg'
    image_source = output / 'DMG'
    if dmg.exists() or image_source.exists():
        raise FileExistsError('Use a fresh output directory; existing installers are preserved')
    packaged_app = output / app.name
    if packaged_app != app:
        shutil.copytree(app, packaged_app, symlinks=True)
    image_source.mkdir()
    shutil.copytree(packaged_app, image_source / app.name, symlinks=True)
    (image_source / 'Applications').symlink_to('/Applications')
    write_offline_guide(image_source)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(image_source / app.name)], check=True)
    subprocess.run(['hdiutil', 'create', '-volname', 'AInauten Voice', '-srcfolder', str(image_source),
                    '-format', 'UDZO', str(dmg)], check=True)
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
    return dmg


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path, required=True, help='Existing verified app, kept unchanged')
    parser.add_argument('--output', type=pathlib.Path, help='Fresh artifact directory')
    args = parser.parse_args()
    output = args.output or ROOT / 'artifacts' / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-installer')
    print('DMG', create_dmg(args.app, output))
