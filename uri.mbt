///|
fn uri_alpha(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn uri_digits(text : String) -> Bool {
  text.iter().all(c => c >= '0' && c <= '9')
}

///|
fn uri_alphanumeric(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
fn uri_unreserved(c : Char) -> Bool {
  uri_alphanumeric(c) || "-._~".contains(c.to_string())
}

///|
fn uri_subdelim(c : Char) -> Bool {
  "!$&'()*+,;=".contains(c.to_string())
}

///|
fn uri_component(text : String, extra : String) -> Bool {
  let mut i = 0
  while i < text.length() {
    if text[i] == '%' {
      if i + 2 >= text.length() ||
        !text[i + 1:i + 3].iter().all(c => c.is_ascii_hexdigit()) {
        return false
      }
      i = i + 3
    } else {
      let unit = text[i:i + 1].to_owned()
      if !unit.iter().all(c => uri_unreserved(c) || uri_subdelim(c)) &&
        !extra.contains(unit) {
        return false
      }
      i = i + 1
    }
  }
  true
}

///|
fn uri_ipv4(text : String) -> Bool {
  let parts = text.split(".").map(p => p.to_owned()).collect()
  if parts.length() != 4 {
    return false
  }
  parts.all(p => {
    if p == "" ||
      p.length() > 3 ||
      !uri_digits(p) ||
      (p.length() > 1 && p[0] == '0') {
      false
    } else {
      let value = @string.parse_int(p[:]) catch { _ => -1 }
      value >= 0 && value <= 255
    }
  })
}

///|
fn uri_ipv6(text : String) -> Bool {
  let halves = text.split("::").map(p => p.to_owned()).collect()
  if halves.length() > 2 {
    return false
  }
  let compressed = halves.length() == 2
  let mut groups = 0
  for h in 0..<halves.length() {
    if halves[h] == "" {
      if !compressed {
        return false
      }
      continue
    }
    let parts = halves[h].split(":").map(p => p.to_owned()).collect()
    for i in 0..<parts.length() {
      let part = parts[i]
      if part.contains(".") {
        if h != halves.length() - 1 ||
          i != parts.length() - 1 ||
          !uri_ipv4(part) {
          return false
        }
        groups = groups + 2
      } else {
        if part == "" ||
          part.length() > 4 ||
          !part.iter().all(c => c.is_ascii_hexdigit()) {
          return false
        }
        groups = groups + 1
      }
    }
  }
  if compressed {
    groups < 8
  } else {
    groups == 8
  }
}

///|
fn uri_ip_literal(text : String) -> Bool {
  if text.has_prefix("v") || text.has_prefix("V") {
    guard text.find(".") is Some(dot) && dot > 1 && dot + 1 < text.length() else {
      return false
    }
    text[1:dot].iter().all(c => c.is_ascii_hexdigit()) &&
    text[dot + 1:]
    .iter()
    .all(c => uri_unreserved(c) || uri_subdelim(c) || c == ':')
  } else {
    uri_ipv6(text)
  }
}

///|
fn uri_authority(text : String) -> Bool {
  let mut hostport = text
  if text.find("@") is Some(at) {
    if !uri_component(text[:at].to_owned(), ":") {
      return false
    }
    hostport = text[at + 1:].to_owned()
  }
  if hostport.has_prefix("[") {
    guard hostport.find("]") is Some(close) else { return false }
    if !uri_ip_literal(hostport[1:close].to_owned()) {
      return false
    }
    let rest = hostport[close + 1:].to_owned()
    rest == "" || (rest.has_prefix(":") && uri_digits(rest[1:].to_owned()))
  } else {
    let colon = hostport.find(":")
    let host = match colon {
      Some(i) => {
        if !uri_digits(hostport[i + 1:].to_owned()) {
          return false
        }
        hostport[:i].to_owned()
      }
      None => hostport
    }
    // An invalid dotted quad can still be a reg-name under RFC 3986's ordered choice.
    uri_component(host, "")
  }
}

///|
/// RFC 3986 section 4.3 absolute-URI: unlike URI-reference, no fragment is allowed.
pub fn check_fetch_url(url : String) -> Unit raise FormatError {
  guard url.find(":") is Some(colon) && colon > 0 else {
    raise Invalid("fetch URL must be an absolute URI")
  }
  let scheme = url[:colon].to_owned()
  guard uri_alpha(scheme[0]) &&
    scheme
    .iter()
    .all(c => uri_alphanumeric(c) || c == '+' || c == '-' || c == '.') else {
    raise Invalid("invalid URI scheme")
  }
  guard !url.contains("#") else {
    raise Invalid("absolute-URI cannot contain a fragment")
  }
  let remainder = url[colon + 1:].to_owned()
  let hier = match remainder.find("?") {
    None => remainder
    Some(query) => {
      guard uri_component(remainder[query + 1:].to_owned(), ":@/?") else {
        raise Invalid("invalid URI query")
      }
      remainder[:query].to_owned()
    }
  }
  let path = if hier.has_prefix("//") {
    let authority_path = hier[2:].to_owned()
    let boundary = authority_path.find("/").unwrap_or(authority_path.length())
    guard uri_authority(authority_path[:boundary].to_owned()) else {
      raise Invalid("invalid URI authority, IP literal or port")
    }
    authority_path[boundary:].to_owned()
  } else {
    hier
  }
  guard uri_component(path, ":@/") else { raise Invalid("invalid URI path") }
}
