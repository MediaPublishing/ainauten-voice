import assert from 'node:assert/strict';
import {test} from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
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
function fixture(provider = async (_url, options) => new Response(JSON.stringify(options?.method === 'POST' ? {number:42} : {private:true})), db = new DatabaseSync(':memory:')) {
  const values = new Map(); const calls = [];
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
test('current packaged release and published retained releases can submit reports',async()=>{
  const plist=readFileSync(new URL('../native/Resources/Info.plist',import.meta.url),'utf8');
  const value=key=>{
    const match=plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`));
    assert(match,`Missing packaged release metadata: ${key}`);return match[1];
  };
  const current=[value('CFBundleShortVersionString'),value('CFBundleVersion')];
  for(const [version,build] of [['0.1.7','11'],['0.1.8','12'],['0.1.9','13'],current]){
    const f=fixture();const response=await f.send({...report(),version,build});
    assert.equal(response.status,202,`Published release rejected: ${version} (${build})`);
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,1);
  }
});
test('future and mismatched release pairs are rejected without storage or provider calls',async()=>{
  for(const [version,build] of [['99.0.0','999'],['0.1.9','999'],['0.1.8','13']]){
    const f=fixture();const response=await f.send({...report(),version,build});
    assert.equal(response.status,400);assert.equal((await response.json()).error,'unknown_release');
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,0);
    assert.equal(f.calls.length,0);
  }
});
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
test('without an injected provider the global fetch is called unbound',async()=>{
  const f=fixture(),original=globalThis.fetch,seen=[];delete f.env.GITHUB_TEST;
  // Workers reject a fetch invoked as a method of another object ("Illegal invocation").
  globalThis.fetch=function(url,options){
    if(this!==undefined&&this!==globalThis)throw new TypeError('Illegal invocation');
    seen.push({url,options});return Promise.resolve(new Response(JSON.stringify(options?.method==='POST'?{number:7}:{private:true})));
  };
  try{await f.send(report());await f.inbox.alarm();}finally{globalThis.fetch=original;}
  assert.equal(seen.length,2);assert.equal(seen[1].options.method,'POST');assert(seen[1].url.endsWith('/repos/Test/Private/issues'));
  assert.deepEqual({...f.db.prepare('SELECT issue, state FROM groups').get()},{issue:7,state:'linked'});
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
test('IDs are immutable for technical data',async()=>{
  const f=fixture(),r=report();await f.send(r);assert.equal((await f.send({...r,code:'model_load_failed'})).status,409);
  assert.equal((await f.send({...r,osVersion:'26.0.2'})).status,409);
  assert.equal((await f.send({...r,userInput:{description:'changed after acceptance',contact:''}})).status,409);
  const reordered=Object.fromEntries(Object.entries(r).reverse());assert.equal((await f.send(reordered)).status,202);
});
test('manual reports group by component, code, version and build; one issue per group',async()=>{
  const f=fixture(),manual=()=>({...report(),component:'app',code:'user_reported'});
  const a=manual(),b={...manual(),userInput:{description:'other words',contact:'x@example.com'}},c={...manual(),build:'4'};
  assert.equal(await fingerprint(a),await fingerprint(b));assert.notEqual(await fingerprint(a),await fingerprint(c));
  // Existing non-manual fingerprints keep their previous value.
  const technical=report();assert.equal(await fingerprint(technical),[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(['0.1.1','3','arm64','recognition','processing_failed',[],null]))))].map(x=>x.toString(16).padStart(2,'0')).join(''));
  for(const r of [a,b,c])assert.equal((await f.send(r)).status,202);
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,3);assert.equal(f.db.prepare('SELECT count(*) AS n FROM groups').get().n,2);
  await f.inbox.alarm();await f.inbox.alarm();
  assert.equal(f.calls.filter(x=>x.options.method==='POST').length,2);
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
  const f=fixture();for(let n=0;n<5;n++)assert.equal((await f.send(report())).status,202);assert.equal((await f.send(report())).status,429);
  f.db.prepare('UPDATE reports SET created=?').run(Date.now()-31*86400000);f.inbox.prune(Date.now());assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,0);
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM groups').get().n,1);
});
test('expired unsent groups do not create a permanent minute alarm; cleanup follows next expiry',async()=>{
  const f=fixture();await f.send(report());f.db.prepare('UPDATE reports SET created=?').run(Date.now()-31*86400000);
  await f.inbox.alarm();assert.equal(f.calls.length,0);
  const scheduled=await f.ctx.storage.get('alarm');assert(scheduled>Date.now()+60000);assert(scheduled<=Date.now()+3600001);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM reports').get().n,0);
});
test('global hourly issue cap defers new groups with a content-free reason',async()=>{
  const f=fixture(),reports=Array.from({length:25},(_,n)=>({...report(),frames:[{binaryUUID:crypto.randomUUID(),offset:n}]}));
  for(const [i,r] of reports.entries())assert.equal((await f.send(r,{"CF-Connecting-IP":"198.51.100."+i})).status,202);
  for(let n=0;n<3;n++)await f.inbox.alarm();
  const posts=()=>f.calls.filter(c=>c.options.method==='POST').length;
  assert.equal(posts(),20);
  assert.equal(f.db.prepare("SELECT count(*) AS n FROM groups WHERE attempted=0 AND state='received' AND reason='issue_cap'").get().n,5);
  const hour=3600000;assert.equal(await f.ctx.storage.get('alarm'),(Math.floor(Date.now()/hour)+1)*hour);
  // Deferred reports stay accepted for clients; only the operator sees the reason code.
  const waiting=reports.find(r=>f.db.prepare('SELECT g.reason FROM reports r JOIN groups g ON g.fingerprint=r.fingerprint WHERE r.id=?').get(r.reportID).reason);
  assert.equal((await(await f.send(waiting)).json()).state,'received');
  f.env.REPORTING_OPERATOR_TOKEN='synthetic-operator-token-with-40-random-characters';
  const status=await(await worker.fetch(new Request(`https://voice.ainauten.com/api/reports/${waiting.reportID}`,{headers:{Authorization:`Bearer ${f.env.REPORTING_OPERATOR_TOKEN}`}}),f.env)).json();
  assert.deepEqual(status,{reportID:waiting.reportID,accepted:true,state:'received',reason:'issue_cap'});
  await f.inbox.alarm();assert.equal(posts(),20);
  // The next hour opens a new budget.
  f.db.prepare("DELETE FROM limits WHERE key LIKE 'issues:%'").run();
  await f.inbox.alarm();assert.equal(posts(),25);
  assert.equal(f.db.prepare("SELECT count(*) AS n FROM groups WHERE reason IS NOT NULL").get().n,0);
});
test('a failed provider check leaves a content-free reason, never report text',async()=>{
  const f=fixture(async()=>new Response('{"private":false}')),r=report();r.userInput.description='PRIVATE';await f.send(r);await f.inbox.alarm();
  assert.deepEqual({...f.db.prepare('SELECT state, reason FROM groups').get()},{state:'needs_review',reason:'repository_check_failed'});
  const g=fixture(async(_url,o)=>{if(o?.method==='POST')throw new Error('PRIVATE provider text');return new Response('{"private":true}');});await g.send(report());await g.inbox.alarm();
  assert.deepEqual({...g.db.prepare('SELECT state, reason FROM groups').get()},{state:'needs_review',reason:'provider_error'});
  assert.equal(g.db.prepare("SELECT count(*) AS n FROM limits WHERE key LIKE 'issues:%'").get().n,1);
});
test('rate-limit salt rotates per UTC day; addresses are never stored',async()=>{
  const f=fixture(),address='203.0.113.77';
  await f.send(report(),{'CF-Connecting-IP':address});
  const first=f.db.prepare('SELECT day, salt FROM salts').all();
  assert.equal(first.length,1);assert.equal(first[0].day,new Date().toISOString().slice(0,10));
  f.db.prepare("UPDATE salts SET day='2000-01-01'").run();
  await f.send(report(),{'CF-Connecting-IP':address});
  const second=f.db.prepare('SELECT day, salt FROM salts').all();
  assert.equal(second.length,1);assert.notEqual(second[0].salt,first[0].salt);
  // Same address in the same hour, but a new day salt: the two rate keys are unlinkable.
  assert.equal(f.db.prepare("SELECT count(*) AS n FROM limits WHERE key NOT LIKE 'issues:%' AND key NOT LIKE 'retained:%' AND key NOT LIKE 'novel:%'").get().n,2);
  for(const table of ['reports','groups','limits','salts'])assert(!JSON.stringify(f.db.prepare(`SELECT * FROM ${table}`).all()).includes(address));
});
test('content-free tombstones are deleted 30 days after their last report expired',async()=>{
  const f=fixture(),day=86400000,codes=['processing_failed','model_load_failed','import_failed'];
  const [old,recent,active]=codes.map(code=>({...report(),code}));
  for(const r of [old,recent,active])await f.send(r);
  const fp=r=>f.db.prepare('SELECT fingerprint FROM reports WHERE id=?').get(r.reportID).fingerprint;
  const [a,b,c]=[old,recent,active].map(fp);
  f.db.prepare('UPDATE reports SET created=? WHERE id IN (?,?)').run(Date.now()-31*day,old.reportID,recent.reportID);
  f.db.prepare('UPDATE groups SET seen=? WHERE fingerprint IN (?,?)').run(Date.now()-61*day,a,c);
  f.db.prepare('UPDATE groups SET seen=? WHERE fingerprint=?').run(Date.now()-59*day,b);
  f.inbox.prune(Date.now());
  assert.deepEqual(f.db.prepare('SELECT fingerprint FROM groups ORDER BY fingerprint').all().map(row=>row.fingerprint),[b,c].sort());
});
test('a collector created before the tombstone columns is migrated in place',()=>{
  const db=new DatabaseSync(':memory:');
  db.exec("CREATE TABLE groups(fingerprint TEXT PRIMARY KEY, issue INTEGER, attempted INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL); INSERT INTO groups VALUES('legacy', 9, 1, 'linked')");
  const f=fixture(undefined,db),row=f.db.prepare('SELECT * FROM groups').get();
  assert.equal(row.issue,9);assert(row.seen>Date.now()-60000);assert.equal(row.reason,null);
  fixture(undefined,db);assert.equal(db.prepare('SELECT count(*) AS n FROM groups').get().n,1);
});
test('Pages leaves every other path to static assets, so a 404 page keeps its status',async()=>{
  const seen=[],env={REPORTING:{fetch:async()=>new Response('report')},ASSETS:{fetch:async r=>{seen.push(new URL(r.url).pathname);return new Response('Seite nicht gefunden',{status:404});}}};
  for(const path of ['/does-not-exist','/api/other','/api/reportsx'])assert.equal((await pages.fetch(new Request('https://voice.ainauten.com'+path),env)).status,404);
  assert.deepEqual(seen,['/does-not-exist','/api/other','/api/reportsx']);
});

test('Pages retires the old installer using current verified release metadata',async()=>{
 const env={ASSETS:{fetch:async r=>{assert.equal(new URL(r.url).pathname,'/downloads/release.json');return Response.json({filename:'AInauten-Voice-0.1.3-arm64.dmg'});}}};
 const response=await pages.fetch(new Request('https://voice.ainauten.com/downloads/AInauten-Voice-0.1.1-arm64.dmg'),env);
 assert.equal(response.status,302);assert.equal(response.headers.get('Location'),'https://voice.ainauten.com/downloads/AInauten-Voice-0.1.3-arm64.dmg');assert.equal(response.headers.get('Cache-Control'),'no-store');
 env.ASSETS.fetch=async()=>Response.json({filename:'AInauten-Voice-0.1.1-arm64.dmg'});
 assert.equal((await pages.fetch(new Request('https://voice.ainauten.com/downloads/AInauten-Voice-0.1.1-arm64.dmg'),env)).status,410);
});

test('one anonymous source cannot consume the global issue budget',async()=>{
  const f=fixture();
  for(let n=0;n<20;n++) {
    const r={...report(),frames:[{binaryUUID:crypto.randomUUID(),offset:n}]};
    assert.equal((await f.send(r,{'CF-Connecting-IP':'198.51.100.1'})).status,n<3?202:429);
  }
  await f.inbox.alarm();assert.equal(f.calls.filter(c=>c.options.method==='POST').length,3);
  assert.equal((await f.send({...report(),code:'model_load_failed'},{'CF-Connecting-IP':'198.51.100.2'})).status,202);
  await f.inbox.alarm();assert.equal(f.calls.filter(c=>c.options.method==='POST').length,4);
  assert.equal((await f.send({...report(),version:'9.9.9',build:'999'},{'CF-Connecting-IP':'198.51.100.3'})).status,400);
});
test('retained report quota limits one source to five rows per UTC day and preserves receipts',async()=>{
  const f=fixture(),r=report();
  for(let n=0;n<40;n++) assert.equal((await f.send({...r,reportID:crypto.randomUUID()})).status,n<5?202:429);
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM reports').get().n,5);
  const first=JSON.parse(f.db.prepare('SELECT payload FROM reports LIMIT 1').get().payload);
  f.db.prepare("DELETE FROM limits WHERE key NOT LIKE 'retained:%' AND key NOT LIKE 'novel:%'").run();
  assert.equal((await f.send(first)).status,202);
  assert.equal((await f.send(report(),{'CF-Connecting-IP':'198.51.100.2'})).status,202);
});
test('operator index is authenticated, omits voluntary text and pages tied timestamps without duplicates',async()=>{
  const f=fixture();f.env.REPORTING_OPERATOR_TOKEN='synthetic-operator-token-with-40-random-characters';
  assert.equal((await worker.fetch(new Request('https://voice.ainauten.com/api/operator/reports'),f.env)).status,401);
  for(let n=0;n<105;n++) assert.equal((await f.send({...report(),userInput:{description:'PRIVATE_TEXT',contact:'private@example.com'}},{'CF-Connecting-IP':'198.51.100.'+n})).status,202);
  f.db.prepare('UPDATE reports SET created=?').run(Date.now()-1000);
  const read=path=>worker.fetch(new Request('https://voice.ainauten.com/api/operator/reports'+path,{headers:{Authorization:'Bearer '+f.env.REPORTING_OPERATOR_TOKEN}}),f.env);
  const first=await(await read('')).json(),second=await(await read('?cursor='+first.nextCursor)).json();
  assert.equal(first.reports.length,100);assert.equal(second.reports.length,5);assert.equal(second.nextCursor,null);
  assert.equal(new Set([...first.reports,...second.reports].map(x=>x.reportID)).size,105);
  assert(!JSON.stringify(first).includes('PRIVATE_TEXT'));assert(!JSON.stringify(first).includes('private@example.com'));
  assert.equal((await read('?cursor=bad')).status,400);
});
