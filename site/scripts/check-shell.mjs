import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(path.join(root, 'index.html'), 'utf8');
const css = readFileSync(path.join(root, 'assets/shell/ainauten-shell.css'), 'utf8');
const provenance = JSON.parse(readFileSync(path.join(root, 'vendor/upstream.json'), 'utf8'));
for (const [source, upstreamExpected] of Object.entries(provenance.source_sha256)) {
  if (!source.startsWith('packages/ui/')) continue;
  const actual = readFileSync(path.join(root, 'vendor/ainauten-ui', source.replace('packages/ui/', '')));
  const expected = provenance.site_overrides?.[source]?.sha256 || upstreamExpected;
  assert.equal(createHash('sha256').update(actual).digest('hex'), expected, source);
}
assert.ok(html.includes('id="ainauten-header"') && html.includes('id="ainauten-footer"'));
assert.ok(html.includes('Alle Tools') && html.includes('Membership') && html.includes('Theme wechseln'));
assert.ok(!html.includes('class="site-header"') && !html.includes('class="site-footer"'));
assert.ok(!css.includes('fonts.googleapis.com') && !css.includes('/Users/'));
assert.ok(css.includes('--bg-secondary') && css.includes('.dark') && css.includes('inter-latin-variable.woff2'));
for (const name of ['search', 'news', 'help', 'nauti', 'widget', 'promptlinks', 'prompts', 'privacy', 'design', 'skills', 'loops']) {
  assert.ok(html.includes(`https://${name}.ainauten.com/`), name);
}
for (const file of ['ainauten-shell.css', 'ainauten-shell.js', 'theme-init.js']) {
  const hash = createHash('sha256').update(readFileSync(path.join(root, 'assets/shell', file))).digest('hex').slice(0, 12);
  assert.ok(html.includes(`/assets/shell/${file}?v=${hash}`), file);
}
console.log('SHELL CHECK PASS: pinned shared components with documented Voice footer override, all tool links, token themes, local font and cache-busted assets');
