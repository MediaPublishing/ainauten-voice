import {validateReport, fingerprint} from '../../site/report-schema.mjs';
import {paths} from './prepare-context.mjs';

const exact=(object,keys)=>object && typeof object==='object' && !Array.isArray(object) && Object.keys(object).sort().join('|')===[...keys].sort().join('|');
export async function validateContext(context) {
  if (!exact(context,['schema','technical','fingerprint','source','constraints']) || context.schema!==1 || Buffer.byteLength(JSON.stringify(context))>180000) throw new Error('invalid_context');
  validateReport(context.technical);
  if (context.technical.userInput.description || context.technical.userInput.contact || context.fingerprint!==await fingerprint(context.technical)) throw new Error('unprojected_context');
  const rules={noUserInput:true,noTools:true,noShellCommands:true,patchOnlyAllowedSources:true,regressionTestRequired:true,automaticMerge:false,automaticRelease:false};
  if (!exact(context.constraints,Object.keys(rules)) || Object.entries(rules).some(([key,value])=>context.constraints[key]!==value)) throw new Error('unsafe_constraints');
  if (!context.source || typeof context.source!=='object' || Array.isArray(context.source) || !Object.keys(context.source).length) throw new Error('no_context');
  for (const [file,content] of Object.entries(context.source)) {
    if (!paths[context.technical.component].includes(file) || typeof content!=='string' || Buffer.byteLength(content)>60000) throw new Error('unsafe_source');
  }
  return context;
}
if (process.argv[1]?.endsWith('/validate-context.mjs')) {
  let input='';for await(const chunk of process.stdin) { input+=chunk; if(Buffer.byteLength(input)>180000)throw new Error('context_too_large'); }
  try { await validateContext(JSON.parse(input)); process.stdout.write('CONTEXT_PASS\n'); }
  catch { process.stderr.write('Invalid technical context\n');process.exitCode=1; }
}
