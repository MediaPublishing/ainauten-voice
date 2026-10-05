#!/usr/bin/env python3
"""Build isolated Sparkle installer probes using the existing approved signing key.
Never launches/installs the real app, edits user data, creates or exports keys.
"""
import argparse, importlib.util, pathlib, plistlib, shutil, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(); p.add_argument('output', type=pathlib.Path); p.add_argument('--port', type=int, default=8917); a = p.parse_args()
out = a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
sparkle = root/'.build/artifacts/sparkle/Sparkle'
framework = sparkle/'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
identity = (root/'.local/signing-identity').read_text().strip()
key = subprocess.check_output([str(sparkle/'bin/generate_keys'),'--account','ainauten-voice','-p'],text=True).strip()
assert key == (root/'Resources/update-public-key.txt').read_text().strip()
exe = out/'UpdateProbe'
subprocess.run(['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macosx14.0','-F',str(framework.parent),'-framework','AppKit','-framework','Sparkle',str(root/'scripts/update-upgrade-probe.swift'),'-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-o',str(exe)],check=True)
for build in [1,2]:
 app = out/f'build-{build}'/'AInauten Voice Updateprüfung.app'; c=app/'Contents'
 for d in ['MacOS','Frameworks']: (c/d).mkdir(parents=True,exist_ok=True)
 shutil.copy2(exe,c/'MacOS/UpdateProbe'); shutil.copytree(framework,c/'Frameworks/Sparkle.framework',symlinks=True)
 info={'CFBundleExecutable':'UpdateProbe','CFBundleName':'AInauten Voice Updateprüfung','CFBundleIdentifier':'com.mediapublishing.VoiceWispr.IsolatedUpdateProbe','CFBundlePackageType':'APPL','CFBundleVersion':str(build),'CFBundleShortVersionString':f'0.0.{build}','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','SUFeedURL':f'http://127.0.0.1:{a.port}/appcast.xml','SUPublicEDKey':key,'SUEnableAutomaticChecks':False,'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':True,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'SUSignedFeedFailureExpirationInterval':0,'SUEnableSystemProfiling':False,'AInautenUpdateProbeReceipt':str(out/'launched.txt')}
 (c/'Info.plist').write_bytes(plistlib.dumps(info))
 f=c/'Frameworks/Sparkle.framework'; v=f/'Versions/B'
 for obj in [*sorted(v.glob('XPCServices/*.xpc')),v/'Autoupdate',v/'Updater.app',f,app]: subprocess.run(['codesign','--force','--sign',identity,str(obj)],check=True,capture_output=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
channel=out/'channel'; channel.mkdir()
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(out/'build-2/AInauten Voice Updateprüfung.app'),str(channel/'UpdateProbe-2.zip')],check=True)
subprocess.run([str(sparkle/'bin/generate_appcast'),'--account','ainauten-voice','--download-url-prefix',f'http://127.0.0.1:{a.port}/',str(channel)],check=True)
subprocess.run([str(sparkle/'bin/sign_update'),'--verify','--account','ainauten-voice',str(channel/'appcast.xml')],check=True)
print('PREPARED isolated probe; production app/profile untouched:',out)
