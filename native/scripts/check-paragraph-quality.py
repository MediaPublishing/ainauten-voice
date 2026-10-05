#!/usr/bin/env python3
"""Optional real local-model regressions. Read-only settings; no microphone or ASR.
Requires already downloaded Qwen model, Apple Silicon and the pinned local runtime.
"""
from pathlib import Path
import argparse,subprocess,json
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk',type=Path,help='Compatible installed SDK, used for both SwiftPM and native test compilation.')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];build=root/'.build/arm64-apple-macosx/release';out=root/'artifacts/receipts';out.mkdir(parents=True,exist_ok=True)
subprocess.run(['swift','build','--build-system','native']+(['--sdk',str(args.sdk)] if args.sdk else [])+['-c','release','-j','4'],cwd=root,check=True)
cmd=['xcrun','swiftc','-O','-parse-as-library','-swift-version','5','-target','arm64-apple-macosx14.0','-I',str(build/'Modules'),'-I',str(root/'Sources/CSQLite'),'-I',str(build/'FastClusterWrapper.build'),'-I',str(build/'MachTaskSelfWrapper.build'),'-F',str(build),'-L',str(build),'-framework','llama','-framework','Accelerate','-framework','CoreML','-framework','AppKit','-framework','AVFoundation','-framework','ApplicationServices','-framework','Security','-framework','Carbon','-lsqlite3','-lc++','-Xlinker','-rpath','-Xlinker',str(build)]
if args.sdk: cmd+=['-sdk',str(args.sdk)]
for target in ['FastClusterWrapper','MachTaskSelfWrapper']:
    cmd += ['-Xcc','-fmodule-map-file='+str(root/'.build/checkouts/FluidAudio/Sources'/target/'include/module.modulemap'),'-Xcc','-I'+str(root/'.build/checkouts/FluidAudio/Sources'/target/'include')]
objects=(build/'VoiceWispr.product/Objects.LinkFileList').read_text().splitlines()
objects=[p for p in objects if '/VoiceWispr.build/' not in p]
cmd += objects+[str(root/'Tests/Native/ParagraphQualityChecks.swift'),'-o',str(out/'ParagraphQualityChecks')]
(out/'paragraph-quality-maintained-compile.json').write_text(json.dumps(cmd,indent=2))
subprocess.run(cmd,check=True)

subprocess.run([str(out/'ParagraphQualityChecks')],cwd=root,check=True)
