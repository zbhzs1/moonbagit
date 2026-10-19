///|
fn linear_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
fn linear_unit(c : UInt16) -> Bool {
  c == ' ' || c == '\t'
}

///|
fn lines(text : String) -> Array[String] raise FormatError {
  guard !text.has_prefix("\uFEFF") else {
    raise Invalid("UTF-8 text must not contain a BOM")
  }
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let result = normalized.split("\n").map(v => v.to_owned()).collect()
  if result.length() > 0 && result[result.length() - 1] == "" {
    ignore(result.pop())
  }
  result
}

///|
pub fn parse_declaration(text : String) -> Declaration raise FormatError {
  let rows = lines(text)
  guard rows.length() == 2 else {
    raise Invalid("bagit.txt requires exactly two lines")
  }
  guard rows[0] == "BagIt-Version: 1.0" else {
    raise Invalid("only BagIt-Version: 1.0 is supported")
  }
  guard rows[1].has_prefix("Tag-File-Character-Encoding: ") else {
    raise Invalid("missing or misplaced character encoding declaration")
  }
  let encoding = rows[1][29:].to_owned()
  guard encoding[:].to_upper().to_owned() == "UTF-8" else {
    raise Invalid("only UTF-8 tag files are supported")
  }
  { version: "1.0", encoding: "UTF-8", }
}

///|
pub fn encode_path(path : String) -> String {
  path
  .replace_all(old="%", new="%25")
  .replace_all(old="\r", new="%0D")
  .replace_all(old="\n", new="%0A")
}

///|
pub fn decode_path(path : String) -> String raise FormatError {
  let out = StringBuilder()
  let mut i = 0
  let mut start = 0
  while i < path.length() {
    if path[i] == '%' {
      out.write_string(path[start:i].to_owned())
      guard i + 2 < path.length() else {
        raise Invalid("truncated percent escape")
      }
      let first = path[i + 1]
      let second = path[i + 2]
      if first == '2' && second == '5' {
        out.write_string("%")
      } else if first == '0' && (second == 'D' || second == 'd') {
        out.write_string("\r")
      } else if first == '0' && (second == 'A' || second == 'a') {
        out.write_string("\n")
      } else {
        raise Invalid("only %, CR and LF may be percent encoded")
      }
      i = i + 3
      start = i
    } else {
      i = i + 1
    }
  }
  out.write_string(path[start:].to_owned())
  out.to_string()
}

///|
/// Conservative portable paths also rule out drive letters and UNC separators.
pub fn check_path(path : String) -> Unit raise FormatError {
  guard path != "" && !path.has_prefix("/") else {
    raise Invalid("path must be relative")
  }
  guard !path.contains("\\") && !path.contains(":") && !path.contains("\u0000") else {
    raise Invalid("unsafe or nonportable path")
  }
  for part in path.split("/") {
    guard part != "" && part != "." && part != ".." else {
      raise Invalid("empty, dot and parent path components are forbidden")
    }
  }
}

///|
fn valid_checksum(value : String, alg : Algorithm) -> Bool {
  value.length() == alg.hex_length() &&
  value.iter().all(c => c.is_ascii_hexdigit())
}

///|
pub fn parse_manifest(
  name : String,
  text : String,
) -> Manifest raise FormatError {
  let tag = name.has_prefix("tagmanifest-")
  let prefix = if tag { "tagmanifest-" } else { "manifest-" }
  guard name.has_prefix(prefix) &&
    name.has_suffix(".txt") &&
    !name.contains("/") else {
    raise Invalid("invalid manifest filename")
  }
  let alg = algorithm(name[prefix.length():name.length() - 4].to_owned())
  let entries : Array[Entry] = []
  let seen : Map[String, Bool] = Map([])
  for row in lines(text) {
    guard row.find_by(linear_space) is Some(start) else {
      raise Invalid("manifest separator missing")
    }
    let checksum = row[:start].to_owned()
    guard valid_checksum(checksum, alg) else {
      raise Invalid("invalid checksum length or hexadecimal value")
    }
    let mut end = start
    while end < row.length() && linear_unit(row[end]) {
      end = end + 1
    }
    let path = decode_path(row[end:].to_owned())
    check_path(path)
    if tag {
      guard !path.has_prefix("data/") && path != "data" else {
        raise Invalid("tag manifest references payload")
      }
      guard !(path.has_prefix("tagmanifest-") &&
        path.has_suffix(".txt") &&
        !path.contains("/")) else {
        raise Invalid("tag manifest references a tag manifest")
      }
    } else {
      guard path.has_prefix("data/") else {
        raise Invalid("payload manifest references a tag file")
      }
    }
    guard !seen.contains(path) else {
      raise Invalid("duplicate manifest path: " + path)
    }
    seen[path] = true
    entries.push({ path, checksum: checksum[:].to_lower().to_owned(), })
  }
  { name, algorithm: alg, tag, entries, }
}

///|
pub fn render_manifest(entries : Array[Entry]) -> String raise FormatError {
  let out = StringBuilder()
  let seen : Map[String, Bool] = Map([])
  for entry in entries {
    check_path(entry.path)
    guard (entry.checksum.length() == 64 || entry.checksum.length() == 128) &&
      entry.checksum.iter().all(c => c.is_ascii_hexdigit()) else {
      raise Invalid("manifest writer requires a SHA-256 or SHA-512 hex digest")
    }
    guard !seen.contains(entry.path) else {
      raise Invalid("duplicate manifest path")
    }
    seen[entry.path] = true
    out.write_string(entry.checksum + "  " + encode_path(entry.path) + "\n")
  }
  out.to_string()
}

///|
fn metadata_label(label : String) -> Unit raise FormatError {
  guard label != "" &&
    !label.contains(":") &&
    label.trim(chars=" \t").to_owned() == label &&
    label.iter().all(c => c == '\t' || (c >= '\u0020' && c != '\u007F')) else {
    raise Invalid(
      "metadata label must not contain boundary whitespace, a colon or control characters",
    )
  }
}

///|
fn metadata_value(value : String) -> Unit raise FormatError {
  guard value
    .iter()
    .all(c => c == '\t' || c == '\n' || (c >= '\u0020' && c != '\u007F')) else {
    raise Invalid("metadata value contains a control character")
  }
}

///|
pub fn parse_metadata(text : String) -> Array[Metadata] raise FormatError {
  let result : Array[Metadata] = []
  for row in lines(text) {
    guard row != "" else { raise Invalid("empty metadata line") }
    metadata_value(row)
    if linear_unit(row[0]) {
      guard result.length() > 0 else {
        raise Invalid("metadata continuation without a field")
      }
      let i = result.length() - 1
      let previous = result[i]
      result[i] = {
        label: previous.label,
        value: previous.value + "\n" + row.trim_start(chars=" \t").to_owned(),
      }
    } else {
      guard row.find(":") is Some(colon) else {
        raise Invalid("metadata colon missing")
      }
      let label = row[:colon].to_owned()
      metadata_label(label)
      guard colon + 1 < row.length() && linear_unit(row[colon + 1]) else {
        raise Invalid("metadata requires whitespace after colon")
      }
      result.push({ label, value: row[colon + 2:].to_owned(), })
    }
  }
  result
}

///|
pub fn render_metadata(fields : Array[Metadata]) -> String raise FormatError {
  let out = StringBuilder()
  for field in fields {
    metadata_label(field.label)
    metadata_value(field.value)
    let parts = field.value.split("\n").collect()
    for i in 1..<parts.length() {
      guard parts[i].is_empty() || !linear_unit(parts[i][0]) else {
        raise Invalid(
          "leading continuation whitespace cannot be preserved by BagIt metadata; normalize the value explicitly",
        )
      }
    }
    let value = field.value.replace_all(old="\n", new="\n ")
    out.write_string(field.label + ": " + value + "\n")
  }
  out.to_string()
}

///|
fn take_token(row : String, start : Int) -> (String, Int) {
  let mut i = start
  while i < row.length() && !linear_unit(row[i]) {
    i = i + 1
  }
  let token = row[start:i].to_owned()
  while i < row.length() && linear_unit(row[i]) {
    i = i + 1
  }
  (token, i)
}

///|
fn check_fetch_url(url : String) -> Unit raise FormatError {
  guard url.find(":") is Some(colon) && colon > 0 else {
    raise Invalid("fetch URL must be an absolute URI")
  }
  let scheme = url[:colon].to_owned()
  let first = scheme[0]
  guard ((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')) &&
    scheme
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '+' ||
      c == '-' ||
      c == '.'
    }) else {
    raise Invalid("invalid URI scheme")
  }
  let mut i = colon + 1
  while i < url.length() {
    let c = url[i]
    if c == '%' {
      guard i + 2 < url.length() &&
        url[i + 1:i + 3].to_owned().iter().all(c => c.is_ascii_hexdigit()) else {
        raise Invalid("invalid percent escape in fetch URI")
      }
      i = i + 3
    } else {
      guard (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        "-._~:/?#[]@!$&'()*+,;=".contains(url[i:i + 1].to_owned()) else {
        raise Invalid("fetch URI contains a non-URI character")
      }
      i = i + 1
    }
  }
}

///|
pub fn parse_fetch(text : String) -> Array[FetchEntry] raise FormatError {
  let result : Array[FetchEntry] = []
  let seen : Map[String, Bool] = Map([])
  for row in lines(text) {
    let (url, next) = take_token(row, 0)
    let (length, end) = take_token(row, next)
    check_fetch_url(url)
    let size = if length == "-" {
      None
    } else {
      guard length != "" && length.iter().all(c => c >= '0' && c <= '9') else {
        raise Invalid("invalid fetch size")
      }
      let size = @string.parse_int64(length[:]) catch {
        _ => raise Invalid("fetch size overflows Int64")
      }
      Some(size)
    }
    let path = decode_path(row[end:].to_owned())
    check_path(path)
    guard path.has_prefix("data/") else {
      raise Invalid("fetch entry must be a payload file")
    }
    guard !seen.contains(path) else { raise Invalid("duplicate fetch path") }
    seen[path] = true
    result.push({ url, size, path, })
  }
  result
}

///|
/// Serialize an offline fetch plan; this function never downloads its URIs.
pub fn render_fetch(entries : Array[FetchEntry]) -> String raise FormatError {
  let out = StringBuilder()
  let seen : Map[String, Bool] = Map([])
  for entry in entries {
    check_fetch_url(entry.url)
    check_path(entry.path)
    guard entry.path.has_prefix("data/") else {
      raise Invalid("fetch entry must be a payload file")
    }
    guard !seen.contains(entry.path) else {
      raise Invalid("duplicate fetch path")
    }
    seen[entry.path] = true
    let size = match entry.size {
      None => "-"
      Some(size) => {
        guard size >= 0L else { raise Invalid("negative fetch size") }
        size.to_string()
      }
    }
    out.write_string(
      entry.url + " " + size + " " + encode_path(entry.path) + "\n",
    )
  }
  out.to_string()
}
