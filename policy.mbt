///|
pub(all) struct PathBudget {
  pattern : String
  max_files : Int64?
  max_bytes : Int64?
}

///|
/// Operational receiving policy, deliberately distinct from RFC validity.
pub(all) struct ReceivingPolicy {
  name : String
  payload_algorithms : Array[String]
  tag_algorithms : Array[String]
  forbid_legacy : Bool
  require_tag_protection : Bool
  require_portable : Bool
  allow_empty : Bool
  allow_fetch : Bool
  max_payload_files : Int64?
  max_payload_bytes : Int64?
  max_file_bytes : Int64?
  max_tag_bytes : Int64?
  max_path_depth : Int64?
  max_manifest_entries : Int64?
  path_budgets : Array[PathBudget]
}

///|
pub fn receiving_policy(name : String) -> ReceivingPolicy {
  {
    name,
    payload_algorithms: ["sha512"],
    tag_algorithms: [],
    forbid_legacy: true,
    require_tag_protection: true,
    require_portable: false,
    allow_empty: true,
    allow_fetch: true,
    max_payload_files: None,
    max_payload_bytes: None,
    max_file_bytes: None,
    max_tag_bytes: None,
    max_path_depth: None,
    max_manifest_entries: None,
    path_budgets: [],
  }
}

///|
fn policy_limit(
  fields : Map[String, Json],
  name : String,
) -> Int64? raise FormatError {
  match fields.get(name) {
    None | Some(Null) => None
    Some(value) => Some(document_count(value, name))
  }
}

///|
fn policy_switch(
  fields : Map[String, Json],
  name : String,
  fallback : Bool,
) -> Bool raise FormatError {
  match fields.get(name) {
    None => fallback
    Some(value) => document_bool(value, name)
  }
}

///|
fn check_receiving_policy(policy : ReceivingPolicy) -> Unit raise FormatError {
  guard policy.name.trim().to_owned() != "" else {
    raise Invalid("receiving policy name is empty")
  }
  for names in [policy.payload_algorithms, policy.tag_algorithms] {
    let seen : Map[String, Bool] = Map([])
    for name in names {
      let alg = algorithm(name)
      guard !seen.contains(name) else {
        raise Invalid("duplicate receiving algorithm: " + name)
      }
      guard !policy.forbid_legacy || (alg != Md5 && alg != Sha1) else {
        raise Invalid(
          "receiving policy both requires and forbids a legacy digest",
        )
      }
      seen[name] = true
    }
  }
  for
    value in [
      policy.max_payload_files,
      policy.max_payload_bytes,
      policy.max_file_bytes,
      policy.max_tag_bytes,
      policy.max_path_depth,
      policy.max_manifest_entries,
    ] {
    if value is Some(limit) && limit < 0L {
      raise Invalid("receiving limits must not be negative")
    }
  }
  let patterns : Map[String, Bool] = Map([])
  for budget in policy.path_budgets {
    guard budget.pattern != "" && !patterns.contains(budget.pattern) else {
      raise Invalid("empty or duplicate path budget pattern")
    }
    let sample = budget.pattern.replace_all(old="*", new="x")
    check_path(sample)
    guard budget.max_files is Some(_) || budget.max_bytes is Some(_) else {
      raise Invalid("path budget requires at least one limit")
    }
    for value in [budget.max_files, budget.max_bytes] {
      if value is Some(limit) && limit < 0L {
        raise Invalid("path budget limits must not be negative")
      }
    }
    patterns[budget.pattern] = true
  }
}

///|
pub fn parse_receiving_policy(
  document : Json,
) -> ReceivingPolicy raise FormatError {
  let keys = [
    "format", "name", "payload_algorithms", "tag_algorithms", "forbid_legacy", "require_tag_protection",
    "require_portable", "allow_empty", "allow_fetch", "max_payload_files", "max_payload_bytes",
    "max_file_bytes", "max_tag_bytes", "max_path_depth", "max_manifest_entries",
    "path_budgets",
  ]
  let fields = document_object(
    document,
    keys,
    ["format", "name"],
    "receiving policy",
  )
  guard document_text(fields["format"], "policy format") ==
    "moonbagit-receiving-policy/1" else {
    raise Invalid("unsupported receiving policy schema")
  }
  let name = document_text(fields["name"], "policy name")
  let defaults = receiving_policy(name)
  let payload_algorithms = match fields.get("payload_algorithms") {
    Some(value) => document_strings(value, "payload algorithms")
    None => defaults.payload_algorithms
  }
  let tag_algorithms = match fields.get("tag_algorithms") {
    Some(value) => document_strings(value, "tag algorithms")
    None => defaults.tag_algorithms
  }
  let path_budgets : Array[PathBudget] = []
  if fields.get("path_budgets") is Some(value) {
    for item in document_array(value, "path budgets") {
      let budget = document_object(
        item,
        ["pattern", "max_files", "max_bytes"],
        ["pattern"],
        "path budget",
      )
      path_budgets.push({
        pattern: document_text(budget["pattern"], "path pattern"),
        max_files: policy_limit(budget, "max_files"),
        max_bytes: policy_limit(budget, "max_bytes"),
      })
    }
  }
  let policy : ReceivingPolicy = {
    name,
    payload_algorithms,
    tag_algorithms,
    forbid_legacy: policy_switch(
      fields,
      "forbid_legacy",
      defaults.forbid_legacy,
    ),
    require_tag_protection: policy_switch(
      fields,
      "require_tag_protection",
      defaults.require_tag_protection,
    ),
    require_portable: policy_switch(
      fields,
      "require_portable",
      defaults.require_portable,
    ),
    allow_empty: policy_switch(fields, "allow_empty", defaults.allow_empty),
    allow_fetch: policy_switch(fields, "allow_fetch", defaults.allow_fetch),
    max_payload_files: policy_limit(fields, "max_payload_files"),
    max_payload_bytes: policy_limit(fields, "max_payload_bytes"),
    max_file_bytes: policy_limit(fields, "max_file_bytes"),
    max_tag_bytes: policy_limit(fields, "max_tag_bytes"),
    max_path_depth: policy_limit(fields, "max_path_depth"),
    max_manifest_entries: policy_limit(fields, "max_manifest_entries"),
    path_budgets,
  }
  check_receiving_policy(policy)
  policy
}

///|
fn limit_document(value : Int64?) -> Json {
  match value {
    Some(count) => Json(count.to_string())
    None => Json::null()
  }
}

///|
pub fn receiving_policy_document(
  policy : ReceivingPolicy,
) -> Json raise FormatError {
  check_receiving_policy(policy)
  let budgets = policy.path_budgets.map(b => {
    (
      {
        "pattern": b.pattern,
        "max_files": limit_document(b.max_files),
        "max_bytes": limit_document(b.max_bytes),
      } : Json)
  })
  {
    "format": "moonbagit-receiving-policy/1",
    "name": policy.name,
    "payload_algorithms": Json(policy.payload_algorithms),
    "tag_algorithms": Json(policy.tag_algorithms),
    "forbid_legacy": policy.forbid_legacy,
    "require_tag_protection": policy.require_tag_protection,
    "require_portable": policy.require_portable,
    "allow_empty": policy.allow_empty,
    "allow_fetch": policy.allow_fetch,
    "max_payload_files": limit_document(policy.max_payload_files),
    "max_payload_bytes": limit_document(policy.max_payload_bytes),
    "max_file_bytes": limit_document(policy.max_file_bytes),
    "max_tag_bytes": limit_document(policy.max_tag_bytes),
    "max_path_depth": limit_document(policy.max_path_depth),
    "max_manifest_entries": limit_document(policy.max_manifest_entries),
    "path_budgets": Json(budgets),
  }
}

///|
pub(all) struct AcceptanceReport {
  accepted : Bool
  policy : String
  bag : Report
  diagnostics : Array[Diagnostic]
} derive(ToJson)

///|
pub extend AcceptanceReport with ToJson::{to_json}

///|
fn enforce_limit(
  diagnostics : Array[Diagnostic],
  actual : Int64,
  maximum : Int64?,
  code : String,
  path : String,
) -> Unit {
  if maximum is Some(limit) && actual > limit {
    issue(
      diagnostics,
      code,
      path,
      "observed " +
      actual.to_string() +
      "; receiving limit " +
      limit.to_string(),
    )
  }
}

///|
/// Policy failure does not rewrite the RFC-validity result to 'invalid'.
pub fn evaluate_receiving_policy(
  view : BagView,
  policy : ReceivingPolicy,
) -> AcceptanceReport raise FormatError {
  check_receiving_policy(policy)
  let audit = audit_bag(view)
  let diagnostics : Array[Diagnostic] = []
  enforce_limit(
    diagnostics,
    audit.report.payload_files.to_int64(),
    policy.max_payload_files,
    "policy_payload_files",
    "data",
  )
  enforce_limit(
    diagnostics,
    audit.report.payload_bytes,
    policy.max_payload_bytes,
    "policy_payload_bytes",
    "data",
  )
  if !policy.allow_empty && audit.report.payload_files == 0 {
    issue(
      diagnostics, "policy_empty", "data", "receiving policy requires payload files",
    )
  }
  if !policy.allow_fetch && view.files.any(f => f.path == "fetch.txt") {
    issue(
      diagnostics, "policy_fetch", "fetch.txt", "receiving policy forbids fetch.txt",
    )
  }
  let mut tag_bytes = 0L
  for file in view.files {
    if file.path.has_prefix("data/") {
      enforce_limit(
        diagnostics,
        file.size,
        policy.max_file_bytes,
        "policy_file_bytes",
        file.path,
      )
    } else if file.size >= 0L {
      tag_bytes = checked_add(tag_bytes, file.size, "receiving tag bytes") catch {
        Invalid(message) => {
          issue(diagnostics, "policy_tag_bytes_overflow", file.path, message)
          tag_bytes
        }
      }
    }
    let depth = file.path.split("/").count().to_int64()
    enforce_limit(
      diagnostics,
      depth,
      policy.max_path_depth,
      "policy_path_depth",
      file.path,
    )
  }
  enforce_limit(
    diagnostics,
    tag_bytes,
    policy.max_tag_bytes,
    "policy_tag_bytes",
    "",
  )
  for file in audit.files {
    let required = if file.payload {
      policy.payload_algorithms
    } else {
      policy.tag_algorithms
    }
    if !file.payload && manifest_name(file.path, true) {
      continue
    }
    for name in required {
      if !file.checksums.any(c => c.algorithm == name && c.status == "verified") {
        issue(
          diagnostics,
          "policy_required_digest",
          file.path,
          "verified " + name + " manifest coverage is required",
        )
      }
    }
    if policy.require_tag_protection &&
      !file.payload &&
      !file.integrity_verified {
      issue(
        diagnostics,
        "policy_tag_protection",
        file.path,
        "receiving policy requires verified tag-manifest coverage",
      )
    }
  }
  for file in view.files {
    if manifest_name(file.path, false) || manifest_name(file.path, true) {
      if view.texts.get(file.path) is Some(text) {
        let parsed = parse_manifest(file.path, text) catch {
          Invalid(_) => continue
        }
        enforce_limit(
          diagnostics,
          parsed.entries.length().to_int64(),
          policy.max_manifest_entries,
          "policy_manifest_entries",
          file.path,
        )
        if policy.forbid_legacy &&
          (parsed.algorithm == Md5 || parsed.algorithm == Sha1) {
          issue(
            diagnostics,
            "policy_legacy",
            file.path,
            "legacy digest manifests are not accepted by this receiving policy",
          )
        }
      }
    }
  }
  for budget in policy.path_budgets {
    let mut files = 0L
    let mut bytes = 0L
    for file in view.files {
      if profile_path_matches(budget.pattern, file.path) {
        files = files + 1L
        if file.size >= 0L {
          bytes = checked_add(bytes, file.size, "path budget bytes") catch {
            Invalid(message) => {
              issue(
                diagnostics,
                "policy_path_bytes_overflow",
                budget.pattern,
                message,
              )
              bytes
            }
          }
        }
      }
    }
    enforce_limit(
      diagnostics,
      files,
      budget.max_files,
      "policy_path_files",
      budget.pattern,
    )
    enforce_limit(
      diagnostics,
      bytes,
      budget.max_bytes,
      "policy_path_bytes",
      budget.pattern,
    )
  }
  if policy.require_portable {
    for item in lint_portability(view) {
      issue(
        diagnostics,
        "policy_portability",
        item.path,
        item.code + ": " + item.message,
      )
    }
  }
  {
    accepted: audit.report.valid && !diagnostics.any(d => d.severity == Error),
    policy: policy.name,
    bag: audit.report,
    diagnostics,
  }
}
