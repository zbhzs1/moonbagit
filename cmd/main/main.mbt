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
  let mut metadata_selected = false
  let mut profile : @bag.Profile? = None
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
        guard !metadata_selected && i + 1 < args.length() else {
          raise @bag.Invalid("metadata requires a JSON file")
        }
        metadata_selected = true
        i = i + 1
        metadata = @json.from_json(host("metadata", { "path": args[i] }))
      }
      "--profile" => {
        guard profile is None && i + 1 < args.length() else {
          raise @bag.Invalid("profile requires exactly one JSON file")
        }
        i = i + 1
        profile = Some(
          @bag.parse_profile(host("metadata", { "path": args[i] })),
        )
      }
      _ => raise @bag.Invalid("unknown option: " + args[i])
    }
    i = i + 1
  }
  // Reject invalid metadata before copying any payload into staging.
  ignore(@bag.create_tags([], metadata~, algorithms~))
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
  let view = scan(stage)
  let report = @bag.validate(view)
  guard report.valid else {
    raise @bag.Invalid(
      "new bag failed verification; staging directory retained: " + stage,
    )
  }
  if profile is Some(profile) {
    let receiving = @bag.validate_profile(view, profile)
    if !receiving.conforms {
      exit_code(1)
      return {
        "command": "create",
        "output": output,
        "published": false,
        "staging": stage,
        "profile": receiving.to_json(),
        "report": report.to_json(),
      }
    }
    ignore(host("commit", { "root": stage, "output": output }))
    return {
      "command": "create",
      "output": output,
      "published": true,
      "profile": receiving.to_json(),
      "report": report.to_json(),
    }
  }
  ignore(host("commit", { "root": stage, "output": output }))
  { "command": "create", "output": output, "report": report.to_json() }
}

///|
fn upgrade(args : Array[String]) -> Json raise {
  guard args.length() == 4 else {
    raise @bag.Invalid(
      "upgrade requires SOURCE OUTPUT and --sha256, --sha512 or --both",
    )
  }
  let algorithms = match args[3] {
    "--sha256" => [@bag.Sha256]
    "--sha512" => [@bag.Sha512]
    "--both" => [@bag.Sha256, @bag.Sha512]
    _ => raise @bag.Invalid("unsupported upgrade option")
  }
  ignore(@bag.plan_upgrade(scan(args[1]), algorithms))
  let stage : String = @json.from_json(
    host("prepare_upgrade", { "source": args[1], "output": args[2] }),
  )
  // Recheck the copied source before any manifests change.
  let plan = @bag.plan_upgrade(scan(stage), algorithms)
  ignore(
    host("write_tags", {
      "root": stage,
      "tags": plan.payload_manifests.to_json(),
    }),
  )
  let records = scan(stage).files.filter(f => {
    !f.path.has_prefix("data/") &&
    !(f.path.has_prefix("tagmanifest-") && !f.path.contains("/"))
  })
  let tags = @bag.create_tag_manifests(records, algorithms=plan.tag_algorithms)
  ignore(
    host("write_tags", {
      "root": stage,
      "tags": tags.to_json(),
      "replace": true,
    }),
  )
  let report = @bag.validate(scan(stage))
  guard report.valid else {
    raise @bag.Invalid(
      "upgraded bag failed verification; staging retained: " + stage,
    )
  }
  ignore(host("commit", { "root": stage, "output": args[2] }))
  { "command": "upgrade", "output": args[2], "report": report.to_json() }
}

///|
fn run(args : Array[String]) -> Json raise {
  guard args.length() > 0 else {
    raise @bag.Invalid("expected create or validate; use --help")
  }
  match args[0] {
    "create" => create(args)
    "upgrade" => upgrade(args)
    "lint" => {
      guard args.length() == 2 else {
        raise @bag.Invalid("lint requires one bag directory")
      }
      let diagnostics = @bag.lint_portability(scan(args[1]))
      { "command": "lint", "diagnostics": diagnostics.to_json() }
    }
    "validate" => {
      guard args.length() == 2 || (args.length() == 4 && args[2] == "--profile") else {
        raise @bag.Invalid("validate requires BAG [--profile FILE.json]")
      }
      let view = scan(args[1])
      if args.length() == 4 {
        let profile = @bag.parse_profile(host("metadata", { "path": args[3] }))
        let report = @bag.validate_profile(view, profile)
        if !report.conforms {
          exit_code(1)
        }
        report.to_json()
      } else {
        let report = @bag.validate(view)
        if !report.valid {
          exit_code(1)
        }
        report.to_json()
      }
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
        "node bin/moonbagit.mjs create SOURCE OUTPUT [--sha256|--sha512|--both] [--metadata FILE.json] [--profile FILE.json]",
      )
      println("node bin/moonbagit.mjs validate BAG [--profile FILE.json]")
      println("node bin/moonbagit.mjs lint BAG")
      println(
        "node bin/moonbagit.mjs upgrade SOURCE OUTPUT --sha256|--sha512|--both",
      )
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
