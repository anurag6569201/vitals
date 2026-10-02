// Renders each page to static HTML and injects it into the built shells in dist/.
import { readFile, writeFile, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(import.meta.dirname, '..');
const { render } = await import(pathToFileURL(resolve(root, '.ssr/entry-server.mjs')).href);

for (const page of ['index', 'support', 'privacy']) {
  const file = resolve(root, 'dist', `${page}.html`);
  const html = await readFile(file, 'utf8');
  if (!html.includes('<!--app-html-->')) throw new Error(`${page}.html is missing <!--app-html-->`);
  await writeFile(file, html.replace('<!--app-html-->', render(page)));
  console.log(`prerendered ${page}.html`);
}
await rm(resolve(root, '.ssr'), { recursive: true, force: true }).catch(() => {}); // ignored by git either way
