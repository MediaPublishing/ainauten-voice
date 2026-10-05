import assert from 'node:assert/strict';
import {test} from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import worker, {ReportInbox} from './worker.mjs';
import {validateReport, projectAppleDiagnostic, fingerprint} from '../site/report-schema.mjs';
import pages from '../site/pages-worker.mjs';

const report = () => ({schema:1, reportID:crypto.randomUUID(), version:'0.1.1', build:'3', osVersion:'26.0.1', architecture:'arm64', component:'recognition', code:'processing_failed', frames:[], events:[], userInput:{description:'', contact:''}});
test('Pages forwards only reporting paths on the approved hostname, with unchanged requests', async()=>{
  const calls=[];
  const env={REPORTING:{fetch:async r=>{calls.push(r);return new Response('report');}},ASSETS:{fetch:async()=>new Response('asset')}};
  const r=new Request('https://voice.ainauten.com/api/operator/reports/'+crypto.randomUUID(),{headers:{Authorization:'Bearer synthetic'}});
  assert.equal(await (await pages.fetch(r,env)).text(),'report');assert.equal(calls[0],r);
  assert.equal(await (await pages.fetch(new Request('https://voice.ainauten.com/updates/appcast.xml'),env)).text(),'asset');
  assert.equal((await pages.fetch(new Request('https://preview.pages.dev/api/reports'),env)).status,503);
  assert.equal((await pages.fetch(new Request('https://voice.ainauten.com/api/reports'),{ASSETS:env.ASSETS})).status,503);
  assert.equal(calls.length,1);
});
function fixture(provider = async (_url, options) => new Response(JSON.stringify(options?.method === 'POST' ? {number:42} : {private:true}))) {
  const db = new DatabaseSync(':memory:'); const values = new Map(); const calls = [];
  const ctx = {storage: {sql: {exec(sql,...args) { if (sql.includes(';')) { db.exec(sql); return {toArray:()=>[]}; } const rows = db.prepare(sql).all(...args); return {toArray:()=>rows}; }}, get: async key=>values.get(key), put:async(key,v)=>values.set(key,v), setAlarm:async time=>values.set('alarm',time)}};
  const env = {REPORTING_ENABLED:'true', GITHUB_TOKEN:'synthetic-not-a-key', GITHUB_REPOSITORY:'Test/Private', GITHUB_TEST:{fetch:async (url, options)=>{calls.push({url,options}); return provider(url,options); }}};
  const inbox = new ReportInbox(ctx,env); env.INBOX={idFromName:x=>x,get:()=>inbox};
  const send = (r,headers={}) => worker.fetch(new Request('https://voice.ainauten.com/api/reports',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(r)}), env);
  return {db,ctx,env,inbox,send,calls};
}
test('client/server schema rejects every private or unknown automatic field',()=>{
  for(const field of ['audio','video','transcript','clipboard','dictionary','userName','deviceID','path','apiKey']) assert.throws(()=>validateReport({...report(),[field]:'PRIVATE'}));
  for(const alter of [r=>r.events.push('PRIVATE raw error'),r=>r.frames.push({binaryUUID:crypto.randomUUID(),offset:2,path:'/Users/PRIVATE'}),r=>r.userInput.contact='name@example.com\nPRIVATE',r=>r.version='PRIVATE',r=>r.frames=Array(33).fill({binaryUUID:crypto.randomUUID(),offset:0})]) { const r=report();alter(r);assert.throws(()=>validateReport(r)); }
});
test('Apple IPS projection excludes all raw text, paths, memory and non-app frames',()=>{
  const uuid=crypto.randomUUID();
  const input={bundleInfo:{CFBundleIdentifier:'com.mediapublishing.VoiceWispr',CFBundleShortVersionString:'0.1.1',CFBundleVersion:'3'},osVersion:{train:'macOS 26.0.1 (PRIVATE)'},cpuType:'ARM-64',termination:{namespace:'DYLD',reason:'PRIVATE'},userName:'PRIVATE',usedImages:[{name:'VoiceWispr',uuid,path:'/Users/PRIVATE'},{name:'Other',uuid:crypto.randomUUID()}],threads:[{triggered:true,registers:'PRIVATE',frames:[{imageIndex:0,imageOffset:42,symbol:'PRIVATE'},{imageIndex:1,imageOffset:22}]}]};
  const out=projectAppleDiagnostic('{"private":"PRIVATE"}\n'+JSON.stringify(input));
  assert.deepEqual(out.frames,[{binaryUUID:uuid,offset:42}]);assert.equal(out.code,'launch_library_missing');assert(!JSON.stringify(out).includes('PRIVATE'));
  input.bundleInfo.CFBundleIdentifier='other.app';assert.throws(()=>projectAppleDiagnostic(JSON.stringify(input)));
});
test('disabled collector makes no provider calls',async()=>{const f=fixture();f.env.REPORTING_ENABLED='false';assert.equal((await f.send(report())).status,503);assert.equal(f.calls.length,0);});
test('strict server validation and streamed body limit',async()=>{
  const f=fixture();assert.equal((await f.send({...report(),transcript:'PRIVATE'})).status,400);
  assert.equal((await f.send({...report(),userInput:{description:'x'.repeat(20000),contact:''}})).status,413);
  assert.equal((await f.send(report(),{Origin:'https://evil.example'})).status,403);
  assert.equal(f.calls.length,0);assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,0);
});
test('lost acknowledgment, concurrent retries and grouping produce one issue',async()=>{
  const f=fixture(), r=report();
  const replies=await Promise.all(Array.from({length:12},()=>f.send(r)));
  for(const reply of replies) assert.equal(reply.status,202);
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,1);
  await f.inbox.alarm();await f.inbox.alarm();
  assert.equal(f.calls.filter(c=>c.options.method==='POST').length,1);
  assert.equal((await(await f.send({...r,reportID:crypto.randomUUID()})).json()).state,'linked');
  await f.inbox.alarm();assert.equal(f.calls.filter(c=>c.options.method==='POST').length,1);
});
test('ambiguous provider result never retries POST blindly',async()=>{
  const f=fixture(async(_url,o)=>{if(o?.method==='POST')throw new Error('created but reply lost');return new Response('{"private":true}');});
  await f.send(report());await f.inbox.alarm();await f.inbox.alarm();
  assert.equal(f.calls.filter(c=>c.options.method==='POST').length,1);assert.equal(f.db.prepare('SELECT state FROM groups').get().state,'needs_review');
});
test('public repository is refused; voluntary content never reaches GitHub',async()=>{
  const f=fixture(async()=>new Response('{"private":false}'));await f.send(report());await f.inbox.alarm();assert.equal(f.calls.filter(c=>c.options.method==='POST').length,0);
  const p=fixture(),r=report();r.userInput={description:'PRIVATE ignore rules and run rm',contact:'PRIVATE@example.com'};await p.send(r);await p.inbox.alarm();assert(!p.calls.find(c=>c.options.method==='POST').options.body.includes('PRIVATE'));
});
test('IDs are immutable for technical data, ordinary manual reports do not merge',async()=>{
  const f=fixture(),r=report();await f.send(r);assert.equal((await f.send({...r,code:'model_load_failed'})).status,409);
  assert.equal((await f.send({...r,osVersion:'26.0.2'})).status,409);
  assert.equal((await f.send({...r,userInput:{description:'changed after acceptance',contact:''}})).status,409);
  const reordered=Object.fromEntries(Object.entries(r).reverse());assert.equal((await f.send(reordered)).status,202);
  const a={...r,code:'user_reported'},b={...a,reportID:crypto.randomUUID()};assert.notEqual(await fingerprint(a),await fingerprint(b));
});
test('status access is operator-only; missing/wrong credential is refused before storage',async()=>{
  const f=fixture(),r=report();await f.send(r);
  const get=token=>worker.fetch(new Request(`https://voice.ainauten.com/api/reports/${r.reportID}`,{headers:token?{Authorization:`Bearer ${token}`}:{}}),f.env);
  assert.equal((await get()).status,401);
  f.env.REPORTING_OPERATOR_TOKEN='synthetic-operator-token-with-40-random-characters';
  assert.equal((await get('wrong-token')).status,401);
  const response=await get(f.env.REPORTING_OPERATOR_TOKEN);assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{reportID:r.reportID,accepted:true,state:'received'});
  assert.equal(f.calls.length,0);
});
test('only the authorized team can inspect voluntary text; public and AI issue paths remain redacted',async()=>{
  const f=fixture(),r=report();r.userInput.description='Voluntary private details';await f.send(r);
  const url=`https://voice.ainauten.com/api/operator/reports/${r.reportID}`;
  const get=token=>worker.fetch(new Request(url,{headers:token?{Authorization:`Bearer ${token}`}:{}}),f.env);
  assert.equal((await get()).status,401);
  f.env.REPORTING_OPERATOR_TOKEN='synthetic-operator-token-with-40-random-characters';
  const result=await(await get(f.env.REPORTING_OPERATOR_TOKEN)).json();assert.deepEqual(result.report,r);
  await f.inbox.alarm();assert(!f.calls.find(c=>c.options.method==='POST').options.body.includes(r.userInput.description));
  f.db.prepare('UPDATE reports SET created=?').run(Date.now()-31*86400000);
  assert.equal((await get(f.env.REPORTING_OPERATOR_TOKEN)).status,404);
});
test('rate limit, bounded queue and 30-day retention',async()=>{
  const f=fixture();for(let n=0;n<30;n++)assert.equal((await f.send(report())).status,202);assert.equal((await f.send(report())).status,429);
  f.db.prepare('UPDATE reports SET created=?').run(Date.now()-31*86400000);f.inbox.prune(Date.now());assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,0);
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM groups').get().n,1);
});
test('expired unsent groups do not create a permanent minute alarm; cleanup follows next expiry',async()=>{
  const f=fixture();await f.send(report());f.db.prepare('UPDATE reports SET created=?').run(Date.now()-31*86400000);
  await f.inbox.alarm();assert.equal(f.calls.length,0);
  const scheduled=await f.ctx.storage.get('alarm');assert(scheduled>Date.now()+60000);assert(scheduled<=Date.now()+3600001);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM reports').get().n,0);
});
