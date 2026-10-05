#!/usr/bin/env python3
"""Run the real app updater delegates on a CLT-only Mac, without launching UI,
provisioning a publisher key, requesting devices or loading personal data.
"""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
build = root/'.build/arm64-apple-macosx/debug'
out = root/'artifacts/receipts/updates-native-checks'; out.mkdir(exist_ok=True)
subprocess.run(['swift', 'build', '-j', '4'], cwd=root, check=True)
cmd = ['xcrun', 'swiftc', '-DDEBUG', '-parse-as-library', '-target', 'arm64-apple-macosx14.0', '-I', str(build/'Modules'), '-I', str(root/'Sources/CSQLite'), '-F', str(build)]
for framework in ['llama', 'Sparkle', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
    cmd += ['-framework', framework]
cmd += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
    headers = root/'.build/checkouts/FluidAudio/Sources'/target/'include'
    cmd += ['-Xcc', '-fmodule-map-file='+str(headers/'module.modulemap'), '-Xcc', '-I'+str(headers)]
for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
    cmd += [str(x) for x in (build/target).glob('*.o')]
cmd += [str(x) for x in (root/'Sources/VoiceWispr').glob('*.swift') if x.name != 'main.swift']
cmd += [str(root/'scripts/update-native-checks.swift'), '-o', str(out/'checks')]
result = subprocess.run(cmd, cwd=root)
if result.returncode: raise SystemExit(result.returncode)
result = subprocess.run([str(out/'checks')], cwd=root)
raise SystemExit(result.returncode)
