import {readFile,realpath,lstat} from 'node:fs/promises';
import path from 'node:path';
import {paths} from './prepare-context.mjs';

export async function validatePatch(plan, context, root) {
  if(Object.keys(plan).sort().join(',')!=='patch,state,summary' || !['needs_reproduction','proposed_patch'].includes(plan.state) || typeof plan.patch!=='string' || Buffer.byteLength(plan.patch)>65536)throw new Error('invalid_plan');
  if(plan.state==='needs_reproduction') {if(plan.patch!=='')throw new Error('invalid_plan');return [];}
  const sourceAllowed = new Set(paths[context.technical.component]);
  const lines=plan.patch.split('\n');const changed=new Set();let source=false,test=false;
  const base=await realpath(root);
  for(const line of lines) {
    if(line.startsWith('diff --git ')) {
      if(!/^diff --git a\/[A-Za-z0-9_./-]+ b\/[A-Za-z0-9_./-]+$/.test(line))throw new Error('unsafe_path');
      const [, ,a,b]=line.split(' ');if(a.slice(2)!==b.slice(2))throw new Error('rename_forbidden');
    }
    if(/^(new file mode|deleted file mode|old mode|new mode|rename|copy|GIT binary|Binary files)/.test(line))throw new Error('unsafe_diff');
    if(line.startsWith('+++ ') || line.startsWith('--- ')) {
      const name=line.slice(4);if(name==='/dev/null' || !/^[ab]\/[A-Za-z0-9_./-]+$/.test(name))throw new Error('unsafe_path');
      const relative=name.slice(2);if(relative.split('/').some(s=>s==='..'||s==='.'||!s))throw new Error('unsafe_path');
      const isTest=/^native\/Tests\/VoiceWisprCoreTests\/[A-Za-z0-9_]+\.swift$/.test(relative);
      if(!sourceAllowed.has(relative) && !isTest)throw new Error('outside_scope');
      const full=path.resolve(base,relative),stat=await lstat(full);if(!stat.isFile() || stat.isSymbolicLink() || await realpath(full)!==full)throw new Error('unsafe_path');
      changed.add(relative);source ||= !isTest;test ||= isTest;
    }
  }
  if(!source || !test || changed.size>6 || !lines.some(l=>l.startsWith('@@ ')))throw new Error('regression_required');
  return [...changed];
}
if(process.argv[1]?.endsWith('/validate-patch.mjs')) {
  const [planFile,contextFile,root]=process.argv.slice(2);
  await validatePatch(JSON.parse(await readFile(planFile,'utf8')),JSON.parse(await readFile(contextFile,'utf8')),root);
  process.stdout.write('PATCH_PREFLIGHT_PASS\n');
}
