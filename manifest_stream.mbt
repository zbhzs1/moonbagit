///|
/// Incremental decoded-text input. Limits are caller policy, not BagIt rules.
pub struct ManifestReader {
  name : String
  alg : Algorithm
  tag : Bool
  max_line_units : Int32?
  max_entries : Int32?
  entries : Array[Entry]
  seen : Map[String, Bool]
  mut buffer : StringBuilder
  mut buffer_units : Int32
  mut line : Int32
  mut after_cr : Bool
  mut finished : Bool
  mut failure : String?
}

///|
pub fn manifest_reader(
  name : String,
  max_line_units? : Int32,
  max_entries? : Int32,
) -> ManifestReader raise FormatError {
  let header = parse_manifest(name, "")
  for limit in [max_line_units, max_entries] {
    if limit is Some(value) && value < 1 {
      raise Invalid("manifest reader limits must be positive")
    }
  }
  {
    name,
    alg: header.algorithm,
    tag: header.tag,
    max_line_units,
    max_entries,
    entries: [],
    seen: Map([]),
    buffer: StringBuilder(),
    buffer_units: 0,
    line: 1,
    after_cr: false,
    finished: false,
    failure: None,
  }
}

///|
fn ManifestReader::ensure_open(self : ManifestReader) -> Unit raise FormatError {
  if self.failure is Some(message) {
    raise Invalid(message)
  }
  guard !self.finished else {
    raise Invalid("manifest reader is already finalized")
  }
}

///|
fn ManifestReader::fail(
  self : ManifestReader,
  message : String,
) -> Unit raise FormatError {
  let message = self.name + ":" + self.line.to_string() + ": " + message
  self.failure = Some(message)
  raise Invalid(message)
}

///|
fn ManifestReader::append_part(
  self : ManifestReader,
  part : String,
) -> Unit raise FormatError {
  if self.max_line_units is Some(limit) &&
    part.length() > limit - self.buffer_units {
    self.fail("decoded line exceeds caller limit")
  }
  self.buffer.write_string(part)
  self.buffer_units = self.buffer_units + part.length()
}

///|
fn ManifestReader::emit(self : ManifestReader) -> Unit raise FormatError {
  if self.max_entries is Some(limit) && self.entries.length() >= limit {
    self.fail("manifest entry count exceeds caller limit")
  }
  let parsed = parse_manifest(self.name, self.buffer.to_string() + "\n") catch {
    Invalid(message) => {
      self.fail(message)
      abort("unreachable")
    }
  }
  let entry = parsed.entries[0]
  if self.seen.contains(entry.path) {
    self.fail("duplicate manifest path: " + entry.path)
  }
  self.seen[entry.path] = true
  self.entries.push(entry)
  self.buffer = StringBuilder()
  self.buffer_units = 0
  self.line = self.line + 1
}

///|
/// Feed well-formed decoded chunks; a CRLF may straddle two chunks.
pub fn ManifestReader::feed(
  self : ManifestReader,
  chunk : String,
) -> Unit raise FormatError {
  self.ensure_open()
  let mut start = 0
  let mut i = 0
  while i < chunk.length() {
    if self.after_cr {
      self.after_cr = false
      if chunk[i] == '\n' {
        i = i + 1
        start = i
        continue
      }
    }
    if chunk[i] == '\r' || chunk[i] == '\n' {
      self.append_part(chunk[start:i].to_owned())
      self.emit()
      self.after_cr = chunk[i] == '\r'
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  self.append_part(chunk[start:].to_owned())
}

///|
pub fn ManifestReader::finish(
  self : ManifestReader,
) -> Manifest raise FormatError {
  self.ensure_open()
  if self.buffer_units != 0 {
    self.emit()
  }
  self.finished = true
  {
    name: self.name,
    algorithm: self.alg,
    tag: self.tag,
    entries: self.entries.copy(),
  }
}

///|
pub(all) struct LocatedDiagnostic {
  path : String
  line : Int32
  code : String
  message : String
} derive(ToJson)

///|
pub extend LocatedDiagnostic with ToJson::{to_json}

///|
pub(all) struct ManifestInspection {
  name : String
  parsed_entries : Array[Entry]
  diagnostics : Array[LocatedDiagnostic]
}

///|
/// Recovery is for diagnostics only; its partial entries never imply validity.
pub fn inspect_manifest(name : String, text : String) -> ManifestInspection {
  let diagnostics : Array[LocatedDiagnostic] = []
  let entries : Array[Entry] = []
  let header_ok = try {
    ignore(parse_manifest(name, ""))
    true
  } catch {
    Invalid(message) => {
      diagnostics.push({ path: name, line: 0, code: "manifest_name", message, })
      false
    }
  }
  if !header_ok {
    return { name, parsed_entries: entries, diagnostics, }
  }
  let rows = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .map(s => s.to_owned())
    .collect()
  if !rows.is_empty() && rows[rows.length() - 1] == "" {
    ignore(rows.pop())
  }
  let seen : Map[String, Int32] = Map([])
  for i in 0..<rows.length() {
    try {
      let parsed = parse_manifest(name, rows[i] + "\n")
      let entry = parsed.entries[0]
      match seen.get(entry.path) {
        Some(first) =>
          diagnostics.push({
            path: name,
            line: i + 1,
            code: "manifest_duplicate",
            message: entry.path + " first appears at line " + first.to_string(),
          })
        None => {
          seen[entry.path] = i + 1
          entries.push(entry)
        }
      }
    } catch {
      Invalid(message) =>
        diagnostics.push({
          path: name,
          line: i + 1,
          code: "manifest_row",
          message,
        })
    }
  }
  { name, parsed_entries: entries, diagnostics, }
}
