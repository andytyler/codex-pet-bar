import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve('build');
const base = process.env.BASE_PATH || '';
const home = readFileSync(join(root, 'index.html'), 'utf8');
assert.match(home, /Your pet/);
assert.match(home, /in your menu bar/);
assert.match(home, /Small pet/);
assert.match(home, /Useful signals/);
assert.match(home, /Works with your local agents/);
assert.match(home, /A new home/);
assert.match(home, /Automatically follows your selected Codex pet/);
assert.match(home, /codex-pet-bar\/releases\/latest/);
assert.match(home, /Integrations/);
assert.match(home, /open at login/);
assert.match(home, /Your choice, always/);
assert.match(home, /Move CodexPetBar\.app to Applications, then open it/);
assert.match(home, /brew install --cask andytyler\/tap\/codex-pet-bar/);
let checked = 0;
function checkDirectory(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) checkDirectory(path);
    else if (entry.name.endsWith('.html')) {
      const html = readFileSync(path, 'utf8');
      for (const [, attribute] of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
        if (/^(?:https?:|data:|mailto:|#)/.test(attribute)) continue;
        const pagePath = path.slice(root.length).replace(/index\.html$/, '');
        const url = new URL(attribute, `https://example.test${base}${pagePath}`);
        let pathname = decodeURIComponent(url.pathname);
        assert.ok(!base || pathname.startsWith(`${base}/`), `Asset outside site base: ${attribute}`);
        pathname = pathname.slice(base.length);
        const file = join(root, pathname);
        assert.ok(existsSync(file) || existsSync(join(file, 'index.html')), `Broken built link: ${attribute} in ${path}`);
        checked++;
      }
    }
  }
}
checkDirectory(root);
console.log(`Production pages and ${checked} local links/assets verified (base: ${base || '/'}).`);
