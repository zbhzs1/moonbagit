///|
extern "js" fn call_host(op : String, args : String) -> String =
  #| (op, args) => globalThis.__moonbagit.call(op, args)

///|
extern "js" fn exit_code(code : Int) -> Unit =
  #| code => { process.exitCode = code; }

///|
fn host(op : String, args : Json) -> Json raise {
  let reply = @json.parse(call_host(op, args.stringify()))
  match reply {
    { "ok": true, "value": value, .. } => value
    { "ok": false, "error": String(message), .. } => raise @bag.Invalid(message)
    _ => raise @bag.Invalid("invalid platform response")
  }
}

///|
fn scan(root : String) -> @bag.BagView raise {
  @json.from_json(host("scan", { "root": root }))
}

///|
fn create(args : Array[String]) -> Json raise {
  guard args.length() >= 3 else {
    raise @bag.Invalid("create requires SOURCE and OUTPUT")
  }
  let source = args[1]
  let output = args[2]
  let mut algorithms = [@bag.Sha512]
  let mut metadata : Array[@bag.Metadata] = []
  let mut selected = false
  let mut i = 3
  while i < args.length() {
    match args[i] {
      "--sha256" | "--sha512" | "--both" => {
        guard !selected else {
          raise @bag.Invalid("choose exactly one algorithm option")
        }
        selected = true
        algorithms = match args[i] {
          "--sha256" => [@bag.Sha256]
          "--sha512" => [@bag.Sha512]
          _ => [@bag.Sha256, @bag.Sha512]
        }
      }
      "--metadata" => {
        guard i + 1 < args.length() else {
          raise @bag.Invalid("metadata requires a JSON file")
        }
        i = i + 1
        metadata = @json.from_json(host("metadata", { "path": args[i] }))
      }
      _ => raise @bag.Invalid("unknown option: " + args[i])
    }
    i = i + 1
  }
  let stage : String = @json.from_json(
    host("prepare", { "source": source, "output": output }),
  )
  let inventory = scan(stage)
  let payload = inventory.files.filter(f => f.path.has_prefix("data/"))
  let initial = @bag.create_tags(payload, metadata~, algorithms~)
  ignore(host("write_tags", { "root": stage, "tags": initial.to_json() }))
  let inventory = scan(stage)
  let tags = inventory.files.filter(f => !f.path.has_prefix("data/"))
  let manifests = @bag.create_tag_manifests(tags, algorithms~)
  ignore(host("write_tags", { "root": stage, "tags": manifests.to_json() }))
  let report = @bag.validate(scan(stage))
  guard report.valid else {
    raise @bag.Invalid(
      "new bag failed verification; staging directory retained: " + stage,
    )
  }
  ignore(host("commit", { "root": stage, "output": output }))
  { "command": "create", "output": output, "report": report.to_json() }
}

///|
fn run(args : Array[String]) -> Json raise {
  guard args.length() > 0 else {
    raise @bag.Invalid("expected create or validate; use --help")
  }
  match args[0] {
    "create" => create(args)
    "validate" => {
      guard args.length() == 2 else {
        raise @bag.Invalid("validate requires one bag directory")
      }
      let report = @bag.validate(scan(args[1]))
      if !report.valid {
        exit_code(1)
      }
      report.to_json()
    }
    _ => raise @bag.Invalid("unknown command: " + args[0])
  }
}

///|
fn main {
  try {
    let args : Array[String] = @json.from_json(host("args", Json::null()))
    if args.is_empty() || args[0] == "--help" {
      println("MoonBagIt - BagIt 1.0 UTF-8 / SHA-256 / SHA-512")
      println(
        "node bin/moonbagit.mjs create SOURCE OUTPUT [--sha256|--sha512|--both] [--metadata FILE.json]",
      )
      println("node bin/moonbagit.mjs validate BAG")
    } else {
      println(run(args).stringify())
    }
  } catch {
    @bag.Invalid(message) => {
      println(({ "error": message } : Json).stringify())
      exit_code(2)
    }
    error => {
      println(({ "error": error.to_string() } : Json).stringify())
      exit_code(2)
    }
  }
}
