///|
pub(all) struct TransferOptions {
  allowed_schemes : Array[String]
  max_total_bytes : Int64
  max_file_bytes : Int64
  max_batch_bytes : Int64
  max_batch_files : Int32
  unknown_size_reservation : Int64?
}

///|
pub fn transfer_options() -> TransferOptions {
  {
    allowed_schemes: ["https"],
    max_total_bytes: 1073741824L,
    max_file_bytes: 1073741824L,
    max_batch_bytes: 1073741824L,
    max_batch_files: 16,
    unknown_size_reservation: None,
  }
}

///|
pub(all) struct TransferTask {
  path : String
  url : String
  scheme : String
  declared_bytes : Int64?
  reserved_bytes : Int64
  checksums : Map[String, String]
} derive(ToJson)

///|
pub extend TransferTask with ToJson::{to_json}

///|
pub(all) struct TransferBatch {
  number : Int32
  reserved_bytes : Int64
  tasks : Array[TransferTask]
} derive(ToJson)

///|
pub extend TransferBatch with ToJson::{to_json}

///|
pub(all) struct TransferPlan {
  pending_files : Int32
  known_bytes : Int64
  reserved_bytes : Int64
  unknown_sizes : Int32
  directories_to_create : Array[String]
  batches : Array[TransferBatch]
} derive(ToJson)

///|
pub extend TransferPlan with ToJson::{to_json}

///|
fn check_transfer_options(options : TransferOptions) -> Unit raise FormatError {
  guard options.max_total_bytes >= 0L &&
    options.max_file_bytes >= 0L &&
    options.max_batch_bytes >= 0L &&
    options.max_batch_files > 0 else {
    raise Invalid(
      "transfer budgets must be nonnegative and batch count positive",
    )
  }
  if options.unknown_size_reservation is Some(limit) && limit < 0L {
    raise Invalid("unknown-size reservation must be nonnegative")
  }
  guard !options.allowed_schemes.is_empty() else {
    raise Invalid("at least one transfer scheme is required")
  }
  let seen : Map[String, Bool] = Map([])
  for scheme in options.allowed_schemes {
    guard scheme != "" &&
      uri_alpha(scheme[0]) &&
      scheme[:].to_lower().to_owned() == scheme &&
      scheme
      .iter()
      .all(c => uri_alphanumeric(c) || c == '+' || c == '-' || c == '.') &&
      !seen.contains(scheme) else {
      raise Invalid("transfer schemes must be unique lowercase URI schemes")
    }
    seen[scheme] = true
  }
}

///|
fn check_transfer_paths(
  view : BagView,
  pending : Array[FetchEntry],
) -> Array[String] raise FormatError {
  let files : Map[String, Bool] = Map([])
  let directories : Map[String, Bool] = Map([])
  let needed : Map[String, Bool] = Map([])
  for file in view.files {
    files[file.path] = true
  }
  for entry in pending {
    files[entry.path] = true
  }
  for path in view.directories {
    directories[path] = true
  }
  for entry in pending {
    guard !directories.contains(entry.path) else {
      raise Invalid("fetch destination is an existing directory: " + entry.path)
    }
    let mut end = entry.path.length()
    while entry.path[:end].to_owned().rev_find("/") is Some(slash) {
      let parent = entry.path[:slash].to_owned()
      guard !files.contains(parent) else {
        raise Invalid("fetch destination has a file ancestor: " + parent)
      }
      if !directories.contains(parent) {
        needed[parent] = true
      }
      end = slash
    }
  }
  sorted_map_keys(needed)
}

///|
/// Planning never authorizes origins or executes a URI. The host enforces real bytes.
pub fn plan_transfer(
  view : BagView,
  options : TransferOptions,
) -> TransferPlan raise FormatError {
  check_transfer_options(options)
  let pending = plan_fetch(view)
  pending.sort_by((a, b) => a.path.lexical_compare(b.path))
  let directories_to_create = check_transfer_paths(view, pending)
  let audit = audit_bag(view)
  let checks : Map[String, Array[ChecksumEvidence]] = Map([])
  for file in audit.files {
    if file.payload {
      checks[file.path] = file.checksums
    }
  }
  let tasks : Array[TransferTask] = []
  let mut known_bytes = 0L
  let mut reserved_bytes = 0L
  let mut unknown_sizes = 0
  for entry in pending {
    let colon = entry.url.find(":").unwrap()
    let scheme = entry.url[:colon].to_owned()[:].to_lower().to_owned()
    guard options.allowed_schemes.contains(scheme) else {
      raise Invalid("transfer scheme is not allowed: " + scheme)
    }
    let reserved = match entry.size {
      Some(size) => {
        known_bytes = checked_add(known_bytes, size, "known transfer bytes")
        size
      }
      None => {
        unknown_sizes = unknown_sizes + 1
        guard options.unknown_size_reservation is Some(reservation) else {
          raise Invalid(
            "unknown fetch size requires an explicit reservation: " + entry.path,
          )
        }
        reservation
      }
    }
    guard reserved <= options.max_file_bytes &&
      reserved <= options.max_batch_bytes else {
      raise Invalid(
        "fetch reservation exceeds per-file or per-batch budget: " + entry.path,
      )
    }
    reserved_bytes = checked_add(
      reserved_bytes, reserved, "transfer reservations",
    )
    guard reserved_bytes <= options.max_total_bytes else {
      raise Invalid("transfer reservations exceed total budget")
    }
    let digests : Map[String, String] = Map([])
    for check in checks.get(entry.path).unwrap_or([]) {
      if digests.get(check.algorithm) is Some(previous) &&
        previous != check.expected {
        raise Invalid("conflicting fetch checksum expectations: " + entry.path)
      }
      digests[check.algorithm] = check.expected
    }
    guard !digests.is_empty() else {
      raise Invalid(
        "fetch destination has no checksum expectations: " + entry.path,
      )
    }
    tasks.push({
      path: entry.path,
      url: entry.url,
      scheme,
      declared_bytes: entry.size,
      reserved_bytes: reserved,
      checksums: digests,
    })
  }
  let batches : Array[TransferBatch] = []
  let mut current : Array[TransferTask] = []
  let mut batch_bytes = 0L
  for task in tasks {
    if !current.is_empty() &&
      (
        current.length() == options.max_batch_files ||
        task.reserved_bytes > options.max_batch_bytes - batch_bytes
      ) {
      batches.push({
        number: batches.length() + 1,
        reserved_bytes: batch_bytes,
        tasks: current,
      })
      current = []
      batch_bytes = 0L
    }
    batch_bytes = checked_add(
      batch_bytes,
      task.reserved_bytes,
      "batch reservations",
    )
    current.push(task)
  }
  if !current.is_empty() {
    batches.push({
      number: batches.length() + 1,
      reserved_bytes: batch_bytes,
      tasks: current,
    })
  }
  {
    pending_files: pending.length(),
    known_bytes,
    reserved_bytes,
    unknown_sizes,
    directories_to_create,
    batches,
  }
}

///|
pub fn parse_transfer_options(
  document : Json,
) -> TransferOptions raise FormatError {
  let keys = [
    "format", "allowed_schemes", "max_total_bytes", "max_file_bytes", "max_batch_bytes",
    "max_batch_files", "unknown_size_reservation",
  ]
  let fields = document_object(document, keys, ["format"], "transfer options")
  guard document_text(fields["format"], "transfer format") ==
    "moonbagit-transfer-options/1" else {
    raise Invalid("unsupported transfer options schema")
  }
  let defaults = transfer_options()
  let allowed_schemes = match fields.get("allowed_schemes") {
    Some(value) => document_strings(value, "allowed schemes")
    None => defaults.allowed_schemes
  }
  let max_batch_files = match policy_limit(fields, "max_batch_files") {
    Some(value) => {
      guard value > 0L && value <= 2147483647L else {
        raise Invalid("max_batch_files must be a positive Int32 decimal string")
      }
      value.to_int()
    }
    None => defaults.max_batch_files
  }
  let result : TransferOptions = {
    allowed_schemes,
    max_total_bytes: policy_limit(fields, "max_total_bytes").unwrap_or(
      defaults.max_total_bytes,
    ),
    max_file_bytes: policy_limit(fields, "max_file_bytes").unwrap_or(
      defaults.max_file_bytes,
    ),
    max_batch_bytes: policy_limit(fields, "max_batch_bytes").unwrap_or(
      defaults.max_batch_bytes,
    ),
    max_batch_files,
    unknown_size_reservation: policy_limit(fields, "unknown_size_reservation"),
  }
  check_transfer_options(result)
  result
}
