import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const MAX_FILES = 100000;
const MAX_DIRECTORIES = 100000;
const MAX_TEXT_BYTES = 16 * 1024 * 1024;
const MAX_TOTAL_TEXT_BYTES = 64 * 1024 * 1024;
const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
const stages = new Map();

function relativePath(root, target) {
  const relative = path.relative(root, target);
  if (path.isAbsolute(relative) || relative === '..' || relative.startsWith(`..${path.sep}`)) {
    throw new Error('path escapes the selected root');
  }
  return relative.split(path.sep).join('/');
}

function directory(root) {
  const absolute = path.resolve(root);
  const stat = fs.lstatSync(absolute);
  if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('root must be a real directory');
  return fs.realpathSync(absolute);
}

function walk(root) {
  const files = [];
  const directories = [];
  const pending = [root];
  while (pending.length) {
    const current = pending.pop();
    for (const name of fs.readdirSync(current).sort()) {
      const absolute = path.join(current, name);
      const relative = relativePath(root, absolute);
      const stat = fs.lstatSync(absolute);
      if (stat.isSymbolicLink()) throw new Error(`symlinks are not supported: ${relative}`);
      if (stat.isDirectory()) {
        directories.push(relative);
        if (directories.length > MAX_DIRECTORIES) throw new Error('directory count limit exceeded');
        pending.push(absolute);
      } else if (stat.isFile()) {
        files.push({ absolute, relative });
        if (files.length > MAX_FILES) throw new Error('file count limit exceeded');
      } else {
        throw new Error(`special files are not supported: ${relative}`);
      }
    }
  }
  files.sort((a, b) => a.relative < b.relative ? -1 : a.relative > b.relative ? 1 : 0);
  directories.sort();
  return { files, directories };
}

function sameFile(a, b) {
  return a.dev === b.dev && a.ino === b.ino && a.size === b.size &&
    a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
}

function hashFile(absolute, text) {
  const before = fs.lstatSync(absolute);
  if (!before.isFile() || before.isSymbolicLink()) throw new Error('not a regular file');
  if (!Number.isSafeInteger(before.size)) throw new Error('file size exceeds host integer precision');
  if (text && before.size > MAX_TEXT_BYTES) throw new Error('tag text exceeds 16 MiB limit');
  const fd = fs.openSync(absolute, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    if (!sameFile(before, fs.fstatSync(fd))) throw new Error('file changed before reading');
    const sha256 = crypto.createHash('sha256');
    const sha512 = crypto.createHash('sha512');
    const buffer = Buffer.allocUnsafe(Math.min(1024 * 1024, Math.max(1, before.size)));
    const chunks = [];
    let size = 0;
    for (;;) {
      const count = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (!count) break;
      const bytes = buffer.subarray(0, count);
      size += count;
      if (text && size > MAX_TEXT_BYTES) throw new Error('tag text grew past size limit');
      sha256.update(bytes);
      sha512.update(bytes);
      if (text) chunks.push(Buffer.from(bytes));
    }
    if (size !== before.size || !sameFile(before, fs.fstatSync(fd)) || !sameFile(before, fs.lstatSync(absolute))) {
      throw new Error('file changed while reading');
    }
    return {
      size,
      digests: { sha256: sha256.digest('hex'), sha512: sha512.digest('hex') },
      text: text ? decoder.decode(Buffer.concat(chunks)) : undefined,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function isTextTag(relative) {
  return relative === 'bagit.txt' || relative === 'bag-info.txt' || relative === 'fetch.txt' ||
    (!relative.includes('/') && /^(?:tag)?manifest-.*\.txt$/.test(relative));
}

function scan(value) {
  const root = directory(value);
  const tree = walk(root);
  const files = [];
  const texts = {};
  let textBytes = 0;
  for (const entry of tree.files) {
    const record = hashFile(entry.absolute, isTextTag(entry.relative));
    files.push({ path: entry.relative, size: String(record.size), digests: record.digests });
    if (record.text !== undefined) {
      textBytes += record.size;
      if (textBytes > MAX_TOTAL_TEXT_BYTES) throw new Error('total tag text exceeds 64 MiB limit');
      texts[entry.relative] = record.text;
    }
  }
  return { files, directories: tree.directories, texts };
}

function prepare({ source, output }, wholeBag = false) {
  const root = directory(source);
  const destination = path.resolve(output);
  if (fs.existsSync(destination)) throw new Error('output must not already exist');
  const parent = directory(path.dirname(destination));
  const resolvedDestination = path.join(parent, path.basename(destination));
  const relative = path.relative(root, resolvedDestination);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) {
    throw new Error('output must not be inside the source directory');
  }
  const inventory = walk(root);
  const stage = fs.mkdtempSync(path.join(parent, '.moonbagit-'));
  stages.set(stage, resolvedDestination);
  const content = wholeBag ? stage : path.join(stage, 'data');
  if (!wholeBag) fs.mkdirSync(content);
  for (const relative of inventory.directories) fs.mkdirSync(path.join(content, ...relative.split('/')), { recursive: true });
  for (const entry of inventory.files) {
    const before = fs.lstatSync(entry.absolute);
    if (!before.isFile() || before.isSymbolicLink()) throw new Error('source changed during copy');
    const target = path.join(content, ...entry.relative.split('/'));
    fs.copyFileSync(entry.absolute, target, fs.constants.COPYFILE_EXCL);
    if (!sameFile(before, fs.lstatSync(entry.absolute))) throw new Error('source changed during copy');
  }
  return stage;
}

function writeTags({ root, tags, replace = false }) {
  const absolute = directory(root);
  if (!stages.has(absolute)) throw new Error('writes are restricted to this process staging directory');
  for (const [name, text] of Object.entries(tags)) {
    if (!/^(bagit|bag-info|(?:tag)?manifest-(sha256|sha512))\.txt$/.test(name) || typeof text !== 'string') {
      throw new Error('unexpected generated tag filename');
    }
    if (replace && !/^tagmanifest-(sha256|sha512)\.txt$/.test(name)) {
      throw new Error('only staging tag manifests may be replaced');
    }
    const target = path.join(absolute, name);
    if (replace && fs.existsSync(target) && !fs.lstatSync(target).isFile()) throw new Error('tag is not a regular file');
    fs.writeFileSync(target, text, { encoding: 'utf8', flag: replace ? 'w' : 'wx' });
  }
  return null;
}

function commit({ root, output }) {
  const stage = directory(root);
  const target = path.resolve(output);
  const resolved = path.join(directory(path.dirname(target)), path.basename(target));
  if (stages.get(stage) !== resolved) throw new Error('unknown staging transaction');
  if (fs.existsSync(resolved)) throw new Error('output appeared while creating bag; staging retained');
  // Callers must keep source/output trees quiescent; this is not a lock service.
  fs.renameSync(stage, resolved);
  stages.delete(stage);
  return null;
}

export function installHost(args = process.argv.slice(2)) {
  globalThis.__moonbagit = {
    call(op, input) {
      try {
        const value = JSON.parse(input);
        let result;
        switch (op) {
          case 'args': result = args; break;
          case 'scan': result = scan(value.root); break;
          case 'prepare': result = prepare(value); break;
          case 'prepare_upgrade': result = prepare(value, true); break;
          case 'write_tags': result = writeTags(value); break;
          case 'commit': result = commit(value); break;
          case 'metadata': {
            const record = hashFile(path.resolve(value.path), true);
            result = JSON.parse(record.text);
            break;
          }
          default: throw new Error('unknown host operation');
        }
        return JSON.stringify({ ok: true, value: result });
      } catch (error) {
        return JSON.stringify({ ok: false, error: error.message });
      }
    },
  };
}
