# Changelog

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
