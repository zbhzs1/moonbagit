///|
fn incomplete_fixture(size~ : Int64? = Some(3L)) -> BagView raise {
  let full = fixture()
  let texts = full.texts.copy()
  // Remove tag manifests to keep the original standard tags unchanged in both views.
  for name in ["tagmanifest-sha256.txt", "tagmanifest-sha512.txt"] {
    texts.remove(name)
  }
  let fetch = render_fetch([
    { url: "https://example.org/bytes", size, path: "data/example.txt", },
  ])
  texts["fetch.txt"] = fetch
  let files = full.files.filter(f => {
    !f.path.has_prefix("data/") && !manifest_name(f.path, true)
  })
  files.push({
    path: "fetch.txt",
    size: fetch.length().to_int64(),
    digests: { "sha256": repeated("e", 64), "sha512": repeated("f", 128) },
  })
  { files, directories: ["data"], texts, }
}

///|
fn received_fixture(source : BagView) -> BagView raise {
  let files = source.files.copy()
  files.push(fixture().files.filter(f => f.path == "data/example.txt")[0])
  { files, directories: source.directories.copy(), texts: source.texts.copy(), }
}

///|
test "incremental manifest matches whole parser at every chunk boundary" {
  let text = repeated("a", 64) +
    "  data/one%25.txt\r\n" +
    repeated("b", 64) +
    "\tdata/two.txt\r"
  let expected = parse_manifest("manifest-sha256.txt", text)
  for split in 0..<=text.length() {
    let reader = manifest_reader("manifest-sha256.txt")
    reader.feed(text[:split].to_owned())
    reader.feed("")
    reader.feed(text[split:].to_owned())
    assert_true(reader.finish() == expected)
  }
}

///|
test "incremental manifest one code unit chunks and unfinished final row" {
  let text = repeated("A", 64) + " data/a.txt"
  let reader = manifest_reader("manifest-sha256.txt")
  for i in 0..<text.length() {
    reader.feed(text[i:i + 1].to_owned())
  }
  assert_eq(reader.finish().entries[0].checksum, repeated("a", 64))
  rejects(() => reader.feed(""))
  rejects(() => ignore(reader.finish()))
}

///|
test "incremental reader retains failure and detects cross chunk duplicates" {
  let row = repeated("a", 64) + " data/a\n"
  let reader = manifest_reader("manifest-sha256.txt")
  reader.feed(row)
  rejects(() => reader.feed(row))
  assert_true(reader.failure.unwrap().contains(":2:"))
  rejects(() => reader.feed(repeated("b", 64) + " data/b\n"))
  rejects(() => ignore(reader.finish()))
}

///|
test "incremental limits are exact and reject before unbounded accumulation" {
  let row = repeated("a", 64) + " data/a"
  let reader = manifest_reader(
    "manifest-sha256.txt",
    max_line_units=row.length(),
    max_entries=1,
  )
  reader.feed(row + "\n")
  assert_eq(reader.finish().entries.length(), 1)
  let too_long = manifest_reader("manifest-sha256.txt", max_line_units=10)
  rejects(() => too_long.feed(repeated("a", 11)))
  let too_many = manifest_reader("manifest-sha256.txt", max_entries=1)
  too_many.feed(row + "\n")
  rejects(() => too_many.feed(repeated("b", 64) + " data/b\n"))
  rejects(() => ignore(manifest_reader("manifest-sha256.txt", max_entries=0)))
}

///|
test "incremental empty manifest allowed but empty rows and BOM fail" {
  assert_true(
    manifest_reader("manifest-sha256.txt").finish().entries.is_empty(),
  )
  for text in ["\n", "\r\n", "\uFEFF" + repeated("a", 64) + " data/a\n"] {
    let reader = manifest_reader("manifest-sha256.txt")
    rejects(() => {
      reader.feed(text)
      ignore(reader.finish())
    })
  }
}

///|
test "inspection recovers multiple errors without claiming validity" {
  let row = repeated("a", 64) + " data/a"
  let result = inspect_manifest(
    "manifest-sha256.txt",
    row + "\r\nbad\n" + row + "\rno separator",
  )
  assert_eq(result.parsed_entries.length(), 1)
  assert_eq(result.diagnostics.length(), 3)
  assert_eq(result.diagnostics[0].line, 2)
  assert_eq(result.diagnostics[1].code, "manifest_duplicate")
  assert_true(result.diagnostics[1].message.contains("line 1"))
  assert_eq(result.diagnostics[2].line, 4)
  assert_eq(inspect_manifest("x.txt", row).diagnostics[0].line, 0)
}

///|
test "audit explains checksum coverage without crediting malformed manifests" {
  let view = fixture()
  let audit = audit_bag(view)
  assert_true(audit.report.valid)
  let payload = audit.files.filter(f => f.payload)[0]
  assert_true(payload.integrity_verified)
  assert_eq(payload.checksums.length(), 2)
  assert_eq(audit.summary.manifest_count, 4)
  assert_eq(audit.summary.missing_files, 0)
  assert_eq(audit.summary.unprotected_tags, 0)
  view.texts["manifest-sha256.txt"] = "broken\n"
  let bad = audit_bag(view)
  assert_true(!bad.report.valid)
  assert_eq(bad.located_diagnostics[0].line, 1)
  assert_eq(bad.files.filter(f => f.payload)[0].checksums.length(), 1)
}

///|
test "audit separates missing mismatch and unavailable digest evidence" {
  let missing = audit_bag(incomplete_fixture())
  assert_eq(missing.summary.missing_files, 1)
  assert_eq(missing.summary.pending_fetches, 1)
  let view = fixture()
  let files = view.files.map(f => {
    if f.path.has_prefix("data/") {
      FileRecord::{
        path: f.path,
        size: f.size,
        digests: { "sha256": repeated("f", 64) },
      }
    } else {
      f
    }
  })
  let changed = audit_bag({
    files,
    directories: view.directories,
    texts: view.texts,
  })
  assert_eq(changed.summary.mismatched_checksums, 1)
  assert_eq(changed.summary.unavailable_checksums, 1)
}

///|
test "diagnostic grouping is sorted stable and deduplicates paths" {
  let items : Array[Diagnostic] = []
  issue(items, "z", "a", "first")
  issue(items, "a", "b", "second", warning=true)
  issue(items, "z", "a", "third")
  let groups = group_diagnostics(items)
  assert_eq(groups[0].code, "a")
  assert_eq(groups[0].warnings, 1)
  assert_eq(groups[1].errors, 2)
  assert_eq(groups[1].paths.length(), 1)
}

///|
test "snapshot wire round trip is deterministic and leaves input untouched" {
  let view = fixture()
  let original_first = view.files[0].path
  let captured = capture_snapshot(view, label="handoff")
  let document = snapshot_document(captured)
  let decoded = parse_snapshot(@json.parse(document.stringify()))
  assert_eq(decoded.label, "handoff")
  assert_true(snapshot_document(decoded) == document)
  assert_eq(view.files[0].path, original_first)
  assert_true(compare_snapshots(captured, decoded).byte_identical)
}

///|
test "snapshot rejects incomplete bags and raw digests missing from any file" {
  rejects(() => ignore(capture_snapshot(incomplete_fixture())))
  let full = fixture()
  let files = full.files.map(f => {
    if f.path == "tagmanifest-sha256.txt" {
      FileRecord::{ path: f.path, size: f.size, digests: Map([]), }
    } else {
      f
    }
  })
  let view : BagView = {
    files,
    directories: full.directories,
    texts: full.texts,
  }
  assert_true(validate(view).valid)
  rejects(() => ignore(capture_snapshot(view)))
}

///|
test "snapshot schema rejects extra keys unknown versions and lossy sizes" {
  let original = snapshot_document(capture_snapshot(fixture()))
  guard original is Object(fields) else { abort("object") }
  let extra = fields.copy()
  extra["surprise"] = true
  rejects(() => ignore(parse_snapshot(Json(extra))))
  let version = fields.copy()
  version["format"] = "moonbagit-snapshot/2"
  rejects(() => ignore(parse_snapshot(Json(version))))
  for value in [Json(3), Json("03"), Json("-1"), Json("9223372036854775808")] {
    let malformed = fields.copy()
    malformed["files"] = [{ "path": "data/x", "size": value, "digests": {} }]
    rejects(() => ignore(parse_snapshot(Json(malformed))))
  }
}

///|
test "snapshot maintains exact Int64 values above JSON safe integer range" {
  assert_eq(document_count(Json("9007199254740993"), "size"), 9007199254740993L)
  assert_eq(
    document_count(Json("9223372036854775807"), "size"),
    9223372036854775807L,
  )
  rejects(() => ignore(checked_add(9223372036854775807L, 1L, "test")))
}

///|
test "snapshot comparison catches same size changed payload and tag only changes" {
  let before = capture_snapshot(fixture())
  let changed = before.files.map(f => {
    if f.path == "data/example.txt" {
      FileRecord::{
        path: f.path,
        size: f.size,
        digests: { "sha256": repeated("f", 64) },
      }
    } else {
      f
    }
  })
  let after : BagSnapshot = { ..before, files: changed, }
  let diff = compare_snapshots(before, after)
  assert_true(!diff.byte_identical && !diff.payload_identical)
  assert_eq(diff.files[0].kind, "modified")
  let tag_changed = before.files.map(f => {
    if f.path == "bagit.txt" {
      FileRecord::{ path: f.path, size: f.size + 1L, digests: f.digests, }
    } else {
      f
    }
  })
  let tags_only = compare_snapshots(before, { ..before, files: tag_changed, })
  assert_true(!tags_only.byte_identical && tags_only.payload_identical)
}

///|
test "no common digest is unverifiable not unchanged" {
  let before = capture_snapshot(fixture())
  let left = before.files.map(f => FileRecord::{
    ..f,
    digests: { "sha256": f.digests["sha256"] },
  })
  let right = before.files.map(f => FileRecord::{
    ..f,
    digests: { "sha512": f.digests["sha512"] },
  })
  let diff = compare_snapshots({ ..before, files: left, }, {
    ..before,
    files: right,
  })
  assert_true(!diff.comparable && !diff.byte_identical)
  assert_true(diff.files.all(f => f.kind == "unverifiable"))
}

///|
test "digest set changes do not imply byte changes when common checks agree" {
  let before = capture_snapshot(fixture())
  let reduced = before.files.map(f => FileRecord::{
    ..f,
    digests: { "sha256": f.digests["sha256"] },
  })
  let diff = compare_snapshots(before, { ..before, files: reduced, })
  assert_true(diff.byte_identical && diff.payload_identical)
  assert_true(
    diff.files.all(f => {
      f.kind == "unchanged" && f.removed_algorithms == ["sha512"]
    }),
  )
}

///|
test "snapshot comparison retains empty directory and repeated metadata changes" {
  let before = capture_snapshot(fixture())
  let dirs = before.directories.copy()
  dirs.push("data/empty")
  let after : BagSnapshot = {
    ..before,
    directories: dirs,
    metadata: [
      { label: "Contact-Name", value: "A", },
      { label: "contact-name", value: "B", },
    ],
  }
  let diff = compare_snapshots(before, after)
  assert_true(!diff.byte_identical && !diff.payload_identical)
  assert_eq(diff.directories_added, ["data/empty"])
  assert_eq(diff.metadata[0].after_values, ["A", "B"])
}

///|
test "snapshot caller constructed duplicate or ancestor paths are rejected" {
  let before = capture_snapshot(fixture())
  let duplicate = before.files.copy()
  duplicate.push(before.files[0])
  rejects(() => ignore(snapshot_document({ ..before, files: duplicate, })))
  rejects(() => {
    ignore(snapshot_document({ ..before, directories: ["data", "data"], }))
  })
  let nested = before.files.copy()
  nested.push({
    path: "data/missing/a",
    size: 0L,
    digests: { "sha256": repeated("a", 64) },
  })
  rejects(() => ignore(snapshot_document({ ..before, files: nested, })))
}

///|
test "receiving policy defaults round trip and do not alter RFC validity" {
  let policy = receiving_policy("archive")
  let parsed = parse_receiving_policy(receiving_policy_document(policy))
  assert_eq(parsed.name, "archive")
  assert_true(evaluate_receiving_policy(fixture(), parsed).accepted)
  let strict : ReceivingPolicy = { ..policy, max_payload_bytes: Some(2L), }
  let rejected = evaluate_receiving_policy(fixture(), strict)
  assert_true(!rejected.accepted && rejected.bag.valid)
  assert_eq(rejected.diagnostics[0].code, "policy_payload_bytes")
}

///|
test "policy schema rejects unknown keys contradictions and negative limits" {
  rejects(() => {
    ignore(
      parse_receiving_policy({
        "format": "moonbagit-receiving-policy/1",
        "name": "bad",
        "typo": true,
      }),
    )
  })
  rejects(() => {
    ignore(
      evaluate_receiving_policy(fixture(), {
        ..receiving_policy("bad"),
        payload_algorithms: ["md5"],
      }),
    )
  })
  rejects(() => {
    ignore(
      receiving_policy_document({
        ..receiving_policy("bad"),
        max_file_bytes: Some(-1L),
      }),
    )
  })
}

///|
test "required manifest coverage is not satisfied by incidental host digests" {
  let view = fixture()
  let texts = view.texts.copy()
  texts.remove("manifest-sha512.txt")
  texts.remove("tagmanifest-sha256.txt")
  texts.remove("tagmanifest-sha512.txt")
  let files = view.files.filter(f => {
    f.path != "manifest-sha512.txt" && !manifest_name(f.path, true)
  })
  let source : BagView = { files, directories: view.directories, texts, }
  let policy : ReceivingPolicy = {
    ..receiving_policy("strong"),
    payload_algorithms: ["sha512"],
    require_tag_protection: false,
  }
  let result = evaluate_receiving_policy(source, policy)
  assert_true(result.bag.valid && !result.accepted)
  assert_true(result.diagnostics.any(d => d.code == "policy_required_digest"))
}

///|
test "overlapping path budgets are all enforced and zero is meaningful" {
  let policy : ReceivingPolicy = {
    ..receiving_policy("quotas"),
    path_budgets: [
      { pattern: "data/*", max_files: Some(1L), max_bytes: Some(3L), },
      { pattern: "data/example.*", max_files: None, max_bytes: Some(0L), },
    ],
  }
  let result = evaluate_receiving_policy(fixture(), policy)
  assert_true(!result.accepted)
  assert_eq(
    result.diagnostics.filter(d => d.code == "policy_path_bytes").length(),
    1,
  )
  assert_eq(
    parse_receiving_policy(receiving_policy_document(policy)).path_budgets.length(),
    2,
  )
}

///|
test "policy limits tag bytes path depth and manifest entries independently" {
  let policy : ReceivingPolicy = {
    ..receiving_policy("strict"),
    max_tag_bytes: Some(0L),
    max_path_depth: Some(1L),
    max_manifest_entries: Some(0L),
  }
  let report = evaluate_receiving_policy(fixture(), policy)
  for
    code in ["policy_tag_bytes", "policy_path_depth", "policy_manifest_entries"] {
    assert_true(report.diagnostics.any(d => d.code == code))
  }
}

///|
test "exact delivery proves original tags and payload or rejects changes" {
  let view = fixture()
  assert_true(verify_delivery(view, view, ExactCopy).accepted)
  let files = view.files.map(f => {
    if f.path == "tagmanifest-sha256.txt" {
      FileRecord::{
        ..f,
        digests: { "sha256": repeated("f", 64), "sha512": repeated("e", 128) },
      }
    } else {
      f
    }
  })
  let after : BagView = {
    files,
    directories: view.directories,
    texts: view.texts,
  }
  assert_true(validate(after).valid)
  let report = verify_delivery(view, after, ExactCopy)
  assert_true(!report.accepted)
  assert_true(report.diagnostics.any(d => d.code == "delivery_changed"))
}

///|
test "delivery requires shared strong evidence even for same size and same text" {
  let view = fixture()
  let files = view.files.map(f => {
    if f.path == "tagmanifest-sha256.txt" {
      FileRecord::{ ..f, digests: Map([]), }
    } else {
      f
    }
  })
  let after : BagView = {
    files,
    directories: view.directories,
    texts: view.texts,
  }
  assert_true(validate(after).valid)
  assert_true(
    verify_delivery(view, after, ExactCopy).diagnostics.any(d => {
      d.code == "delivery_unverifiable"
    }),
  )
}

///|
test "fetch delivery permits only missing declared payload and needed parents" {
  let source = incomplete_fixture()
  let target = received_fixture(source)
  let report = verify_delivery(source, target, CompleteFetch)
  assert_true(report.accepted)
  assert_eq(report.completed_files, 1)
  assert_eq(report.preserved_files, source.files.length())
  assert_true(!verify_delivery(source, target, ExactCopy).accepted)
  let dirs = target.directories.copy()
  dirs.push("data/unexpected-empty")
  let extra : BagView = { ..target, directories: dirs, }
  assert_true(
    verify_delivery(source, extra, CompleteFetch).diagnostics.any(d => {
      d.code == "delivery_directory_unexpected"
    }),
  )
}

///|
test "fetch delivery cannot silently lose existing empty directories" {
  let source = incomplete_fixture()
  let dirs = source.directories.copy()
  dirs.push("data/keep")
  let before : BagView = { ..source, directories: dirs, }
  let target = received_fixture(source)
  let report = verify_delivery(before, target, CompleteFetch)
  assert_true(!report.accepted)
  assert_true(
    report.diagnostics.any(d => d.code == "delivery_directory_missing"),
  )
}

///|
test "transfer planning is deterministic budgeted and offline" {
  let plan = plan_transfer(incomplete_fixture(), transfer_options())
  assert_eq(plan.pending_files, 1)
  assert_eq(plan.known_bytes, 3L)
  assert_eq(plan.reserved_bytes, 3L)
  assert_eq(plan.batches[0].tasks[0].checksums.length(), 2)
  assert_true(plan.directories_to_create.is_empty())
  rejects(() => {
    ignore(
      plan_transfer(incomplete_fixture(), {
        ..transfer_options(),
        max_total_bytes: 2L,
      }),
    )
  })
  rejects(() => {
    ignore(
      plan_transfer(incomplete_fixture(), {
        ..transfer_options(),
        allowed_schemes: ["http"],
      }),
    )
  })
}

///|
test "unknown fetch length needs explicit reservation not fake byte certainty" {
  let view = incomplete_fixture(size=None)
  rejects(() => ignore(plan_transfer(view, transfer_options())))
  let plan = plan_transfer(view, {
    ..transfer_options(),
    unknown_size_reservation: Some(100L),
  })
  assert_eq(plan.known_bytes, 0L)
  assert_eq(plan.reserved_bytes, 100L)
  assert_eq(plan.unknown_sizes, 1)
  assert_true(plan.batches[0].tasks[0].declared_bytes is None)
}

///|
test "transfer rejects file ancestor and existing destination directory" {
  let source = incomplete_fixture()
  let entries : Array[FetchEntry] = [
    { url: "https://example.org/a", size: Some(1L), path: "data/a", },
    { url: "https://example.org/b", size: Some(1L), path: "data/a/b", },
  ]
  rejects(() => ignore(check_transfer_paths(source, entries)))
  let dirs = source.directories.copy()
  dirs.push("data/example.txt")
  rejects(() => {
    ignore(plan_transfer({ ..source, directories: dirs, }, transfer_options()))
  })
}

///|
test "transfer options strict schema validates counts and scheme spelling" {
  let options = parse_transfer_options({
    "format": "moonbagit-transfer-options/1",
    "max_batch_files": "1",
    "allowed_schemes": ["https", "urn"],
  })
  assert_eq(options.max_batch_files, 1)
  for value in [Json("0"), Json("2147483648"), Json(1)] {
    rejects(() => {
      ignore(
        parse_transfer_options({
          "format": "moonbagit-transfer-options/1",
          "max_batch_files": value,
        }),
      )
    })
  }
  rejects(() => {
    ignore(
      plan_transfer(incomplete_fixture(), {
        ..transfer_options(),
        allowed_schemes: ["HTTPS"],
      }),
    )
  })
}

///|
test "collection keeps per bag rejection and stable identifiers" {
  let policy = receiving_policy("collection")
  let result = evaluate_collection(
    [
      { identifier: "z-valid", view: fixture(), },
      { identifier: "a-incomplete", view: incomplete_fixture(), },
    ],
    policy,
  )
  assert_true(!result.accepted)
  assert_eq(result.accepted_bags, 1)
  assert_eq(result.rejected_bags, 1)
  assert_eq(result.items[0].identifier, "a-incomplete")
  assert_eq(result.payload_bytes, 3L)
  assert_true(!evaluate_collection([], policy).accepted)
  rejects(() => {
    ignore(
      evaluate_collection(
        [
          { identifier: "same", view: fixture(), },
          { identifier: "same", view: fixture(), },
        ],
        policy,
      ),
    )
  })
}

///|
test "snapshot revalidation requires all recorded digests not one successful hash" {
  let view = fixture()
  let snapshot = capture_snapshot(view)
  let good = revalidate_snapshot(snapshot, view)
  assert_true(good.preserved)
  assert_eq(good.inventory.checked_files, view.files.length())
  let files = view.files.map(f => FileRecord::{
    ..f,
    digests: { "sha256": f.digests["sha256"] },
  })
  let reduced = verify_snapshot_inventory(snapshot, files, view.directories)
  assert_true(!reduced.matches)
  assert_eq(reduced.verified_checksums, view.files.length())
  assert_true(
    reduced.diagnostics.all(d => d.code == "snapshot_digest_unavailable"),
  )
}

///|
test "snapshot revalidation catches extra missing duplicate and unsafe inventory" {
  let view = fixture()
  let snapshot = capture_snapshot(view)
  let files = view.files.filter(f => f.path != "data/example.txt")
  files.push({ path: "../outside", size: 0L, digests: Map([]), })
  files.push(files[0])
  let report = verify_snapshot_inventory(snapshot, files, [
    "data", "data", "data/new",
  ])
  assert_true(!report.matches)
  for
    code in [
      "snapshot_missing_file", "snapshot_unsafe_path", "snapshot_duplicate_file",
      "snapshot_duplicate_directory", "snapshot_unexpected_file", "snapshot_unexpected_directory",
    ] {
    assert_true(report.diagnostics.any(d => d.code == code))
  }
}

///|
test "snapshot revalidation detects corrupted tag manifests even if bag remains valid" {
  let view = fixture()
  let snapshot = capture_snapshot(view)
  let files = view.files.map(f => {
    if manifest_name(f.path, true) {
      FileRecord::{
        ..f,
        digests: { "sha256": repeated("e", 64), "sha512": repeated("f", 128) },
      }
    } else {
      f
    }
  })
  let changed : BagView = { ..view, files, }
  assert_true(validate(changed).valid)
  let result = revalidate_snapshot(snapshot, changed)
  assert_true(!result.preserved && result.bag.valid)
  assert_true(
    result.inventory.diagnostics.any(d => d.code == "snapshot_digest_changed"),
  )
}

///|
test "receiving invalid inventory remains rejected instead of aborting collection" {
  let view = fixture()
  let files = view.files.map(f => {
    if f.path == "bagit.txt" {
      FileRecord::{ ..f, size: -1L, }
    } else {
      f
    }
  })
  let bad : BagView = { ..view, files, }
  assert_true(
    !evaluate_receiving_policy(bad, receiving_policy("invalid")).accepted,
  )
  let result = evaluate_collection(
    [{ identifier: "bad", view: bad, }],
    receiving_policy("invalid"),
  )
  assert_eq(result.rejected_bags, 1)
}

///|
test "transfer batches split at file count and byte boundaries without omissions" {
  let payload : Array[FileRecord] = [
    { path: "data/z", size: 2L, digests: { "sha512": repeated("a", 128) }, },
    { path: "data/aaa", size: 2L, digests: { "sha512": repeated("b", 128) }, },
    { path: "data/b", size: 0L, digests: { "sha512": repeated("c", 128) }, },
  ]
  let texts = create_tags(payload)
  let entries = payload.map(f => FetchEntry::{
    url: "https://example.org/file",
    size: Some(f.size),
    path: f.path,
  })
  texts["fetch.txt"] = render_fetch(entries)
  let files = texts
    .to_array()
    .map(pair => {
      let (path, text) = pair
      FileRecord::{ path, size: text.length().to_int64(), digests: Map([]), }
    })
  let view : BagView = { files, directories: ["data"], texts, }
  let plan = plan_transfer(view, {
    ..transfer_options(),
    max_batch_files: 2,
    max_batch_bytes: 2L,
  })
  assert_eq(plan.pending_files, 3)
  assert_eq(plan.batches.length(), 2)
  assert_eq(plan.batches[0].tasks.map(t => t.path), ["data/aaa", "data/b"])
  assert_eq(plan.batches[1].tasks.map(t => t.path), ["data/z"])
  assert_eq(plan.batches[0].reserved_bytes, 2L)
  assert_eq(plan.reserved_bytes, 4L)
}

///|
test "portable receiver can reject valid bags without changing format verdict" {
  let view = fixture()
  let dirs = view.directories.copy()
  dirs.push("data/CON")
  let result = evaluate_receiving_policy({ ..view, directories: dirs, }, {
    ..receiving_policy("windows"),
    require_portable: true,
  })
  assert_true(result.bag.valid && !result.accepted)
  assert_true(result.diagnostics.any(d => d.code == "policy_portability"))
}
