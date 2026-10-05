#!/usr/bin/env python3
"""Verify release security with throwaway RAM-only keys, never Keychain.

Fixtures are isolated public test artifacts. This is not a delivered client
upgrade, a real publisher identity, or a production-channel E2E claim.
"""
import base64
import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('packager', ROOT/'scripts/package-update.py')
packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
tools = ROOT/'.build/artifacts/sparkle/Sparkle/bin'

def run(*args, seed=None, success=True):
    r = subprocess.run(list(map(str, args)), input=seed, capture_output=True, text=True)
    assert (r.returncode == 0) == success, r.stdout+r.stderr
    return r.stdout

def main():
    app = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=False)
    seed, public = run('swift', '-e', 'import Foundation; import CryptoKit; let k = Curve25519.Signing.PrivateKey(); print(k.rawRepresentation.base64EncodedString()); print(k.publicKey.rawRepresentation.base64EncodedString())').splitlines()
    # Only volatile seed enters stdin of Sparkle signing tools, never argv/files.
    stdin = seed+'\n'
    fixture = out/'AInauten Voice.app'; shutil.copytree(app, fixture, symlinks=True)
    info_file = fixture/'Contents/Info.plist'; info = plistlib.loads(info_file.read_bytes())
    info['SUPublicEDKey'] = public; info_file.write_bytes(plistlib.dumps(info))
    identity = (ROOT/'.local/signing-identity').read_text().strip()
    run('codesign', '--force', '--sign', identity, fixture)
    updates = out/'updates'; updates.mkdir()
    name = f'AInauten-Voice-{info["CFBundleShortVersionString"]}-{info["CFBundleVersion"]}-arm64'
    archive = updates/(name+'.zip')
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', fixture, archive)
    (updates/(name+'.md')).write_text('# Public signing fixture\n\nNo user data or persistent signing key.\n')
    run(tools/'generate_appcast', '--ed-key-file', '-', '--download-url-prefix', packager.PREFIX, '--embed-release-notes', updates, seed=stdin)
    receipt = packager.verify_channel(updates, fixture)
    run(tools/'sign_update', '--verify', '--ed-key-file', '-', updates/'appcast.xml', seed=stdin)
    item = packager.xml_feed(updates/'appcast.xml').find('./channel/item')
    signature = item.find('enclosure').get('{'+packager.NS['s']+'}edSignature')
    run(tools/'sign_update', '--verify', '--ed-key-file', '-', archive, signature, seed=stdin)
    damaged = out/'modified.zip'; damaged.write_bytes(archive.read_bytes()+b'modified')
    run(tools/'sign_update', '--verify', '--ed-key-file', '-', damaged, signature, seed=stdin, success=False)
    modified_feed = out/'modified.xml'; modified_feed.write_bytes((updates/'appcast.xml').read_bytes().replace(b'Public signing fixture', b'Modified signing text'))
    assert modified_feed.read_bytes() != (updates/'appcast.xml').read_bytes()
    run(tools/'sign_update', '--verify', '--ed-key-file', '-', modified_feed, seed=stdin, success=False)
    try: packager.verify_channel(updates, fixture, updates/'appcast.xml'); raise RuntimeError('duplicate build accepted')
    except AssertionError: pass
    unsigned = out/'unsigned.xml'; unsigned.write_text('<rss><channel/></rss>')
    run(tools/'sign_update', '--verify', '--ed-key-file', '-', unsigned, seed=stdin, success=False)
    invalid_xml = out/'entities.xml'; invalid_xml.write_text('<!DOCTYPE rss [<!ENTITY test "x">]><rss/>')
    try: packager.xml_feed(invalid_xml); raise RuntimeError('DTD accepted')
    except AssertionError: pass
    # Persistent publisher key is not provisioned by any of these tests.
    seed = stdin = ''
    (out/'receipt.json').write_text(json.dumps({**receipt, 'fixture_only': True, 'keychain_writes': False, 'passed': ['signed archive', 'signed feed', 'tampered archive rejected', 'tampered feed rejected', 'unsigned feed rejected', 'duplicate build rejected', 'XML entities rejected']}, indent=2)+'\n')
    print('PASS Sparkle signed archive/feed and five negative release/security cases; RAM-only fixture key')

if __name__ == '__main__': main()
