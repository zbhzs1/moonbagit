#!/usr/bin/env node
import { installHost } from './host.mjs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

installHost();
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const compiled = path.join(root, '_build/js/debug/build/cmd/main/main.js');
if (!fs.existsSync(compiled)) {
  console.error('Build first: moon build --target js');
  process.exitCode = 2;
} else {
  await import(pathToFileURL(compiled).href);
}
