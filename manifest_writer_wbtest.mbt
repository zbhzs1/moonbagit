///|
test "manifest writer refuses leading path whitespace instead of silently renaming" {
  for path in [" notes.bin", "\tnotes.bin", " \tmeta/file"] {
    rejects(() => {
      ignore(render_manifest([{ path, checksum: repeated("a", 64), }]))
    })
  }
}

///|
test "manifest writer refuses algorithm mixtures in either order" {
  let small : Entry = { path: "data/a", checksum: repeated("a", 64), }
  let large : Entry = { path: "data/b", checksum: repeated("b", 128), }
  rejects(() => ignore(render_manifest([small, large])))
  rejects(() => ignore(render_manifest([large, small])))
}

///|
test "manifest writer preserves nested whitespace Unicode and escaped paths" {
  for
    path in [
      "data/ file", "data/\tfile", "data/a\n%.txt", "data/\u{4E2D}\u{6587}",
    ] {
    let entries : Array[Entry] = [{ path, checksum: repeated("a", 64), }]
    assert_eq(
      parse_manifest("manifest-sha256.txt", render_manifest(entries)).entries,
      entries,
    )
  }
  let entries : Array[Entry] = [
    { path: "metadata/ notes.bin", checksum: repeated("b", 128), },
  ]
  assert_eq(
    parse_manifest("tagmanifest-sha512.txt", render_manifest(entries)).entries,
    entries,
  )
}

///|
test "tag creation refuses an unrepresentable root tag name" {
  rejects(() => {
    ignore(
      create_tag_manifests([
        {
          path: "manifest-sha256.txt",
          size: 0L,
          digests: { "sha512": repeated("b", 128) },
        },
        {
          path: " notes.bin",
          size: 0L,
          digests: { "sha512": repeated("b", 128) },
        },
      ]),
    )
  })
}
