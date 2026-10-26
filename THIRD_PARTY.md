# Standards and independent test references

The MoonBit rules implementation is original code under MIT, written against
published specifications. It is not a source translation of the independent
Python tool. No adjacent MoonBit archive or evidence project's source is included.

| Reference | Use | License/status |
| --- | --- | --- |
| RFC 8493, https://www.rfc-editor.org/rfc/rfc8493.html | BagIt 1.0 requirements | IETF specification; referenced, not redistributed |
| BagIt Profiles 1.4.0, https://bagit-profiles.github.io/bagit-profiles-specification/ | Directory receiving-rule semantics | CC0 1.0; referenced, not redistributed |
| LibraryOfCongress/bagit-python, https://github.com/LibraryOfCongress/bagit-python | Independent CLI test oracle | CC0 1.0; test-only, not in published library |
| LibraryOfCongress/bagit-conformance-suite, https://github.com/LibraryOfCongress/bagit-conformance-suite | Unmodified external valid/invalid fixtures | US government public domain plus CC0 worldwide; CI checkout outside this source tree |
| Node.js node:crypto / node:fs | Maintained runtime hashing and filesystem adapter | Node.js runtime dependency, not vendored |
| Node.js node:http / node:https | Explicitly authorized streaming transport with standard TLS verification | Node.js runtime, not vendored |
| iconv-lite 0.7.0, https://github.com/ashtuchkin/iconv-lite | Declared tag-encoding conversion in the host, not custom codecs | MIT; pinned npm dependency, lockfile integrity; license in node_modules/iconv-lite/LICENSE |
| safer-buffer 2.1.2, https://github.com/ChALkeR/safer-buffer | Transitive iconv-lite buffer helper | MIT; pinned in package-lock.json, license in node_modules/safer-buffer/LICENSE |
| MoonBit core | Standard JSON/string/debug APIs | Toolchain standard library, not vendored |

Pinning, known upstream limitations and fixture counts are documented in
`docs/CONFORMANCE.md` and `docs/VERIFICATION.md`. Generated project examples are
MIT. External test data is neither counted as implementation LOC nor packaged
as this project's original code.
