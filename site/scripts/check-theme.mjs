import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const code = readFileSync(new URL('../content-theme.js', import.meta.url), 'utf8');
function fixture(saved, dark, blocked = false) {
  const events = {}, classes = new Set();
  const label = { hidden: true };
  const select = { value: '', closest: () => label, addEventListener: (name, fn) => events[name] = fn };
  const media = { matches: dark, addEventListener: (_, fn) => events.os = fn };
  let storage = saved;
  const root = { dataset: {}, classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } } };
  const context = {
    document: { documentElement: root, querySelector: () => select },
    matchMedia: () => media,
    window: { addEventListener: (name, fn) => events[name] = fn },
    localStorage: {
      getItem() { if (blocked) throw Error('blocked'); return storage; },
      setItem(_, value) { if (blocked) throw Error('blocked'); storage = value; },
      removeItem() { if (blocked) throw Error('blocked'); storage = null; },
    },
  };
  vm.runInNewContext(code, context);
  return {
    dark: () => classes.has('dark'), saved: () => storage, label, select,
    choose(value) { select.value = value; events.change(); },
    os(value) { media.matches = value; events.os(); },
    otherTab(value) { events.storage({ key: 'theme', newValue: value }); },
  };
}
const system = fixture(null, true);
assert.equal(system.dark(), true);
assert.equal(system.label.hidden, false);
system.os(false); assert.equal(system.dark(), false);
system.choose('dark'); assert.equal(system.saved(), 'dark');
system.os(false); assert.equal(system.dark(), true);
assert.equal(fixture(system.saved(), false).dark(), true, 'manual preference survives reload');
system.choose('light'); system.os(true); assert.equal(system.dark(), false);
system.choose('system'); assert.equal(system.saved(), null); assert.equal(system.dark(), true);
system.os(false); assert.equal(system.dark(), false);
system.otherTab('dark'); assert.equal(system.select.value, 'dark'); assert.equal(system.dark(), true);
system.otherTab(null); assert.equal(system.select.value, 'system'); assert.equal(system.dark(), false);
const denied = fixture(null, true, true);
denied.choose('light'); assert.equal(denied.dark(), false);
denied.choose('system'); denied.os(true); assert.equal(denied.dark(), true);
assert.equal(fixture('invalid', true).select.value, 'system');
console.log('THEME PASS: OS changes, manual override, reload, shared preference, storage denial, invalid preference');
