"""Independent BagIt 1.0 interoperability and CLI regression checks."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument("--bagit-path", help="Optional directory containing the independent bagit module")
options, remaining = parser.parse_known_args()
if options.bagit_path:
    sys.path.insert(0, str(Path(options.bagit_path).resolve()))
import bagit  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "moonbagit.mjs"


def run(*args, code=0):
    result = subprocess.run(["node", str(CLI), *map(str, args)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8", timeout=60)
    if result.returncode != code:
        raise AssertionError(f"expected exit {code}, got {result.returncode}: {result.stdout} {result.stderr}")
    return json.loads(result.stdout)


def payload(directory):
    directory.mkdir()
    (directory / "nested").mkdir()
    (directory / "nested" / "a b.txt").write_bytes(b"abc\r\n\x00\xff")
    (directory / "100percent.txt").write_bytes(b"percent")
    (directory / "empty.bin").write_bytes(b"")
    (directory / "\u4e2d\u6587.txt").write_bytes(b"unicode filename")


class Interop(unittest.TestCase):
    def setUp(self):
        # A new directory per test avoids mutating any existing user files.
        self.temp = tempfile.TemporaryDirectory(prefix="moonbagit-interop-")
        self.base = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def moon_bag(self, option="--both"):
        source = self.base / "source"
        payload(source)
        output = self.base / "bag"
        run("create", source, output, option)
        return source, output

    def test_moon_to_python_both(self):
        source, output = self.moon_bag()
        self.assertTrue(bagit.Bag(str(output)).validate())
        self.assertTrue(run("validate", output)["valid"])
        self.assertEqual((source / "100percent.txt").read_bytes(), b"percent")
        self.assertFalse((source / "bagit.txt").exists())

    def test_moon_to_python_sha256(self):
        _, output = self.moon_bag("--sha256")
        self.assertTrue(bagit.Bag(str(output)).validate())
        self.assertFalse((output / "manifest-sha512.txt").exists())

    def test_moon_to_python_sha512_default(self):
        source = self.base / "source"
        payload(source)
        output = self.base / "bag"
        run("create", source, output)
        self.assertTrue(bagit.Bag(str(output)).validate())
        self.assertTrue((output / "manifest-sha512.txt").exists())

    def test_python_to_moon(self):
        directory = self.base / "python-bag"
        payload(directory)
        independent = bagit.make_bag(str(directory), checksums=["sha256", "sha512"])
        if independent.version_info == (0, 97):
            # Released bagit-python creates 0.97. Upgrade only the declaration;
            # the independent tool recomputes its tag manifests, not MoonBagIt.
            declaration = directory / "bagit.txt"
            declaration.write_text(declaration.read_text(encoding="utf-8").replace("0.97", "1.0"), encoding="utf-8")
            independent = bagit.Bag(str(directory))
            independent.save()
        self.assertEqual(independent.version_info, (1, 0))
        self.assertTrue(independent.validate())
        result = run("validate", directory)
        self.assertTrue(result["complete"])
        self.assertTrue(result["valid"])

    def test_same_size_corruption_is_complete_not_valid(self):
        _, output = self.moon_bag()
        target = output / "data" / "100percent.txt"
        target.write_bytes(b"corrupt")
        result = run("validate", output, code=1)
        self.assertTrue(result["complete"])
        self.assertFalse(result["valid"])
        self.assertFalse(bagit.Bag(str(output)).is_valid())

    def test_missing_payload(self):
        _, output = self.moon_bag()
        (output / "data" / "empty.bin").unlink()
        self.assertFalse(run("validate", output, code=1)["complete"])
        self.assertFalse(bagit.Bag(str(output)).is_valid())

    def test_extra_payload(self):
        _, output = self.moon_bag()
        (output / "data" / "extra.bin").write_bytes(b"new")
        self.assertFalse(run("validate", output, code=1)["complete"])

    def test_tag_corruption(self):
        _, output = self.moon_bag()
        with (output / "bag-info.txt").open("a", encoding="utf-8") as stream:
            stream.write("Contact-Name: Someone else\n")
        result = run("validate", output, code=1)
        self.assertTrue(result["complete"])
        self.assertFalse(result["valid"])
        self.assertFalse(bagit.Bag(str(output)).is_valid())

    def test_no_overwrite(self):
        source, output = self.moon_bag()
        before = (output / "bagit.txt").read_bytes()
        self.assertIn("error", run("create", source, output, code=2))
        self.assertEqual((output / "bagit.txt").read_bytes(), before)

    def test_output_cannot_be_inside_source(self):
        source = self.base / "source"
        payload(source)
        self.assertIn("error", run("create", source, source / "bag", code=2))
        self.assertFalse((source / "bag").exists())

    def test_traversal_manifest_is_rejected(self):
        _, output = self.moon_bag()
        (output / "manifest-sha256.txt").write_text("0" * 64 + "  data/../../secret\n", encoding="utf-8")
        result = run("validate", output, code=1)
        self.assertTrue(any(d["code"] == "manifest_format" for d in result["diagnostics"]))

    def test_symlink_rejected(self):
        source = self.base / "source"
        payload(source)
        try:
            (source / "link").symlink_to(source / "empty.bin")
        except OSError:
            self.skipTest("OS does not permit symlink creation for this user")
        self.assertIn("symlinks", run("create", source, self.base / "bag", code=2)["error"])

    def test_invalid_utf8_is_rejected(self):
        _, output = self.moon_bag()
        (output / "bag-info.txt").write_bytes(b"Contact-Name: \xff\n")
        self.assertIn("error", run("validate", output, code=2))

    def test_utf8_bom_is_not_silently_removed(self):
        _, output = self.moon_bag()
        target = output / "bagit.txt"
        target.write_bytes(b"\xef\xbb\xbf" + target.read_bytes())
        result = run("validate", output, code=1)
        self.assertTrue(any(d["code"] == "declaration" for d in result["diagnostics"]))

    def test_empty_payload(self):
        source = self.base / "source"
        source.mkdir()
        output = self.base / "bag"
        run("create", source, output)
        self.assertTrue(run("validate", output)["valid"])
        self.assertTrue(bagit.Bag(str(output)).validate())

    def test_newline_filename(self):
        if os.name == "nt":
            self.skipTest("Windows does not support newline filenames")
        source = self.base / "source"
        source.mkdir()
        (source / "a\nb\r.txt").write_bytes(b"newline")
        output = self.base / "bag"
        run("create", source, output)
        self.assertTrue(bagit.Bag(str(output)).validate())

    def test_percent_filename_normative_escape(self):
        source = self.base / "source"
        source.mkdir()
        (source / "100%.txt").write_bytes(b"percent")
        output = self.base / "bag"
        run("create", source, output)
        manifest = (output / "manifest-sha512.txt").read_text(encoding="utf-8")
        self.assertIn("data/100%25.txt", manifest)
        self.assertTrue(run("validate", output)["valid"])
        # Upstream does not decode %25; do not change normative output to suit it.
        self.assertFalse(bagit.Bag(str(output)).is_valid())

    def test_metadata_repetition(self):
        source = self.base / "source"
        payload(source)
        metadata = self.base / "metadata.json"
        metadata.write_text(json.dumps([
            {"label": "Contact-Name", "value": "First"},
            {"label": "Contact-Name", "value": "Second"},
        ]), encoding="utf-8")
        output = self.base / "bag"
        run("create", source, output, "--metadata", metadata)
        self.assertEqual(bagit.Bag(str(output)).info["Contact-Name"], ["First", "Second"])


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
