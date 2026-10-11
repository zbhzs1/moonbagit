///|
fn device_name(component : String) -> Bool {
  let base = component.split(".").collect()[0].to_upper().to_owned()
  if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(base) {
    return true
  }
  if base.length() == 4 && (base.has_prefix("COM") || base.has_prefix("LPT")) {
    return base[3] >= '1' && base[3] <= '9'
  }
  false
}

///|
/// Advisory destination portability checks, distinct from BagIt validity.
pub fn lint_portability(view : BagView) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let paths = view.directories.copy()
  paths.append(view.files.map(f => f.path))
  let seen : Map[String, Bool] = Map([])
  let folded : Map[String, String] = Map([])
  for path in paths {
    if seen.contains(path) {
      continue
    }
    seen[path] = true
    let key = path[:].to_lower().to_owned()
    if folded.get(key) is Some(other) && other != path {
      issue(
        diagnostics,
        "portable_case_collision",
        path,
        "case-insensitive destination collides with " + other,
        warning=true,
      )
    } else {
      folded[key] = path
    }
    if path.length() >= 260 {
      issue(
        diagnostics,
        "portable_long_path",
        path,
        "legacy Windows path limit may be exceeded after adding the destination root",
        warning=true,
      )
    }
    for component in path.split("/") {
      let component = component.to_owned()
      if device_name(component) {
        issue(
          diagnostics,
          "portable_device_name",
          path,
          "Windows reserved component: " + component,
          warning=true,
        )
      }
      if component.has_suffix(".") || component.has_suffix(" ") {
        issue(
          diagnostics,
          "portable_trailing_character",
          path,
          "trailing dot/space may be stripped by a destination filesystem",
          warning=true,
        )
      }
      if component
        .iter()
        .any(c => c < '\u0020' || "<>\"|?*".contains(c.to_string())) {
        issue(
          diagnostics,
          "portable_character",
          path,
          "component contains a control or Windows-reserved character",
          warning=true,
        )
      }
      if component.length() > 255 {
        issue(
          diagnostics,
          "portable_long_component",
          path,
          "component exceeds 255 UTF-16 units; byte-limited filesystems may have a lower limit",
          warning=true,
        )
      }
    }
  }
  diagnostics.sort_by((a, b) => {
    let order = a.path.compare(b.path)
    if order == 0 {
      a.code.compare(b.code)
    } else {
      order
    }
  })
  diagnostics
}
