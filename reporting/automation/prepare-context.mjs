import {readFile, realpath, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {validateReport, fingerprint} from '../../site/report-schema.mjs';

export const paths = {
  recognition:['native/Sources/VoiceWisprCore/ErrorReport.swift','native/Sources/VoiceWisprCore/ProcessingPipeline.swift','native/Sources/VoiceWisprCore/SpeechRuntime.swift'],
  models:['native/Sources/VoiceWisprCore/ModelDownloads.swift'],
  settings:['native/Sources/VoiceWisprCore/SettingsStore.swift'],
  migration:['native/Sources/VoiceWisprCore/Migration.swift'],
  updates:['native/Sources/VoiceWisprCore/UpdatePolicy.swift'],
  launch:['native/scripts/app_bundle.py'],
  app:['native/Sources/VoiceWisprCore/ErrorReport.swift','native/Sources/VoiceWisprCore/CrashDiagnosticProjection.swift']
};
export async function prepareContext(report, root) {
  validateReport(report);
  const technical={...report,userInput:{description:'',contact:''}}, source={};
  const base=await realpath(root);
  for(const relative of paths[report.component]) {
    const candidate=path.resolve(base,relative);
    let resolved;try{resolved=await realpath(candidate);}catch{continue;}
    if(resolved!==candidate || !resolved.startsWith(base+path.sep))throw new Error('unsafe_source');
    const content=await readFile(resolved,'utf8');if(Buffer.byteLength(content)>60000)continue;
    source[relative]=content;
  }
  if(!Object.keys(source).length)throw new Error('no_context');
  const result={schema:1,technical, fingerprint:await fingerprint(report), source, constraints:{noUserInput:true,noTools:true,noShellCommands:true,patchOnlyAllowedSources:true,regressionTestRequired:true,automaticMerge:false,automaticRelease:false}};
  if(Buffer.byteLength(JSON.stringify(result))>180000)throw new Error('context_too_large');
  return result;
}
if(process.argv[1]?.endsWith('/prepare-context.mjs')) {
  const [file,root,out]=process.argv.slice(2);
  const report=JSON.parse(await readFile(file,'utf8'));
  await writeFile(out,JSON.stringify(await prepareContext(report,root),null,2),{mode:0o600});
}
