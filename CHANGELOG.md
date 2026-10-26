# Changelog

## 0.4.0 - 2026-10-26

- Add a stateful decoded-text manifest reader with cross-chunk CRLF handling,
  caller-selected resource limits, duplicate tracking, finalization and latched
  line-numbered failures. A separate recovery inspector reports multiple rows
  without treating partial output as a valid manifest.
- Add deterministic per-file checksum evidence and diagnostic grouping, keeping
  the original full validity report authoritative.
- Add versioned local preservation snapshots, strict JSON parsing, exact Int64
  wire counts, file/directory/metadata differences and full snapshot revalidation.
  Missing common hashes are explicitly unverifiable, not inferred equal by size.
- Add receiving policies for verified algorithms, protected tags, portability,
  total/per-file/tag/path quotas and overlapping path budgets. Policy rejection
  stays separate from RFC invalidity and from BagIt Profiles 1.4 validation.
- Add offline transfer reservations and deterministic bounded batches, expected
  checksums, pending-path conflict checks and explicit unknown-size accounting.
  A plan does not authorize origins or enforce actual network byte limits.
- Add exact-copy and fetch-completion handoff checks preserving existing tags,
  payload and empty directories. Real HTTP receipt now executes the handoff gate
  before publication and accepts an optional receiving-policy gate.
- Add independent per-bag collection decisions and CLI commands for the new APIs.
- Retain original RFC and bidirectional interoperability tests; add 38 core
  preservation regressions and 16 real-filesystem CLI cases on both CI platforms.

Published source/tag: `d067f64`. Source CI passed both platforms; 0.4.0 was
formally published and a fresh registry consumer passed on both core backends.
See docs/VERIFICATION.md for the immutable ZIP checksum and exact source versus
post-publication evidence distinction. Earlier release records remain historical.

## 0.3.0 - 2026-10-26

- Deliver the RFC 8493 mandatory-behavior endpoint and a clause-to-code/test
  audit rather than deferring grammar required by the supported fetch format.
- Validate RFC 3986 absolute-URI components, including IPv6, embedded IPv4,
  IPvFuture, authority and query; reject fragments and malformed ports/escapes.
- Add MoonBit fetch preflight and explicit bounded HTTP(S) receipt into private
  staging, with origin authorization, no redirects, raw streamed bytes, and
  complete digest/profile verification before publishing a new directory.
- Decode tags according to their declared encoding; retain UTF-8/no-BOM for the
  declaration; create with `--encoding`, preserve encoding during digest upgrade,
  and refuse malformed/unrepresentable bytes instead of silently replacing them.
- Add MD5/SHA-1 legacy interoperability and warnings, retain SHA-512 default;
  `--all` explicitly creates all four supported algorithms.
- Stop confusing POSIX filename portability and non-linebreaking metadata
  characters with mandatory format restrictions. Preserve traversal defenses.
- Add the RFC/receipt regression suite, keep the existing bidirectional
  bagit-python matrix and external fixtures; run new tests on both CI platforms.
- Add pinned MIT iconv-lite/safer-buffer host dependencies and documented
  `npm ci` installation. Pure MoonBit library consumers do not need Node codecs.

API additions include `Md5`, `Sha1`, `check_fetch_url`, `plan_fetch` and optional
`create_tags(..., encoding=...)`. Callers with exhaustive Algorithm matches must
handle the two additional cases. Format support is not an authenticity claim,
unbounded resource promise or implementation of every URI transport.

The published ZIP corresponds to `144b29a`; subsequent registry-consumer and
verification-note updates do not change that released implementation.

## 0.2.1 - 2026-10-19

- Reject manifest writer inputs that mix digest lengths or have ambiguous
  leading path whitespace rather than generating text that changes a filename.
- Refuse creation/upgrade over an existing dangling output symlink, including
  the final publication check; do not treat a failed symlink target as absence.
- Reject orphan decoded-text entries so nonexistent metadata cannot satisfy a
  receiving profile through an inconsistent host inventory.
- Add six core regressions (90 total) and two CLI regressions (37 total).
- Normalize native MoonBit module/package files to LF, preventing fresh Windows
  checkouts from failing October 16 toolchain format checks under autocrlf.
- Document architecture, actual adjacent-project differences and reproducible
  review evidence without claiming organizer approval or complete RFC support.

The published ZIP corresponds to source revision `51debbe`. Subsequent
0.2.1 published-consumer and verification-note updates do not change its implementation.

## 0.2.0 - 2026-10-19

- Validate directory inventories: ancestor coverage, duplicate directories,
  file/directory collisions, unsafe paths and reserved standard-tag directories.
- Reject metadata controls and continuation values that cannot round-trip
  without silently discarding caller-supplied indentation.
- Add `render_fetch` for offline fetch plans, with shared URI character/escape
  checks, nonnegative sizes and unique safe payload paths. No networking added.
- Add `create --profile FILE.json`: publish the output only after the staged
  bag satisfies the receiving profile; retain rejected staging and report it.
- Reject duplicate metadata/profile CLI options and validate configuration
  before copying files.
- Adapt format and JSON conversion calls to the October 12 MoonBit toolchain.
- Expand core regression tests from 65 to 84 and CLI/interoperability scenarios
  from 28 to 35. JS and WASM-GC run the same core suite, not distinct tests.

This release intentionally rejects previously accepted inconsistent inventories
and metadata/URI inputs. See README for conservative policy boundaries.
The published ZIP corresponds to source revision `83c3ff1`. Subsequent
published-consumer and verification-note updates do not change its implementation.

## 0.1.0 - 2026-10-11

- BagIt 1.0 UTF-8 parsing, deterministic creation and full supported-manifest verification.
- SHA-256/SHA-512 streaming host and separate completeness/validity reports.
- Local BagIt Profiles 1.4.0 receiving constraints and research-dataset example.
- Non-destructive digest upgrade with source and staged-copy verification.
- Advisory Windows/path portability checks.
- Independent bagit-python interoperability, pinned external conformance fixtures,
  real-filesystem benchmark, Linux/Windows CI and published-package consumer.

The published ZIP predates the final verification-log and consumer-runner
documentation commits; the library implementation and CLI are unchanged.
