#!/usr/bin/env python3
"""Verify public site links, assets, version and essential release information."""
from html.parser import HTMLParser
from pathlib import Path
import argparse
import plistlib
import re
from urllib.parse import urlsplit

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
redirects = {}
if (root / '_redirects').is_file():
    for line in (root / '_redirects').read_text().splitlines():
        route, target, status = line.split()
        assert status == '302'
        assert target.startswith(f'https://github.com/MediaPublishing/ainauten-voice/releases/download/v{version}/')
        assert urlsplit(target).path.rsplit('/', 1)[-1] == route.rsplit('/', 1)[-1]
        redirects[route] = target
assert page.h1 == 1
assert len(page.ids) == len(set(page.ids)), 'Duplicate IDs'
for ref in page.refs:
    if ref.startswith('#'): assert ref[1:] in page.ids, ref
    elif ref.startswith('/') and ref != '/':
        path = urlsplit(ref).path
        # The source checkout excludes release binaries. A dist check requires
        # every asset, including the original video and the download package.
        if root == source and (path.startswith('/downloads/') or path == '/assets/video/ainauten-voice-promo-de.mp4'):
            continue
        if root == source and path == '/installation.html':
            assert (source.parent / 'native/Resources/InstallerGuide/installation.html').is_file(), ref
            continue
        assert (root / path[1:]).is_file() or path in redirects, ref
assert f'AInauten-Voice-{version}-arm64.dmg' in text
assert f'Beta {version}' in text
for term in ['Beispieldaten', 'nicht Apple-notarisiert', 'Audio bleibt', 'Mikrofon', 'Bedienungshilfen', 'Apple Silicon', 'SHA256SUMS.txt', 'aria-selected', 'Impressum', 'Datenschutz']:
    assert term in text, term
assert not re.search(r'<script[^>]+src="https?://', text), 'External script'
assert not re.search(r'<link[^>]+rel="stylesheet"[^>]+href="https?://', text), 'External stylesheet'
assert 'LocalWhisper.git' not in text
for meta in ['<meta property="og:locale" content="de_DE">', '<meta property="og:site_name" content="AInauten Voice">', 'href="/assets/favicon-32.png" sizes="32x32"', 'rel="apple-touch-icon" href="/assets/apple-touch-icon.png"', 'href="/assets/icon-192.png" sizes="192x192"']:
    assert meta in text, meta
# Readable text: no font size below 12 px in the main stylesheet.
assert not [size for size in re.findall(r'font(?:-size)?:[^;}]*?(\d+(?:\.\d+)?)px', (root / 'styles.css').read_text()) if float(size) < 12], 'Text below 12 px'
# Honest requirements, the one-time model download and a checkable download.
assert 'macOS 14 oder neuer (Build-Ziel), bisher getestet auf macOS 27 mit Apple Silicon M2' in text
assert 'etwa 3 GB von Hugging Face' in text and 'GB RAM' not in text
assert 'Voice Wispr' not in text and 'Voice-Wispr' not in text, 'Old working title'
assert 'ohne Verbindung zu Wispr und wird von Wispr weder unterstützt noch geprüft' in text
assert f'shasum -a 256 ~/Downloads/AInauten-Voice-{version}-arm64.dmg' in text
shown = re.findall(r'id="dmg-sha256">([0-9a-f]{64})<', text)
assert len(shown) == 1 if root != source else text.count('{{DOWNLOAD_SHA256}}') == 1, 'Visible SHA-256 missing'
if root != source:
    sums = (root / 'downloads/SHA256SUMS.txt').read_text().split()
    assert sums == [shown[0], f'AInauten-Voice-{version}-arm64.dmg'], 'Visible SHA-256 does not match the packaged DMG'
assert len(list((root / 'assets/screenshots').glob('*.png'))) == 4
assert 'https://youtu.be/UBhxxBohiMU' in text
assert '<iframe' not in text, 'Third-party player loads are not needed'
vtt = (root / 'assets/video/promo-de.vtt').read_text()
assert vtt.startswith('WEBVTT') and vtt.count('-->') == 9, 'Missing caption cues'
assert 'AInauten Voice' in vtt and 'Wispr Flow' in vtt
headers = (root / '_headers').read_text()
assert "media-src 'self'" in headers
assert '  Strict-Transport-Security: max-age=31536000\n' in headers and 'includeSubDomains' not in headers and 'preload' not in headers
readme = (source.parent / 'README.md').read_text()
assert '## In 36 Sekunden erklärt' in readme
assert 'https://voice.ainauten.com/#video' in readme or re.search(r'https://github.com/user-attachments/assets/[a-f0-9-]+', readme), 'README video missing'
assert f'**{version}, Build {info["CFBundleVersion"]}**' in readme, 'README release does not match the app'
if root != source:
    import json
    release = json.loads((root / 'downloads/release.json').read_text())
    assert release['version'] == version and release['build'] == int(info['CFBundleVersion'])
    assert release['updaterIncluded'] is True and release['automaticUpdatesByDefault'] is True
print(f'SITE PASS: {len(page.refs)} links/assets, four screenshots, release {version}, local player/no autoplay, nine German captions, privacy/install information')

# A claimed illustrated guide must ship its two locally served images.
guide_root = root if root != source else source.parent/'native/Resources/InstallerGuide'
guide = (guide_root/'installation.html').read_text()
assert guide.count('installation-images/') == 2
for name in ['macos-warnung.png', 'dennoch-oeffnen.png']:
    assert (guide_root/'installation-images'/name).is_file()
help_html = (root/'help.html').read_text()
assert 'data-reporting-enabled="false"' in help_html
assert f'id="build" value="{info["CFBundleVersion"]}"' in help_html
assert 'buymeacoffee.com' not in text, 'Support link belongs in help, not primary navigation'
print('INSTALLER/HELP PASS: two illustrated installation steps, consistent support version, inactive receiver identified')
