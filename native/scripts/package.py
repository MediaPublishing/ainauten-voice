#!/usr/bin/env python3
"""Build a signed app and DMG without deleting existing artifacts or keys."""
import argparse, base64, datetime, os, pathlib, plistlib, re, shutil, subprocess
from package_dmg import create_dmg

root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(); p.add_argument('--debug', action='store_true'); p.add_argument('--install', action='store_true')
p.add_argument('--sdk', type=pathlib.Path, help='Explicit compatible macOS SDK; leaves the system default unchanged')
p.add_argument('--built-products', type=pathlib.Path, help='Resume explicit local beta packaging from this checkout’s successful release build; no compilation')
p.add_argument('--build-system', choices=['native', 'swiftbuild'], help='Swift build engine override for compatible CLT packaging')
p.add_argument('--local-beta', action='store_true', help='Explicit locally signed public beta; no Apple notarization, existing publisher pin required')
p.add_argument('--development', action='store_true', help='Explicit local test package only; never accepted by public distribution gates')
p.add_argument('--notary-profile', help='Existing notarytool Keychain profile for Apple distribution; no credentials are created')
p.add_argument('--adhoc', action='store_true', help='Local test build only: allow ad-hoc signing without the stable identity')
p.add_argument('--sign-identity', help='SHA-1 of an existing code-signing identity in the macOS keychain')
p.add_argument('--install-directory', type=pathlib.Path, help='Existing installation directory; defaults to the system installation when writable')
args = p.parse_args()
if args.local_beta and (args.development or args.adhoc or args.debug or args.notary_profile):
    p.error('--local-beta cannot be combined with development, ad-hoc, debug or notarization modes')
if args.adhoc and not args.development:
    p.error('--adhoc requires --development; ad-hoc signing is never a public release')
if args.debug and not args.development:
    p.error('--debug requires --development')
if not args.development and not args.local_beta and not args.notary_profile:
    p.error('public packaging requires --notary-profile; use --development only for local testing')
# Public update key only. Generating a new private signing identity is a separate
# explicitly approved action; an absent key leaves the runtime updater inactive.
public_key_file = root/'Resources/update-public-key.txt'
public_key = public_key_file.read_text().strip() if public_key_file.exists() else None
if public_key is not None:
    try: decoded_key = base64.b64decode(public_key, validate=True)
    except ValueError: p.error('invalid public update key')
    if len(decoded_key) != 32 or not any(decoded_key): p.error('invalid public update key')
# Only a public fingerprint is stored here. The signing key stays in Keychain.
identity_file = root / '.local' / 'signing-identity'
identity = args.sign_identity or (identity_file.read_text().strip() if identity_file.exists() else '-')
# Ad-hoc bundles lose macOS permissions on every update; never produce them silently.
if identity == '-' and not args.adhoc: p.error('stable signing identity missing (.local/signing-identity); pass --adhoc only for a local test build')
if identity != '-':
    pinned = (root/'Resources/release-signing-fingerprint.txt').read_text().strip()
    if identity.upper() != pinned: p.error('signing identity differs from the reviewed publisher pin')
    if not re.fullmatch(r'[0-9a-fA-F]{40}', identity): p.error('signing identity must be a 40-character certificate fingerprint')
    identities = subprocess.check_output(['security', 'find-identity', '-p', 'codesigning'], text=True)
    if identity.upper() not in identities.upper(): p.error('configured signing identity is unavailable; refusing ad-hoc fallback')
# Reject a local certificate before expensive builds. Certificate creation and
# publisher-pin migration are separate, explicitly approved setup steps.
if not args.development and not args.local_beta:
    valid = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    matches = [line for line in valid.splitlines() if identity.upper() in line.upper()]
    if not any('"Developer ID Application:' in line for line in matches):
        p.error('existing valid Developer ID Application identity required; local signing cannot be distributed')
timestamp_options = [] if (args.development or args.local_beta) else ['--timestamp']
def run(*cmd): return subprocess.run(cmd, cwd=root, check=True)
# The internal development report must never be distributed in an app bundle.
user_report = root/'docs/user-verification-report.md'
report_text = user_report.read_text()
if not report_text.startswith('# AInauten Voice: Prüfbericht') or any(value in report_text for value in ['/Users/', '/home/', 'PRIVATE KEY', 'Administratorpasswort', 'Voice Wispr']):
    raise SystemExit('The user verification report is missing or contains internal data')
configuration = 'debug' if args.debug else 'release'
if args.built_products:
    if not args.local_beta: p.error('--built-products is only available for an explicit local beta')
    build = args.built_products.resolve()
    if build != (root/'.build/out/Products/Release').resolve() or not (build/'VoiceWispr').is_file():
        p.error('--built-products must be this checkout’s existing successful release products')
else:
    run('python3', 'scripts/bootstrap.py')
    build_options = (['--sdk', str(args.sdk)] if args.sdk else []) + (['--build-system', args.build_system] if args.build_system else [])
    run('swift', 'build', *build_options, '-c', configuration, '-j', '4')
    build = pathlib.Path(subprocess.check_output(['swift', 'build', *build_options, '-c', configuration, '--show-bin-path'], cwd=root, text=True).strip())
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
out = root / 'artifacts' / stamp; out.mkdir(parents=True)
app = out / 'AInauten Voice.app'; contents = app / 'Contents'
for name in ['MacOS', 'Frameworks', 'Resources']: (contents/name).mkdir(parents=True)
shutil.copy2(root/'Resources/Info.plist', contents/'Info.plist')
info = plistlib.loads((contents/'Info.plist').read_bytes())
info['AInautenDistributionMode'] = 'local-beta' if args.local_beta else ('development' if args.development else 'apple-notarized')
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
for language in ['de', 'en']:
    source = root/'Resources'/f'{language}.lproj'
    shutil.copytree(source, contents/'Resources'/source.name)
if public_key:
    info = plistlib.loads((contents/'Info.plist').read_bytes())
    info['SUPublicEDKey'] = public_key
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
shutil.copy2(build/'VoiceWispr', contents/'MacOS/VoiceWispr')
for bundle in build.glob('*.bundle'):
    target_bundle = contents/'Resources'/bundle.name
    # Keep the app's established flat SwiftPM resource layout under both build engines.
    resource_base = bundle/'Contents/Resources'
    if resource_base.is_dir():
        shutil.copytree(resource_base, target_bundle)
        shutil.copy2(bundle/'Contents/Info.plist', target_bundle/'Info.plist')
    else:
        shutil.copytree(bundle, target_bundle)
localized_bundles = list((contents/'Resources').glob('*.bundle'))
for language in ['de', 'en']:
    if not any((base/f'{language}.lproj/Localizable.strings').is_file() for bundle in localized_bundles for base in [bundle, bundle/'Contents/Resources']):
        raise SystemExit(f'Missing packaged interface language: {language}')
framework = root/'Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework'
shutil.copytree(framework, contents/'Frameworks/llama.framework', symlinks=True)
sparkle_distribution = root/'.build/artifacts/sparkle/Sparkle'
sparkle = contents/'Frameworks/Sparkle.framework'
shutil.copytree(sparkle_distribution/'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework', sparkle, symlinks=True)
shutil.copytree(root/'Resources/Licenses', contents/'Resources/Licenses')
shutil.copy2(sparkle_distribution/'LICENSE', contents/'Resources/Licenses/Sparkle-MIT.txt')
shutil.copy2(user_report, contents/'Resources/verification-report.md')
# Only our adapter/installer is bundled. Research sources and model weights
# remain in the user's private support directory after explicit Beta setup.
lip = contents/'Resources/LipReading'; lip.mkdir()
for source in (root/'lipreading_runtime').glob('*.py'): shutil.copy2(source, lip/source.name)
for name in ['pyproject.toml', 'uv.lock']:
    source = root/'lipreading_runtime'/name
    if source.exists(): shutil.copy2(source, lip/name)
shutil.copytree(root/'lipreading_runtime/licenses', lip/'licenses')
shutil.copytree(root/'lipreading_runtime/german', lip/'german', ignore=shutil.ignore_patterns('__pycache__', '.venv'))
uv = pathlib.Path('/opt/homebrew/Cellar/uv/0.12.5/bin/uv')
if not uv.exists(): raise SystemExit('Pinned uv 0.12.5 is required for packaging the optional installer')
shutil.copy2(uv, lip/'uv')
for name in ['LICENSE-MIT', 'LICENSE-APACHE']:
    shutil.copy2(uv.parents[1]/name, lip/'licenses'/('uv-' + name))
run('codesign', '--force', '--options', 'runtime', *timestamp_options, '--sign', identity, str(lip/'uv'))
iconset = out/'VoiceWispr.iconset'
run('swift', str(root/'scripts/make-icon.swift'), str(iconset))
run('iconutil', '-c', 'icns', str(iconset), '-o', str(contents/'Resources/VoiceWispr.icns'))
run('install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(contents/'MacOS/VoiceWispr'))
run('codesign', '--force', '--options', 'runtime', *timestamp_options, '--sign', identity, str(contents/'Frameworks/llama.framework'))
# Re-sign actual nested helpers inside out; do not follow framework symlinks.
sparkle_version = sparkle/'Versions/B'
for helper in sorted(sparkle_version.glob('XPCServices/*.xpc')):
    run('codesign', '--force', '--options', 'runtime', '--preserve-metadata=entitlements', *timestamp_options, '--sign', identity, str(helper))
run('codesign', '--force', '--options', 'runtime', '--preserve-metadata=entitlements', *timestamp_options, '--sign', identity, str(sparkle_version/'Autoupdate'))
run('codesign', '--force', '--options', 'runtime', '--preserve-metadata=entitlements', *timestamp_options, '--sign', identity, str(sparkle_version/'Updater.app'))
run('codesign', '--force', '--options', 'runtime', *timestamp_options, '--sign', identity, str(sparkle))
# Developer ID bundles use library validation. The existing local identity has
# no Team ID and still requires the explicit exception: never claim notarization.
signer = subprocess.run(['codesign', '-dv', '--verbose=4', str(lip/'uv')], capture_output=True, text=True, check=True).stderr
has_team = re.search(r'^TeamIdentifier=(?!not set)(.+)$', signer, re.MULTILINE) is not None
entitlements = root/'Resources'/('Release.entitlements' if has_team else 'LocalRelease.entitlements')
if not has_team and not args.development and not args.local_beta: raise SystemExit('Developer ID Team ID missing; no public package produced')
if not has_team: print('LOCAL BETA: library-validation exception; NOT Apple-notarized' if args.local_beta else 'LOCAL DEVELOPMENT ONLY: not distributable or Apple-notarized')
run('codesign', '--force', '--options', 'runtime', '--entitlements', str(entitlements), *timestamp_options, '--sign', identity, str(app))
run('codesign', '--verify', '--deep', '--strict', str(app))
# A build-machine resource fallback can hide a broken .app layout. Execute the
# signed release's app-only resolver before accepting an installer.
run(str(contents/'MacOS/VoiceWispr'), '--check-bundled-resources')
if not args.development and not args.local_beta:
    run('python3', 'scripts/notarize-release.py', str(app), '--keychain-profile', args.notary_profile,
        '--output', str(out/'notarization-app'))
if args.local_beta:
    from distribution_security import verify_local_beta_app
    print('VERIFIED LOCAL BETA', verify_local_beta_app(app))
dmg = create_dmg(app, out)
if not args.development and not args.local_beta:
    # Apple checks the exact final DMG too; only Accepted may reach verification.
    run('codesign', '--force', *timestamp_options, '--sign', identity, str(dmg))
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(dmg), '--keychain-profile', args.notary_profile,
                             '--wait', '--timeout', '20m', '--output-format', 'json'], capture_output=True, check=True, timeout=1260)
    import json
    submission = json.loads(result.stdout)
    (out/'notarization-dmg.json').write_text(json.dumps(submission, indent=2)+'\n')
    if submission.get('status') != 'Accepted': raise SystemExit('Apple did not accept DMG; no release allowed')
    run('xcrun', 'stapler', 'staple', str(dmg))
    import sys
    sys.path.insert(0, str(root.parent/'site'))
    from release_verification import verify_release
    print('VERIFIED INSTALLER', verify_release(app, dmg))
if args.install:
    system_apps = pathlib.Path('/Applications')
    apps = args.install_directory or (system_apps if (system_apps/app.name).exists() and os.access(system_apps, os.W_OK) else pathlib.Path.home()/'Applications')
    apps.mkdir(exist_ok=True)
    target = apps/app.name
    previous = [path for path in [target, apps/'Voice Wispr.app'] if path.exists()]
    if previous:
        backup = pathlib.Path.home()/'AI/backups'/f'ainauten-voice-app-{stamp}'
        backup.mkdir(parents=True, exist_ok=False)
        for path in previous: path.rename(backup/path.name)
    shutil.copytree(app, target, symlinks=True)
    print('INSTALLED', target)
print('APP', app)
print('DMG', dmg)
