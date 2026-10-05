// Shared by the browser and collector. Unknown fields are rejected, never logged.
export const codes = ['user_reported', 'processing_failed', 'model_load_failed', 'settings_load_failed', 'import_failed', 'update_failed', 'crash_signal', 'crash_exception', 'launch_library_missing'];
const components = ['app', 'recognition', 'models', 'settings', 'migration', 'updates', 'launch'];
const events = ['launch', 'recording_started', 'processing_started', 'processing_failed', 'model_load_started'];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function exact(object, keys) {
  if (!object || typeof object !== 'object' || Array.isArray(object) || Object.keys(object).sort().join('|') !== [...keys].sort().join('|')) throw new Error('invalid_report');
}
const byteLength = value => new TextEncoder().encode(value).length;
export function validateReport(r) {
  exact(r, ['schema', 'reportID', 'version', 'build', 'osVersion', 'architecture', 'component', 'code', 'frames', 'events', 'userInput']);
  if (r.schema !== 1 || typeof r.reportID !== 'string' || !uuid.test(r.reportID) || typeof r.version !== 'string' || !/^\d{1,3}(\.\d{1,3}){1,3}$/.test(r.version) || typeof r.build !== 'string' || !/^\d{1,9}$/.test(r.build) || typeof r.osVersion !== 'string' || !/^\d{1,3}(\.\d{1,3}){1,2}$/.test(r.osVersion) || !['arm64', 'x86_64'].includes(r.architecture) || !components.includes(r.component) || !codes.includes(r.code)) throw new Error('invalid_report');
  if (!Array.isArray(r.frames) || r.frames.length > 32 || !Array.isArray(r.events) || r.events.length > 12 || r.events.some(e => !events.includes(e))) throw new Error('invalid_report');
  for (const f of r.frames) {
    exact(f, ['binaryUUID', 'offset']);
    if (typeof f.binaryUUID !== 'string' || !uuid.test(f.binaryUUID) || !Number.isInteger(f.offset) || f.offset < 0 || f.offset > 2147483647) throw new Error('invalid_report');
  }
  exact(r.userInput, ['description', 'contact']);
  if (typeof r.userInput.description !== 'string' || byteLength(r.userInput.description) > 2000 || typeof r.userInput.contact !== 'string' || byteLength(r.userInput.contact) > 254 || (r.userInput.contact && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(r.userInput.contact))) throw new Error('invalid_report');
  if (byteLength(JSON.stringify(r)) > 16384) throw new Error('invalid_report');
  return r;
}
export function projectAppleDiagnostic(text) {
  if (typeof text !== 'string' || byteLength(text) > 2097152) throw new Error('invalid_diagnostic');
  let o;
  try { o = JSON.parse(text); } catch { o = JSON.parse(text.slice(text.indexOf('\n') + 1)); }
  if (o.bundleInfo?.CFBundleIdentifier !== 'com.mediapublishing.VoiceWispr') throw new Error('wrong_app');
  const images = o.usedImages || [], thread = (o.threads || []).find(t => t.triggered === true);
  const frames = (thread?.frames || []).flatMap(f => {
    const image = images[f.imageIndex];
    if (!image || !['VoiceWispr', 'AInauten Voice'].includes(image.name) || typeof image.uuid !== 'string' || !uuid.test(image.uuid.toLowerCase()) || !Number.isInteger(f.imageOffset) || f.imageOffset < 0 || f.imageOffset > 2147483647) return [];
    return [{ binaryUUID: image.uuid.toLowerCase(), offset: f.imageOffset }];
  }).slice(0, 32);
  return validateReport({ schema: 1, reportID: crypto.randomUUID(), version: o.bundleInfo.CFBundleShortVersionString, build: o.bundleInfo.CFBundleVersion, osVersion: /\d+\.\d+(?:\.\d+)?/.exec(o.osVersion?.train || '')?.[0] || '', architecture: o.cpuType === 'X86-64' ? 'x86_64' : 'arm64', component: 'launch', code: o.termination?.namespace === 'DYLD' ? 'launch_library_missing' : o.exception?.signal ? 'crash_signal' : 'crash_exception', frames, events: [], userInput: { description: '', contact: '' } });
}
export async function fingerprint(r) {
  // User input and random IDs never affect technical grouping, also not for manual reports.
  // The trailing null keeps existing fingerprints (and their issue tombstones) stable.
  const data = JSON.stringify([r.version, r.build, r.architecture, r.component, r.code, r.frames.map(f => [f.binaryUUID, f.offset]), null]);
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(data)))].map(x => x.toString(16).padStart(2, '0')).join('');
}
