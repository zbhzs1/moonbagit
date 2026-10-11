///|
fn profile_fixture_json() -> Json {
  {
    "BagIt-Profile-Info": {
      "Source-Organization": "Example archive",
      "External-Description": "Research data receiving rules",
      "Version": "1.0",
      "BagIt-Profile-Identifier": "urn:example:research",
      "BagIt-Profile-Version": "1.4.0",
    },
    "Serialization": "forbidden",
    "Accept-BagIt-Version": ["1.0"],
  }
}

///|
fn profiled_fixture() -> BagView raise {
  let view = fixture()
  view.texts["bag-info.txt"] = "Payload-Oxum: 3.1\nBagIt-Profile-Identifier: urn:example:research\n"
  view
}

///|
fn profile_field(key : String, value : Json) -> Json {
  let fields = profile_object(profile_fixture_json()) catch {
    _ => abort("fixture")
  }
  fields[key] = value
  fields.to_json()
}

///|
fn has_profile_code(report : ProfileReport, code : String) -> Bool {
  report.diagnostics.any(d => d.code == code)
}

///|
test "minimal directory profile defaults and successful receiving" {
  let profile = parse_profile(profile_fixture_json())
  assert_eq(profile.identifier, "urn:example:research")
  assert_true(profile.allow_fetch)
  assert_false(profile.require_fetch)
  assert_eq(profile.tags_allowed, ["*"])
  assert_true(validate_profile(profiled_fixture(), profile).conforms)
}

///|
test "profile identifier mandatory even when Bag-Info rules are empty" {
  let report = validate_profile(
    fixture(),
    parse_profile(profile_fixture_json()),
  )
  assert_false(report.conforms)
  assert_true(report.bag.valid)
  assert_true(has_profile_code(report, "profile_identifier"))
}

///|
test "profile parsing fails closed on unknown fields and versions" {
  rejects(() => {
    ignore(parse_profile(profile_field("Unknown-Future-Rule", true)))
  })
  rejects(() => ignore(parse_profile(Json::null())))
  rejects(() => {
    ignore(
      parse_profile(profile_field("BagIt-Profile-Info", Json::empty_object())),
    )
  })
  let fields = profile_object(profile_fixture_json())
  let info = profile_object(fields.get("BagIt-Profile-Info").unwrap())
  info["BagIt-Profile-Version"] = "1.1.0"
  fields["BagIt-Profile-Info"] = info.to_json()
  rejects(() => ignore(parse_profile(fields.to_json())))
}

///|
test "profile type errors never become permissive defaults" {
  let cases : Array[(String, Json)] = [
    ("Allow-Fetch.txt", "false"),
    ("Data-Empty", 1),
    ("Accept-BagIt-Version", []),
    ("Accept-BagIt-Version", [1]),
    ("Manifests-Required", ["sha512", "sha512"]),
    ("Bag-Info", { "Name": { "required": "true" } }),
    ("Bag-Info", { "Name": { "unknown": true } }),
    ("Serialization", "zip"),
  ]
  for entry in cases {
    let (key, value) = entry
    rejects(() => ignore(parse_profile(profile_field(key, value))))
  }
}

///|
test "metadata required repeatability values and case insensitive labels" {
  let profile = parse_profile(
    profile_field("Bag-Info", {
      "Dataset-Type": {
        "required": true,
        "repeatable": false,
        "values": ["research"],
      },
    }),
  )
  let view = profiled_fixture()
  assert_true(
    has_profile_code(
      validate_profile(view, profile),
      "profile_metadata_required",
    ),
  )
  let original = view.texts.get("bag-info.txt").unwrap()
  view.texts["bag-info.txt"] = original + "dataset-type: research\n"
  assert_true(validate_profile(view, profile).conforms)
  view.texts["bag-info.txt"] = original +
    "Dataset-Type: research\nDATASET-TYPE: other\n"
  let report = validate_profile(view, profile)
  assert_true(has_profile_code(report, "profile_metadata_repeat"))
  assert_true(has_profile_code(report, "profile_metadata_value"))
}

///|
test "empty allowed values means any value and repeatable defaults true" {
  let profile = parse_profile(
    profile_field("Bag-Info", { "Name": { "values": [] } }),
  )
  let view = profiled_fixture()
  view.texts["bag-info.txt"] = view.texts.get("bag-info.txt").unwrap() +
    "Name: a\nName: b\n"
  assert_true(validate_profile(view, profile).conforms)
}

///|
test "profile algorithm requirements and exclusions are independent" {
  let profile = parse_profile(profile_field("Manifests-Allowed", ["sha512"]))
  assert_true(
    has_profile_code(
      validate_profile(profiled_fixture(), profile),
      "profile_manifest_forbidden",
    ),
  )
  let profile = parse_profile(profile_field("Tag-Manifests-Required", ["sha1"]))
  assert_true(
    has_profile_code(
      validate_profile(profiled_fixture(), profile),
      "profile_manifest_required",
    ),
  )
  let fields = profile_object(profile_fixture_json())
  fields["Manifests-Required"] = ["sha512"]
  fields["Manifests-Allowed"] = ["sha256"]
  rejects(() => ignore(parse_profile(fields.to_json())))
}

///|
test "profile fetch rules and inconsistent profile rejection" {
  let view = profiled_fixture()
  let required = parse_profile(profile_field("Fetch.txt-Required", true))
  assert_true(
    has_profile_code(validate_profile(view, required), "profile_fetch_required"),
  )
  view.files.push({ path: "fetch.txt", size: 0L, digests: Map([]), })
  view.texts["fetch.txt"] = ""
  let forbidden = parse_profile(profile_field("Allow-Fetch.txt", false))
  assert_true(
    has_profile_code(
      validate_profile(view, forbidden),
      "profile_fetch_forbidden",
    ),
  )
  let fields = profile_object(profile_fixture_json())
  fields["Allow-Fetch.txt"] = false
  fields["Fetch.txt-Required"] = true
  rejects(() => ignore(parse_profile(fields.to_json())))
}

///|
test "serialization required rejects directory rather than silently ignoring it" {
  rejects(() => {
    ignore(parse_profile(profile_field("Serialization", "optional")))
  })
  let fields = profile_object(profile_fixture_json())
  fields["Serialization"] = "required"
  fields["Accept-Serialization"] = ["application/zip"]
  let report = validate_profile(
    profiled_fixture(),
    parse_profile(fields.to_json()),
  )
  assert_true(has_profile_code(report, "profile_serialization"))
  assert_false(report.conforms)
}

///|
test "profile versions cannot override core supported version" {
  let report = validate_profile(
    profiled_fixture(),
    parse_profile(profile_field("Accept-BagIt-Version", ["0.97"])),
  )
  assert_true(has_profile_code(report, "profile_version"))
  assert_false(report.conforms)
}

///|
test "profile required payload directory must contain an entry" {
  let profile = parse_profile(
    profile_field("Payload-Files-Required", ["data/empty/"]),
  )
  let view = profiled_fixture()
  view.directories.push("data/empty")
  assert_true(
    has_profile_code(
      validate_profile(view, profile),
      "profile_payload_required",
    ),
  )
  view.directories.push("data/empty/sub")
  assert_false(
    has_profile_code(
      validate_profile(view, profile),
      "profile_payload_required",
    ),
  )
}

///|
test "profile tag and payload required missing paths" {
  let fields = profile_object(profile_fixture_json())
  fields["Tag-Files-Required"] = ["receipt.txt"]
  fields["Payload-Files-Required"] = ["data/absent.txt"]
  let report = validate_profile(
    profiled_fixture(),
    parse_profile(fields.to_json()),
  )
  assert_true(has_profile_code(report, "profile_tag_required"))
  assert_true(has_profile_code(report, "profile_payload_required"))
}

///|
test "wildcards cover nested and Unicode paths without regex interpretation" {
  for
    entry in [
      ("data/*", "data/a/b.txt"),
      ("*a*b*", "zzaxybzz"),
      ("data/*.csv", "data/a.csv"),
      ("*", ""),
      ("data/\u{1F600}*", "data/\u{1F600}x"),
    ] {
    let (pattern, path) = entry
    assert_true(profile_path_matches(pattern, path))
  }
  for
    entry in [
      ("data/*.csv", "data/a.csvx"),
      ("a*b", "abc"),
      ("[ab]", "a"),
      ("x?", "xy"),
      ("x", ""),
    ] {
    let (pattern, path) = entry
    assert_false(profile_path_matches(pattern, path))
  }
}

///|
test "profile safe path restrictions and contradictory paths" {
  let cases : Array[(String, Json)] = [
    ("Tag-Files-Required", ["../outside"]),
    ("Tag-Files-Required", ["data/a"]),
    ("Payload-Files-Required", ["tag.txt"]),
    ("Payload-Files-Required", ["data/*"]),
    ("Payload-Files-Allowed", ["data/nested/"]),
    ("Tag-Files-Allowed", ["/absolute"]),
  ]
  for entry in cases {
    let (key, value) = entry
    rejects(() => ignore(parse_profile(profile_field(key, value))))
  }
  let fields = profile_object(profile_fixture_json())
  fields["Tag-Files-Required"] = ["required.txt"]
  fields["Tag-Files-Allowed"] = ["bagit.txt"]
  rejects(() => ignore(parse_profile(fields.to_json())))
}

///|
test "profile allowed paths reject extras even with valid checksums" {
  let report = validate_profile(
    profiled_fixture(),
    parse_profile(profile_field("Payload-Files-Allowed", ["data/*.csv"])),
  )
  assert_true(report.bag.valid)
  assert_false(report.conforms)
  assert_true(has_profile_code(report, "profile_path_forbidden"))
}

///|
test "profile checks empty payload directories as well as files" {
  let view = profiled_fixture()
  view.directories.push("data/unexpected")
  let profile = parse_profile(
    profile_field("Payload-Files-Allowed", ["data/example.txt"]),
  )
  let report = validate_profile(view, profile)
  assert_true(report.bag.valid)
  assert_true(has_profile_code(report, "profile_directory_forbidden"))
  assert_false(report.conforms)
}

///|
test "Data-Empty supports exactly one empty file or no files" {
  let profile = parse_profile(profile_field("Data-Empty", true))
  let view = profiled_fixture()
  assert_true(
    has_profile_code(validate_profile(view, profile), "profile_data_empty"),
  )
  view.files[0] = { ..view.files[0], size: 0L, }
  assert_false(
    has_profile_code(validate_profile(view, profile), "profile_data_empty"),
  )
  view.files.push({ ..view.files[0], path: "data/second", })
  assert_true(
    has_profile_code(validate_profile(view, profile), "profile_data_empty"),
  )
}

///|
test "profile never turns a corrupt bag into a conforming bag" {
  let view = profiled_fixture()
  view.files[0] = { ..view.files[0], digests: Map([]), }
  let report = validate_profile(view, parse_profile(profile_fixture_json()))
  assert_true(report.diagnostics.is_empty())
  assert_false(report.conforms)
  assert_false(report.bag.valid)
}

///|
test "upgrade plan preserves old manifests and adds missing algorithm" {
  let view = fixture()
  let view = {
    ..view,
    files: view.files.filter(f => {
      f.path != "manifest-sha512.txt" && !manifest_name(f.path, true)
    }),
  }
  let plan = plan_upgrade(view, [Sha512])
  assert_eq(plan.payload_manifests.length(), 1)
  assert_true(plan.payload_manifests.contains("manifest-sha512.txt"))
  assert_eq(plan.tag_algorithms, [Sha512])
  assert_true(validate(view).valid)
}

///|
test "upgrade existing algorithms is idempotent and retains tag algorithms" {
  let plan = plan_upgrade(fixture(), [Sha512])
  assert_true(plan.payload_manifests.is_empty())
  assert_true(plan.tag_algorithms.contains(Sha256))
  assert_true(plan.tag_algorithms.contains(Sha512))
}

///|
test "upgrade refuses invalid sources and duplicate requested algorithms" {
  let view = fixture()
  view.files[0] = { ..view.files[0], digests: Map([]), }
  rejects(() => ignore(plan_upgrade(view, [Sha512])))
  rejects(() => ignore(plan_upgrade(fixture(), [])))
  rejects(() => ignore(plan_upgrade(fixture(), [Sha512, Sha512])))
}
