///|
pub(all) struct MetadataRule {
  label : String
  required : Bool
  repeatable : Bool
  values : Array[String]
} derive(@debug.Debug)

///|
pub(all) struct Profile {
  identifier : String
  version : String
  metadata : Array[MetadataRule]
  manifests_required : Array[String]
  manifests_allowed : Array[String]?
  tag_manifests_required : Array[String]
  tag_manifests_allowed : Array[String]?
  allow_fetch : Bool
  require_fetch : Bool
  data_empty : Bool
  serialization : String
  accepted_serializations : Array[String]
  bag_versions : Array[String]
  tags_required : Array[String]
  tags_allowed : Array[String]
  payload_required : Array[String]
  payload_allowed : Array[String]
} derive(@debug.Debug)

///|
pub(all) struct ProfileReport {
  conforms : Bool
  bag : Report
  diagnostics : Array[Diagnostic]
} derive(@debug.Debug, ToJson)

///|
fn profile_object(json : Json) -> Map[String, Json] raise FormatError {
  match json {
    Object(fields) => fields
    _ => raise Invalid("profile field must be an object")
  }
}

///|
fn profile_keys(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise FormatError {
  for key, _ in fields {
    guard allowed.contains(key) else {
      raise Invalid("unknown profile constraint: " + key)
    }
  }
}

///|
fn profile_string(
  fields : Map[String, Json],
  key : String,
) -> String raise FormatError {
  match fields.get(key) {
    Some(String(value)) if value != "" => value
    _ => raise Invalid("missing or invalid profile string: " + key)
  }
}

///|
fn profile_bool(
  fields : Map[String, Json],
  key : String,
  fallback : Bool,
) -> Bool raise FormatError {
  match fields.get(key) {
    None => fallback
    Some(True) => true
    Some(False) => false
    _ => raise Invalid("profile field must be boolean: " + key)
  }
}

///|
fn profile_strings(
  fields : Map[String, Json],
  key : String,
  fallback : Array[String],
) -> Array[String] raise FormatError {
  match fields.get(key) {
    None => fallback.copy()
    Some(Array(values)) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(text) if text != "" => {
            guard !result.contains(text) else {
              raise Invalid("duplicate profile value: " + key)
            }
            result.push(text)
          }
          _ =>
            raise Invalid("profile field must contain nonempty strings: " + key)
        }
      }
      result
    }
    _ => raise Invalid("profile field must be an array: " + key)
  }
}

///|
/// Only '*' is special. It matches zero or more code units, including '/'.
pub fn profile_path_matches(pattern : String, path : String) -> Bool {
  let mut p = 0
  let mut i = 0
  let mut star = -1
  let mut retry = 0
  while i < path.length() {
    if p < pattern.length() && pattern[p] == path[i] && pattern[p] != '*' {
      p = p + 1
      i = i + 1
    } else if p < pattern.length() && pattern[p] == '*' {
      star = p
      p = p + 1
      retry = i
    } else if star >= 0 {
      retry = retry + 1
      i = retry
      p = star + 1
    } else {
      return false
    }
  }
  while p < pattern.length() && pattern[p] == '*' {
    p = p + 1
  }
  p == pattern.length()
}

///|
fn profile_paths(
  paths : Array[String],
  payload : Bool,
  patterns : Bool,
) -> Unit raise FormatError {
  for path in paths {
    guard patterns || !path.contains("*") else {
      raise Invalid("required paths cannot contain wildcards")
    }
    let cleaned = path.replace(old="*", new="x")
    let cleaned = if cleaned.has_suffix("/") { cleaned + "x" } else { cleaned }
    check_path(cleaned)
    guard !patterns || !path.has_suffix("/") else {
      raise Invalid("allowed directories must end in /*")
    }
    guard payload == path.has_prefix("data/") || (patterns && path == "*") else {
      raise Invalid(
        "profile path is in the wrong payload/tag namespace: " + path,
      )
    }
    guard payload || !path.has_suffix("/") else {
      raise Invalid("required tag must be a file")
    }
  }
}

///|
fn profile_subset(
  required : Array[String],
  allowed : Array[String]?,
  key : String,
) -> Unit raise FormatError {
  if allowed is Some(names) {
    for name in required {
      guard names.contains(name) else {
        raise Invalid(key + " excludes a required algorithm")
      }
    }
  }
}

///|
/// Strict BagIt Profiles 1.4 JSON. Older versions and unknown constraints fail closed.
pub fn parse_profile(json : Json) -> Profile raise FormatError {
  let fields = profile_object(json)
  profile_keys(fields, [
    "BagIt-Profile-Info", "Bag-Info", "Manifests-Required", "Manifests-Allowed",
    "Tag-Manifests-Required", "Tag-Manifests-Allowed", "Allow-Fetch.txt", "Fetch.txt-Required",
    "Data-Empty", "Serialization", "Accept-Serialization", "Accept-BagIt-Version",
    "Tag-Files-Required", "Tag-Files-Allowed", "Payload-Files-Required", "Payload-Files-Allowed",
  ])
  let info = profile_object(
    fields.get("BagIt-Profile-Info").unwrap_or(Json::null()),
  )
  profile_keys(info, [
    "Source-Organization", "External-Description", "Version", "BagIt-Profile-Identifier",
    "BagIt-Profile-Version", "Contact-Name", "Contact-Email", "Contact-Phone",
  ])
  let identifier = profile_string(info, "BagIt-Profile-Identifier")
  let version = profile_string(info, "Version")
  ignore(profile_string(info, "Source-Organization"))
  ignore(profile_string(info, "External-Description"))
  guard profile_string(info, "BagIt-Profile-Version") == "1.4.0" else {
    raise Invalid("only BagIt Profiles 1.4.0 is supported")
  }
  for key in ["Contact-Name", "Contact-Email", "Contact-Phone"] {
    if info.contains(key) {
      ignore(profile_string(info, key))
    }
  }
  let metadata : Array[MetadataRule] = []
  if fields.get("Bag-Info") is Some(value) {
    for label, rule in profile_object(value) {
      ignore(render_metadata([{ label, value: "check" }]))
      let rule = profile_object(rule)
      profile_keys(rule, ["required", "repeatable", "values", "description"])
      if rule.contains("description") {
        ignore(profile_string(rule, "description"))
      }
      metadata.push({
        label,
        required: profile_bool(rule, "required", false),
        repeatable: profile_bool(rule, "repeatable", true),
        values: profile_strings(rule, "values", []),
      })
    }
  }
  let manifests_required = profile_strings(fields, "Manifests-Required", [])
  let manifests_allowed = if fields.contains("Manifests-Allowed") {
    Some(profile_strings(fields, "Manifests-Allowed", []))
  } else {
    None
  }
  let tag_manifests_required = profile_strings(
    fields,
    "Tag-Manifests-Required",
    [],
  )
  let tag_manifests_allowed = if fields.contains("Tag-Manifests-Allowed") {
    Some(profile_strings(fields, "Tag-Manifests-Allowed", []))
  } else {
    None
  }
  profile_subset(manifests_required, manifests_allowed, "Manifests-Allowed")
  profile_subset(
    tag_manifests_required, tag_manifests_allowed, "Tag-Manifests-Allowed",
  )
  let allow_fetch = profile_bool(fields, "Allow-Fetch.txt", true)
  let require_fetch = profile_bool(fields, "Fetch.txt-Required", false)
  guard allow_fetch || !require_fetch else {
    raise Invalid("required fetch.txt cannot be forbidden")
  }
  let serialization = match fields.get("Serialization") {
    None => "optional"
    Some(String("forbidden" | "required" | "optional" as value)) => value
    _ => raise Invalid("invalid Serialization constraint")
  }
  let accepted_serializations = profile_strings(
    fields,
    "Accept-Serialization",
    [],
  )
  guard serialization == "forbidden" || !accepted_serializations.is_empty() else {
    raise Invalid(
      "Accept-Serialization is required for optional/required serialization",
    )
  }
  let bag_versions = profile_strings(fields, "Accept-BagIt-Version", [])
  guard !bag_versions.is_empty() else {
    raise Invalid("Accept-BagIt-Version must not be empty")
  }
  let tags_required = profile_strings(fields, "Tag-Files-Required", [])
  let tags_allowed = profile_strings(fields, "Tag-Files-Allowed", ["*"])
  let payload_required = profile_strings(fields, "Payload-Files-Required", [])
  let payload_allowed = profile_strings(fields, "Payload-Files-Allowed", ["*"])
  profile_paths(tags_required, false, false)
  profile_paths(tags_allowed, false, true)
  profile_paths(payload_required, true, false)
  profile_paths(payload_allowed, true, true)
  for path in tags_required {
    guard tags_allowed.any(p => profile_path_matches(p, path)) else {
      raise Invalid("required tag is forbidden: " + path)
    }
  }
  for path in payload_required {
    let probe = if path.has_suffix("/") { path + "x" } else { path }
    guard payload_allowed.any(p => profile_path_matches(p, probe)) else {
      raise Invalid("required payload is forbidden: " + path)
    }
  }
  {
    identifier,
    version,
    metadata,
    manifests_required,
    manifests_allowed,
    tag_manifests_required,
    tag_manifests_allowed,
    allow_fetch,
    require_fetch,
    data_empty: profile_bool(fields, "Data-Empty", false),
    serialization,
    accepted_serializations,
    bag_versions,
    tags_required,
    tags_allowed,
    payload_required,
    payload_allowed,
  }
}

///|
fn profile_algorithms(
  diagnostics : Array[Diagnostic],
  files : Array[FileRecord],
  required : Array[String],
  allowed : Array[String]?,
  tag : Bool,
) -> Unit {
  let prefix = if tag { "tagmanifest-" } else { "manifest-" }
  for name in required {
    let path = prefix + name + ".txt"
    if !files.any(f => f.path == path) {
      issue(
        diagnostics, "profile_manifest_required", path, "required by profile",
      )
    }
  }
  if allowed is Some(names) {
    for file in files {
      if manifest_name(file.path, tag) &&
        !names.any(n => file.path == prefix + n + ".txt") {
        issue(
          diagnostics,
          "profile_manifest_forbidden",
          file.path,
          "algorithm is not allowed by profile",
        )
      }
    }
  }
}

///|
/// Validates a directory bag and receiving rules; no profile URL or payload is fetched.
pub fn validate_profile(view : BagView, profile : Profile) -> ProfileReport {
  let bag = validate(view)
  let diagnostics : Array[Diagnostic] = []
  if profile.serialization == "required" {
    issue(
      diagnostics, "profile_serialization", "", "profile requires a serialized bag; input is a directory",
    )
  }
  match view.texts.get("bagit.txt") {
    Some(text) => {
      let declaration = parse_declaration(text) catch {
        Invalid(_) => { version: "", encoding: "" }
      }
      if !profile.bag_versions.contains(declaration.version) {
        issue(
          diagnostics, "profile_version", "bagit.txt", "version is not accepted by profile",
        )
      }
    }
    None =>
      issue(
        diagnostics, "profile_version", "bagit.txt", "declaration is unavailable",
      )
  }
  let metadata = match view.texts.get("bag-info.txt") {
    Some(text) => parse_metadata(text) catch { Invalid(_) => [] }
    None => []
  }
  let identifiers = metadata.filter(m => {
    m.label[:].to_lower().to_owned() == "bagit-profile-identifier"
  })
  if !identifiers.any(m => m.value == profile.identifier) {
    issue(
      diagnostics, "profile_identifier", "bag-info.txt", "matching BagIt-Profile-Identifier is required",
    )
  }
  for rule in profile.metadata {
    let label = rule.label[:].to_lower().to_owned()
    let entries = metadata.filter(m => m.label[:].to_lower().to_owned() == label)
    if rule.required && entries.is_empty() {
      issue(
        diagnostics,
        "profile_metadata_required",
        "bag-info.txt",
        rule.label + " is required",
      )
    }
    if !rule.repeatable && entries.length() > 1 {
      issue(
        diagnostics,
        "profile_metadata_repeat",
        "bag-info.txt",
        rule.label + " must not repeat",
      )
    }
    for entry in entries {
      if !rule.values.is_empty() && !rule.values.contains(entry.value) {
        issue(
          diagnostics,
          "profile_metadata_value",
          "bag-info.txt",
          rule.label + " has a disallowed value",
        )
      }
    }
  }
  profile_algorithms(
    diagnostics,
    view.files,
    profile.manifests_required,
    profile.manifests_allowed,
    false,
  )
  profile_algorithms(
    diagnostics,
    view.files,
    profile.tag_manifests_required,
    profile.tag_manifests_allowed,
    true,
  )
  let fetch = view.files.any(f => f.path == "fetch.txt")
  if !profile.allow_fetch && fetch {
    issue(
      diagnostics, "profile_fetch_forbidden", "fetch.txt", "fetch.txt is forbidden",
    )
  }
  if profile.require_fetch && !fetch {
    issue(
      diagnostics, "profile_fetch_required", "fetch.txt", "fetch.txt is required",
    )
  }
  let payload = view.files.filter(f => f.path.has_prefix("data/"))
  if profile.data_empty &&
    !(payload.is_empty() || (payload.length() == 1 && payload[0].size == 0L)) {
    issue(
      diagnostics, "profile_data_empty", "data", "profile requires zero files or one empty file",
    )
  }
  for path in profile.tags_required {
    if !view.files.any(f => f.path == path) {
      issue(
        diagnostics, "profile_tag_required", path, "required tag is missing",
      )
    }
  }
  for path in profile.payload_required {
    let present = if path.has_suffix("/") {
      payload.any(f => f.path.has_prefix(path)) ||
      view.directories.any(d => d.has_prefix(path))
    } else {
      payload.any(f => f.path == path)
    }
    if !present {
      issue(
        diagnostics, "profile_payload_required", path, "required payload file or nonempty directory is missing",
      )
    }
  }
  for file in view.files {
    let patterns = if file.path.has_prefix("data/") {
      profile.payload_allowed
    } else {
      profile.tags_allowed
    }
    if !patterns.any(p => profile_path_matches(p, file.path)) {
      issue(
        diagnostics,
        "profile_path_forbidden",
        file.path,
        "path is not allowed by profile",
      )
    }
  }
  { conforms: bag.valid && diagnostics.is_empty(), bag, diagnostics }
}
