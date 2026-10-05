#!/usr/bin/env python3
"""Exercise native CFRunLoop callbacks with synthetic keys and no user data."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
build = root / '.build/arm64-apple-macosx/debug'
out = root / 'artifacts/receipts/hotkey-callback-checks'
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '-j', '4'], cwd=root, check=True)
cmd = ['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-target', 'arm64-apple-macosx14.0', '-I', str(build/'Modules'), '-I', str(root/'Sources/CSQLite'), '-F', str(build)]
for framework in ['llama', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
    cmd += ['-framework', framework]
cmd += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
    headers = root/'.build/checkouts/FluidAudio/Sources'/target/'include'
    cmd += ['-Xcc', '-fmodule-map-file='+str(headers/'module.modulemap'), '-Xcc', '-I'+str(headers)]
for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
    cmd += [str(x) for x in (build/target).glob('*.o')]
cmd += [str(root/'scripts/hotkey-callback-checks.swift'), '-o', str(out/'checks')]
subprocess.run(cmd, cwd=root, check=True)
subprocess.run([str(out/'checks')], cwd=root, check=True)
