#!/usr/bin/env python3
"""Check native translation catalogs and optional packaged resources."""
import argparse,json,pathlib,re,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--app',type=pathlib.Path);a=p.parse_args()
base=root/'Sources/VoiceWisprCore/Localization'
errors=[];catalogs={};owners={}
for code in ['en','de']:
 values={}
 for path in sorted((base/f'{code}.lproj').glob('*.strings')):
  subprocess.run(['plutil','-lint',str(path)],check=True,stdout=subprocess.DEVNULL)
  lines=re.findall(r'^\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;',path.read_text(),re.M)
  seen=set()
  for rawkey,rawvalue in lines:
   key,value=json.loads(rawkey),json.loads(rawvalue)
   if key in seen:errors.append(f'{path.name}: duplicate {key}')
   seen.add(key)
   if key in values and values[key]!=value:errors.append(f'{code}: conflicting table key {key}')
   values[key]=value
   owners[(code,key)]=path.name
 for path in sorted((base/f'{code}.lproj').glob('*.stringsdict')):
  import plistlib
  subprocess.run(['plutil','-lint',str(path)],check=True,stdout=subprocess.DEVNULL)
  data=plistlib.loads(path.read_bytes())
  for key,value in data.items():
   if key in values:errors.append(f'{code}: duplicate plural key {key}')
   values[key]=value
 catalogs[code]=values
if catalogs['de'].keys()!=catalogs['en'].keys():
 for code,other in [('en','de'),('de','en')]:
  errors.extend(f'Missing {code}: {k}' for k in catalogs[other].keys()-catalogs[code].keys())
def tokens(value):return sorted(re.findall(r'%(?:\d+\$)?(?:@|d|ld|lld|f|\.\df)',value))
for key in catalogs['en'].keys()&catalogs['de'].keys():
 en,de=catalogs['en'][key],catalogs['de'][key]
 if isinstance(en,str) and isinstance(de,str):
  # Argument order may differ, but argument types and count must match.
  if sorted(re.sub(r'\d+\$','',x) for x in tokens(en))!=sorted(re.sub(r'\d+\$','',x) for x in tokens(de)):errors.append(f'Placeholders: {key}')
  if not en.strip() or not de.strip():errors.append(f'Empty: {key}')
 elif isinstance(en,dict) and isinstance(de,dict):
  for value in [en,de]:
   if 'NSStringLocalizedFormatKey' not in value:errors.append(f'Plural format missing: {key}')
   for rule in [v for v in value.values() if isinstance(v,dict)]:
    if not {'one','other','NSStringFormatValueTypeKey'}<=rule.keys():errors.append(f'Plural forms missing: {key}')
 else:errors.append(f'Plural type mismatch: {key}')
for path in list((root/'Sources/VoiceWispr').glob('*.swift'))+[root/'Sources/VoiceWisprCore/Contracts.swift',root/'Sources/VoiceWisprCore/InterfaceLanguage.swift']:
 for key in re.findall(r'L10n\.(?:text|format|plural)\("([^"\\]+)"',path.read_text()):
  if key not in catalogs['en']:errors.append(f'{path.name}: missing literal key {key}')
for code in ['de','en']:
 subprocess.run(['plutil','-lint',str(root/f'Resources/{code}.lproj/InfoPlist.strings')],check=True,stdout=subprocess.DEVNULL)
if a.app:
 resources=a.app/'Contents/Resources'
 for code in ['de','en']:
  if not (resources/f'{code}.lproj/InfoPlist.strings').is_file():errors.append(f'Packaged permission strings missing {code}')
  matches=list(resources.glob(f'*.bundle/{code}.lproj/Localizable.strings'))
  if not matches:errors.append(f'Packaged core translations missing {code}')
  else:
   for source in (base/f'{code}.lproj').glob('*'):
    packaged=matches[0].parent/source.name
    if not packaged.exists() or packaged.read_bytes()!=source.read_bytes():errors.append(f'Packaged catalog mismatch {code}/{source.name}')
if errors:
 print('\n'.join(errors));sys.exit(1)
print(f'PASS localization: {len(catalogs["en"])} matching English/German keys, placeholders, plurals'+(', packaged resources' if a.app else ''))
