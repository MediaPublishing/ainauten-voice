import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const cache = path.join(root, '.shell-build');
const output = path.join(root, 'assets/shell');
mkdirSync(cache, { recursive: true }); mkdirSync(output, { recursive: true });
const options = { absWorkingDir: root, bundle: true, jsx: 'automatic', logLevel: 'warning', define: { 'process.env.NODE_ENV': '"production"' } };
await build({ ...options, entryPoints: ['shell/render.jsx'], platform: 'node', format: 'cjs', outfile: path.join(cache, 'render.cjs') });
const fragments = JSON.parse(execFileSync(process.execPath, [path.join(cache, 'render.cjs')], { encoding: 'utf8' }));
await build({ ...options, entryPoints: ['shell/client.jsx'], platform: 'browser', format: 'iife', minify: true, legalComments: 'eof', outfile: path.join(output, 'ainauten-shell.js') });
copyFileSync(path.join(root, 'shell/theme-init.js'), path.join(output, 'theme-init.js'));
copyFileSync(path.join(root, 'vendor/LICENSE-MIT.txt'), path.join(output, 'LICENSE-AInauten-UI.txt'));
execFileSync(process.execPath, [require.resolve('tailwindcss/lib/cli.js'), '-i', 'shell/utilities.css', '-c', 'tailwind.config.cjs', '-o', '.shell-build/utilities.css', '--minify'], { cwd: root, stdio: 'inherit' });
const tokens = readFileSync(path.join(root, 'vendor/ainauten-tokens/colors.css'), 'utf8').replace(/^@import[^\n]+\n/m, '');
const font = '@font-face{font-family:Inter;font-style:normal;font-weight:100 900;font-display:swap;src:url("/assets/fonts/inter-latin-variable.woff2") format("woff2")}\n';
const css = font + tokens + readFileSync(path.join(root, 'vendor/ainauten-ui/src/shell.css'), 'utf8') + readFileSync(path.join(root, 'shell/integration.css'), 'utf8') + readFileSync(path.join(cache, 'utilities.css'), 'utf8');
writeFileSync(path.join(output, 'ainauten-shell.css'), css);
let html = readFileSync(path.join(root, 'index.html'), 'utf8');
for (const [name, content] of Object.entries(fragments)) {
  const expression = new RegExp(`<!-- AINAUTEN_${name.toUpperCase()}_START -->[\\s\\S]*?<!-- AINAUTEN_${name.toUpperCase()}_END -->`);
  if (!expression.test(html)) throw new Error(`Missing ${name} shell markers`);
  html = html.replace(expression, `<!-- AINAUTEN_${name.toUpperCase()}_START --><div id="ainauten-${name}">${content}</div><!-- AINAUTEN_${name.toUpperCase()}_END -->`);
}
for (const file of ['ainauten-shell.css', 'ainauten-shell.js', 'theme-init.js']) {
  const digest = createHash('sha256').update(readFileSync(path.join(output, file))).digest('hex').slice(0, 12);
  html = html.replace(new RegExp(`/assets/shell/${file.replaceAll('.', '\\.')}([?]v=[a-f0-9]+)?`, 'g'), `/assets/shell/${file}?v=${digest}`);
}
writeFileSync(path.join(root, 'index.html'), html);
console.log('SHELL BUILD PASS: pinned @ainauten/ui Header/Footer/ThemeToggle, static HTML, local React and CSS, self-hosted Inter');
