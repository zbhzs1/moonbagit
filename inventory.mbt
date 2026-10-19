///|
fn check_inventory(view : BagView, diagnostics : Array[Diagnostic]) -> Unit {
  let directories : Map[String, Bool] = Map([])
  let files : Map[String, Bool] = Map([])
  for file in view.files {
    files[file.path] = true
  }
  for path, _ in view.texts {
    if !files.contains(path) {
      issue(
        diagnostics, "orphan_text", path, "decoded text has no inventory file record",
      )
    }
  }
  for directory in view.directories {
    check_path(directory) catch {
      Invalid(message) =>
        issue(diagnostics, "unsafe_directory", directory, message)
    }
    if directories.contains(directory) {
      issue(
        diagnostics, "duplicate_directory", directory, "duplicate inventory directory",
      )
    }
    directories[directory] = true
    if files.contains(directory) {
      issue(
        diagnostics, "file_directory_collision", directory, "inventory path is both a file and a directory",
      )
    }
    if directory == "bagit.txt" ||
      directory == "bag-info.txt" ||
      directory == "fetch.txt" ||
      manifest_name(directory, false) ||
      manifest_name(directory, true) {
      issue(
        diagnostics, "reserved_tag_directory", directory, "standard tag filename is occupied by a directory",
      )
    }
  }
  if files.contains("data") {
    issue(
      diagnostics, "payload_root_file", "data", "payload root must be a directory, not a file",
    )
  }
  let paths = view.directories.copy()
  paths.append(view.files.map(f => f.path))
  let checked : Map[String, Bool] = Map([])
  // Each parent is checked once even for a large flat inventory.
  for path in paths {
    let mut end = path.length()
    while path[:end].to_owned().rev_find("/") is Some(slash) {
      let parent = path[:slash].to_owned()
      if checked.contains(parent) {
        break
      }
      checked[parent] = true
      if !directories.contains(parent) {
        issue(
          diagnostics, "missing_parent_directory", parent, "parent directory is missing from inventory",
        )
      }
      if files.contains(parent) {
        issue(
          diagnostics, "ancestor_file", parent, "a file cannot be an ancestor of another entry",
        )
      }
      end = slash
    }
  }
}
