///|
fn portability_view(
  paths : Array[String],
  directories~ : Array[String] = [],
) -> BagView {
  {
    files: paths.map(path => { path, size: 0L, digests: Map([]), }),
    directories,
    texts: Map([]),
  }
}

///|
test "portable ordinary Unicode nested names have no warnings" {
  assert_true(
    lint_portability(
      portability_view(
        ["data/measurements/a.csv", "data/\u{4E2D}\u{6587}.txt"],
        directories=["data", "data/measurements"],
      ),
    ).is_empty(),
  )
}

///|
test "device names are case insensitive and apply before extensions" {
  for
    name in [
      "CON", "con.txt", "AUX.bin", "NUL.tar.gz", "COM1.csv", "LPT9", "CONIN$",
    ] {
    assert_true(
      lint_portability(portability_view(["data/" + name])).any(d => {
        d.code == "portable_device_name"
      }),
    )
  }
  for name in ["console.txt", "COM0", "COM10", "LPT0", "AUXILIARY"] {
    assert_false(
      lint_portability(portability_view(["data/" + name])).any(d => {
        d.code == "portable_device_name"
      }),
    )
  }
}

///|
test "trailing characters controls and wildcard filenames are advisory" {
  let warnings = lint_portability(
    portability_view(["data/a.", "data/a ", "data/a\n.txt", "data/a*.txt"]),
  )
  assert_eq(warnings.length(), 4)
  assert_true(warnings.all(d => d.severity == Warning))
}

///|
test "case collisions also include directories with different children" {
  let warnings = lint_portability(
    portability_view(["data/A/one", "data/a/two"], directories=[
      "data", "data/A", "data/a",
    ]),
  )
  assert_eq(warnings.length(), 1)
  assert_eq(warnings[0].code, "portable_case_collision")
}

///|
test "long paths and components yield different warning codes" {
  let name = repeated("a", 256)
  let warnings = lint_portability(portability_view(["data/" + name]))
  assert_true(warnings.any(d => d.code == "portable_long_path"))
  assert_true(warnings.any(d => d.code == "portable_long_component"))
}

///|
test "portability lint de-duplicates inventory paths and orders output" {
  let warnings = lint_portability(
    portability_view(["data/z.", "data/CON", "data/CON"]),
  )
  assert_eq(warnings.length(), 2)
  let reversed = lint_portability(portability_view(["data/CON", "data/z."]))
  assert_eq(warnings.map(d => d.path), reversed.map(d => d.path))
}
