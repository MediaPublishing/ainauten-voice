#!/usr/bin/env python3
"""Prepare a stable, signed Sparkle channel using an existing Keychain identity.

Never generates/exports keys, installs, pushes or publishes. The caller uploads
the complete returned directory only after the signed-release checks pass.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
ACCOUNT = 'ainauten-voice'
PREFIX = 'https://voice.ainauten.com/updates/'
NS = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}

def info_for(app):
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.mediapublishing.VoiceWispr'
    assert info['SUFeedURL'] == PREFIX+'appcast.xml'
    key = base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)
    assert len(key) == 32 and any(key), 'Missing AInauten Voice update identity; do not create keys implicitly'
    assert info['SUVerifyUpdateBeforeExtraction'] is True and info['SURequireSignedFeed'] is True
    assert info['SUSignedFeedFailureExpirationInterval'] == 0
    assert re.fullmatch(r'[1-9][0-9]*', info['CFBundleVersion']), 'Build number must be a positive monotonic integer'
    assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', info['CFBundleShortVersionString']), 'Only stable numeric releases'
    return info

def xml_feed(path):
    data = path.read_bytes()
    assert len(data) <= 1024*1024 and b'<!DOCTYPE' not in data.upper() and b'<!ENTITY' not in data.upper()
    return ET.fromstring(data)

def verify_channel(directory, app, previous=None):
    info = info_for(app)
    tree = xml_feed(directory/'appcast.xml')
    assert b'<!-- sparkle-signatures:\n' in (directory/'appcast.xml').read_bytes(), 'Feed signature missing'
    items = tree.findall('./channel/item')
    assert len(items) == 1, 'Release channel must contain exactly its verified candidate'
    build = int(info['CFBundleVersion'])
    selected = [item for item in items if int(item.findtext('s:version', default='0', namespaces=NS)) == build]
    assert len(selected) == 1, 'Missing or duplicate release'
    item = selected[0]
    assert item.find('s:channel', NS) is None, 'Research/beta update is not a stable release'
    enclosure = item.find('enclosure'); assert enclosure is not None
    url = enclosure.get('url', '')
    name = url.removeprefix(PREFIX)
    assert url.startswith(PREFIX) and '/' not in name and re.fullmatch(r'AInauten-Voice-[0-9.]+-[0-9]+-arm64\.zip', name)
    archive = directory/name; assert archive.is_file() and not archive.is_symlink()
    assert int(enclosure.get('length', '0')) == archive.stat().st_size
    signature = enclosure.get('{'+NS['s']+'}edSignature', '')
    assert len(base64.b64decode(signature, validate=True)) == 64, 'Archive signature missing'
    if previous:
        builds = [int(x.text) for x in xml_feed(previous).findall('./channel/item/s:version', NS)]
        assert not builds or build > max(builds), 'Release build must increase'
    return {'version': info['CFBundleShortVersionString'], 'build': build, 'filename': name,
            'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'size': archive.stat().st_size}

def verify_signatures(directory, app):
    info = info_for(app)
    tools = ROOT/'.build/artifacts/sparkle/Sparkle/bin'
    existing = subprocess.check_output([str(tools/'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    assert existing == info['SUPublicEDKey'], 'Signing identity does not match the bundled public key'
    receipt = verify_channel(directory, app)
    item = xml_feed(directory/'appcast.xml').find('./channel/item')
    subprocess.run([str(tools/'sign_update'), '--verify', '--account', ACCOUNT, str(directory/'appcast.xml')], check=True)
    subprocess.run([str(tools/'sign_update'), '--verify', '--account', ACCOUNT, str(directory/receipt['filename']), item.find('enclosure').get('{'+NS['s']+'}edSignature')], check=True)
    return receipt

def verify_empty_channel(directory):
    """Verify initial signed feed without offering an unaccepted release."""
    tree = xml_feed(directory/'appcast.xml')
    assert tree.tag == 'rss' and len(tree.findall('./channel')) == 1
    assert not tree.findall('./channel/item'), 'Initial channel must not offer a release'
    assert tree.findtext('./channel/link') == 'https://voice.ainauten.com/'
    assert b'<!-- sparkle-signatures:\n' in (directory/'appcast.xml').read_bytes()
    tools = ROOT/'.build/artifacts/sparkle/Sparkle/bin'
    key = (ROOT/'Resources/update-public-key.txt').read_text().strip()
    assert len(base64.b64decode(key, validate=True)) == 32
    existing = subprocess.check_output([str(tools/'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    assert key == existing, 'Initial channel must use the approved project identity'
    subprocess.run([str(tools/'sign_update'), '--verify', '--account', ACCOUNT, str(directory/'appcast.xml')], check=True)
    return {'filename': None, 'channel_ready': True, 'release_published': False,
            'sha256': hashlib.sha256((directory/'appcast.xml').read_bytes()).hexdigest()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    previous = parser.add_mutually_exclusive_group(required=True)
    previous.add_argument('--previous-feed', type=pathlib.Path, help='Previously published channel for monotonic-version verification')
    previous.add_argument('--bootstrap', action='store_true', help='First channel publication only')
    parser.add_argument('--release-notes', type=pathlib.Path, required=True)
    args = parser.parse_args()
    info = info_for(args.app)
    tools = ROOT/'.build/artifacts/sparkle/Sparkle/bin'
    # Public-key lookup only, in the explicitly named existing account.
    existing = subprocess.check_output([str(tools/'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    assert existing == info['SUPublicEDKey'], 'Keychain signing identity does not match bundled public key'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
    if args.previous_feed:
        builds = [int(x.text) for x in xml_feed(args.previous_feed).findall('./channel/item/s:version', NS)]
        assert not builds or int(info['CFBundleVersion']) > max(builds), 'Release build must increase'
    args.output.mkdir(parents=True, exist_ok=False)
    name = f'AInauten-Voice-{info["CFBundleShortVersionString"]}-{info["CFBundleVersion"]}-arm64'
    archive = args.output/(name+'.zip')
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(args.app), str(archive)], check=True)
    (args.output/(name+'.md')).write_text(args.release_notes.read_text())
    subprocess.run([str(tools/'generate_appcast'), '--account', ACCOUNT, '--download-url-prefix', PREFIX, '--embed-release-notes', str(args.output)], check=True)
    verify_channel(args.output, args.app, args.previous_feed)
    receipt = verify_signatures(args.output, args.app)
    (args.output/'release.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print('Verified signed update channel:', args.output)

if __name__ == '__main__':
    main()
