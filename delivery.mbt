///|
pub(all) enum DeliveryMode {
  ExactCopy
  CompleteFetch
} derive(Eq)

///|
pub extend DeliveryMode with Eq::{equal, not_equal}

///|
pub(all) struct DeliveryReport {
  accepted : Bool
  mode : String
  source : Report
  received : Report
  preserved_files : Int32
  completed_files : Int32
  diagnostics : Array[Diagnostic]
} derive(ToJson)

///|
pub extend DeliveryReport with ToJson::{to_json}

///|
fn delivery_issue(
  diagnostics : Array[Diagnostic],
  code : String,
  path : String,
  message : String,
) -> Unit {
  issue(diagnostics, "delivery_" + code, path, message)
}

///|
fn delivery_record(
  before : FileRecord,
  after : FileRecord,
  diagnostics : Array[Diagnostic],
) -> Bool {
  if before.size != after.size {
    delivery_issue(
      diagnostics,
      "size",
      before.path,
      "previously present file changed byte length",
    )
    return false
  }
  let mut shared_strong = false
  let mut mismatch = false
  for name in sorted_map_keys(before.digests) {
    let alg = algorithm(name) catch { Invalid(_) => continue }
    if after.digests.get(name) is Some(value) {
      if !valid_checksum(before.digests[name], alg) ||
        !valid_checksum(value, alg) {
        delivery_issue(
          diagnostics,
          "digest_format",
          before.path,
          "invalid shared raw-byte digest",
        )
        mismatch = true
        continue
      }
      if alg == Sha256 || alg == Sha512 {
        shared_strong = true
      }
      if before.digests[name][:].to_lower().to_owned() !=
        value[:].to_lower().to_owned() {
        delivery_issue(
          diagnostics,
          "changed",
          before.path,
          "previously present bytes changed according to " + name,
        )
        mismatch = true
      }
    }
  }
  if !shared_strong {
    delivery_issue(
      diagnostics,
      "unverifiable",
      before.path,
      "a shared valid SHA-256 or SHA-512 raw-byte digest is required",
    )
  }
  shared_strong && !mismatch
}

///|
/// Verify a read-only handoff. This does not authenticate the sender or sign a receipt.
pub fn verify_delivery(
  source : BagView,
  received : BagView,
  mode : DeliveryMode,
) -> DeliveryReport {
  let before = validate(source)
  let after = validate(received)
  let diagnostics : Array[Diagnostic] = []
  let expected_new : Map[String, FetchEntry] = Map([])
  if mode == ExactCopy {
    if !before.valid {
      delivery_issue(
        diagnostics, "source_invalid", "", "exact copy requires a fully valid source bag",
      )
    }
  } else {
    try {
      let pending = plan_fetch(source)
      ignore(check_transfer_paths(source, pending))
      for entry in pending {
        expected_new[entry.path] = entry
      }
    } catch {
      Invalid(message) =>
        delivery_issue(diagnostics, "source_invalid", "", message)
    }
  }
  if !after.valid {
    delivery_issue(
      diagnostics, "received_invalid", "", "received bag failed full validation",
    )
  }
  let source_files : Map[String, FileRecord] = Map([])
  let target_files : Map[String, FileRecord] = Map([])
  for file in source.files {
    source_files[file.path] = file
  }
  for file in received.files {
    target_files[file.path] = file
  }
  let mut preserved_files = 0
  for path in sorted_map_keys(source_files) {
    match target_files.get(path) {
      None =>
        delivery_issue(
          diagnostics, "missing", path, "previously present file was removed",
        )
      Some(file) =>
        if delivery_record(source_files[path], file, diagnostics) {
          preserved_files = preserved_files + 1
        }
    }
  }
  let mut completed_files = 0
  for path in sorted_map_keys(target_files) {
    if source_files.contains(path) {
      continue
    }
    match expected_new.get(path) {
      None =>
        delivery_issue(
          diagnostics, "unexpected", path, "new file is not a declared pending fetch destination",
        )
      Some(entry) =>
        if entry.size is Some(size) && size != target_files[path].size {
          delivery_issue(
            diagnostics, "fetch_size", path, "completed file does not match the declared fetch length",
          )
        } else {
          completed_files = completed_files + 1
        }
    }
  }
  for path in sorted_map_keys(expected_new) {
    if !target_files.contains(path) {
      delivery_issue(
        diagnostics, "fetch_missing", path, "declared pending file remains missing",
      )
    }
  }
  let source_dirs : Map[String, Bool] = Map([])
  let target_dirs : Map[String, Bool] = Map([])
  let allowed_new_dirs : Map[String, Bool] = Map([])
  for path in source.directories {
    source_dirs[path] = true
  }
  for path in received.directories {
    target_dirs[path] = true
  }
  for path in sorted_map_keys(expected_new) {
    let mut end = path.length()
    while path[:end].to_owned().rev_find("/") is Some(slash) {
      allowed_new_dirs[path[:slash].to_owned()] = true
      end = slash
    }
  }
  for path in sorted_map_keys(source_dirs) {
    if !target_dirs.contains(path) {
      delivery_issue(
        diagnostics, "directory_missing", path, "existing directory was removed, including empty directories",
      )
    }
  }
  for path in sorted_map_keys(target_dirs) {
    if !source_dirs.contains(path) && !allowed_new_dirs.contains(path) {
      delivery_issue(
        diagnostics, "directory_unexpected", path, "new directory is not needed by a declared fetch destination",
      )
    }
  }
  for path in sorted_map_keys(source.texts) {
    if received.texts.get(path) != Some(source.texts[path]) {
      delivery_issue(
        diagnostics, "tag_text", path, "decoded source tag text changed or is unavailable",
      )
    }
  }
  {
    accepted: after.valid && !diagnostics.any(d => d.severity == Error),
    mode: if mode == ExactCopy {
      "exact-copy"
    } else {
      "complete-fetch"
    },
    source: before,
    received: after,
    preserved_files,
    completed_files,
    diagnostics,
  }
}

///|
pub(all) struct CollectionItem {
  identifier : String
  view : BagView
}

///|
pub(all) struct CollectionResult {
  identifier : String
  acceptance : AcceptanceReport
} derive(ToJson)

///|
pub extend CollectionResult with ToJson::{to_json}

///|
pub(all) struct CollectionReport {
  accepted : Bool
  accepted_bags : Int32
  rejected_bags : Int32
  payload_files : Int64
  payload_bytes : Int64
  items : Array[CollectionResult]
} derive(ToJson)

///|
pub extend CollectionReport with ToJson::{to_json}

///|
/// Every bag gets an independent report; one bad bag cannot hide another result.
pub fn evaluate_collection(
  collection : Array[CollectionItem],
  policy : ReceivingPolicy,
) -> CollectionReport raise FormatError {
  check_receiving_policy(policy)
  let identifiers : Map[String, BagView] = Map([])
  for item in collection {
    guard item.identifier.trim().to_owned() != "" &&
      !identifiers.contains(item.identifier) else {
      raise Invalid("collection identifiers must be nonempty and unique")
    }
    identifiers[item.identifier] = item.view
  }
  let items : Array[CollectionResult] = []
  let mut accepted_bags = 0
  let mut rejected_bags = 0
  let mut payload_files = 0L
  let mut payload_bytes = 0L
  for identifier in sorted_map_keys(identifiers) {
    let acceptance = evaluate_receiving_policy(identifiers[identifier], policy)
    if acceptance.accepted {
      accepted_bags = accepted_bags + 1
    } else {
      rejected_bags = rejected_bags + 1
    }
    payload_files = checked_add(
      payload_files,
      acceptance.bag.payload_files.to_int64(),
      "collection file count",
    )
    payload_bytes = checked_add(
      payload_bytes,
      acceptance.bag.payload_bytes,
      "collection payload bytes",
    )
    items.push({ identifier, acceptance, })
  }
  {
    accepted: rejected_bags == 0 && !items.is_empty(),
    accepted_bags,
    rejected_bags,
    payload_files,
    payload_bytes,
    items,
  }
}
