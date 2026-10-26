"""Real-filesystem regressions for preservation, policies and delivery receipts."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "moonbagit.mjs"


def moon(*args, code=0):
    result = subprocess.run(["node", str(CLI), *map(str, args)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8", timeout=60)
    if result.returncode != code:
        raise AssertionError(f"expected {code}, got {result.returncode}: {result.stdout} {result.stderr}")
    return json.loads(result.stdout)


class Preservation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="moonbagit-preservation-")
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "file.bin").write_bytes(b"abc")
        self.bag = self.root / "bag"
        moon("create", self.source, self.bag, "--both")

    def tearDown(self):
        self.temp.cleanup()

    def document(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        return path

    def policy(self, **fields):
        return self.document("policy.json", {
            "format": "moonbagit-receiving-policy/1", "name": "real receiver", **fields,
        })

    def pending(self, size="3"):
        (self.bag / "data" / "file.bin").unlink()
        (self.bag / "fetch.txt").write_text(
            f"https://example.invalid/object {size} data/file.bin\n", encoding="utf-8")

    def rehash_tags(self, root):
        # Independent hashlib hashes, not a MoonBagIt manifest writer round trip.
        for name in ("tagmanifest-sha256.txt", "tagmanifest-sha512.txt"):
            algorithm = name.split("-")[1].split(".")[0]
            rows = []
            for path in sorted(root.rglob("*")):
                relative = path.relative_to(root).as_posix()
                if not path.is_file() or relative.startswith("data/") or relative.startswith("tagmanifest-"):
                    continue
                rows.append(f"{hashlib.new(algorithm, path.read_bytes()).hexdigest()}  {relative}\n")
            (root / name).write_text("".join(rows), encoding="utf-8", newline="\n")

    def test_audit_matches_independent_hashes(self):
        report = moon("audit", self.bag)
        self.assertTrue(report["report"]["valid"])
        payload = next(f for f in report["files"] if f["payload"])
        self.assertTrue(payload["integrity_verified"])
        for check in payload["checksums"]:
            self.assertEqual(check["expected"], hashlib.new(check["algorithm"], b"abc").hexdigest())

    def test_snapshot_saved_json_and_copy_comparison(self):
        captured = moon("snapshot", self.bag, "--label", "outgoing")
        self.assertEqual(captured["format"], "moonbagit-snapshot/1")
        self.assertTrue(all(isinstance(f["size"], str) for f in captured["files"]))
        copy = self.root / "copy"
        shutil.copytree(self.bag, copy)
        after = moon("snapshot", copy, "--label", "incoming")
        delta = moon("compare", self.document("before.json", captured), self.document("after.json", after))
        self.assertTrue(delta["byte_identical"])
        self.assertTrue(moon("verify-delivery", self.bag, copy)["accepted"])

    def test_revalidation_checks_saved_evidence_against_current_raw_bytes(self):
        expected = self.document("snapshot.json", moon("snapshot", self.bag))
        self.assertTrue(moon("verify-snapshot", self.bag, expected)["preserved"])
        (self.bag / "data" / "file.bin").write_bytes(b"xyz")
        result = moon("verify-snapshot", self.bag, expected, code=1)
        self.assertFalse(result["preserved"])
        self.assertTrue(any(d["code"] == "snapshot_digest_changed"
                            for d in result["inventory"]["diagnostics"]))

    def test_corrupt_same_size_payload_rejected_in_audit_and_snapshot(self):
        (self.bag / "data" / "file.bin").write_bytes(b"xyz")
        audit = moon("audit", self.bag, code=1)
        self.assertEqual(audit["summary"]["mismatched_checksums"], 2)
        self.assertIn("cannot snapshot", moon("snapshot", self.bag, code=2)["error"])

    def test_audit_locates_multiple_manifest_rows(self):
        (self.bag / "manifest-sha256.txt").write_text("broken\nnot-hex data/file.bin\n", encoding="utf-8")
        report = moon("audit", self.bag, code=1)
        self.assertEqual([d["line"] for d in report["located_diagnostics"]], [1, 2])

    def test_policy_accept_and_resource_rejection_preserve_rfc_result(self):
        self.assertTrue(moon("accept", self.bag, self.policy())["accepted"])
        report = moon("accept", self.bag, self.policy(max_payload_bytes="2"), code=1)
        self.assertFalse(report["accepted"])
        self.assertTrue(report["bag"]["valid"])
        self.assertTrue(moon("validate", self.bag)["valid"])

    def test_policy_typo_numeric_count_and_contradiction_rejected(self):
        for fields in ({"max_payload_bytez": "2"}, {"max_payload_bytes": 2},
                       {"payload_algorithms": ["md5"]}):
            self.assertIn("error", moon("accept", self.bag, self.policy(**fields), code=2))

    def test_policy_requires_actual_tag_protection(self):
        for tag in self.bag.glob("tagmanifest-*.txt"):
            tag.unlink()
        self.assertTrue(moon("validate", self.bag)["valid"])
        report = moon("accept", self.bag, self.policy(), code=1)
        self.assertTrue(any(d["code"] == "policy_tag_protection" for d in report["diagnostics"]))

    def test_overlap_budgets_do_not_hide_narrower_quota(self):
        report = moon("accept", self.bag, self.policy(path_budgets=[
            {"pattern": "data/*", "max_bytes": "3"},
            {"pattern": "data/file.*", "max_bytes": "2"},
        ]), code=1)
        self.assertEqual([d["path"] for d in report["diagnostics"]], ["data/file.*"])

    def test_valid_modified_metadata_is_not_exact_delivery(self):
        before = moon("snapshot", self.bag)
        received = self.root / "received"
        shutil.copytree(self.bag, received)
        with (received / "bag-info.txt").open("a", encoding="utf-8") as output:
            output.write("Contact-Name: New receiver\n")
        self.rehash_tags(received)
        self.assertTrue(moon("validate", received)["valid"])
        delivery = moon("verify-delivery", self.bag, received, code=1)
        self.assertFalse(delivery["accepted"])
        after = moon("snapshot", received)
        diff = moon("compare", self.document("before.json", before), self.document("after.json", after), code=1)
        self.assertTrue(diff["payload_identical"])
        self.assertFalse(diff["byte_identical"])
        self.assertTrue(any(m["label"] == "contact-name" for m in diff["metadata"]))

    def test_snapshot_rejects_tampered_schema_and_duplicate_record(self):
        value = moon("snapshot", self.bag)
        value["files"].append(value["files"][0])
        path = self.document("duplicate.json", value)
        self.assertIn("duplicate", moon("compare", path, path, code=2)["error"])

    def test_fetch_completion_preserves_original_tags(self):
        self.pending()
        received = self.root / "received"
        shutil.copytree(self.bag, received)
        (received / "data" / "file.bin").write_bytes(b"abc")
        delivery = moon("verify-delivery", self.bag, received, "--complete-fetch")
        self.assertTrue(delivery["accepted"])
        self.assertEqual(delivery["completed_files"], 1)
        self.assertFalse(moon("verify-delivery", self.bag, received, code=1)["accepted"])

    def test_known_transfer_budget_and_expected_hashes(self):
        self.pending()
        options = self.document("options.json", {"format": "moonbagit-transfer-options/1"})
        plan = moon("transfer-plan", self.bag, options)
        self.assertEqual(plan["pending_files"], 1)
        self.assertEqual(plan["known_bytes"], "3")
        self.assertEqual(plan["batches"][0]["tasks"][0]["checksums"]["sha256"], hashlib.sha256(b"abc").hexdigest())
        limited = self.document("limited.json", {"format": "moonbagit-transfer-options/1", "max_total_bytes": "2"})
        self.assertIn("budget", moon("transfer-plan", self.bag, limited, code=2)["error"])

    def test_unknown_transfer_reservation_does_not_claim_known_bytes(self):
        self.pending("-")
        empty = self.document("options.json", {"format": "moonbagit-transfer-options/1"})
        self.assertIn("reservation", moon("transfer-plan", self.bag, empty, code=2)["error"])
        options = self.document("options.json", {
            "format": "moonbagit-transfer-options/1", "unknown_size_reservation": "100",
        })
        plan = moon("transfer-plan", self.bag, options)
        self.assertEqual(plan["known_bytes"], "0")
        self.assertEqual(plan["reserved_bytes"], "100")
        self.assertEqual(plan["unknown_sizes"], 1)

    def test_collection_reports_each_bag_and_rejects_duplicate_identity(self):
        received = self.root / "incomplete"
        shutil.copytree(self.bag, received)
        (received / "data" / "file.bin").unlink()
        bags = self.document("bags.json", [
            {"identifier": "z-good", "path": str(self.bag)},
            {"identifier": "a-bad", "path": str(received)},
        ])
        report = moon("collection", bags, self.policy(), code=1)
        self.assertEqual(report["accepted_bags"], 1)
        self.assertEqual(report["rejected_bags"], 1)
        self.assertEqual(report["items"][0]["identifier"], "a-bad")
        duplicates = self.document("duplicates.json", [
            {"identifier": "same", "path": str(self.bag)},
            {"identifier": "same", "path": str(self.bag)},
        ])
        self.assertIn("unique", moon("collection", duplicates, self.policy(), code=2)["error"])

    def test_empty_directories_are_part_of_preservation_record(self):
        before = moon("snapshot", self.bag)
        (self.bag / "data" / "empty").mkdir()
        after = moon("snapshot", self.bag)
        diff = moon("compare", self.document("before.json", before), self.document("after.json", after), code=1)
        self.assertEqual(diff["directories_added"], ["data/empty"])
        self.assertFalse(diff["payload_identical"])


if __name__ == "__main__":
    unittest.main()
