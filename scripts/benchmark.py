"""Reproducible real-filesystem create/validate benchmark; no synthetic digests."""
import argparse
import json
import platform
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--files", type=int, default=10000)
parser.add_argument("--bytes", type=int, default=1024)
args = parser.parse_args()
if not 1 <= args.files <= 50000 or not 0 <= args.bytes <= 1048576:
    parser.error("files must be 1..50000 and bytes must be 0..1048576")

def run(*commands):
    start = time.perf_counter()
    result = subprocess.run(["node", str(ROOT / "bin/moonbagit.mjs"), *map(str, commands)], capture_output=True, text=True, encoding="utf-8", timeout=600, check=True)
    return time.perf_counter() - start, json.loads(result.stdout)

with tempfile.TemporaryDirectory(prefix="moonbagit-benchmark-") as temp:
    base = Path(temp)
    source = base / "source"
    source.mkdir()
    data = bytes((i % 251 for i in range(args.bytes)))
    for i in range(args.files):
        folder = source / str(i // 100)
        folder.mkdir(exist_ok=True)
        (folder / f"file-{i:06d}.bin").write_bytes(data)
    create_seconds, result = run("create", source, base / "bag", "--both")
    validate_seconds, report = run("validate", base / "bag")
    assert result["report"]["valid"] and report["valid"]
    assert report["payload_files"] == args.files
    assert report["payload_bytes"] == str(args.files * args.bytes)
    assert report["verified_checksums"] == 2 * args.files + 8
    print(json.dumps({"platform": platform.platform(), "python": platform.python_version(), "node": subprocess.check_output(["node", "--version"], text=True).strip(), "files": args.files, "payload_bytes": report["payload_bytes"], "verified_checksums": report["verified_checksums"], "create_seconds": round(create_seconds, 3), "validate_seconds": round(validate_seconds, 3), "valid": report["valid"]}, indent=2))
