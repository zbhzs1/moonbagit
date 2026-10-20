"""Retain reproducible, direction-specific independent BagIt validation evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib
import json
import logging
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def moon(*args, code=0):
    command = ["node", str(ROOT / "bin" / "moonbagit.mjs"), *map(str, args)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            encoding="utf-8", timeout=60)
    require(result.returncode == code,
            f"{command}: expected {code}, got {result.returncode}: {result.stdout} {result.stderr}")
    return {"command": command, "exit_code": result.returncode, "result": json.loads(result.stdout)}


def snapshot(directory):
    return {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob("*") if p.is_file()}


def python_validation(bagit, directory):
    try:
        valid = bagit.Bag(str(directory)).validate()
        return {"call": "bagit.Bag(path).validate()", "valid": bool(valid), "error": None}
    except bagit.BagValidationError as error:
        return {"call": "bagit.Bag(path).validate()", "valid": False, "error": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory; never overwrite")
    parser.add_argument("--bagit-path", type=Path)
    parser.add_argument("--source-id", required=True, help="Dependency release or pinned revision, recorded verbatim")
    parser.add_argument("--require-native-1", action="store_true")
    args = parser.parse_args()
    if args.bagit_path:
        sys.path.insert(0, str(args.bagit_path.resolve()))
    bagit = importlib.import_module("bagit")
    logging.getLogger("bagit").setLevel(logging.CRITICAL)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {
        "schema": 1, "status": "running", "created_at": datetime.now(timezone.utc).isoformat(),
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_worktree_status": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True),
        "python": platform.python_version(), "platform": platform.platform(),
        "dependency": {"source_id": args.source_id, "module": bagit.__file__,
                       "module_sha256": hashlib.sha256(Path(bagit.__file__).read_bytes()).hexdigest(),
                       "reported_version": getattr(bagit, "VERSION", None)},
        "require_native_1": args.require_native_1, "positive_cases": [], "negative_cases": [],
    }
    try:
        source = output / "input"
        (source / "nested").mkdir(parents=True)
        (source / "nested" / "a b.bin").write_bytes(b"abc\r\n\x00\xff")
        (source / "empty.bin").write_bytes(b"")
        (source / "\u4e2d\u6587.txt").write_bytes(b"unicode filename")
        before = snapshot(source)
        for direction in ("moon-to-python", "python-to-moon"):
            for algorithms in (("sha256",), ("sha512",), ("sha256", "sha512")):
                name = direction + "-" + "-".join(algorithms)
                directory = output / name
                adaptation = None
                if direction == "moon-to-python":
                    option = "--both" if len(algorithms) == 2 else "--" + algorithms[0]
                    creation = moon("create", source, directory, option)
                    producer_version = [1, 0]
                else:
                    shutil.copytree(source, directory)
                    independent = bagit.make_bag(str(directory), checksums=list(algorithms))
                    producer_version = list(independent.version_info)
                    if producer_version == [0, 97] and not args.require_native_1:
                        declaration = directory / "bagit.txt"
                        declaration.write_bytes(b"BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n")
                        independent = bagit.Bag(str(directory))
                        independent.save()
                        adaptation = "0.97 declaration replaced by 1.0; bagit-python save() regenerated tag manifests"
                    else:
                        require(producer_version == [1, 0], "Independent producer did not create native BagIt 1.0")
                    creation = {"call": "bagit.make_bag(path, checksums=algorithms)", "adaptation": adaptation}
                expected_manifests = {f"manifest-{algorithm}.txt" for algorithm in algorithms}
                require({p.name for p in directory.glob("manifest-*.txt")} == expected_manifests,
                        f"Producer emitted unexpected algorithms for {name}")
                require(all((directory / f"tagmanifest-{algorithm}.txt").is_file() for algorithm in algorithms),
                        f"Missing tag manifests for {name}")
                bag_before = snapshot(directory)
                received = moon("validate", directory)
                independent_result = python_validation(bagit, directory)
                require(received["result"]["complete"] and received["result"]["valid"], f"MoonBagIt rejected {name}")
                require(independent_result["valid"], f"bagit-python rejected {name}")
                require(snapshot(directory / "data") == before, f"Payload bytes changed in {name}")
                require(snapshot(directory) == bag_before, f"Validation mutated {name}")
                report["positive_cases"].append({
                    "name": name, "direction": direction, "algorithms": algorithms,
                    "producer_version": producer_version, "adaptation": adaptation,
                    "creation": creation, "moon": received, "bagit_python": independent_result,
                    "payload_sha256": before, "bag_sha256": bag_before, "validation_read_only": True,
                })
                for mutation in ("same-size-corruption", "missing-payload", "tag-corruption"):
                    damaged = output / (name + "-" + mutation)
                    shutil.copytree(directory, damaged)
                    if mutation == "same-size-corruption":
                        (damaged / "data" / "nested" / "a b.bin").write_bytes(b"XYZ\r\n\x00\xff")
                    elif mutation == "missing-payload":
                        (damaged / "data" / "empty.bin").unlink()
                    else:
                        with (damaged / "bag-info.txt").open("ab") as stream:
                            stream.write(b"Contact-Name: altered\n")
                    received = moon("validate", damaged, code=1)
                    independent_result = python_validation(bagit, damaged)
                    require(not received["result"]["valid"] and not independent_result["valid"],
                            f"Validators disagreed or accepted damaged {damaged.name}")
                    require(received["result"]["complete"] == (mutation != "missing-payload"),
                            f"Unexpected completeness result for {damaged.name}")
                    report["negative_cases"].append({"name": damaged.name, "mutation": mutation,
                                                     "moon": received, "bagit_python": independent_result})
        require(snapshot(source) == before, "Original input changed")
        require(len(report["positive_cases"]) == 6 and len(report["negative_cases"]) == 18,
                "Incomplete evidence matrix")
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: 6 bidirectional positive cases and 18 independent negative controls; {output / 'report.json'}")


if __name__ == "__main__":
    main()
