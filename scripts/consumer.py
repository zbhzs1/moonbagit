"""Install the published library in a fresh project; never import this checkout."""
from pathlib import Path
import subprocess
import sys
import tempfile

FILES = {
    "moon.mod": '''name = "acceptance/moonbagit-consumer"
version = "0.1.0"
preferred_target = "wasm-gc"
import {
  "zbhzs1/moonbagit@0.2.1",
}
''',
    "moon.pkg": '''import {
  "zbhzs1/moonbagit" @bag,
}
pkgtype(kind: "executable")
''',
    "main.mbt": '''fn main {
  try {
    let declaration = @bag.parse_declaration("BagIt-Version: 1.0\\nTag-File-Character-Encoding: UTF-8\\n")
    let tags = @bag.create_tags([])
    let profile = @bag.parse_profile({
      "BagIt-Profile-Info": {
        "Source-Organization": "Independent consumer",
        "External-Description": "Empty dataset receiving rules",
        "Version": "1.0",
        "BagIt-Profile-Identifier": "urn:example:consumer",
        "BagIt-Profile-Version": "1.4.0",
      },
      "Serialization": "forbidden",
      "Accept-BagIt-Version": ["1.0"],
      "Data-Empty": true,
    })
    tags["bag-info.txt"] = "Payload-Oxum: 0.0\\nBagIt-Profile-Identifier: urn:example:consumer\\n"
    let records = tags.to_array().map(entry => {
      let (path, text) = entry
      @bag.FileRecord::{ path, size: text.length().to_int64(), digests: Map([]), }
    })
    let view : @bag.BagView = { files: records, directories: ["data"], texts: tags, }
    let report = @bag.validate_profile(view, profile)
    guard declaration.version == "1.0" && report.conforms else { abort("consumer validation failed") }
    let plan = @bag.plan_upgrade(view, [@bag.Sha256])
    guard plan.payload_manifests.contains("manifest-sha256.txt") else { abort("consumer upgrade failed") }
    assert_true(@bag.lint_portability(view).is_empty())
    let fetch = @bag.render_fetch([
      @bag.FetchEntry::{ url: "https://example.org/data%20file", size: Some(3L), path: "data/a%.txt", },
    ])
    let entries = @bag.parse_fetch(fetch)
    guard entries.length() == 1 && entries[0].path == "data/a%.txt" else { abort("consumer fetch round trip failed") }
    let invalid_view : @bag.BagView = { files: records, directories: ["data", "bagit.txt"], texts: tags, }
    assert_true(@bag.validate(invalid_view).has_code("file_directory_collision"))
    let orphan_texts = tags.copy()
    orphan_texts["missing.txt"] = "phantom metadata"
    let orphan_view : @bag.BagView = { files: records, directories: ["data"], texts: orphan_texts, }
    assert_true(@bag.validate(orphan_view).has_code("orphan_text"))
    let rejected = try {
      ignore(@bag.render_manifest([
        @bag.Entry::{ path: " notes.bin", checksum: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", },
      ]))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    println("Mooncakes consumer 0.2.1: declaration, creation, receiving profile, upgrade, portability, fetch and inventory checks passed")
  } catch {
    error => abort(error.to_string())
  }
}
''',
}

with tempfile.TemporaryDirectory(prefix="moonbagit-consumer-") as temporary:
    root = Path(temporary)
    for name, text in FILES.items():
        (root / name).write_text(text, encoding="utf-8", newline="\n")
    for args in (["update"], ["check", "--target", "js", "--deny-warn"],
                 ["run", ".", "--target", "wasm-gc"], ["run", ".", "--target", "js"]):
        result = subprocess.run(["moon", *args], cwd=root, text=True, encoding="utf-8",
                                capture_output=True, timeout=180)
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        result.check_returncode()
        if args[0] == "run":
            assert "Mooncakes consumer 0.2.1" in result.stdout, result.stdout
    package = root / ".mooncakes" / "zbhzs1" / "moonbagit"
    assert package.is_dir() and not package.is_symlink(), "registry package was not installed"
    print("PASS: fresh published-package consumer on JS and WASM-GC")
