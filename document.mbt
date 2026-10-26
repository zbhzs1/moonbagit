///|
fn document_object(
  value : Json,
  allowed : Array[String],
  required : Array[String],
  context : String,
) -> Map[String, Json] raise FormatError {
  guard value is Object(fields) else {
    raise Invalid(context + " must be an object")
  }
  for key in sorted_map_keys(fields) {
    guard allowed.contains(key) else {
      raise Invalid(context + ": unknown field " + key)
    }
  }
  for key in required {
    guard fields.contains(key) else {
      raise Invalid(context + ": missing field " + key)
    }
  }
  fields
}

///|
fn document_text(value : Json, context : String) -> String raise FormatError {
  match value {
    String(text) => text
    _ => raise Invalid(context + " must be a string")
  }
}

///|
fn document_array(
  value : Json,
  context : String,
) -> Array[Json] raise FormatError {
  match value {
    Array(items) => items
    _ => raise Invalid(context + " must be an array")
  }
}

///|
fn document_bool(value : Json, context : String) -> Bool raise FormatError {
  match value {
    True => true
    False => false
    _ => raise Invalid(context + " must be a boolean")
  }
}

///|
/// Decimal strings avoid JSON double rounding above 2^53.
fn document_count(value : Json, context : String) -> Int64 raise FormatError {
  let text = document_text(value, context)
  guard text != "" && uri_digits(text) && (text == "0" || !text.has_prefix("0")) else {
    raise Invalid(context + " must be a canonical nonnegative decimal string")
  }
  @string.parse_int64(text[:]) catch {
    _ => raise Invalid(context + " exceeds Int64 range")
  }
}

///|
fn document_strings(
  value : Json,
  context : String,
  unique~ : Bool = true,
) -> Array[String] raise FormatError {
  let result : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for item in document_array(value, context) {
    let text = document_text(item, context)
    guard !unique || !seen.contains(text) else {
      raise Invalid(context + ": duplicate value " + text)
    }
    seen[text] = true
    result.push(text)
  }
  result
}

///|
fn checked_add(
  a : Int64,
  b : Int64,
  context : String,
) -> Int64 raise FormatError {
  guard a >= 0L && b >= 0L && b <= 9223372036854775807L - a else {
    raise Invalid(context + ": nonnegative Int64 total overflow")
  }
  a + b
}

///|
fn normalized_digests(
  digests : Map[String, String],
  context : String,
) -> Map[String, String] raise FormatError {
  let result : Map[String, String] = Map([])
  for name in sorted_map_keys(digests) {
    let alg = algorithm(name)
    let digest = digests[name]
    guard valid_checksum(digest, alg) else {
      raise Invalid(context + ": invalid " + name + " digest")
    }
    result[name] = digest[:].to_lower().to_owned()
  }
  result
}

///|
fn document_record(value : Json) -> FileRecord raise FormatError {
  let fields = document_object(
    value,
    ["path", "size", "digests"],
    ["path", "size", "digests"],
    "file record",
  )
  let path = document_text(fields["path"], "file path")
  check_path(path)
  let size = document_count(fields["size"], "file size")
  guard fields["digests"] is Object(raw) else {
    raise Invalid("file digests must be an object")
  }
  let digests : Map[String, String] = Map([])
  for name in sorted_map_keys(raw) {
    digests[name] = document_text(raw[name], "digest")
  }
  { path, size, digests: normalized_digests(digests, path), }
}

///|
fn record_document(file : FileRecord) -> Json {
  {
    "path": file.path,
    "size": file.size.to_string(),
    "digests": Json(file.digests),
  }
}
