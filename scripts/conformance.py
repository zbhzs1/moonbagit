"""Run the five externally maintained BagIt 1.0 fixtures without rewriting bytes."""
import argparse
import json
from pathlib import Path
import subprocess

PIN = "9ab48705c06664f9f419ca740c728c9f89a61e7c"
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("suite", type=Path)
args = parser.parse_args()
suite = args.suite.resolve()
identity = subprocess.run(["git", "-C", str(suite), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
if identity != PIN:
    raise SystemExit(f"expected conformance suite {PIN}, got {identity}")
cases = [("valid/basicBag", True),
         ("invalid/bagit-with-invalid-whitespace", False),
         ("invalid/notAllManifestsListAllFiles", False),
         ("invalid/same-filename-listed-twice-with-different-hashes", False),
         ("invalid/same-filename-listed-twice-with-the-same-hash", False)]
for name, expected in cases:
    result = subprocess.run(["node", str(ROOT / "bin/moonbagit.mjs"), "validate", str(suite / "v1.0" / name)], capture_output=True, text=True, encoding="utf-8", timeout=60)
    report = json.loads(result.stdout)
    assert "valid" in report, (name, report, result.stderr)
    assert report["valid"] == expected, (name, report)
    assert result.returncode == (0 if expected else 1), (name, result.returncode)
    print(json.dumps({"fixture": name, "expected_valid": expected, "valid": report["valid"], "diagnostic_codes": [d["code"] for d in report["diagnostics"]]}))
print(f"PASS: {len(cases)} independently maintained BagIt 1.0 fixtures at {PIN}")
