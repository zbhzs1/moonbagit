///|
pub(all) struct ChecksumEvidence {
  manifest : String
  algorithm : String
  expected : String
  observed : String?
  status : String
} derive(ToJson)

///|
pub extend ChecksumEvidence with ToJson::{to_json}

///|
pub(all) struct FileAudit {
  path : String
  payload : Bool
  present : Bool
  size : Int64?
  checksums : Array[ChecksumEvidence]
  integrity_verified : Bool
} derive(ToJson)

///|
pub extend FileAudit with ToJson::{to_json}

///|
pub(all) struct AuditSummary {
  manifest_count : Int32
  expected_files : Int32
  missing_files : Int32
  mismatched_checksums : Int32
  unavailable_checksums : Int32
  unprotected_tags : Int32
  pending_fetches : Int32
  verified_algorithms : Array[String]
} derive(ToJson)

///|
pub extend AuditSummary with ToJson::{to_json}

///|
pub(all) struct BagAudit {
  report : Report
  summary : AuditSummary
  files : Array[FileAudit]
  located_diagnostics : Array[LocatedDiagnostic]
} derive(ToJson)

///|
pub extend BagAudit with ToJson::{to_json}

///|
fn[T] sorted_map_keys(values : Map[String, T]) -> Array[String] {
  let keys = values.keys().collect()
  keys.sort_by((a, b) => a.lexical_compare(b))
  keys
}

///|
fn evidence_status(
  expected : String,
  observed : String?,
  alg : Algorithm,
  present : Bool,
) -> String {
  if !present {
    return "missing"
  }
  match observed {
    Some(value) if valid_checksum(value, alg) =>
      if value[:].to_lower().to_owned() == expected {
        "verified"
      } else {
        "mismatch"
      }
    _ => "unavailable"
  }
}

///|
/// A deterministic per-file explanation in addition to the authoritative report.
pub fn audit_bag(view : BagView) -> BagAudit {
  let report = validate(view)
  let inventory : Map[String, FileRecord] = Map([])
  let paths : Map[String, Bool] = Map([])
  let expected : Map[String, Array[ChecksumEvidence]] = Map([])
  let located : Array[LocatedDiagnostic] = []
  let algorithms : Map[String, Bool] = Map([])
  let mut manifest_count = 0
  for file in view.files {
    inventory[file.path] = file
    paths[file.path] = true
  }
  let names = view.files
    .filter(f => manifest_name(f.path, false) || manifest_name(f.path, true))
    .map(f => f.path)
  names.sort_by((a, b) => a.lexical_compare(b))
  for name in names {
    if view.texts.get(name) is Some(text) {
      let inspection = inspect_manifest(name, text)
      located.append(inspection.diagnostics)
      // Do not credit a partially parsed or duplicate-containing manifest.
      if !inspection.diagnostics.is_empty() {
        continue
      }
      let manifest = parse_manifest(name, text) catch { Invalid(_) => continue }
      manifest_count = manifest_count + 1
      for entry in manifest.entries {
        paths[entry.path] = true
        let record = inventory.get(entry.path)
        let observed = match record {
          Some(file) => file.digests.get(manifest.algorithm.name())
          None => None
        }
        let status = evidence_status(
          entry.checksum,
          observed,
          manifest.algorithm,
          record is Some(_),
        )
        if status == "verified" {
          algorithms[manifest.algorithm.name()] = true
        }
        let evidence : ChecksumEvidence = {
          manifest: name,
          algorithm: manifest.algorithm.name(),
          expected: entry.checksum,
          observed,
          status,
        }
        match expected.get(entry.path) {
          Some(items) => items.push(evidence)
          None => expected[entry.path] = [evidence]
        }
      }
    } else {
      located.push({
        path: name,
        line: 0,
        code: "manifest_text",
        message: "manifest text is unavailable",
      })
    }
  }
  let files : Array[FileAudit] = []
  let mut missing_files = 0
  let mut mismatched_checksums = 0
  let mut unavailable_checksums = 0
  let mut unprotected_tags = 0
  for path in sorted_map_keys(paths) {
    let present = inventory.contains(path)
    let payload = path.has_prefix("data/")
    let checksums = expected.get(path).unwrap_or([])
    let integrity_verified = !checksums.is_empty() &&
      checksums.all(e => e.status == "verified")
    if !present {
      missing_files = missing_files + 1
    }
    for check in checksums {
      if check.status == "mismatch" {
        mismatched_checksums = mismatched_checksums + 1
      }
      if check.status == "unavailable" {
        unavailable_checksums = unavailable_checksums + 1
      }
    }
    if !payload && !manifest_name(path, true) && !integrity_verified {
      unprotected_tags = unprotected_tags + 1
    }
    files.push({
      path,
      payload,
      present,
      size: inventory.get(path).map(f => f.size),
      checksums,
      integrity_verified,
    })
  }
  let pending_fetches = match view.texts.get("fetch.txt") {
    Some(text) => {
      let fetch = parse_fetch(text) catch { Invalid(_) => [] }
      fetch.filter(e => !inventory.contains(e.path)).length()
    }
    None => 0
  }
  {
    report,
    summary: {
      manifest_count,
      expected_files: expected.length(),
      missing_files,
      mismatched_checksums,
      unavailable_checksums,
      unprotected_tags,
      pending_fetches,
      verified_algorithms: sorted_map_keys(algorithms),
    },
    files,
    located_diagnostics: located,
  }
}

///|
pub(all) struct DiagnosticGroup {
  code : String
  errors : Int32
  warnings : Int32
  paths : Array[String]
} derive(ToJson)

///|
pub extend DiagnosticGroup with ToJson::{to_json}

///|
pub fn group_diagnostics(items : Array[Diagnostic]) -> Array[DiagnosticGroup] {
  let groups : Map[String, Array[Diagnostic]] = Map([])
  for item in items {
    match groups.get(item.code) {
      Some(group) => group.push(item)
      None => groups[item.code] = [item]
    }
  }
  let result : Array[DiagnosticGroup] = []
  for code in sorted_map_keys(groups) {
    let group = groups[code]
    let paths : Map[String, Bool] = Map([])
    for item in group {
      paths[item.path] = true
    }
    result.push({
      code,
      errors: group.filter(d => d.severity == Error).length(),
      warnings: group.filter(d => d.severity == Warning).length(),
      paths: sorted_map_keys(paths),
    })
  }
  result
}
