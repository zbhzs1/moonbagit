# BagIt 1.0 delivery endpoint and requirement audit

This audit responds to the October 26 review: the delivery must implement
BagIt 1.0 mandatory behavior, not stop at a local UTF-8/SHA subset or defer the
URI grammar required by an already supported fetch.txt. The implementation
target for 0.3.0 is RFC 8493 sections 2 and 3. Optional elements are checked when
present; absence of optional metadata, tag manifests or fetch.txt is valid.
An implementation self-audit is not organizer approval or a formal proof.

The 0.4.1 host correction explicitly selects UTF-16 byte order from its BOM
before strict decoding. The regression covers both byte orders, validation of
independently encoded bags and upgrades checked by the unmodified Python tool.
Malformed surrogates remain rejected; this fixes a valid-input rejection rather
than weakening the mandatory-format target.

## Normative behavior and evidence

| RFC 8493 clause | Delivered behavior | Code and executable evidence |
| --- | --- | --- |
| 2 base structure | Required declaration, data directory, at least one payload manifest; arbitrary tag hierarchy | inventory.mbt, validate.mbt; bagit_wbtest, inventory_wbtest, rfc8493.py |
| 2.1.1 declaration | Exactly two ordered lines, BagIt 1.0; raw UTF-8/no BOM declaration; declared charset for remaining tags | parse_declaration, host decodeTag; core declaration tests; six independent codec fixtures |
| 2.1.2 payload | Opaque raw bytes in arbitrary nested data directories, including empty content | create_tags, host streaming hashes; binary/20 MiB interop; empty bag regression |
| 2.1.3 manifest presence and coverage | Every payload in every manifest exactly once; no tag/directory references | parse_manifest, validate; duplicate/missing/extra/per-manifest tests and external fixtures |
| 2.1.3 record syntax | Hex case and expected digest length; one or more SP/TAB; root-relative POSIX paths | parse_manifest, render_manifest; malformed digest/separator and whitespace tests |
| 2.1.3 escapes | Encode only percent, CR and LF; decode case-insensitive CR/LF hex; preserve remaining characters | encode_path/decode_path; percent and POSIX edge-path tests |
| 2.2.1 tag manifests | Every payload manifest covered; no payload/tagmanifest entries; verify all referenced tags by raw bytes | validate; tag corruption, arbitrary binary tag, mixed-algorithm upgrade tests |
| 2.2.1 SHOULD guidance | Warn for differing tag sets and unprotected tags; generated tag manifests include the full eligible tag set | different_tag_sets/unprotected_tag diagnostics; create_tag_manifests |
| 2.2.2 metadata | Ordered and repeated fields preserved; colon, label whitespace and continuation syntax; arbitrary non-linebreaking characters | parse_metadata/render_metadata, metadata_wbtest; Python repeated-field interop |
| 2.2.2 Payload-Oxum | At most one, decimal byte/file count; not a substitute for hashing | validate; duplicate/format/mismatch tests; same-length corruption and receipt final verification |
| 2.2.3 fetch records | Absolute-URI, decimal or unknown size, three whitespace-separated fields, safe payload path in every payload manifest | parse_fetch/render_fetch, uri.mbt, fetch_wbtest/uri_wbtest; bad URI rejected before network |
| 2.2.3 URI grammar | RFC 3986 scheme, hier-part, authority, userinfo, reg-name/IP literal, IPv6 compression/embedded IPv4, IPvFuture, port, path, query, percent escapes; no fragment in absolute-URI | check_fetch_url; positive/negative grammar tables and parser/writer shared validation on JS/WASM-GC |
| 2.2.4 other tags | Ignore arbitrary content semantics, still verify any digest reference | host opaque hashing; arbitrary binary-tag upgrade/interoperability tests |
| 2.3 text tags | LF/CR/CRLF; declaration independent of remaining charset; no UTF-8 BOM; required UTF-16 BOM; hash encoded bytes | lines/decodeTag/writeTags; codec fixtures, BOM/malformed UTF-8 tests |
| 2.4 algorithms | Required SHA-256/SHA-512; default SHA-512; recommended legacy MD5/SHA-1 with warnings | Algorithm, maintained node:crypto; independent four-algorithm validation and upgrade |
| 3 complete and valid | All required/listed files and per-manifest coverage before complete; every checksum must verify before valid | validate; dual-tool positive/negative matrix, rfc8493.py, conformance.py |

The non-normative ABNF in section 7 does not override normative text. For
example, the format permits empty payloads with an empty required manifest;
the ABNF's one-or-more entry notation must not incorrectly reject them.

## Receiver and transfer guarantees

The endpoint is a **new, fully verified BagIt directory**. Creation, digest
upgrade and network receipt do not publish an incomplete, corrupt or
profile-rejected staging directory. Input remains unchanged. `plan_fetch` in
MoonBit accepts only missing payload declared in every manifest; it verifies
present content and protected tags before the host may retrieve anything.

`fetch SOURCE OUTPUT --allow-origin ORIGIN` is explicit, not a side effect of
validation. HTTP(S) transport requires an exact operator-authorized origin for
every pending entry before staging/network activity. It disallows embedded
credentials, redirects, partial/non-200 responses and HTTP body transformations;
enforces elapsed time and streamed total byte limits; writes only new payload
files in a private staging tree; then reruns all digests and optional receiving
profile before rename. Files with valid grammar but other schemes do not get
executed. HTTP(S) is the shipped transport, **not a restriction on URI syntax**.

RFC 8493 does not require a validator to fetch resources automatically, support
every URI transport, extract archives or implement authentication signatures.
Our explicit receiver closes the missing-file workflow without claiming those
unrelated guarantees. TLS uses Node's default certificate validation. A trusted
origin includes its DNS/network destination; the receiver is not an arbitrary
URL proxy or a substitute for an isolated network security boundary.

## Compatibility versus operating policy

Core format paths are no longer rejected merely for a colon/backslash that is
legal in a POSIX filename. Absolute/drive paths, NUL and traversal components
are refused as security-sensitive inputs. OS-inexpressible paths fail at the
host boundary instead of becoming silent renamed files. Unicode names are
compared exactly; normalization/case collisions are not silently merged.
Resource caps (100,000 files/directories, 16 MiB per standard text tag, 64 MiB
total tag text, host safe-integer/Int64 file sizes) are deployment limits, not
claims that larger bags violate BagIt. The pure parser has no short URI/path
length limit, but the size API uses checked Int64; overflow is explicit.

Charset support uses pinned iconv-lite and ICU, not handwritten codecs. Required
UTF-8 and tested UTF-16, ISO-8859-1, ASCII, Shift_JIS and GB18030 work with raw-byte
digests and encoding-preserving upgrades. An unavailable codec is reported as
unsupported by this host, never silently decoded with replacement or called an
RFC violation. Future registry algorithms/legacy BagIt versions are likewise
not misrepresented as required BagIt 1.0 behavior. SHA-256/SHA-512 are always
available; weak digests do not imply authenticity.

`render_manifest` rejects ambiguous leading separator whitespace in a root tag
path, and `render_metadata` rejects values whose intended continuation indentation
cannot be represented without loss. These writer errors are not assertions
that arbitrary input models can always be losslessly represented by the format.

## Independent tests and honest fixture identities

The existing unmodified native BagIt 1.0 producer/receiver matrix remains:
two directions, three algorithm sets, six positive cases and eighteen negative
controls per tool identity. The PyPI 1.9.0 adaptation remains separately labelled.
See [INTEROPERABILITY.md](INTEROPERABILITY.md) and its CI artifact instructions.

The added `scripts/rfc8493.py` uses the pinned native Python producer, real
filesystem bytes and a local loopback HTTP server. Its non-UTF-8 fixtures are
**explicit codec adaptations**, not falsely labelled unmodified Python output:
upstream make_bag hardcodes UTF-8 in the declaration even with a different
encoding argument, so the fixture transcodes original Python-produced tags
with Python codecs and rehashes exact tag bytes with hashlib. The unpatched
Python validator then independently verifies them; Python also receives the
new MoonBagIt non-UTF-8 output directly. Empty-payload fixtures supply the empty
required manifest omitted by that producer. No external implementation is
patched or counted as original MoonBit code.

Run `npm ci --ignore-scripts`, `moon build --target js`, then
`python scripts/rfc8493.py --bagit-path .interop/upstream` after installing the
pinned producer from INTEROPERABILITY.md. The Linux/Windows CI executes this
suite, the existing 37 CLI scenarios, dual-backend core tests, five unmodified
external fixtures, fresh registry consumers and both dual-tool evidence matrices.
Only POSIX-only filename cases are skipped on Windows, not the transfer tests.
