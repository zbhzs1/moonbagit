///|
pub(all) suberror FormatError {
  Invalid(String)
} derive(Eq, @debug.Debug)

///|
pub(all) enum Algorithm {
  Md5
  Sha1
  Sha256
  Sha512
} derive(Eq, @debug.Debug)

///|
pub fn Algorithm::name(self : Algorithm) -> String {
  match self {
    Md5 => "md5"
    Sha1 => "sha1"
    Sha256 => "sha256"
    Sha512 => "sha512"
  }
}

///|
pub fn Algorithm::hex_length(self : Algorithm) -> Int32 {
  match self {
    Md5 => 32
    Sha1 => 40
    Sha256 => 64
    Sha512 => 128
  }
}

///|
pub fn algorithm(name : String) -> Algorithm raise FormatError {
  match name {
    "md5" => Md5
    "sha1" => Sha1
    "sha256" => Sha256
    "sha512" => Sha512
    _ => raise Invalid("unsupported algorithm: " + name)
  }
}

///|
pub(all) struct Declaration {
  version : String
  encoding : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct Metadata {
  label : String
  value : String
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct Entry {
  path : String
  checksum : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct Manifest {
  name : String
  algorithm : Algorithm
  tag : Bool
  entries : Array[Entry]
} derive(Eq, @debug.Debug)

///|
pub(all) struct FetchEntry {
  url : String
  size : Int64?
  path : String
} derive(Eq, @debug.Debug, ToJson)

///|
/// The host supplies hashes of raw file bytes, not hashes of decoded text.
pub(all) struct FileRecord {
  path : String
  size : Int64
  digests : Map[String, String]
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct BagView {
  files : Array[FileRecord]
  directories : Array[String]
  texts : Map[String, String]
} derive(@debug.Debug, @json.FromJson)

///|
pub(all) enum Severity {
  Error
  Warning
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  path : String
  message : String
} derive(@debug.Debug, ToJson)

///|
pub(all) struct Report {
  complete : Bool
  valid : Bool
  payload_files : Int32
  payload_bytes : Int64
  verified_checksums : Int32
  diagnostics : Array[Diagnostic]
} derive(@debug.Debug, ToJson)

///|
pub fn Report::has_code(self : Report, code : String) -> Bool {
  self.diagnostics.any(d => d.code == code)
}
