///|
/// Preflight an incomplete transfer before an explicitly authorized host retrieves holes.
/// Existing bytes and all present tag manifests must already verify.
pub fn plan_fetch(view : BagView) -> Array[FetchEntry] raise FormatError {
  guard view.texts.get("fetch.txt") is Some(text) else {
    raise Invalid("fetch.txt is required for retrieval")
  }
  let entries = parse_fetch(text)
  let missing = entries.filter(e => !view.files.any(f => f.path == e.path))
  let report = validate(view)
  for diagnostic in report.diagnostics {
    if diagnostic.severity == Error {
      let pending = diagnostic.code == "missing_file" &&
        missing.any(e => e.path == diagnostic.path)
      let provisional_oxum = diagnostic.code == "oxum_mismatch" &&
        !missing.is_empty()
      guard pending || provisional_oxum else {
        raise Invalid(
          "unsafe fetch source: " + diagnostic.code + ": " + diagnostic.path,
        )
      }
    }
  }
  missing
}
