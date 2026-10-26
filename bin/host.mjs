import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import iconv from 'iconv-lite';

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

function pathEntryExists(target) {
  // existsSync follows symlinks and incorrectly treats a dangling link as absent.
  return fs.lstatSync(target, { throwIfNoEntry: false }) !== undefined;
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

export function decodeTag(bytes, encoding) {
  const normalized = encoding.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (!iconv.encodingExists(encoding)) throw new Error(`unsupported host character encoding: ${encoding}`);
  if (normalized === 'utf8') return decoder.decode(bytes);
  if (['ascii', 'usascii', 'ansix341968', 'iso646us'].includes(normalized) && bytes.some(value => value > 127)) {
    throw new Error('invalid US-ASCII tag bytes');
  }
  if (normalized === 'utf16' && !(bytes[0] === 0xff && bytes[1] === 0xfe) &&
      !(bytes[0] === 0xfe && bytes[1] === 0xff)) throw new Error('UTF-16 requires a byte order mark');
  // ICU rejects malformed sequences where available; iconv provides IANA legacy encodings.
  // Round-trip validation below also protects codecs not implemented by ICU.
  let decoded;
  try {
    decoded = new TextDecoder(encoding, { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
  }
  const result = iconv.decode(bytes, encoding);
  const encoded = iconv.encode(result, encoding);
  if (!encoded.equals(bytes) && !['utf16le', 'utf16be', 'utf16'].includes(normalized)) {
    // Some legacy encodings have multiple byte representations. ICU's strict
    // decoder is authoritative for those; never silently accept a replacement.
    if (decoded === undefined || result.includes('\uFFFD')) throw new Error(`invalid ${encoding} tag bytes`);
  }
  if (['utf16le', 'utf16be', 'utf16'].includes(normalized)) {
    if (bytes.length % 2) throw new Error('invalid UTF-16 tag bytes');
  }
  return result;
}

function tagEncoding(root) {
  const declaration = path.join(root, 'bagit.txt');
  if (!fs.lstatSync(declaration, { throwIfNoEntry: false })?.isFile()) return 'UTF-8';
  const record = hashFile(declaration, 'UTF-8');
  const match = /^Tag-File-Character-Encoding: ([A-Za-z0-9_.:-]+)$/m.exec(record.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  return match?.[1] ?? 'UTF-8';
}

function hashFile(absolute, text) {
  const before = fs.lstatSync(absolute);
  if (!before.isFile() || before.isSymbolicLink()) throw new Error('not a regular file');
  if (!Number.isSafeInteger(before.size)) throw new Error('file size exceeds host integer precision');
  if (text && before.size > MAX_TEXT_BYTES) throw new Error('tag text exceeds 16 MiB limit');
  const fd = fs.openSync(absolute, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    if (!sameFile(before, fs.fstatSync(fd))) throw new Error('file changed before reading');
    const hashes = Object.fromEntries(['md5', 'sha1', 'sha256', 'sha512'].map(name => [name, crypto.createHash(name)]));
    const buffer = Buffer.allocUnsafe(Math.min(1024 * 1024, Math.max(1, before.size)));
    const chunks = [];
    let size = 0;
    for (;;) {
      const count = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (!count) break;
      const bytes = buffer.subarray(0, count);
      size += count;
      if (text && size > MAX_TEXT_BYTES) throw new Error('tag text grew past size limit');
      for (const hash of Object.values(hashes)) hash.update(bytes);
      if (text) chunks.push(Buffer.from(bytes));
    }
    if (size !== before.size || !sameFile(before, fs.fstatSync(fd)) || !sameFile(before, fs.lstatSync(absolute))) {
      throw new Error('file changed while reading');
    }
    return {
      size,
      digests: Object.fromEntries(Object.entries(hashes).map(([name, hash]) => [name, hash.digest('hex')])),
      text: text ? decodeTag(Buffer.concat(chunks), text === true ? 'UTF-8' : text) : undefined,
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
  const encoding = tagEncoding(root);
  const files = [];
  const texts = {};
  let textBytes = 0;
  for (const entry of tree.files) {
    const text = isTextTag(entry.relative);
    const record = hashFile(entry.absolute, text ? (entry.relative === 'bagit.txt' ? 'UTF-8' : encoding) : false);
    files.push({ path: entry.relative, size: String(record.size), digests: record.digests });
    if (record.text !== undefined) {
      textBytes += record.size;
      if (textBytes > MAX_TOTAL_TEXT_BYTES) throw new Error('total tag text exceeds 64 MiB limit');
      texts[entry.relative] = record.text;
    }
  }
  return { files, directories: tree.directories, texts };
}

export function prepare({ source, output }, wholeBag = false) {
  const root = directory(source);
  const destination = path.resolve(output);
  if (pathEntryExists(destination)) throw new Error('output must not already exist');
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
  const declaration = tags['bagit.txt'];
  const selectedEncoding = declaration?.match(/^Tag-File-Character-Encoding: ([A-Za-z0-9_.:-]+)$/m)?.[1] ?? tagEncoding(absolute);
  for (const [name, text] of Object.entries(tags)) {
    if (!/^(bagit|bag-info|(?:tag)?manifest-(md5|sha1|sha256|sha512))\.txt$/.test(name) || typeof text !== 'string') {
      throw new Error('unexpected generated tag filename');
    }
    if (replace && !/^tagmanifest-(md5|sha1|sha256|sha512)\.txt$/.test(name)) {
      throw new Error('only staging tag manifests may be replaced');
    }
    const target = path.join(absolute, name);
    if (replace && fs.existsSync(target) && !fs.lstatSync(target).isFile()) throw new Error('tag is not a regular file');
    const encoding = name === 'bagit.txt' ? 'UTF-8' : selectedEncoding;
    const bytes = iconv.encode(text, encoding);
    if (decodeTag(bytes, encoding) !== text) throw new Error(`generated text is not representable in ${encoding}`);
    fs.writeFileSync(target, bytes, { flag: replace ? 'w' : 'wx' });
  }
  return null;
}

export function commit({ root, output }) {
  const stage = directory(root);
  const target = path.resolve(output);
  const resolved = path.join(directory(path.dirname(target)), path.basename(target));
  if (stages.get(stage) !== resolved) throw new Error('unknown staging transaction');
  if (pathEntryExists(resolved)) throw new Error('output appeared while creating bag; staging retained');
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
          case 'codec': {
            if (typeof value.encoding !== 'string' || !iconv.encodingExists(value.encoding)) throw new Error('unsupported host character encoding');
            result = value.encoding;
            break;
          }
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
