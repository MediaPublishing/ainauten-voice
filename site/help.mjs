import { validateReport, projectAppleDiagnostic } from './report-schema.mjs';
const $ = id => document.getElementById(id);
const deliveryAvailable = $('report-form').dataset.reportingEnabled === 'true';
let draft = null, diagnostic = null, controller = null, busy = false, generation = 0;
function update() {
  try {
    draft = validateReport({ schema: 1, reportID: draft?.reportID || crypto.randomUUID(), version: $('version').value, build: $('build').value, osVersion: $('os').value, architecture: diagnostic?.architecture || 'arm64', component: diagnostic?.component || 'app', code: diagnostic?.code || 'user_reported', frames: diagnostic?.frames || [], events: [], userInput: {description: $('description').value, contact: $('contact').value} });
    $('preview').textContent = JSON.stringify(draft, null, 2);
    $('send').disabled = !deliveryAvailable || busy || !$('consent').checked; $('save').disabled = busy;
  } catch { draft = null; $('preview').textContent = 'Bitte Version, macOS-Version und die freiwilligen Angaben prüfen.'; $('send').disabled = true; $('save').disabled = true; }
}
for (const id of ['description','contact','version','build','os','consent']) $(id).addEventListener('input', () => { if (id !== 'consent' && draft) draft.reportID = crypto.randomUUID(); update(); });
$('diagnostic').addEventListener('change', async () => {
  const file = $('diagnostic').files[0]; if (!file) return;
  try {
    if (file.size > 2097152) throw new Error('size');
    diagnostic = projectAppleDiagnostic(await file.text());
    $('version').value = diagnostic.version; $('build').value = diagnostic.build; $('os').value = diagnostic.osVersion;
    $('file-status').textContent = 'Lokal ausgewertet. Die Originaldatei wird nicht hochgeladen.';
  } catch { diagnostic = null; $('file-status').textContent = 'Keine passende Apple-Diagnose von AInauten Voice. Du kannst den Fehler ohne Datei beschreiben.'; }
  $('diagnostic').value = ''; update();
  if (draft) { draft.reportID = crypto.randomUUID(); update(); }
});
$('report-form').addEventListener('submit', async event => {
  event.preventDefault(); update(); if (!deliveryAvailable || !draft || !$('consent').checked || busy) return;
  const current = generation; const report = structuredClone(draft); const body = JSON.stringify(report); controller = new AbortController(); busy = true; update(); $('result').textContent = 'Bericht wird gesendet …';
  try {
    const response = await fetch('/api/reports', {method:'POST', headers:{'Content-Type':'application/json'}, body, signal:controller.signal, redirect:'error', credentials:'omit'});
    const receipt = response.ok ? await response.json() : null;
    if (!receipt?.accepted || receipt.reportID !== report.reportID || !['received','linked','needs_review','fixed'].includes(receipt.state)) throw new Error('not_accepted');
    if (current !== generation) return;
    $('result').textContent = `Empfangen · Bericht ${report.reportID.slice(0,8)}. Bitte die ID bei Rückfragen angeben.`;
    $('consent').checked = false;
  } catch (error) { if (current === generation) $('result').textContent = 'Empfang nicht bestätigt. Bitte später erneut versuchen oder den Bericht lokal speichern.'; }
  finally { busy = false; controller = null; update(); }
});
$('save').addEventListener('click', () => {
  update(); if (!draft) return;
  const url = URL.createObjectURL(new Blob([JSON.stringify(draft,null,2)], {type:'application/json'}));
  const a = document.createElement('a'); a.href=url; a.download=`AInauten-Voice-Fehler-${draft.reportID.slice(0,8)}.json`; a.click(); URL.revokeObjectURL(url);
  $('result').textContent='Lokal gespeichert. Es wurde nichts gesendet.';
});
$('cancel').addEventListener('click', () => {
  const started = busy; generation++; controller?.abort(); $('report-form').reset(); draft=null; diagnostic=null; $('file-status').textContent=''; $('result').textContent=started ? 'Abgebrochen. Ein bereits gestarteter Versand kann trotzdem angekommen sein.' : 'Abgebrochen. Es wurde nichts übermittelt.'; update();
});
update();
