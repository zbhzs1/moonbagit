///|
fn sorted_records(files : Array[FileRecord]) -> Array[FileRecord] {
  let sorted = files.copy()
  sorted.sort_by((a, b) => a.path.compare(b.path))
  sorted
}

///|
fn checked_algorithms(algorithms : Array[Algorithm]) -> Unit raise FormatError {
  guard algorithms.length() > 0 else {
    raise Invalid("at least one algorithm required")
  }
  for i in 0..<algorithms.length() {
    for j in 0..<i {
      guard algorithms[i] != algorithms[j] else {
        raise Invalid("duplicate algorithm")
      }
    }
  }
}

///|
fn record_entries(
  files : Array[FileRecord],
  alg : Algorithm,
) -> Array[Entry] raise FormatError {
  let entries : Array[Entry] = []
  let seen : Map[String, Bool] = Map([])
  for file in sorted_records(files) {
    check_path(file.path)
    guard file.size >= 0 else { raise Invalid("negative file size") }
    guard !seen.contains(file.path) else {
      raise Invalid("duplicate file record")
    }
    seen[file.path] = true
    guard file.digests.get(alg.name()) is Some(checksum) &&
      valid_checksum(checksum, alg) else {
      raise Invalid("missing or malformed digest: " + file.path)
    }
    entries.push({
      path: file.path,
      checksum: checksum[:].to_lower().to_owned(),
    })
  }
  entries
}

///|
pub fn payload_oxum(files : Array[FileRecord]) -> String raise FormatError {
  let mut bytes = 0L
  for file in files {
    guard file.size >= 0 && bytes <= 9223372036854775807L - file.size else {
      raise Invalid("payload byte count overflows Int64")
    }
    bytes = bytes + file.size
  }
  "\{bytes}.\{files.length()}"
}

///|
/// Returns initial tag text; callers then hash these bytes to build tag manifests.
pub fn create_tags(
  payload : Array[FileRecord],
  metadata~ : Array[Metadata] = [],
  algorithms~ : Array[Algorithm] = [Sha512],
) -> Map[String, String] raise FormatError {
  checked_algorithms(algorithms)
  for file in payload {
    guard file.path.has_prefix("data/") else {
      raise Invalid("payload paths must start with data/")
    }
  }
  let tags : Map[String, String] = Map([])
  tags["bagit.txt"] = "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n"
  let fields = metadata.copy()
  guard !fields.any(f => f.label[:].to_lower().to_owned() == "payload-oxum") else {
    raise Invalid("Payload-Oxum is computed, not supplied by the caller")
  }
  fields.push({ label: "Payload-Oxum", value: payload_oxum(payload), })
  tags["bag-info.txt"] = render_metadata(fields)
  for alg in algorithms {
    tags["manifest-" + alg.name() + ".txt"] = render_manifest(
      record_entries(payload, alg),
    )
  }
  tags
}

///|
pub fn create_tag_manifests(
  tags : Array[FileRecord],
  algorithms~ : Array[Algorithm] = [Sha512],
) -> Map[String, String] raise FormatError {
  checked_algorithms(algorithms)
  for file in tags {
    guard !file.path.has_prefix("data/") && file.path != "data" else {
      raise Invalid("tag record is payload")
    }
    guard !(file.path.has_prefix("tagmanifest-") &&
      file.path.has_suffix(".txt") &&
      !file.path.contains("/")) else {
      raise Invalid("tag manifests cannot hash themselves")
    }
  }
  guard tags.any(f => {
    f.path.has_prefix("manifest-") &&
    f.path.has_suffix(".txt") &&
    !f.path.contains("/")
  }) else {
    raise Invalid("tag manifests must include payload manifests")
  }
  let result : Map[String, String] = Map([])
  for alg in algorithms {
    result["tagmanifest-" + alg.name() + ".txt"] = render_manifest(
      record_entries(tags, alg),
    )
  }
  result
}
