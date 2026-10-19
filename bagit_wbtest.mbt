///|
fn repeated(c : String, length : Int32) -> String {
  let out = StringBuilder()
  for _ in 0..<length {
    out.write_string(c)
  }
  out.to_string()
}

///|
fn fixture() -> BagView raise {
  let file : FileRecord = {
    path: "data/example.txt",
    size: 3L,
    digests: {
      "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "sha512": "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    },
  }
  let texts = create_tags([file], algorithms=[Sha256, Sha512])
  let files = [file]
  // Core tests exercise supplied inventory contracts; real hashes are tested by interop.
  for name, text in texts {
    files.push({
      path: name,
      size: text.length().to_int64(),
      digests: { "sha256": repeated("a", 64), "sha512": repeated("b", 128) },
    })
  }
  let tags = create_tag_manifests(
    files.filter(f => !f.path.has_prefix("data/")),
    algorithms=[Sha256, Sha512],
  )
  for name, text in tags {
    texts[name] = text
    files.push({
      path: name,
      size: text.length().to_int64(),
      digests: { "sha256": repeated("c", 64), "sha512": repeated("d", 128) },
    })
  }
  { files, directories: ["data"], texts, }
}

///|
fn rejects(action : () -> Unit raise) -> Unit raise {
  let rejected = try {
    action()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "declaration supports line endings and case-insensitive UTF-8 label value" {
  for ending in ["\n", "\r", "\r\n"] {
    let declaration = parse_declaration(
      "BagIt-Version: 1.0" +
      ending +
      "Tag-File-Character-Encoding: utf-8" +
      ending,
    )
    assert_eq(declaration.version, "1.0")
    assert_eq(declaration.encoding, "UTF-8")
  }
}

///|
test "declaration rejects BOM version encoding order and extra rows" {
  for
    text in [
      "\uFEFFBagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n", "BagIt-Version: 0.97\nTag-File-Character-Encoding: UTF-8\n",
      "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-16\n", "Tag-File-Character-Encoding: UTF-8\nBagIt-Version: 1.0\n",
      "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n\n",
    ] {
    rejects(() => ignore(parse_declaration(text)))
  }
}

///|
test "path escaping roundtrip including non-BMP characters" {
  for
    path in [
      "data/100%.txt", "data/line\nfeed\r.txt", "data/a b.txt", "data/\u4E2D\u6587\u{1F600}.txt",
      "data/%0A.txt",
    ] {
    assert_eq(decode_path(encode_path(path)), path)
  }
}

///|
test "only normative percent escapes decode" {
  for
    path in [
      "data/%", "data/%2", "data/%20.txt", "data/%2F..", "data/%GG", "data/%a\u{1F600}",
    ] {
    rejects(() => ignore(decode_path(path)))
  }
  assert_eq(decode_path("data/%0a%0d%25"), "data/\n\r%")
}

///|
test "reject traversal and platform path escapes" {
  for
    path in [
      "", "/etc/passwd", "C:/x", "data/../x", "data/./x", "data//x", "data/", "data\\x",
      "data/\u0000x",
    ] {
    rejects(() => check_path(path))
  }
}

///|
test "manifest parses mixed case hex and tabs with spaces in filenames" {
  let checksum = repeated("A", 64)
  let m = parse_manifest(
    "manifest-sha256.txt",
    checksum + "\tdata/a b%.txt".replace_all(old="%", new="%25") + "\r\n",
  )
  assert_eq(m.entries.length(), 1)
  assert_eq(m.entries[0].path, "data/a b%.txt")
  assert_eq(m.entries[0].checksum, repeated("a", 64))
}

///|
test "manifest rejects bad algorithm checksum and separators" {
  for
    item in [
      ("manifest-md5.txt", repeated("a", 32) + "  data/a\n"),
      ("manifest-sha256.txt", repeated("a", 63) + "  data/a\n"),
      ("manifest-sha256.txt", repeated("g", 64) + "  data/a\n"),
      ("manifest-sha256.txt", repeated("a", 64)),
      ("manifest-sha256.txt", repeated("a", 64) + " \n"),
      ("sub/manifest-sha256.txt", repeated("a", 64) + " data/a\n"),
    ] {
    let (name, text) = item
    rejects(() => ignore(parse_manifest(name, text)))
  }
}

///|
test "payload and tag manifest domain constraints" {
  let checksum = repeated("a", 64)
  rejects(() => {
    ignore(parse_manifest("manifest-sha256.txt", checksum + " bagit.txt\n"))
  })
  rejects(() => {
    ignore(parse_manifest("tagmanifest-sha256.txt", checksum + " data/a\n"))
  })
  rejects(() => {
    ignore(
      parse_manifest(
        "tagmanifest-sha256.txt",
        checksum + " tagmanifest-sha512.txt\n",
      ),
    )
  })
}

///|
test "manifest rejects duplicate decoded filenames" {
  let row = repeated("a", 64) + "  data/a\n"
  rejects(() => ignore(parse_manifest("manifest-sha256.txt", row + row)))
}

///|
test "manifest writer rejects digest and path injection" {
  rejects(() => {
    ignore(render_manifest([{ path: "data/a", checksum: "bad\nline", }]))
  })
  rejects(() => {
    ignore(render_manifest([{ path: "../a", checksum: repeated("a", 64), }]))
  })
  let entry : Entry = { path: "data/a", checksum: repeated("a", 64), }
  rejects(() => ignore(render_manifest([entry, entry])))
}

///|
test "metadata preserves repetitions order and continuations" {
  let fields = parse_metadata(
    "Contact-Name: Alice\r\nDescription: First\r\n  Second\r\nContact-Name:\tBob\r\n",
  )
  assert_eq(fields.length(), 3)
  assert_eq(fields[1].value, "First\nSecond")
  assert_eq(fields[2].label, "Contact-Name")
  assert_eq(fields[2].value, "Bob")
  assert_eq(parse_metadata(render_metadata(fields)), fields)
}

///|
test "metadata rejects malformed labels and orphan continuations" {
  for
    text in [
      " first\n", "Name:value\n", " Name: value\n", "Name : value\n", ": value\n",
      "Name: x\n\n",
    ] {
    rejects(() => ignore(parse_metadata(text)))
  }
}

///|
test "metadata writer rejects injection" {
  for
    field in [
      { label: "bad:name", value: "x", },
      { label: "bad\nname", value: "x", },
      { label: "bad ", value: "x", },
      { label: "Name", value: "x\ry", },
    ] {
    rejects(() => ignore(render_metadata([field])))
  }
}

///|
test "fetch parser supports unknown size and escaped file paths" {
  let entries = parse_fetch(
    "https://example.org/a 3 data/a\nurn:example:b - data/b%25\n",
  )
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].size, Some(3L))
  assert_eq(entries[1].size, None)
  assert_eq(entries[1].path, "data/b%")
}

///|
test "fetch rejects relative URI sizes and nonpayload paths" {
  for
    text in [
      "/a 3 data/a\n", "1bad:a 3 data/a\n", "https://example.org/a -3 data/a\n",
      "https://example.org/a 9223372036854775808 data/a\n", "https://example.org/a 3 bagit.txt\n",
      "https://example.org/a 3 data/../a\n",
    ] {
    rejects(() => ignore(parse_fetch(text)))
  }
}

///|
test "complete valid fixture checks both digest algorithms and tag manifests" {
  let report = validate(fixture())
  assert_true(report.complete)
  assert_true(report.valid)
  assert_eq(report.payload_files, 1)
  assert_eq(report.payload_bytes, 3L)
  assert_eq(report.verified_checksums, 10)
}

///|
test "checksum corruption preserves completeness but invalidates bag" {
  let view = fixture()
  view.files[0] = {
    ..view.files[0],
    digests: { "sha256": repeated("0", 64), "sha512": repeated("0", 128) },
  }
  let report = validate(view)
  assert_true(report.complete)
  assert_false(report.valid)
  assert_true(report.has_code("checksum_mismatch"))
}

///|
test "missing payload is incomplete" {
  let view = fixture()
  let report = validate({
    ..view,
    files: view.files.filter(f => !f.path.has_prefix("data/")),
  })
  assert_false(report.complete)
  assert_false(report.valid)
  assert_true(report.has_code("missing_file"))
}

///|
test "extra payload must be in every payload manifest" {
  let view = fixture()
  view.files.push({ ..view.files[0], path: "data/extra", })
  let report = validate(view)
  assert_false(report.complete)
  assert_true(report.has_code("payload_coverage"))
}

///|
test "second manifest incomplete coverage is not rescued by first" {
  let view = fixture()
  view.texts["manifest-sha512.txt"] = ""
  let report = validate(view)
  assert_false(report.complete)
  assert_true(report.has_code("payload_coverage"))
}

///|
test "missing tag reference makes bag incomplete" {
  let view = fixture()
  let report = validate({
    ..view,
    files: view.files.filter(f => f.path != "bag-info.txt"),
  })
  assert_false(report.complete)
  assert_true(report.has_code("missing_file"))
}

///|
test "tag manifest must include each payload manifest" {
  let view = fixture()
  view.texts["tagmanifest-sha256.txt"] = repeated("a", 64) + " bagit.txt\n"
  let report = validate(view)
  assert_false(report.complete)
  assert_true(report.has_code("tag_coverage"))
}

///|
test "tag checksum mismatch preserves completeness" {
  let view = fixture()
  let files = view.files.map(f => {
    if f.path == "bagit.txt" {
      {
        ..f,
        digests: { "sha256": repeated("0", 64), "sha512": repeated("0", 128) },
      }
    } else {
      f
    }
  })
  let report = validate({ ..view, files, })
  assert_true(report.complete)
  assert_false(report.valid)
}

///|
test "different optional tag coverage is a recommendation warning" {
  let view = fixture()
  view.texts["tagmanifest-sha256.txt"] = render_manifest(
    parse_manifest(
      "tagmanifest-sha256.txt",
      view.texts.get("tagmanifest-sha256.txt").unwrap(),
    ).entries.filter(e => e.path != "bag-info.txt"),
  )
  let report = validate(view)
  assert_true(report.valid)
  assert_true(report.has_code("different_tag_sets"))
}

///|
test "required declaration directory and manifest diagnostics" {
  let report = validate({ files: [], directories: [], texts: Map([]), })
  assert_true(report.has_code("missing_declaration"))
  assert_true(report.has_code("missing_data"))
  assert_true(report.has_code("missing_manifest"))
}

///|
test "host must supply valid checksums rather than empty strings" {
  let view = fixture()
  view.files[0] = { ..view.files[0], digests: Map([]), }
  let report = validate(view)
  assert_true(report.complete)
  assert_false(report.valid)
  assert_true(report.has_code("digest_unavailable"))
}

///|
test "unprotected arbitrary tag is warning not rejection" {
  let view = fixture()
  view.files.push({ path: "extra.bin", size: 0L, digests: Map([]), })
  let report = validate(view)
  assert_true(report.valid)
  assert_true(report.has_code("unprotected_tag"))
}

///|
test "Payload-Oxum never replaces checksum validation" {
  let view = fixture()
  view.texts["bag-info.txt"] = "Payload-Oxum: 3.1\n"
  view.files[0] = {
    ..view.files[0],
    digests: { "sha256": repeated("0", 64), "sha512": repeated("0", 128) },
  }
  assert_false(validate(view).valid)
}

///|
test "Payload-Oxum mismatch detects incompleteness" {
  let view = fixture()
  view.texts["bag-info.txt"] = "Payload-Oxum: 300.1\n"
  let report = validate(view)
  assert_true(report.has_code("oxum_mismatch"))
  assert_false(report.complete)
}

///|
test "Payload-Oxum repetitions and malformed counts are invalid" {
  for
    text in [
      "Payload-Oxum: 3.1\nPayload-Oxum: 3.1\n", "Payload-Oxum: x.1\n", "Payload-Oxum: -3.1\n",
      "Payload-Oxum: 9223372036854775808.1\n",
    ] {
    let view = fixture()
    view.texts["bag-info.txt"] = text
    assert_false(validate(view).complete)
  }
}

///|
test "Payload-Oxum accepts leading zeroes as numeric counts" {
  let view = fixture()
  view.texts["bag-info.txt"] = "Payload-Oxum: 003.01\n"
  assert_false(validate(view).has_code("oxum_mismatch"))
}

///|
test "fetch is offline and pending files remain incomplete" {
  let view = fixture()
  view.files.push({ path: "fetch.txt", size: 40L, digests: Map([]), })
  view.texts["fetch.txt"] = "https://example.org/a 1 data/absent\n"
  let report = validate(view)
  assert_false(report.complete)
  assert_true(report.has_code("fetch_coverage"))
  assert_true(report.has_code("fetch_pending"))
}

///|
test "empty payload bag creation has default sha512 and zero oxum" {
  let tags = create_tags([])
  assert_true(tags.contains("manifest-sha512.txt"))
  assert_eq(tags.get("manifest-sha512.txt"), Some(""))
  assert_eq(tags.get("bag-info.txt"), Some("Payload-Oxum: 0.0\n"))
}

///|
test "creator rejects unsupported contracts" {
  let view = fixture()
  rejects(() => ignore(create_tags([view.files[0]], algorithms=[])))
  rejects(() => {
    ignore(create_tags([view.files[0]], algorithms=[Sha512, Sha512]))
  })
  rejects(() => {
    ignore(
      create_tags([view.files[0]], metadata=[
        { label: "payload-oxum", value: "1.1", },
      ]),
    )
  })
  rejects(() => ignore(create_tags([{ ..view.files[0], path: "other", }])))
  rejects(() => ignore(create_tags([{ ..view.files[0], size: -1L, }])))
  rejects(() => ignore(create_tags([{ ..view.files[0], digests: Map([]), }])))
}

///|
test "creator rejects duplicate payload and tag manifest recursion" {
  let file = fixture().files[0]
  rejects(() => ignore(create_tags([file, file])))
  rejects(() => ignore(create_tag_manifests([file])))
  rejects(() => {
    ignore(create_tag_manifests([{ ..file, path: "tagmanifest-sha512.txt", }]))
  })
  rejects(() => ignore(create_tag_manifests([{ ..file, path: "bagit.txt", }])))
}

///|
test "creator sorts manifest entries for deterministic output" {
  let file = fixture().files[0]
  let tags = create_tags([
    { ..file, path: "data/z", },
    { ..file, path: "data/a", },
  ])
  let manifest = parse_manifest(
    "manifest-sha512.txt",
    tags.get("manifest-sha512.txt").unwrap(),
  )
  assert_eq(manifest.entries[0].path, "data/a")
  assert_eq(manifest.entries[1].path, "data/z")
}

///|
test "creator prevents byte count overflow" {
  let file = fixture().files[0]
  rejects(() => {
    ignore(
      payload_oxum([
        { ..file, size: 9223372036854775807L, },
        { ..file, size: 1L, },
      ]),
    )
  })
}

///|
test "large synthetic inventory verifies every manifest entry" {
  let digests : Map[String, String] = { "sha256": repeated("a", 64) }
  let payload : Array[FileRecord] = []
  for i in 0..<10000 {
    payload.push({ path: "data/file-\{i}.bin", size: 1L, digests, })
  }
  let texts = create_tags(payload, algorithms=[Sha256])
  let files = payload.copy()
  for path, text in texts {
    files.push({ path, size: text.length().to_int64(), digests: Map([]), })
  }
  let report = validate({ files, directories: ["data"], texts, })
  assert_true(report.valid)
  assert_eq(report.verified_checksums, 10000)
  assert_eq(report.payload_bytes, 10000L)
}
