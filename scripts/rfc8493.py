"""BagIt 1.0 mandatory-behavior and authorized receipt regression suite."""
import argparse
from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('--bagit-path', required=True)
options, remaining = parser.parse_known_args()
sys.path.insert(0, str(Path(options.bagit_path).resolve()))
import bagit

ROOT = Path(__file__).resolve().parents[1]
BODY = b'abc\r\n\x00\xff'


def moon(*args, code=0):
    result = subprocess.run(['node', str(ROOT / 'bin/moonbagit.mjs'), *map(str, args)],
                            capture_output=True, text=True, encoding='utf-8', timeout=60)
    if result.returncode != code:
        raise AssertionError(f'Expected {code}, got {result.returncode}: {result.stdout} {result.stderr}')
    return json.loads(result.stdout)


def snapshot(root):
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob('*') if p.is_file()}


@contextmanager
def server(body=BODY, status=200, delay=0, length=None):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            time.sleep(delay)
            try:
                self.send_response(status)
                if status == 302:
                    self.send_header('Location', 'http://example.invalid/do-not-follow')
                if length is not None:
                    self.send_header('Content-Length', str(length))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = threading.Thread(target=httpd.serve_forever, daemon=True)
    worker.start()
    try:
        yield f'http://127.0.0.1:{httpd.server_port}', requests
    finally:
        httpd.shutdown()
        httpd.server_close()
        worker.join(timeout=5)


class Standard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonbagit-rfc8493-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def independent(self, encoding='utf-8', algorithms=('sha256', 'sha512'), name='source', filename='nested/a b.bin', utf16_big_endian=False):
        root = self.root / name
        root.mkdir()
        file = root / filename
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(BODY)
        instance = bagit.make_bag(str(root), checksums=list(algorithms))
        self.assertEqual(instance.version_info, (1, 0), 'Use the pinned native 1.0 producer')
        if encoding != 'utf-8':
            def encode_tag(text):
                if utf16_big_endian:
                    self.assertEqual(encoding, 'utf-16')
                    return b'\xfe\xff' + text.encode('utf-16-be')
                return text.encode(encoding)

            # Upstream make_bag hardcodes UTF-8 in bagit.txt even when its encoding
            # argument changes manifests. Use an explicitly labelled codec fixture:
            # transcode original Python-produced tag text and independently rehash
            # the raw bytes with stdlib hashlib. Do not patch the external tool.
            for tag in root.glob('*.txt'):
                if tag.name != 'bagit.txt' and not tag.name.startswith('tagmanifest-'):
                    tag.write_bytes(encode_tag(tag.read_text(encoding='utf-8')))
            (root / 'bagit.txt').write_bytes(f'BagIt-Version: 1.0\nTag-File-Character-Encoding: {encoding}\n'.encode('utf-8'))
            for algorithm in algorithms:
                lines = []
                for tag in sorted(root.glob('*.txt')):
                    if not tag.name.startswith('tagmanifest-'):
                        lines.append(hashlib.new(algorithm, tag.read_bytes()).hexdigest() + '  ' + tag.name + '\n')
                (root / f'tagmanifest-{algorithm}.txt').write_bytes(encode_tag(''.join(lines)))
            instance = bagit.Bag(str(root))
        self.assertTrue(instance.validate())
        return root

    def incomplete(self, url):
        root = self.independent()
        (root / 'fetch.txt').write_text(f'{url} {len(BODY)} data/nested/a b.bin\n', encoding='utf-8')
        bagit.Bag(str(root)).save()
        (root / 'data/nested/a b.bin').unlink()
        return root

    def test_independent_legacy_algorithms_and_safe_upgrade(self):
        root = self.independent(algorithms=('md5', 'sha1', 'sha256', 'sha512'))
        before = snapshot(root)
        self.assertTrue(moon('validate', root)['valid'])
        output = self.root / 'upgraded'
        self.assertTrue(moon('upgrade', root, output, '--both')['report']['valid'])
        self.assertTrue(bagit.Bag(str(output)).validate())
        self.assertEqual(snapshot(root), before)
        for name in ('manifest-md5.txt', 'manifest-sha1.txt'):
            self.assertEqual((root / name).read_bytes(), (output / name).read_bytes())

    def test_independent_iana_encodings_and_raw_byte_tag_digests(self):
        for i, (encoding, filename) in enumerate([
            ('iso-8859-1', 'caf\u00e9.bin'), ('utf-16', '\u4e2d\u6587.bin'),
            ('utf-16-be', '\u4e2d\u6587.bin'), ('shift_jis', '\u65e5\u672c.bin'),
            ('gb18030', '\u4e2d\u6587.bin'), ('ascii', 'plain.bin'),
        ]):
            with self.subTest(encoding=encoding):
                root = self.independent(encoding=encoding, name=f'encoding-{i}', filename=filename)
                before = snapshot(root)
                self.assertTrue(moon('validate', root)['valid'])
                self.assertEqual(snapshot(root), before)

    def test_moon_creates_encoded_bags_for_independent_python_receiver(self):
        source = self.root / 'original'
        source.mkdir()
        (source / 'file.bin').write_bytes(BODY)
        for i, encoding in enumerate(('iso-8859-1', 'utf-16', 'shift_jis', 'gb18030')):
            output = self.root / f'created-{i}'
            result = moon('create', source, output, '--all', '--encoding', encoding)
            self.assertTrue(result['report']['valid'])
            self.assertTrue(bagit.Bag(str(output)).validate())
            self.assertEqual((output / 'data/file.bin').read_bytes(), BODY)

    def test_generic_utf16_uses_bom_byte_order_for_validation_and_upgrade(self):
        for i, big_endian in enumerate((False, True)):
            with self.subTest(big_endian=big_endian):
                root = self.independent(encoding='utf-16', algorithms=('sha256',),
                                        name=f'bom-{i}', filename='\u00d8.bin',
                                        utf16_big_endian=big_endian)
                before = snapshot(root)
                self.assertTrue(moon('validate', root)['valid'])
                output = self.root / f'upgraded-bom-{i}'
                self.assertTrue(moon('upgrade', root, output, '--sha512')['report']['valid'])
                self.assertTrue(bagit.Bag(str(output)).validate())
                self.assertEqual(snapshot(root), before)
                for name in ('bagit.txt', 'bag-info.txt', 'manifest-sha256.txt'):
                    self.assertEqual((root / name).read_bytes(), (output / name).read_bytes())

    def test_bad_codec_or_unrepresentable_name_never_publishes(self):
        source = self.root / 'original'
        source.mkdir()
        (source / '\u4e2d\u6587.bin').write_bytes(BODY)
        for i, encoding in enumerate(('not-a-charset', 'ascii')):
            output = self.root / f'created-{i}'
            moon('create', source, output, '--encoding', encoding, code=2)
            self.assertFalse(output.exists())

    def test_codecs_reject_malformed_bytes_without_replacing_valid_replacement_characters(self):
        code = '''import { decodeTag } from './bin/host.mjs';
        for (const [encoding, hex] of [['UTF-8','ff'], ['US-ASCII','80'],
          ['UTF-16','6100'], ['UTF-16LE','61'], ['UTF-16LE','00d8'],
          ['UTF-16','feffd800'], ['UTF-16','fffe00d8'], ['Shift_JIS','81']]) {
          let rejected = false;
          try { decodeTag(Buffer.from(hex,'hex'), encoding); } catch { rejected = true; }
          if (!rejected) throw new Error(`malformed ${encoding} accepted`);
        }
        if (decodeTag(Buffer.from('ff fefdff'.replaceAll(' ',''),'hex'), 'UTF-16') !== '\\uFFFD') {
          throw new Error('valid literal replacement character was discarded');
        }'''
        result = subprocess.run(['node', '--input-type=module', '-e', code], cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_upgrade_preserves_declared_non_utf8_encoding(self):
        for i, encoding in enumerate(('iso-8859-1', 'utf-16', 'shift_jis')):
            with self.subTest(encoding=encoding):
                root = self.independent(encoding=encoding, algorithms=('sha256',), name=f'old-{i}', filename='caf\u00e9.bin' if i == 0 else 'file.bin')
                output = self.root / f'new-{i}'
                before = snapshot(root)
                self.assertTrue(moon('upgrade', root, output, '--sha512')['report']['valid'])
                self.assertTrue(bagit.Bag(str(output)).validate())
                self.assertEqual((root / 'bagit.txt').read_bytes(), (output / 'bagit.txt').read_bytes())
                self.assertEqual(snapshot(root), before)

    def test_no_optional_tags_and_empty_payload_are_valid(self):
        root = self.independent()
        for entry in root.glob('tagmanifest-*.txt'):
            entry.unlink()
        (root / 'bag-info.txt').unlink()
        self.assertTrue(moon('validate', root)['valid'])
        empty = self.root / 'empty'
        empty.mkdir()
        bagit.make_bag(str(empty), checksums=['sha512'])
        # Upstream omits manifests for zero files; supply the required empty
        # manifest and remove stale optional tag manifests in this explicit fixture.
        (empty / 'manifest-sha512.txt').write_bytes(b'')
        for tag in empty.glob('tagmanifest-*.txt'):
            tag.unlink()
        self.assertTrue(moon('validate', empty)['valid'])

    def test_nonportable_posix_names_not_misclassified_as_rfc_errors(self):
        if os.name == 'nt':
            self.skipTest('Windows cannot represent the POSIX filenames')
        source = self.root / 'posix'
        source.mkdir()
        for name in ('file:name', 'literal\\backslash', 'line\nreturn\r%', 'a?b*'):
            (source / name).write_bytes(BODY)
        output = self.root / 'posix-bag'
        moon('create', source, output, '--both')
        self.assertTrue(moon('validate', output)['valid'])
        self.assertEqual(snapshot(output / 'data'), snapshot(source))

    def test_fetch_validates_full_uri_before_network_or_staging(self):
        root = self.incomplete('http://[broken/path')
        before = set(self.root.iterdir())
        self.assertIn('error', moon('fetch-plan', root, code=2))
        moon('fetch', root, self.root / 'out', '--allow-origin', 'http://127.0.0.1:1', code=2)
        self.assertEqual(set(self.root.iterdir()), before)

    def test_fetch_receives_and_preserves_source_and_standard_manifests(self):
        with server(length=len(BODY)) as (origin, requests):
            root = self.incomplete(origin + '/a%20b?source=test')
            before = snapshot(root)
            report = moon('fetch', root, self.root / 'received', '--allow-origin', origin)
            self.assertTrue(report['published'])
            self.assertTrue(report['report']['valid'])
            self.assertTrue(bagit.Bag(str(self.root / 'received')).validate())
            self.assertEqual((self.root / 'received/data/nested/a b.bin').read_bytes(), BODY)
            self.assertEqual(snapshot(root), before)
            self.assertEqual(requests, ['/a%20b?source=test'])
            for relative, content in before.items():
                self.assertEqual((self.root / 'received' / relative).read_bytes(), content)

    def test_fetch_refuses_unauthorized_origin_without_request(self):
        with server() as (origin, requests):
            root = self.incomplete(origin + '/a')
            before = set(self.root.iterdir())
            moon('fetch', root, self.root / 'out', '--allow-origin', 'http://example.invalid', code=2)
            self.assertEqual(requests, [])
            self.assertEqual(set(self.root.iterdir()), before)

    def test_fetch_checks_final_digest_not_just_file_length(self):
        with server(body=b'XYZ\r\n\x00\xff') as (origin, _):
            root = self.incomplete(origin + '/a')
            result = moon('fetch', root, self.root / 'out', '--allow-origin', origin, code=2)
            self.assertIn('checksum_mismatch', result['error'])
            self.assertFalse((self.root / 'out').exists())
            self.assertTrue(Path(result['staging']).is_dir())
            self.assertFalse((root / 'data/nested/a b.bin').exists())

    def test_fetch_refuses_redirects_length_mismatch_and_non200(self):
        for i, (status, length) in enumerate(((302, None), (404, None), (200, len(BODY) + 1))):
            with self.subTest(status=status, length=length), server(status=status, length=length) as (origin, requests):
                root = self.independent(name=f'bad-{i}')
                (root / 'fetch.txt').write_text(f'{origin}/a {len(BODY)} data/nested/a b.bin\n', encoding='utf-8')
                bagit.Bag(str(root)).save()
                (root / 'data/nested/a b.bin').unlink()
                target = self.root / f'out-{i}'
                moon('fetch', root, target, '--allow-origin', origin, code=2)
                self.assertFalse(target.exists())
                self.assertEqual(requests, ['/a'])

    def test_fetch_budget_and_deadline_do_not_publish(self):
        with server(delay=0.2) as (origin, _):
            root = self.incomplete(origin + '/a')
            moon('fetch', root, self.root / 'timed-out', '--allow-origin', origin, '--timeout-ms', '20', code=2)
            self.assertFalse((self.root / 'timed-out').exists())
        root = self.root / 'source'
        moon('fetch', root, self.root / 'too-large', '--allow-origin', origin, '--max-bytes', '1', code=2)
        self.assertFalse((self.root / 'too-large').exists())

    def test_unknown_fetch_length_accepts_valid_bytes_and_enforces_streamed_budget(self):
        with server() as (origin, _):
            root = self.incomplete(origin + '/a')
            fetch = root / 'fetch.txt'
            fetch.write_text(fetch.read_text(encoding='utf-8').replace(f' {len(BODY)} data/', ' - data/'), encoding='utf-8')
            bagit.Bag(str(root)).save()
            result = moon('fetch', root, self.root / 'received', '--allow-origin', origin)
            self.assertTrue(result['report']['valid'])
            limited = moon('fetch', root, self.root / 'limited', '--allow-origin', origin,
                           '--max-bytes', str(len(BODY) - 1), code=2)
            self.assertIn('budget', limited['error'])
            self.assertFalse((self.root / 'limited').exists())

    def test_fetch_receiving_profile_failure_keeps_staging(self):
        with server() as (origin, _):
            root = self.incomplete(origin + '/a')
            result = moon('fetch', root, self.root / 'out', '--allow-origin', origin,
                          '--profile', ROOT / 'examples/research-profile.json', code=2)
            self.assertFalse(result['published'])
            self.assertTrue(Path(result['staging']).is_dir())
            self.assertFalse((self.root / 'out').exists())

    def test_fetch_no_overwrite_and_existing_payload_corruption_preflight(self):
        with server() as (origin, requests):
            root = self.incomplete(origin + '/a')
            target = self.root / 'out'
            target.mkdir()
            moon('fetch', root, target, '--allow-origin', origin, code=2)
            self.assertEqual(requests, [])
            # A present corrupt file is never silently replaced from fetch.txt.
            (root / 'data/nested/a b.bin').write_bytes(b'XYZ\r\n\x00\xff')
            moon('fetch', root, self.root / 'new', '--allow-origin', origin, code=2)
            self.assertEqual(requests, [])


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
