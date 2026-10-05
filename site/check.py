#!/usr/bin/env python3
"""Verify public site links, assets, version and essential release information."""
from html.parser import HTMLParser
from pathlib import Path
import argparse
import plistlib
import re

source = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=source, help='Site source or built dist directory')
args = parser.parse_args()
root = args.root.resolve()
text = (root / 'index.html').read_text()
info = plistlib.loads((source.parent / 'native/Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.refs, self.h1 = [], [], 0
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        for key in ['href', 'src']: 
            if key in a: self.refs.append(a[key])
        if tag == 'h1': self.h1 += 1
        if tag == 'img': assert 'alt' in a, 'Missing image alt'
        if tag == 'video':
            assert 'controls' in a and 'playsinline' in a
            assert a.get('preload') == 'none' and 'autoplay' not in a
            assert a.get('aria-label') and a.get('poster')
            self.refs.append(a['poster'])
        if tag == 'track':
            assert a.get('kind') == 'captions' and a.get('srclang') == 'de'
            assert a.get('label') == 'Deutsch'

page = Page()
page.feed(text)
assert page.h1 == 1
assert len(page.ids) == len(set(page.ids)), 'Duplicate IDs'
for ref in page.refs:
    if ref.startswith('#'): assert ref[1:] in page.ids, ref
    elif ref.startswith('/') and ref != '/':
        # The source checkout excludes release binaries. A dist check requires
        # every asset, including the original video and the download package.
        if root == source and (ref.startswith('/downloads/') or ref == '/assets/video/ainauten-voice-promo-de.mp4'):
            continue
        if root == source and ref == '/installation.html':
            assert (source.parent / 'native/Resources/InstallerGuide/installation.html').is_file(), ref
            continue
        assert (root / ref[1:]).is_file(), ref
assert f'AInauten-Voice-{version}-arm64.dmg' in text
assert f'Beta {version}' in text
for term in ['Beispieldaten', 'nicht Apple-notarisiert', 'Audio bleibt', 'Mikrofon', 'Bedienungshilfen', 'Apple Silicon', 'SHA256SUMS.txt', 'aria-selected', 'Impressum', 'Datenschutz']:
    assert term in text, term
assert not re.search(r'<script[^>]+src="https?://', text), 'External script'
assert not re.search(r'<link[^>]+rel="stylesheet"[^>]+href="https?://', text), 'External stylesheet'
assert 'LocalWhisper.git' not in text
assert len(list((root / 'assets/screenshots').glob('*.png'))) == 4
assert 'https://youtu.be/UBhxxBohiMU' in text
assert '<iframe' not in text, 'Third-party player loads are not needed'
vtt = (root / 'assets/video/promo-de.vtt').read_text()
assert vtt.startswith('WEBVTT') and vtt.count('-->') == 9, 'Missing caption cues'
assert 'AInauten Voice' in vtt and 'Wispr Flow' in vtt
assert "media-src 'self'" in (root / '_headers').read_text()
readme = (source.parent / 'README.md').read_text()
assert '[![AInauten Voice: Videovorschau' in readme and 'https://youtu.be/UBhxxBohiMU' in readme
assert 'https://voice.ainauten.com/#video' in readme
print(f'SITE PASS: {len(page.refs)} links/assets, four screenshots, release {version}, local player/no autoplay, nine German captions, privacy/install information')
