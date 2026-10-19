# Observed verification

Date: 2026-10-19. Source tests and commands are in this repository; this document
does not promise full RFC conformance, production performance or committee approval.

## Local checks

- MoonBit 0.1.20261016 / moonc 0.10.16: strict JS check, JS build and format check;
  the October 12 toolchain also checked and packaged the release successfully.
- 90 distinct MoonBit unit tests on JS and WASM-GC (not 180 distinct tests).
- 37 CLI/independent-tool scenarios against both published bagit-python 1.9.0
  source and pinned upstream source. Local unprivileged Windows skips four
  newline/symlink cases; Windows CI executes the symlink cases and skips only
  the newline filename. See CONFORMANCE.md for source identities.
- Five independently maintained v1.0 fixtures from LibraryOfCongress's
  conformance suite, pinned to `9ab48705c06664f9f419ca740c728c9f89a61e7c`.
  One valid fixture accepted and four invalid fixtures rejected. This small
  externally supplied suite is not proof of exhaustive RFC coverage.
- One 20 MiB binary payload exercised streaming hashing and independent validation.
- New cases cover invalid host directory inventories, lossless metadata writing,
  offline fetch writing, pre-staging configuration rejection, receiving-profile
  failures without output publication, and source preservation.

## Real filesystem measurement

The October 11 run of `python scripts/benchmark.py --files 10000 --bytes 1024` created real files,
generated both algorithms and independently recomputed every listed digest via
the shipped host (not an independent tool for this benchmark).

| Observation | Value |
| --- | --- |
| Environment | Windows 11 10.0.26200; Python 3.12.3; Node 24.14.1 |
| Payload | 10,000 files, 10,240,000 bytes, 100 source directories |
| Digests verified | 20,008 |
| Create including copy/hash/output verification | 33.916 seconds |
| Separate validation | 6.864 seconds |
| Result | complete and valid |

These are one local run, not a throughput guarantee. Runtime includes filesystem
overheads and depends on the disk and host. CI uses 1,000 files to bound runner
cost. The exposed 100,000-file cap is a safety limit, not a tested throughput
claim. The separate synthetic inventory unit test covers 10,000 file records
without doing I/O and is not substituted for this measurement.

On October 19, a new 1,000-file run (1,024,000 payload bytes and 2,008 verified
digests) completed creation in 6.011 seconds and validation in 1.363 seconds,
with a valid result on the same local Node/Python versions. The 10,000-file
measurement above is historical, not a claim that it was repeated for 0.2.1.

## Remote and release evidence

### Version 0.2.1

Published source revision `51debbe975ffb64b51b01e364732537d8c234027` passed
Linux and Windows in
[run 39260170557](https://github.com/zbhzs1/moonbagit/actions/runs/39260170557).
Both jobs passed formatting, strict checking, building, 90 tests on each
JS/WASM-GC target and five external fixtures. Linux passed all 37 CLI scenarios;
Windows passed all applicable scenarios, including dangling-symlink preservation,
with only the newline-filename case skipped. This run still used the 0.2.0
published consumer; the consumer was updated after publishing 0.2.1.

Mooncakes `zbhzs1/moonbagit@0.2.1` was published with server `200 OK`; its registry
creation time is 2026-10-19T13:33:48.385131Z. The registry SHA-256 is
`b5ce179d6f62fd3eff49f2d38676d2654d6aac19236e2666778f736a5b6d8591`, matching
the submitted ZIP. The record is not yanked and declares MIT. A fresh temporary
consumer installed this exact registry version and passed strict JS checking,
JS execution and WASM-GC execution, including orphan-text and ambiguous manifest
path rejection. `scripts/consumer.py` reproduces that version-specific check.
Its update and these evidence notes postdate the immutable published ZIP and do
not change the released library or CLI. Consult the latest main CI run for the
subsequent consumer/evidence commit.

### Version 0.2.0

Version 0.2.0 source revision `83c3ff11384a3a4e92b5563241de46362763351d`
passed both Linux and Windows in
[run 39196129587](https://github.com/zbhzs1/moonbagit/actions/runs/39196129587).
Linux ran all 35 CLI/interoperability scenarios without skips; Windows skipped
the two OS-restricted cases. Both ran 84 core tests on each JS/WASM-GC target,
strict checking, formatting, building and five pinned external fixtures.

Mooncakes `zbhzs1/moonbagit@0.2.0` was published with server `200 OK` at
2026-10-19T03:46:53Z. The registry SHA-256 is
`1e5ffec23027437762f67fdf3d729e3dd3523115f253042c7c4f2b55342b4600`, matching
the local submitted ZIP; the record is not yanked and declares MIT.
A fresh temporary consumer installed the real registry package and passed on
JS and WASM-GC, including the new fetch round-trip and invalid-inventory checks.
The version-specific consumer check was reproduced in CI (the current script
targets 0.2.1). Its update and these release-evidence notes postdate the published ZIP;
they do not change the released library or CLI implementation.

### Previous release

Public repository: https://github.com/zbhzs1/moonbagit

CI: https://github.com/zbhzs1/moonbagit/actions/workflows/ci.yml

The source revision `e1be6ec9d8b5a89eed084cd8571849776e7953f5` passed both
Linux and Windows jobs in [run 38140063677](https://github.com/zbhzs1/moonbagit/actions/runs/38140063677).
Linux ran all 28 interop scenarios without skips, including newline filenames
and symlink rejection. Later documentation/consumer-test commits can have
different run identities; consult the latest run for the current revision.

Mooncakes `zbhzs1/moonbagit@0.1.0` was published with server `200 OK` at
2026-10-11T12:42:31Z. The registry records its SHA-256 as
`7cde06e5293ddae134b880c6a515fb6c92576c9c47e2e090597040814bfbfe18`, matching
the locally submitted ZIP. The package is not yanked and declares MIT.

A separate consumer project installed this exact version from the registry,
with no local path override, and ran declaration parsing, empty-bag creation,
profile checks, upgrade planning and portability lint on JS and WASM-GC.
`python scripts/consumer.py` reproduces this fresh-directory installation and
was included in subsequent CI runs (it now targets 0.2.1). No local credentials are necessary to
install this public package. Registry release contents correspond to the
release source revision above; documentation added after publication does not
change the already published ZIP.

## Remaining work

Future compatibility work includes legacy versions/algorithms, additional tag
encodings, URI grammar coverage and Unicode-normalization-aware transport
checks. Remote fetching and serialized-bag handling need separately reviewed
transport and extraction adapters. Signatures, lock services, hostile mutation
isolation and crash durability are distinct security concerns, not guarantees
of the current checksum validator.
