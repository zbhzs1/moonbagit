"""Independent BagIt 1.0 interoperability and CLI regression checks."""
import argparse
import json
import os
import hashlib
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

    def test_create_never_replaces_dangling_output_symlink(self):
        source = self.base / "source"
        payload(source)
        output = self.base / "dangling-output"
        target = self.base / "absent-target"
        try:
            output.symlink_to(target, target_is_directory=True)
        except OSError:
            self.skipTest("OS does not permit symlink creation for this user")
        before = set(self.base.iterdir())
        link_before = output.readlink()
        result = run("create", source, output, code=2)
        self.assertIn("already exist", result["error"])
        self.assertTrue(output.is_symlink())
        self.assertEqual(output.readlink(), link_before)
        self.assertFalse(target.exists())
        self.assertEqual(set(self.base.iterdir()), before)

    def test_upgrade_never_replaces_dangling_output_symlink(self):
        _, original = self.moon_bag("--sha256")
        output = self.base / "dangling-upgrade"
        target = self.base / "absent-target"
        try:
            output.symlink_to(target, target_is_directory=True)
        except OSError:
            self.skipTest("OS does not permit symlink creation for this user")
        before = set(self.base.iterdir())
        link_before = output.readlink()
        self.assertIn("already exist", run("upgrade", original, output, "--sha512", code=2)["error"])
        self.assertTrue(output.is_symlink())
        self.assertEqual(output.readlink(), link_before)
        self.assertEqual(set(self.base.iterdir()), before)

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

    def test_upgrade_preserves_bytes_and_independent_validity(self):
        _, original = self.moon_bag("--sha256")
        before = {p.relative_to(original): p.read_bytes() for p in original.rglob("*") if p.is_file()}
        upgraded = self.base / "upgraded"
        report = run("upgrade", original, upgraded, "--sha512")["report"]
        self.assertTrue(report["valid"])
        self.assertTrue(bagit.Bag(str(upgraded)).validate())
        for relative, content in before.items():
            self.assertEqual((original / relative).read_bytes(), content)
            if not str(relative).startswith("tagmanifest-"):
                self.assertEqual((upgraded / relative).read_bytes(), content)
        self.assertTrue((upgraded / "tagmanifest-sha256.txt").exists())
        for algorithm in ("sha256", "sha512"):
            text = (upgraded / f"tagmanifest-{algorithm}.txt").read_text(encoding="utf-8")
            self.assertIn("manifest-sha256.txt", text)
            self.assertIn("manifest-sha512.txt", text)

    def test_upgrade_preserves_arbitrary_binary_tags(self):
        _, original = self.moon_bag("--sha256")
        (original / "receipt.bin").write_bytes(b"\x00\xff\x80")
        upgraded = self.base / "upgraded"
        run("upgrade", original, upgraded, "--both")
        self.assertEqual((upgraded / "receipt.bin").read_bytes(), b"\x00\xff\x80")
        self.assertTrue(bagit.Bag(str(upgraded)).validate())
        for algorithm in ("sha256", "sha512"):
            digest = hashlib.new(algorithm, b"\x00\xff\x80").hexdigest()
            self.assertIn(digest + "  receipt.bin", (upgraded / f"tagmanifest-{algorithm}.txt").read_text(encoding="utf-8"))

    def test_upgrade_refuses_corruption_without_resigning(self):
        _, original = self.moon_bag()
        (original / "data" / "100percent.txt").write_bytes(b"corrupt")
        target = self.base / "upgraded"
        self.assertIn("invalid", run("upgrade", original, target, "--sha512", code=2)["error"])
        self.assertFalse(target.exists())

    def test_upgrade_no_overwrite_and_idempotent_manifests(self):
        _, original = self.moon_bag()
        target = self.base / "upgraded"
        run("upgrade", original, target, "--both")
        for p in original.rglob("*"):
            if p.is_file():
                self.assertEqual(p.read_bytes(), (target / p.relative_to(original)).read_bytes())
        self.assertIn("error", run("upgrade", original, target, "--both", code=2))

    def test_upgrade_inside_source_is_refused(self):
        _, original = self.moon_bag()
        self.assertIn("error", run("upgrade", original, original / "copy", "--sha512", code=2))
        self.assertFalse((original / "copy").exists())

    def research_bag(self):
        output = self.base / "research-bag"
        run("create", ROOT / "examples" / "payload", output, "--both", "--metadata", ROOT / "examples" / "research-metadata.json")
        return output

    def test_research_receiving_profile(self):
        output = self.research_bag()
        report = run("validate", output, "--profile", ROOT / "examples" / "research-profile.json")
        self.assertTrue(report["bag"]["valid"])
        self.assertTrue(report["conforms"])
        self.assertEqual(report["diagnostics"], [])
        self.assertTrue(bagit.Bag(str(output)).validate())

    def test_create_enforces_receiving_profile_before_publication(self):
        output = self.base / "accepted"
        result = run("create", ROOT / "examples" / "payload", output, "--both",
                     "--metadata", ROOT / "examples" / "research-metadata.json",
                     "--profile", ROOT / "examples" / "research-profile.json")
        self.assertTrue(result["published"])
        self.assertTrue(result["profile"]["conforms"])
        self.assertTrue(bagit.Bag(str(output)).validate())

    def test_create_profile_mismatch_retains_staging_not_output(self):
        source = self.base / "source"
        payload(source)
        before = {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()}
        output = self.base / "rejected"
        result = run("create", source, output, "--profile",
                     ROOT / "examples" / "research-profile.json", code=1)
        self.assertFalse(result["published"])
        self.assertTrue(result["report"]["valid"])
        self.assertFalse(result["profile"]["conforms"])
        self.assertTrue(any(d["code"] == "profile_identifier" for d in result["profile"]["diagnostics"]))
        self.assertFalse(output.exists())
        staging = Path(result["staging"])
        self.assertEqual(staging.parent, output.parent)
        self.assertTrue(run("validate", staging)["valid"])
        self.assertEqual(before, {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()})

    def test_create_profile_rejects_missing_required_algorithm(self):
        output = self.base / "rejected"
        result = run("create", ROOT / "examples" / "payload", output, "--sha256",
                     "--metadata", ROOT / "examples" / "research-metadata.json",
                     "--profile", ROOT / "examples" / "research-profile.json", code=1)
        self.assertFalse(result["published"])
        self.assertFalse(output.exists())
        self.assertTrue(result["report"]["valid"])
        self.assertTrue(result["profile"]["diagnostics"])

    def test_create_bad_profile_fails_before_staging(self):
        profile = json.loads((ROOT / "examples" / "research-profile.json").read_text(encoding="utf-8"))
        profile["Unknown-Constraint"] = True
        path = self.base / "bad-profile.json"
        path.write_text(json.dumps(profile), encoding="utf-8")
        output = self.base / "never-created"
        before = set(self.base.iterdir())
        self.assertIn("unknown profile", run("create", ROOT / "examples" / "payload", output,
                      "--profile", path, code=2)["error"])
        self.assertEqual(set(self.base.iterdir()), before)

    def test_create_rejects_duplicate_or_missing_profile_option(self):
        path = ROOT / "examples" / "research-profile.json"
        for options in [("--profile",), ("--profile", path, "--profile", path)]:
            output = self.base / "never-created"
            before = set(self.base.iterdir())
            self.assertIn("error", run("create", ROOT / "examples" / "payload", output, *options, code=2))
            self.assertEqual(set(self.base.iterdir()), before)

    def test_create_unsafe_metadata_fails_before_staging(self):
        path = self.base / "bad-metadata.json"
        output = self.base / "never-created"
        for field in [{"label": "Name:injection", "value": "value"},
                      {"label": "Description", "value": "first\n hidden"},
                      {"label": "Payload-Oxum", "value": "0.0"}]:
            path.write_text(json.dumps([field]), encoding="utf-8")
            before = set(self.base.iterdir())
            self.assertIn("error", run("create", ROOT / "examples" / "payload", output,
                          "--metadata", path, code=2))
            self.assertEqual(set(self.base.iterdir()), before)

    def test_create_duplicate_metadata_option_fails_before_staging(self):
        path = ROOT / "examples" / "research-metadata.json"
        before = set(self.base.iterdir())
        self.assertIn("error", run("create", ROOT / "examples" / "payload", self.base / "never-created",
                      "--metadata", path, "--metadata", path, code=2))
        self.assertEqual(set(self.base.iterdir()), before)

    def test_profile_rejects_wrong_identifier_on_otherwise_valid_bag(self):
        _, output = self.moon_bag()
        result = run("validate", output, "--profile", ROOT / "examples" / "research-profile.json", code=1)
        self.assertTrue(result["bag"]["valid"])
        self.assertFalse(result["conforms"])
        self.assertTrue(any(d["code"] == "profile_identifier" for d in result["diagnostics"]))

    def test_unknown_profile_constraint_fails_closed(self):
        output = self.research_bag()
        profile = json.loads((ROOT / "examples" / "research-profile.json").read_text(encoding="utf-8"))
        profile["Future-Constraint"] = True
        path = self.base / "profile.json"
        path.write_text(json.dumps(profile), encoding="utf-8")
        self.assertIn("unknown profile", run("validate", output, "--profile", path, code=2)["error"])

    def test_serialized_profile_never_silently_passes_directory(self):
        output = self.research_bag()
        profile = json.loads((ROOT / "examples" / "research-profile.json").read_text(encoding="utf-8"))
        profile["Serialization"] = "required"
        profile["Accept-Serialization"] = ["application/zip"]
        path = self.base / "profile.json"
        path.write_text(json.dumps(profile), encoding="utf-8")
        result = run("validate", output, "--profile", path, code=1)
        self.assertTrue(any(d["code"] == "profile_serialization" for d in result["diagnostics"]))

    def test_streaming_large_binary_file(self):
        source = self.base / "source"
        source.mkdir()
        chunk = bytes(range(256)) * 4096
        with (source / "large.bin").open("wb") as stream:
            for _ in range(20):
                stream.write(chunk)
        output = self.base / "bag"
        result = run("create", source, output, "--both")["report"]
        self.assertEqual(result["payload_bytes"], str(20 * len(chunk)))
        self.assertTrue(bagit.Bag(str(output)).validate())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
