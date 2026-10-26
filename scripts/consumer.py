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
  "zbhzs1/moonbagit@0.4.0",
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
      // Fixed raw-byte SHA-512 values for these three known ASCII fixture tags.
      let digest = if path == "bagit.txt" {
        "1d73ae108d4109b61f56698a5e19ee1f8947bdf8940bbce6adbe5e0940c2363caace6a547b4f1b3ec6a4fd2b7fa845e9cb9d28823bc72c59971718bb26f2fbd8"
      } else if path == "bag-info.txt" {
        "c08b51541afbdb96138230017fd35ffa3449f181c4187ef8d4873ad4ccf3905f7214016ac0e18b37e737d08d6b66882c315abe7bef117b36f1649395fe150cd4"
      } else {
        "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
      }
      @bag.FileRecord::{ path, size: text.length().to_int64(), digests: {"sha512": digest}, }
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
    @bag.check_fetch_url("https://[2001:db8::1]:443/a?x=%25")
    let rejected_uri = try {
      @bag.check_fetch_url("https://[broken/a")
      false
    } catch { _ => true }
    assert_true(rejected_uri)
    assert_eq(@bag.algorithm("md5"), @bag.Md5)
    assert_eq(@bag.algorithm("sha1"), @bag.Sha1)
    let encoded = @bag.parse_declaration("BagIt-Version: 1.0\\nTag-File-Character-Encoding: ISO-8859-1\\n")
    assert_eq(encoded.encoding, "ISO-8859-1")
    let encoded_tags = @bag.create_tags([], encoding="UTF-16")
    assert_true(encoded_tags["bagit.txt"].contains("UTF-16"))
    let empty_fetch_tags = tags.copy()
    empty_fetch_tags["fetch.txt"] = ""
    let fetch_records = records.copy()
    fetch_records.push(@bag.FileRecord::{path: "fetch.txt", size: 0L, digests: Map([])})
    let fetch_view : @bag.BagView = { files: fetch_records, directories: ["data"], texts: empty_fetch_tags }
    assert_true(@bag.plan_fetch(fetch_view).is_empty())
    let reader = @bag.manifest_reader("manifest-sha512.txt", max_entries=10)
    reader.feed("")
    assert_true(reader.finish().entries.is_empty())
    assert_true(@bag.inspect_manifest("manifest-sha512.txt", "").diagnostics.is_empty())
    let audit = @bag.audit_bag(view)
    assert_true(audit.report.valid)
    assert_true(@bag.group_diagnostics(audit.report.diagnostics).is_empty())
    let captured = @bag.capture_snapshot(view, label="registry-consumer")
    let loaded = @bag.parse_snapshot(@bag.snapshot_document(captured))
    assert_true(@bag.compare_snapshots(captured, loaded).byte_identical)
    assert_true(@bag.verify_snapshot_inventory(loaded, records, ["data"]).matches)
    assert_true(@bag.revalidate_snapshot(loaded, view).preserved)
    let policy : @bag.ReceivingPolicy = {
      ..@bag.receiving_policy("consumer"), require_tag_protection: false,
    }
    let policy = @bag.parse_receiving_policy(@bag.receiving_policy_document(policy))
    assert_true(@bag.evaluate_receiving_policy(view, policy).accepted)
    assert_true(@bag.verify_delivery(view, view, @bag.ExactCopy).accepted)
    let options = @bag.parse_transfer_options({"format": "moonbagit-transfer-options/1"})
    assert_eq(@bag.plan_transfer(fetch_view, options).pending_files, 0)
    assert_true(@bag.evaluate_collection([{identifier: "one", view}], policy).accepted)
    println("Mooncakes consumer 0.4.0: published format, preservation, incremental input, policy, transfer and delivery APIs passed")
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
            assert "Mooncakes consumer 0.4.0" in result.stdout, result.stdout
    package = root / ".mooncakes" / "zbhzs1" / "moonbagit"
    assert package.is_dir() and not package.is_symlink(), "registry package was not installed"
    print("PASS: fresh published-package consumer on JS and WASM-GC")
