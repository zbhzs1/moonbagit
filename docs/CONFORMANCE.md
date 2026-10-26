# Support and verification matrix

RFC 8493 is an informational RFC defining BagIt 1.0. The 0.3.0 endpoint is its
mandatory directory-format creation/validation behavior, with optional elements
validated when present. See [RFC8493-AUDIT.md](RFC8493-AUDIT.md) for individual
requirements, implementation and executable evidence. Operational limits are
not additional format rules. Unsupported host codecs or future algorithms are
never silently treated as verified or declared RFC violations.

| RFC section | Implemented checks | Remaining work |
| --- | --- | --- |
| 2.1.1 | Two ordered declaration lines, version 1.0, UTF-8 declaration without BOM; declared encoding for other tags | Legacy BagIt versions are not the 1.0 target; codec availability depends on pinned host |
| 2.1.2 | Required data directory, nested opaque payload | Host adapters beyond Node.js |
| 2.1.3 | One or more payload manifests, hex lengths/case, separator, every file exactly once, escaped filenames | Future optional algorithms and checksum-tool quirks outside strict format |
| 2.2.1 | Forbid payload/tagmanifest entries; include every payload manifest; verify raw-byte digests; warn on different optional tag sets | Wider compatibility fixtures |
| 2.2.2 | Metadata order/repetitions, continuation syntax; Payload-Oxum uniqueness, numeric syntax, counts; local receiving profiles | Wider receiving agreements |
| 2.2.3 | Parse/write fetch; full RFC3986 absolute-URI grammar, size/coverage/path checks; explicitly authorized bounded HTTP(S) receipt with final integrity/profile gate | Additional optional transports are separate adapters, never executed by validation |
| 2.2.4 | Arbitrary tag files checked if listed; content ignored | None within current host restrictions |
| 2.3 | LF, CR, CRLF; UTF-8/no BOM, declared IANA encoding via maintained codecs, required UTF-16 BOM; raw-byte hashing | Unavailable host codecs report unsupported rather than substitute characters |
| 2.4 | Required SHA-256/SHA-512; default SHA-512; MD5/SHA-1 compatibility and warnings; encoding-preserving manifest upgrade | Future optional registry algorithms |
| 3 | Separate completeness from hash validity; verify all checksums even if Oxum matches | Unsupported formats require another validator |
| 5 | Path containment, reject traversal/links/special files; authorized origins, no redirect/credential/partial response, size/time limits, final digest/profile check | Hostile concurrent mutation, sandboxing, signatures are separate security guarantees |
| 6 | Deterministic manifests; case/file/directory collisions, Windows device-name, character and length lint | Unicode normalization matching |

The library's `FileRecord` contract is trusted input from its host. A caller
that supplies fabricated digests can fabricate the result. The shipped CLI
computes streaming digests using Node's maintained cryptographic implementation.
Directory relationships and text-to-file membership are checked, but cannot
authenticate fabricated hashes or prove that supplied text matches actual bytes.
The writer also refuses leading-space/TAB root-relative paths and mixed digest
lengths rather than producing an ambiguous or inconsistent manifest. These are
writer representability checks, not assertions that the bag format prohibits
all such existing filenames. POSIX colons/backslashes are no longer rejected
as nonportable format syntax; Windows host restrictions remain explicit.

## Independent verification

The [bidirectional verification guide](INTEROPERABILITY.md) gives exact producer
and receiver operations, the released/native-version distinction, the six-case
positive matrix, eighteen independent negative controls, and downloadable CI
evidence. `scripts/interop_report.py` retains real bags and machine-readable
results rather than relying only on a test-count summary.

Test dependency: LibraryOfCongress/bagit-python, CC0. PyPI source release 1.9.0
archive SHA-256: `9455006c2d1df88be95ec1fccabc5ea623389589ea4c85b3d85bd256f29d7656`.
The local test installation built this exact source with version metadata
`0.0.0` because the isolated environment initially lacked its SCM build plugin;
this is a packaging metadata limitation, not modified validation code.

Its published source creates 0.97 bags. The reverse interoperability test uses
only ordinary UTF-8 filenames, updates the declaration, reloads the independent
Bag object and calls its own `save()` to recompute tag manifests. Ordinary
ASCII/Unicode filenames, spaces, binary payloads, empty payloads, SHA-256 and
SHA-512 are in the positive interoperability suite.

Both the published source and upstream snapshot passed the local positive
interoperability suite. The upstream snapshot at
`4bd2713cedbe1f8e634567c20ef0dded9622011d` natively creates BagIt 1.0; its
reverse test did not need the legacy declaration upgrade. Its local source
build uses explicitly supplied `0.0.0` distribution metadata because a GitHub
source archive does not carry the Git tag history needed by hatch-vcs. Source
identity is the pinned commit, not that synthetic packaging version.

The upstream released source `_encode_filename` / `_decode_filename` processes
CR/LF but not `%`. The current upstream source inspected at
`4bd2713cedbe1f8e634567c20ef0dded9622011d` creates 1.0 but retains that `%25`
decoding limitation. The percent-filename case is therefore a local normative
test plus an explicit **expected upstream rejection**, not a positive
interoperability claim. Neither upstream source was patched for these tests.

The project's own tests also exercise missing/extra files, corrupt payload and
tag bytes, multiple-manifest coverage, BOM and malformed UTF-8, metadata
injection, path escapes, no-overwrite behavior and unsupported input. They are
not a substitute for running an external full BagIt conformance suite.

The pinned LibraryOfCongress/bagit-conformance-suite revision
`9ab48705c06664f9f419ca740c728c9f89a61e7c` contains five v1.0 fixtures, all run
without rewriting their bytes by `scripts/conformance.py`. Legacy fixture
directories are deliberately not presented as supported BagIt versions.
