///|
pub(all) struct SnapshotVerification {
  matches : Bool
  checked_files : Int32
  verified_checksums : Int32
  diagnostics : Array[Diagnostic]
} derive(ToJson)

///|
pub extend SnapshotVerification with ToJson::{to_json}

///|
/// Recheck every recorded digest, without treating unchanged timestamps as evidence.
/// This checks preservation against a trusted local snapshot, not RFC conformance.
pub fn verify_snapshot_inventory(
  expected : BagSnapshot,
  observed : Array[FileRecord],
  directories : Array[String],
) -> SnapshotVerification raise FormatError {
  validate_snapshot(expected)
  let diagnostics : Array[Diagnostic] = []
  let before : Map[String, FileRecord] = Map([])
  let after : Map[String, FileRecord] = Map([])
  let expected_dirs : Map[String, Bool] = Map([])
  let observed_dirs : Map[String, Bool] = Map([])
  for file in expected.files {
    before[file.path] = file
  }
  for directory in expected.directories {
    expected_dirs[directory] = true
  }
  for file in observed {
    check_path(file.path) catch {
      Invalid(message) =>
        issue(diagnostics, "snapshot_unsafe_path", file.path, message)
    }
    if after.contains(file.path) {
      issue(
        diagnostics,
        "snapshot_duplicate_file",
        file.path,
        "duplicate observed file record",
      )
    }
    if file.size < 0L {
      issue(
        diagnostics,
        "snapshot_invalid_size",
        file.path,
        "negative observed byte count",
      )
    }
    after[file.path] = file
  }
  for directory in directories {
    check_path(directory) catch {
      Invalid(message) =>
        issue(diagnostics, "snapshot_unsafe_directory", directory, message)
    }
    if observed_dirs.contains(directory) {
      issue(
        diagnostics, "snapshot_duplicate_directory", directory, "duplicate observed directory",
      )
    }
    if after.contains(directory) {
      issue(
        diagnostics, "snapshot_path_collision", directory, "observed path is both file and directory",
      )
    }
    observed_dirs[directory] = true
  }
  let mut checked_files = 0
  let mut verified_checksums = 0
  for path in sorted_map_keys(before) {
    let original = before[path]
    match after.get(path) {
      None =>
        issue(
          diagnostics, "snapshot_missing_file", path, "recorded file is missing",
        )
      Some(file) => {
        checked_files = checked_files + 1
        if file.size != original.size {
          issue(
            diagnostics, "snapshot_size_changed", path, "byte count differs from preservation record",
          )
        }
        for name in sorted_map_keys(original.digests) {
          let alg = algorithm(name)
          match file.digests.get(name) {
            None =>
              issue(
                diagnostics,
                "snapshot_digest_unavailable",
                path,
                "host did not recompute recorded algorithm " + name,
              )
            Some(digest) =>
              if !valid_checksum(digest, alg) {
                issue(
                  diagnostics,
                  "snapshot_digest_invalid",
                  path,
                  "host supplied a malformed " + name + " digest",
                )
              } else if digest[:].to_lower().to_owned() !=
                original.digests[name][:].to_lower().to_owned() {
                issue(
                  diagnostics,
                  "snapshot_digest_changed",
                  path,
                  "raw-byte " +
                  name +
                  " digest differs from preservation record",
                )
              } else {
                verified_checksums = verified_checksums + 1
              }
          }
        }
      }
    }
  }
  for path in sorted_map_keys(after) {
    if !before.contains(path) {
      issue(
        diagnostics, "snapshot_unexpected_file", path, "unrecorded file is present",
      )
    }
  }
  for path in sorted_map_keys(expected_dirs) {
    if !observed_dirs.contains(path) {
      issue(
        diagnostics, "snapshot_missing_directory", path, "recorded directory is missing",
      )
    }
  }
  for path in sorted_map_keys(observed_dirs) {
    if !expected_dirs.contains(path) {
      issue(
        diagnostics, "snapshot_unexpected_directory", path, "unrecorded directory is present",
      )
    }
  }
  {
    matches: !diagnostics.any(d => d.severity == Error),
    checked_files,
    verified_checksums,
    diagnostics,
  }
}

///|
pub(all) struct PreservationReport {
  preserved : Bool
  bag : Report
  inventory : SnapshotVerification
  metadata : Array[MetadataChange]
  declaration_matches : Bool
} derive(ToJson)

///|
pub extend PreservationReport with ToJson::{to_json}

///|
/// Combine independent preservation evidence with a fresh full BagIt validation.
pub fn revalidate_snapshot(
  expected : BagSnapshot,
  current : BagView,
) -> PreservationReport raise FormatError {
  let inventory = verify_snapshot_inventory(
    expected,
    current.files,
    current.directories,
  )
  let bag = validate(current)
  let declaration_matches = match current.texts.get("bagit.txt") {
    Some(text) => {
      let declaration = parse_declaration(text) catch {
        Invalid(_) => { version: "", encoding: "", }
      }
      declaration.version == expected.bag_version &&
      declaration.encoding == expected.encoding
    }
    None => false
  }
  let fields = match current.texts.get("bag-info.txt") {
    Some(text) => parse_metadata(text) catch { Invalid(_) => [] }
    None => []
  }
  let metadata = compare_metadata(expected.metadata, fields)
  {
    preserved: bag.valid &&
    inventory.matches &&
    declaration_matches &&
    metadata.is_empty(),
    bag,
    inventory,
    metadata,
    declaration_matches,
  }
}
