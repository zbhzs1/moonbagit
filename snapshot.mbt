///|
/// A local preservation record, not a signed proof or a BagIt standard tag.
pub(all) struct BagSnapshot {
  label : String
  bag_version : String
  encoding : String
  directories : Array[String]
  files : Array[FileRecord]
  metadata : Array[Metadata]
}

///|
fn validate_snapshot(value : BagSnapshot) -> Unit raise FormatError {
  guard value.bag_version == "1.0" else {
    raise Invalid("snapshot requires BagIt 1.0")
  }
  ignore(
    parse_declaration(
      "BagIt-Version: 1.0\nTag-File-Character-Encoding: " +
      value.encoding +
      "\n",
    ),
  )
  let files : Map[String, Bool] = Map([])
  let dirs : Map[String, Bool] = Map([])
  for path in value.directories {
    check_path(path)
    guard !dirs.contains(path) else {
      raise Invalid("duplicate snapshot directory: " + path)
    }
    dirs[path] = true
  }
  guard dirs.contains("data") else {
    raise Invalid("snapshot payload root is missing")
  }
  let mut bytes = 0L
  for file in value.files {
    check_path(file.path)
    guard !files.contains(file.path) && !dirs.contains(file.path) else {
      raise Invalid("duplicate or colliding snapshot path: " + file.path)
    }
    guard !file.digests.is_empty() else {
      raise Invalid("snapshot requires a raw-byte digest for " + file.path)
    }
    ignore(normalized_digests(file.digests, file.path))
    bytes = checked_add(bytes, file.size, "snapshot bytes")
    files[file.path] = true
  }
  guard files.contains("bagit.txt") &&
    value.files.any(f => manifest_name(f.path, false)) else {
    raise Invalid("snapshot requires declaration and payload manifest records")
  }
  let paths = value.directories.copy()
  paths.append(value.files.map(f => f.path))
  for path in paths {
    let mut end = path.length()
    while path[:end].to_owned().rev_find("/") is Some(slash) {
      let parent = path[:slash].to_owned()
      guard dirs.contains(parent) && !files.contains(parent) else {
        raise Invalid("snapshot parent directory is missing: " + parent)
      }
      end = slash
    }
  }
  ignore(render_metadata(value.metadata))
}

///|
/// Full validation always runs first; timestamps are not used as hash substitutes.
pub fn capture_snapshot(
  view : BagView,
  label~ : String = "",
) -> BagSnapshot raise FormatError {
  let report = validate(view)
  guard report.valid else {
    raise Invalid("cannot snapshot an invalid or incomplete bag")
  }
  let declaration = parse_declaration(view.texts["bagit.txt"])
  let files = view.files.map(f => FileRecord::{
    path: f.path,
    size: f.size,
    digests: normalized_digests(f.digests, f.path),
  })
  files.sort_by((a, b) => a.path.lexical_compare(b.path))
  let directories = view.directories.copy()
  directories.sort_by((a, b) => a.lexical_compare(b))
  let metadata = match view.texts.get("bag-info.txt") {
    Some(text) => parse_metadata(text)
    None => []
  }
  let result : BagSnapshot = {
    label,
    bag_version: declaration.version,
    encoding: declaration.encoding,
    directories,
    files,
    metadata,
  }
  validate_snapshot(result)
  result
}

///|
/// The versioned wire schema has exact Int64 decimal strings and ordered arrays.
pub fn snapshot_document(value : BagSnapshot) -> Json raise FormatError {
  validate_snapshot(value)
  let files = value.files.copy()
  files.sort_by((a, b) => a.path.lexical_compare(b.path))
  let directories = value.directories.copy()
  directories.sort_by((a, b) => a.lexical_compare(b))
  {
    "format": "moonbagit-snapshot/1",
    "label": value.label,
    "bag_version": value.bag_version,
    "encoding": value.encoding,
    "directories": Json(directories),
    "files": Json(files.map(record_document)),
    "metadata": Json(value.metadata),
  }
}

///|
pub fn parse_snapshot(document : Json) -> BagSnapshot raise FormatError {
  let keys = [
    "format", "label", "bag_version", "encoding", "directories", "files", "metadata",
  ]
  let fields = document_object(document, keys, keys, "snapshot")
  guard document_text(fields["format"], "snapshot format") ==
    "moonbagit-snapshot/1" else {
    raise Invalid("unsupported snapshot schema")
  }
  let metadata : Array[Metadata] = []
  for item in document_array(fields["metadata"], "snapshot metadata") {
    let field = document_object(
      item,
      ["label", "value"],
      ["label", "value"],
      "metadata",
    )
    metadata.push({
      label: document_text(field["label"], "metadata label"),
      value: document_text(field["value"], "metadata value"),
    })
  }
  let files : Array[FileRecord] = []
  for item in document_array(fields["files"], "snapshot files") {
    files.push(document_record(item))
  }
  files.sort_by((a, b) => a.path.lexical_compare(b.path))
  let directories = document_strings(
    fields["directories"],
    "snapshot directories",
  )
  directories.sort_by((a, b) => a.lexical_compare(b))
  let result : BagSnapshot = {
    label: document_text(fields["label"], "snapshot label"),
    bag_version: document_text(fields["bag_version"], "snapshot bag version"),
    encoding: document_text(fields["encoding"], "snapshot encoding"),
    files,
    directories,
    metadata,
  }
  validate_snapshot(result)
  result
}

///|
pub(all) struct FileChange {
  path : String
  kind : String
  payload : Bool
  before_size : Int64?
  after_size : Int64?
  compared_algorithms : Array[String]
  added_algorithms : Array[String]
  removed_algorithms : Array[String]
} derive(ToJson)

///|
pub extend FileChange with ToJson::{to_json}

///|
pub(all) struct MetadataChange {
  label : String
  before_values : Array[String]
  after_values : Array[String]
} derive(ToJson)

///|
pub extend MetadataChange with ToJson::{to_json}

///|
pub(all) struct SnapshotDelta {
  byte_identical : Bool
  payload_identical : Bool
  comparable : Bool
  unchanged_files : Int32
  files : Array[FileChange]
  directories_added : Array[String]
  directories_removed : Array[String]
  metadata : Array[MetadataChange]
  declaration_changed : Bool
} derive(ToJson)

///|
pub extend SnapshotDelta with ToJson::{to_json}

///|
fn digest_names_difference(
  left : Map[String, String],
  right : Map[String, String],
) -> Array[String] {
  sorted_map_keys(left).filter(name => !right.contains(name))
}

///|
fn compare_records(before : FileRecord?, after : FileRecord?) -> FileChange {
  match (before, after) {
    (Some(a), Some(b)) => {
      let common = sorted_map_keys(a.digests).filter(n => b.digests.contains(n))
      let differs = common.any(n => {
        a.digests[n][:].to_lower().to_owned() !=
        b.digests[n][:].to_lower().to_owned()
      })
      let kind = if a.size != b.size || differs {
        "modified"
      } else if common.is_empty() {
        "unverifiable"
      } else {
        "unchanged"
      }
      {
        path: a.path,
        kind,
        payload: a.path.has_prefix("data/"),
        before_size: Some(a.size),
        after_size: Some(b.size),
        compared_algorithms: common,
        added_algorithms: digest_names_difference(b.digests, a.digests),
        removed_algorithms: digest_names_difference(a.digests, b.digests),
      }
    }
    (Some(a), None) =>
      {
        path: a.path,
        kind: "removed",
        payload: a.path.has_prefix("data/"),
        before_size: Some(a.size),
        after_size: None,
        compared_algorithms: [],
        added_algorithms: [],
        removed_algorithms: sorted_map_keys(a.digests),
      }
    (None, Some(b)) =>
      {
        path: b.path,
        kind: "added",
        payload: b.path.has_prefix("data/"),
        before_size: None,
        after_size: Some(b.size),
        compared_algorithms: [],
        added_algorithms: sorted_map_keys(b.digests),
        removed_algorithms: [],
      }
    (None, None) => abort("comparison requires at least one record")
  }
}

///|
fn metadata_groups(values : Array[Metadata]) -> Map[String, Array[String]] {
  let groups : Map[String, Array[String]] = Map([])
  for item in values {
    let key = item.label[:].to_lower().to_owned()
    match groups.get(key) {
      Some(group) => group.push(item.value)
      None => groups[key] = [item.value]
    }
  }
  groups
}

///|
fn compare_metadata(
  before : Array[Metadata],
  after : Array[Metadata],
) -> Array[MetadataChange] {
  let left = metadata_groups(before)
  let right = metadata_groups(after)
  let names : Map[String, Bool] = Map([])
  for key in left.keys() {
    names[key] = true
  }
  for key in right.keys() {
    names[key] = true
  }
  let changes : Array[MetadataChange] = []
  for label in sorted_map_keys(names) {
    let before_values = left.get(label).unwrap_or([])
    let after_values = right.get(label).unwrap_or([])
    if before_values != after_values {
      changes.push({ label, before_values, after_values, })
    }
  }
  changes
}

///|
/// Matching size without a common digest is explicitly not proof of equality.
pub fn compare_snapshots(
  before : BagSnapshot,
  after : BagSnapshot,
) -> SnapshotDelta raise FormatError {
  validate_snapshot(before)
  validate_snapshot(after)
  let left : Map[String, FileRecord] = Map([])
  let right : Map[String, FileRecord] = Map([])
  let names : Map[String, Bool] = Map([])
  for file in before.files {
    left[file.path] = file
    names[file.path] = true
  }
  for file in after.files {
    right[file.path] = file
    names[file.path] = true
  }
  let changes : Array[FileChange] = []
  let mut unchanged_files = 0
  let mut payload_identical = true
  let mut comparable = true
  let mut byte_identical = true
  for path in sorted_map_keys(names) {
    let change = compare_records(left.get(path), right.get(path))
    if change.kind == "unchanged" {
      unchanged_files = unchanged_files + 1
    } else {
      byte_identical = false
      if change.payload {
        payload_identical = false
      }
      if change.kind == "unverifiable" {
        comparable = false
      }
    }
    if change.kind != "unchanged" ||
      !change.added_algorithms.is_empty() ||
      !change.removed_algorithms.is_empty() {
      changes.push(change)
    }
  }
  let dirs_left : Map[String, Bool] = Map([])
  let dirs_right : Map[String, Bool] = Map([])
  for path in before.directories {
    dirs_left[path] = true
  }
  for path in after.directories {
    dirs_right[path] = true
  }
  let directories_added = sorted_map_keys(dirs_right).filter(p => {
    !dirs_left.contains(p)
  })
  let directories_removed = sorted_map_keys(dirs_left).filter(p => {
    !dirs_right.contains(p)
  })
  let declaration_changed = before.bag_version != after.bag_version ||
    before.encoding != after.encoding
  let metadata = compare_metadata(before.metadata, after.metadata)
  {
    byte_identical: byte_identical &&
    directories_added.is_empty() &&
    directories_removed.is_empty() &&
    !declaration_changed &&
    metadata.is_empty(),
    payload_identical: payload_identical &&
    !directories_added.any(p => p == "data" || p.has_prefix("data/")) &&
    !directories_removed.any(p => p == "data" || p.has_prefix("data/")),
    comparable,
    unchanged_files,
    files: changes,
    directories_added,
    directories_removed,
    metadata,
    declaration_changed,
  }
}
