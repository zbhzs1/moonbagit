///|
fn issue(
  out : Array[Diagnostic],
  code : String,
  path : String,
  message : String,
  warning~ : Bool = false,
) -> Unit {
  out.push({
    severity: if warning {
      Warning
    } else {
      Error
    },
    code,
    path,
    message,
  })
}

///|
fn manifest_name(path : String, tag : Bool) -> Bool {
  path.has_prefix(if tag { "tagmanifest-" } else { "manifest-" }) &&
  path.has_suffix(".txt") &&
  !path.contains("/")
}

///|
pub fn validate(view : BagView) -> Report {
  let diagnostics : Array[Diagnostic] = []
  check_inventory(view, diagnostics)
  let files : Map[String, FileRecord] = Map([])
  let payload : Array[FileRecord] = []
  let payload_names : Array[String] = []
  let tag_names : Array[String] = []
  let mut bytes = 0L
  let folded : Map[String, String] = Map([])
  for file in view.files {
    check_path(file.path) catch {
      Invalid(message) => issue(diagnostics, "unsafe_path", file.path, message)
    }
    if files.contains(file.path) {
      issue(
        diagnostics,
        "duplicate_file",
        file.path,
        "duplicate inventory entry",
      )
    }
    files[file.path] = file
    let lower = file.path[:].to_lower().to_owned()
    match folded.get(lower) {
      Some(other) if other != file.path =>
        issue(
          diagnostics,
          "case_collision",
          file.path,
          "case collision with " + other,
          warning=true,
        )
      _ => ()
    }
    folded[lower] = file.path
    if file.size < 0 {
      issue(diagnostics, "invalid_size", file.path, "negative byte length")
    }
    if file.path.has_prefix("data/") {
      payload.push(file)
      if file.size >= 0 && bytes <= 9223372036854775807L - file.size {
        bytes = bytes + file.size
      } else {
        issue(
          diagnostics,
          "size_overflow",
          file.path,
          "invalid total byte count",
        )
      }
    }
    if manifest_name(file.path, false) {
      payload_names.push(file.path)
    }
    if manifest_name(file.path, true) {
      tag_names.push(file.path)
    }
  }
  if !view.directories.contains("data") {
    issue(
      diagnostics, "missing_data", "data", "required payload directory is missing",
    )
  }
  match (files.get("bagit.txt"), view.texts.get("bagit.txt")) {
    (Some(_), Some(text)) =>
      ignore(parse_declaration(text)) catch {
        Invalid(message) =>
          issue(diagnostics, "declaration", "bagit.txt", message)
      }
    _ =>
      issue(
        diagnostics, "missing_declaration", "bagit.txt", "declaration missing or not decoded",
      )
  }
  if payload_names.is_empty() {
    issue(
      diagnostics, "missing_manifest", "", "at least one payload manifest is required",
    )
  }
  payload_names.sort()
  tag_names.sort()
  let manifests : Array[Manifest] = []
  let names = payload_names.copy()
  names.append(tag_names)
  for name in names {
    match view.texts.get(name) {
      Some(text) =>
        manifests.push(parse_manifest(name, text)) catch {
          Invalid(message) =>
            issue(diagnostics, "manifest_format", name, message)
        }
      None => issue(diagnostics, "manifest_text", name, "manifest not decoded")
    }
  }
  let coverage : Map[String, Map[String, Bool]] = Map([])
  let mut first_tag : Manifest? = None
  for manifest in manifests {
    if manifest.algorithm == Md5 || manifest.algorithm == Sha1 {
      issue(
        diagnostics,
        "legacy_checksum",
        manifest.name,
        "legacy digest verified for interoperability; prefer SHA-256/SHA-512 for new bags",
        warning=true,
      )
    }
    let listed : Map[String, Bool] = Map([])
    for entry in manifest.entries {
      listed[entry.path] = true
      if !files.contains(entry.path) {
        issue(
          diagnostics,
          "missing_file",
          entry.path,
          "referenced by " + manifest.name,
        )
      }
    }
    coverage[manifest.name] = listed
    if manifest.tag {
      match first_tag {
        None => first_tag = Some(manifest)
        Some(first) => {
          let original = coverage.get(first.name).unwrap()
          if original.length() != listed.length() ||
            first.entries.any(e => !listed.contains(e.path)) {
            issue(
              diagnostics,
              "different_tag_sets",
              manifest.name,
              "tag manifests SHOULD list the same tag files",
              warning=true,
            )
          }
        }
      }
      for name in payload_names {
        if !listed.contains(name) {
          issue(
            diagnostics,
            "tag_coverage",
            manifest.name,
            "must list payload manifest " + name,
          )
        }
      }
      for file in view.files {
        if !file.path.has_prefix("data/") &&
          !manifest_name(file.path, true) &&
          !listed.contains(file.path) {
          issue(
            diagnostics,
            "unprotected_tag",
            file.path,
            "not listed in " + manifest.name,
            warning=true,
          )
        }
      }
    } else {
      for file in payload {
        if !listed.contains(file.path) {
          issue(
            diagnostics,
            "payload_coverage",
            manifest.name,
            "must list payload file " + file.path,
          )
        }
      }
    }
  }
  let metadata = match
    (files.get("bag-info.txt"), view.texts.get("bag-info.txt")) {
    (Some(_), Some(text)) =>
      parse_metadata(text) catch {
        Invalid(message) => {
          issue(diagnostics, "metadata_format", "bag-info.txt", message)
          []
        }
      }
    (Some(_), None) => {
      issue(
        diagnostics, "metadata_text", "bag-info.txt", "metadata not decoded",
      )
      []
    }
    _ => []
  }
  let oxums = metadata.filter(m => {
    m.label[:].to_lower().to_owned() == "payload-oxum"
  })
  if oxums.length() > 1 {
    issue(
      diagnostics, "multiple_oxum", "bag-info.txt", "Payload-Oxum MUST NOT be repeated",
    )
  }
  for oxum in oxums {
    let parts = oxum.value.split(".").collect()
    if parts.length() != 2 ||
      parts.any(p => p == "" || !p.iter().all(c => c >= '0' && c <= '9')) {
      issue(
        diagnostics, "oxum_format", "bag-info.txt", "expected byte-count.file-count",
      )
    } else {
      try {
        let expected_bytes = @string.parse_int64(parts[0])
        let expected_files = @string.parse_int64(parts[1])
        if expected_bytes != bytes ||
          expected_files != payload.length().to_int64() {
          let actual = "\{bytes}.\{payload.length()}"
          issue(
            diagnostics,
            "oxum_mismatch",
            "bag-info.txt",
            "declared " + oxum.value + ", observed " + actual,
          )
        }
      } catch {
        _ =>
          issue(
            diagnostics, "oxum_format", "bag-info.txt", "Payload-Oxum exceeds supported Int64 range",
          )
      }
    }
  }
  match (files.get("fetch.txt"), view.texts.get("fetch.txt")) {
    (Some(_), Some(text)) =>
      try {
        for entry in parse_fetch(text) {
          for manifest in manifests {
            if !manifest.tag &&
              !coverage.get(manifest.name).unwrap().contains(entry.path) {
              issue(
                diagnostics,
                "fetch_coverage",
                "fetch.txt",
                entry.path + " is absent from " + manifest.name,
              )
            }
          }
          match files.get(entry.path) {
            None =>
              issue(
                diagnostics,
                "fetch_pending",
                entry.path,
                "not downloaded; no network requests were made",
                warning=true,
              )
            Some(file) =>
              if entry.size is Some(expected) && file.size != expected {
                issue(
                  diagnostics,
                  "fetch_size",
                  entry.path,
                  "downloaded size does not match fetch entry",
                )
              }
          }
        }
      } catch {
        Invalid(message) =>
          issue(diagnostics, "fetch_format", "fetch.txt", message)
      }
    (Some(_), None) =>
      issue(diagnostics, "fetch_text", "fetch.txt", "fetch file not decoded")
    _ => ()
  }
  let complete = !diagnostics.any(d => d.severity == Error)
  let mut verified = 0
  for manifest in manifests {
    for entry in manifest.entries {
      if files.get(entry.path) is Some(file) {
        match file.digests.get(manifest.algorithm.name()) {
          Some(digest) if valid_checksum(digest, manifest.algorithm) =>
            if digest[:].to_lower().to_owned() == entry.checksum {
              verified = verified + 1
            } else {
              issue(
                diagnostics,
                "checksum_mismatch",
                entry.path,
                "checksum differs in " + manifest.name,
              )
            }
          _ =>
            issue(
              diagnostics,
              "digest_unavailable",
              entry.path,
              "host did not provide a valid raw-byte digest",
            )
        }
      }
    }
  }
  {
    complete,
    valid: complete && !diagnostics.any(d => d.severity == Error),
    payload_files: payload.length(),
    payload_bytes: bytes,
    verified_checksums: verified,
    diagnostics,
  }
}
