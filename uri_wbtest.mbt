///|
test "RFC3986 absolute URI forms include empty rootless absolute and authority paths" {
  for
    url in [
      "urn:example:animal:ferret:nose",
      "mailto:John.Doe@example.com",
      "news:comp.infosystems.www.servers.unix",
      "tel:+1-816-555-1212",
      "foo:",
      "foo:?",
      "foo:/",
      "foo:/a/b:c",
      "foo:a:b",
      "foo://",
      "foo:///a",
      "foo://user:password@example.org:8042/over/there?name=ferret",
      "https://example.org/a%20b?x=%23%25&y=?/@:~",
      "ftp://ftp.is.co.za/rfc/rfc1808.txt",
      "http://[2001:db8::7]/c=GB?objectClass?one",
      "http://[::]/",
      "http://[::1]:443/",
      "http://[1:2:3:4:5:6:7:8]/",
      "http://[::ffff:192.0.2.1]/",
      "http://[1:2:3:4:5:6:192.0.2.1]/",
      "foo://[v1.a:b!$&'()*+,;=]/",
      "foo://[VF.a]:/",
      "foo://user%40name@reg%2Dname:12/",
      "foo://192.0.2.256/",
      "foo://host:/",
      "foo://:12/",
      "file:///tmp/data",
      "foo:a!$&'()*+,;=:@/b",
      "foo://a.b/[]?x=1".replace_all(old="[]", new="%5B%5D"),
    ] {
    check_fetch_url(url)
    let entry : FetchEntry = { url, size: None, path: "data/a", }
    assert_eq(parse_fetch(render_fetch([entry])), [entry])
  }
}

///|
test "RFC3986 rejects malformed authority IP literals ports components escapes and fragments" {
  for
    url in [
      "//example.com/a", "/a", "1http:a", ":a", "http s:a", "https://example.org/#part",
      "urn:a#", "https://[::1", "https://::1/", "https://[1:2:3:4:5:6:7]/", "https://[1:2:3:4:5:6:7:8:9]/",
      "https://[1:2:3:4:5:6:7:8::]/", "https://[1::2::3]/", "https://[:1]/", "https://[1:]/",
      "https://[::ffff:192.0.2.256]/", "https://[::ffff:192.00.2.1]/", "https://[192.0.2.1]/",
      "https://[::ffff:192.0.2.1:1]/", "https://[fe80::1%25eth0]/", "https://[v.a]/",
      "https://[v1.]/", "https://[v1.%20]/", "https://[::1]junk/", "https://[::1]:abc/",
      "https://host:abc/", "https://a@b@c/", "https://ho[st]/", "https://host/a[b]",
      "https://host/a?x=[a]", "https://host/%2", "https://host/?x=%GG", "https://host/a b",
      "https://host/\\x", "urn:中文",
    ] {
    rejects(() => check_fetch_url(url))
    rejects(() => ignore(parse_fetch(url + " - data/a\n")))
    rejects(() => ignore(render_fetch([{ url, size: None, path: "data/a", }])))
  }
}

///|
test "URI token grammar is not HTTP transport policy and imposes no short field limit" {
  check_fetch_url("custom+v1.2://user@host:/path?query")
  check_fetch_url("urn:" + repeated("a", 100000))
  rejects(() => ignore(parse_fetch("http://host/ -data/a\n")))
  rejects(() => ignore(parse_fetch("http://host/ 1data/a\n")))
}

///|
test "legacy checksum algorithms and encoding declarations are accepted independently of host codecs" {
  for
    (name, width) in [
      ("md5", 32),
      ("sha1", 40),
      ("sha256", 64),
      ("sha512", 128),
    ] {
    let parsed = parse_manifest(
      "manifest-" + name + ".txt",
      repeated("a", width) + " data/a\n",
    )
    assert_eq(parsed.algorithm.name(), name)
    assert_eq(parsed.algorithm.hex_length(), width)
    assert_eq(
      render_manifest(parsed.entries),
      repeated("a", width) + "  data/a\n",
    )
  }
  for encoding in ["ISO-8859-1", "UTF-16", "Shift_JIS", "GB18030", "US-ASCII"] {
    assert_eq(
      parse_declaration(
        "BagIt-Version: 1.0\nTag-File-Character-Encoding: " + encoding + "\n",
      ).encoding,
      encoding,
    )
  }
  check_path("data/file:name")
  check_path("data/literal\\backslash")
}

///|
test "fetch preflight only permits declared missing payload and provisional oxum" {
  let view = fixture()
  let missing = view.files.filter(f => f.path != "data/example.txt")
  let texts = view.texts.copy()
  texts["fetch.txt"] = "https://example.org/file 3 data/example.txt\n"
  missing.push({ path: "fetch.txt", size: 1L, digests: Map([]), })
  let entries = plan_fetch({
    files: missing,
    directories: view.directories,
    texts,
  })
  assert_eq(entries.length(), 1)
  texts["fetch.txt"] = "https://[broken 3 data/example.txt\n"
  rejects(() => {
    ignore(
      plan_fetch({ files: missing, directories: view.directories, texts, }),
    )
  })
  texts["fetch.txt"] = "https://example.org/file 3 data/not-listed\n"
  rejects(() => {
    ignore(
      plan_fetch({ files: missing, directories: view.directories, texts, }),
    )
  })
}
