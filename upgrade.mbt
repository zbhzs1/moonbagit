///|
pub(all) struct UpgradePlan {
  payload_manifests : Map[String, String]
  tag_algorithms : Array[Algorithm]
} derive(@debug.Debug)

///|
/// Refuses invalid sources. The caller must rehash all tags after writing the plan.
pub fn plan_upgrade(
  view : BagView,
  algorithms : Array[Algorithm],
) -> UpgradePlan raise FormatError {
  checked_algorithms(algorithms)
  guard validate(view).valid else {
    raise Invalid("cannot upgrade an invalid or incomplete bag")
  }
  let payload = view.files.filter(f => f.path.has_prefix("data/"))
  let payload_manifests : Map[String, String] = Map([])
  let tag_algorithms : Array[Algorithm] = []
  for file in view.files {
    if manifest_name(file.path, true) {
      let manifest = parse_manifest(
        file.path,
        view.texts.get(file.path).unwrap(),
      )
      if !tag_algorithms.contains(manifest.algorithm) {
        tag_algorithms.push(manifest.algorithm)
      }
    }
  }
  for alg in algorithms {
    let name = "manifest-" + alg.name() + ".txt"
    if !view.files.any(f => f.path == name) {
      payload_manifests[name] = render_manifest(record_entries(payload, alg))
    }
    if !tag_algorithms.contains(alg) {
      tag_algorithms.push(alg)
    }
  }
  { payload_manifests, tag_algorithms, }
}
