///|
test "offline fetch writer preserves URI escapes and encodes only the path" {
  let entries : Array[FetchEntry] = [
    {
      url: "https://example.org/a%20b?x=1&y=2",
      size: Some(3L),
      path: "data/a b%.txt",
    },
    {
      url: "urn:example:payload",
      size: None,
      path: "data/\u{4E2D}\u{6587}\nfile",
    },
  ]
  let text = render_fetch(entries)
  assert_true(text.contains("a%20b?x=1&y=2 3 data/a b%25.txt"))
  assert_true(text.contains("%0Afile"))
  assert_eq(parse_fetch(text), entries)
}

///|
test "fetch handles empty plans zero bytes and the Int64 maximum" {
  assert_eq(render_fetch([]), "")
  assert_eq(parse_fetch(""), [])
  let entries : Array[FetchEntry] = [
    { url: "https://example.org/empty", size: Some(0L), path: "data/empty", },
    {
      url: "urn:example:large",
      size: Some(9223372036854775807L),
      path: "data/large",
    },
  ]
  assert_eq(parse_fetch(render_fetch(entries)), entries)
}

///|
test "fetch parser and writer reject malformed escapes and raw non URI characters" {
  for
    url in [
      "relative", "1bad:x", "https://example.org/%", "https://example.org/%2", "https://example.org/%gg",
      "https://example.org/\u{4E2D}", "https://example.org/<bad>", "https://example.org/\\file",
      "urn:example:\u001B",
    ] {
    rejects(() => ignore(parse_fetch(url + " 1 data/a\n")))
    rejects(() => {
      ignore(render_fetch([{ url, size: Some(1L), path: "data/a", }]))
    })
  }
}

///|
test "fetch writer prevents token and line injection" {
  for url in ["https://example.org/a b", "urn:a\tb", "urn:a\nb", "urn:a\rb"] {
    rejects(() => ignore(render_fetch([{ url, size: None, path: "data/a", }])))
  }
}

///|
test "fetch writer rejects negative duplicate and escaping payload entries" {
  rejects(() => {
    ignore(render_fetch([{ url: "urn:a", size: Some(-1L), path: "data/a", }]))
  })
  let entry : FetchEntry = { url: "urn:a", size: None, path: "data/a", }
  rejects(() => ignore(render_fetch([entry, entry])))
  for
    path in [
      "tag.txt", "data", "data/../tag", "/data/a", "data//a", "data/a\u0000",
    ] {
    rejects(() => ignore(render_fetch([{ url: "urn:a", size: None, path, }])))
  }
}

///|
test "fetch parser retains existing size and duplicate safeguards" {
  for
    text in [
      "urn:a -1 data/a\n", "urn:a 9223372036854775808 data/a\n", "urn:a 1 data/a\nurn:b 2 data/a\n",
      "urn:a - data/a%20b\n",
    ] {
    rejects(() => ignore(parse_fetch(text)))
  }
}
