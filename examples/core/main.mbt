///|
fn main {
  try {
    // SHA-256 of the raw bytes "abc", supplied by the application's hash provider.
    let payload : Array[@bag.FileRecord] = [
      {
        path: "data/abc.txt",
        size: 3L,
        digests: {
          "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        },
      },
    ]
    let tags = @bag.create_tags(payload, algorithms=[@bag.Sha256])
    println(tags.get("manifest-sha256.txt").unwrap())
    let tags_on_disk = tags
      .iter()
      .map(pair => {
        let (path, text) = pair
        // There is no tag manifest here, so these tag digests are not required.
        @bag.FileRecord::{
          path,
          size: text.length().to_int64(),
          digests: Map([]),
        }
      })
      .collect()
    let files = payload.copy()
    files.append(tags_on_disk)
    let report = @bag.validate({ files, directories: ["data"], texts: tags })
    println("complete=\{report.complete}; valid=\{report.valid}")
  } catch {
    @bag.Invalid(message) => println(message)
  }
}
