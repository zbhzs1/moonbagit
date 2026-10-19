///|
test "directory inventory rejects unsafe and duplicate paths" {
  let view = fixture()
  let report = validate({ ..view, directories: ["data", "data", "../escape"], })
  assert_false(report.valid)
  assert_true(report.has_code("unsafe_directory"))
  assert_true(report.has_code("duplicate_directory"))
}

///|
test "a file cannot also be the payload root or an inventory directory" {
  let view = fixture()
  view.files.push({ path: "data", size: 0L, digests: Map([]), })
  let report = validate(view)
  assert_true(report.has_code("file_directory_collision"))
  assert_true(report.has_code("payload_root_file"))
  assert_false(report.complete)
}

///|
test "reserved tag names must not be directories" {
  for
    name in [
      "bagit.txt", "bag-info.txt", "fetch.txt", "manifest-sha512.txt", "tagmanifest-sha256.txt",
    ] {
    let view = fixture()
    view.directories.push(name)
    assert_true(validate(view).has_code("reserved_tag_directory"))
  }
}

///|
test "nested file inventory requires all parent directories" {
  let view = fixture()
  view.files.push({
    path: "tags/nested/receipt.bin",
    size: 0L,
    digests: Map([]),
  })
  assert_true(validate(view).has_code("missing_parent_directory"))
  view.directories.append(["tags", "tags/nested"])
  assert_true(validate(view).valid)
}

///|
test "directory children also require parent directories" {
  let view = fixture()
  view.directories.push("data/missing/child")
  assert_true(validate(view).has_code("missing_parent_directory"))
  view.directories.push("data/missing")
  assert_true(validate(view).valid)
}

///|
test "file ancestor is impossible even if another child has a directory record" {
  let view = fixture()
  view.files.push({ path: "notes", size: 0L, digests: Map([]), })
  view.files.push({ path: "notes/a", size: 0L, digests: Map([]), })
  let report = validate(view)
  assert_true(report.has_code("ancestor_file"))
  assert_false(report.valid)
}

///|
test "ordinary empty nested directories remain permitted" {
  let view = fixture()
  view.directories.append(["data/empty", "notes", "notes/empty"])
  assert_true(validate(view).valid)
}

///|
test "decoded text without a corresponding file is rejected" {
  let view = fixture()
  view.texts["notes.txt"] = "not an actual inventory file"
  let report = validate(view)
  assert_false(report.valid)
  assert_true(report.has_code("orphan_text"))
}
