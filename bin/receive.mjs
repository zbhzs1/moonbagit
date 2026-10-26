import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import https from 'node:https';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { prepare, commit } from './host.mjs';

const cli = fileURLToPath(new URL('./moonbagit.mjs', import.meta.url));

function checked(...args) {
  const result = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  const report = JSON.parse(result.stdout);
  if (result.status !== 0) throw new Error(`receipt validation failed: ${JSON.stringify(report)}`);
  return report;
}

function options(args) {
  if (args.length < 4) throw new Error('fetch requires SOURCE OUTPUT --allow-origin ORIGIN');
  const result = { source: args[0], output: args[1], origins: new Set(), maxBytes: 1024 * 1024 * 1024, timeout: 30000, profile: null };
  const seen = new Set();
  for (let i = 2; i < args.length; i += 2) {
    const option = args[i], value = args[i + 1];
    if (value === undefined) throw new Error(`missing value for ${option}`);
    if (option !== '--allow-origin' && seen.has(option)) throw new Error(`duplicate ${option}`);
    seen.add(option);
    switch (option) {
      case '--allow-origin': {
        const url = new URL(value);
        if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.href !== `${url.origin}/`) {
          throw new Error('allow-origin must be an exact HTTP(S) origin without credentials, path, query or fragment');
        }
        result.origins.add(url.origin);
        break;
      }
      case '--max-bytes':
      case '--timeout-ms': {
        if (!/^[1-9][0-9]*$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error(`invalid ${option}`);
        if (option === '--max-bytes') result.maxBytes = Number(value);
        else result.timeout = Number(value);
        break;
      }
      case '--profile': result.profile = value; break;
      default: throw new Error(`unknown option: ${option}`);
    }
  }
  if (!result.origins.size) throw new Error('at least one explicitly trusted origin is required');
  return result;
}

function destination(stage, relative) {
  const target = path.resolve(stage, ...relative.split('/'));
  const sub = path.relative(stage, target);
  if (path.isAbsolute(sub) || sub === '..' || sub.startsWith(`..${path.sep}`) || !sub.startsWith(`data${path.sep}`)) {
    throw new Error('retrieval destination escapes payload');
  }
  // The private staging tree contains no links. Check each new/existing parent anyway.
  let parent = stage;
  const components = path.relative(stage, path.dirname(target)).split(path.sep);
  for (const component of components) {
    parent = path.join(parent, component);
    if (!fs.existsSync(parent)) fs.mkdirSync(parent);
    const stat = fs.lstatSync(parent);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('unsafe retrieval directory');
  }
  return target;
}

async function download(url, target, expected, config, budget) {
  const fd = fs.openSync(target, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | (fs.constants.O_NOFOLLOW ?? 0), 0o600);
  let size = 0;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeout);
  try {
    const response = await new Promise((resolve, reject) => {
      const request = (url.protocol === 'https:' ? https : http).get(url, {
        signal: controller.signal, headers: { 'Accept-Encoding': 'identity' },
      }, resolve);
      request.on('error', reject);
    });
    try {
      if (response.statusCode !== 200) throw new Error(`HTTP ${response.statusCode}; redirects and partial responses are not accepted`);
      if (response.headers['content-encoding'] && response.headers['content-encoding'] !== 'identity') throw new Error('encoded HTTP body is not accepted');
      const length = response.headers['content-length'];
      if (length !== undefined && (!/^[0-9]+$/.test(length) || BigInt(length) > BigInt(budget.remaining))) throw new Error('HTTP length exceeds receipt budget');
      if (expected !== null && length !== undefined && BigInt(length) !== BigInt(expected)) throw new Error('HTTP length differs from fetch entry');
      for await (const chunk of response) {
        if (chunk.length > budget.remaining) throw new Error('receipt byte budget exceeded');
        size += chunk.length;
        budget.remaining -= chunk.length;
        if (expected !== null && BigInt(size) > BigInt(expected)) throw new Error('received bytes exceed fetch length');
        let offset = 0;
        while (offset < chunk.length) offset += fs.writeSync(fd, chunk, offset, chunk.length - offset);
      }
      if (expected !== null && BigInt(size) !== BigInt(expected)) throw new Error('received bytes differ from fetch length');
    } finally { response.destroy(); }
    return size;
  } finally {
    clearTimeout(timer);
    controller.abort();
    fs.closeSync(fd);
  }
}

export async function receive(args) {
  const config = options(args);
  const plan = checked('fetch-plan', config.source);
  // Authorize every URI before making even the first request or staging a copy.
  const transfers = plan.entries.map(entry => {
    const size = entry.size ?? null;
    const url = new URL(entry.url);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || !config.origins.has(url.origin)) {
      throw new Error(`fetch origin or transport is not authorized: ${url.origin}`);
    }
    if (size !== null && BigInt(size) > BigInt(config.maxBytes)) throw new Error('fetch length exceeds receipt budget');
    return { ...entry, size, parsed: url };
  });
  const stage = prepare(config, true);
  try {
    const staged = checked('fetch-plan', stage);
    if (JSON.stringify(staged.entries) !== JSON.stringify(plan.entries)) throw new Error('source changed while staging receipt');
    const budget = { remaining: config.maxBytes };
    const received = [];
    for (const entry of transfers) {
      const size = await download(entry.parsed, destination(stage, entry.path), entry.size, config, budget);
      received.push({ path: entry.path, bytes: String(size), origin: entry.parsed.origin });
    }
    const report = config.profile ? checked('validate', stage, '--profile', config.profile) : checked('validate', stage);
    commit({ root: stage, output: config.output });
    return { command: 'fetch', published: true, output: config.output, received, report };
  } catch (error) {
    error.staging = stage;
    throw error;
  }
}
