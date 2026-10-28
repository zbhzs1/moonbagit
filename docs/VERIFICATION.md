# Observed verification

Updated: 2026-10-28. The format target is BagIt 1.0 mandatory behavior, mapped to
implementation and executable evidence in [RFC8493-AUDIT.md](RFC8493-AUDIT.md).
These observed checks are not a formal certification, an exhaustive proof,
a production performance guarantee or committee approval.

## Local checks

The following historical 0.2.1 observations are retained, not relabelled as
0.3.0 results. The current release's requirement/receipt suite and final CI are
recorded in its release section below and RFC8493-AUDIT.md.

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

### Version 0.4.1 source checks

The October 28 recheck reproduced a valid-input failure before fixing it:
generic UTF-16 with a big-endian BOM and U+00D8 in a filename was incorrectly
decoded by ICU as little endian. The host now selects the strict decoder from
the BOM. The new independent Python codec fixture checks both byte orders,
read-only validation, preserved original tags during upgrade, and independent
validation of the upgraded bags. Malformed surrogate rejection remains strict.

Locally, formatting, strict JS checking, JS build and the 133 core tests on
each JS/WASM-GC target passed. All 18 RFC/real-HTTP scenarios passed where
applicable (one POSIX filename skip on Windows); the 16 preservation cases and
37 CLI scenarios also passed (four local Windows filename/symlink skips).
The pinned native Python matrix passed all six positives and eighteen negative
controls, and all five unmodified external fixtures produced their expected
decisions. These local skips do not replace full Linux/privileged Windows CI.
The MoonBit library APIs and implementation LOC are unchanged from 0.4.0.

### Version 0.4.0

The new implementation has 133 distinct core tests (the prior 95 plus 38),
all passed locally on JS and WASM-GC, along with strict checks, formatting and
the JS build. The October 12 toolchain also passed strict JS checking.
The new `scripts/preservation.py` ran 16 real-filesystem scenarios successfully.
Existing 37 CLI scenarios against the pinned unmodified native Python module
passed with four local Windows filename/symlink skips. The 17 RFC/real-HTTP cases
passed with one POSIX-only filename skip, including the new pre-publication
handoff gate. CI is responsible for privileged symlink cases and Linux cases.

The native module for these local reruns was fetched unchanged from pinned
`src/bagit/__init__.py`; its Git blob is
`2b4adcebf0164d3254d01f2532578103b8df9dee`. A local `0.0.0` distribution metadata
stub supplies importlib's version query, not a change to validation code. Do
not mistake that local metadata for an upstream release identity. A pip build
dependency download stalled and was cancelled; no unsuccessful installation
is claimed as a passed dependency check.

Published source and tag `v0.4.0` are
`d067f64d523cfe588a4fd703b41042e383709d9e`. Both OS jobs passed in
[source CI 40303108408](https://github.com/zbhzs1/moonbagit/actions/runs/40303108408).
The actual Windows job log confirms 133 tests on both targets, 37 CLI scenarios
(one filename skip), both 6-positive/18-negative bidirectional matrices,
17 RFC/receipt cases (one POSIX filename skip), 16 preservation cases and five
unmodified external fixtures. No local Windows permission skip is being
substituted for these CI symlink checks. The source run still used the old
0.3.0 registry consumer; the consumer was updated after actual 0.4.0 publication.

Mooncakes returned `200 OK` for `zbhzs1/moonbagit@0.4.0`; the public registry
records creation at `2026-10-26T09:57:13.740747Z`, MIT and not yanked.
The registry checksum equals the submitted ZIP SHA-256:
`6bc1cfe60e50eba41fffb18c9fb3ed41760725a290d94328440327265759a398`.
A new temporary consumer downloaded that exact version from the public registry
without path substitution. Strict JS check and both JS/WASM-GC runs passed,
including new public incremental-reader, audit, snapshot round-trip/comparison,
revalidation, receiving-policy, transfer and delivery/collection APIs. These
consumer/evidence updates postdate the immutable ZIP; do not move the release
tag to a later documentation commit. Temporary toolchain credentials were
deleted; the user's original credentials were left unchanged.

Non-test implementation at that revision: 20 MoonBit files, 4,535 physical lines
and 4,099 nonblank/noncomment lines, including the actual MoonBit CLI but
excluding runnable examples, tests, generated interfaces, build output, Node,
Python and third-party sources. This is a transparent size measurement, not an
official minimum, quality certificate or organizer approval.

### Version 0.3.0

Published source revision `144b29a75bdea1c245a4908279c0e36775fce541` passed
Linux and Windows in
[run 40290038265](https://github.com/zbhzs1/moonbagit/actions/runs/40290038265).
Both platforms ran 95 core tests on each JS/WASM-GC target, strict checking,
formatting, JS build, the existing 37 CLI scenarios, five external fixtures,
both bagit-python evidence matrices and the new 17-case RFC/receipt suite.
Linux ran all 17 new cases; Windows skipped only the POSIX-only filename case.
The earlier 17-case run exposed omitted optional fetch sizes at the JSON/host
boundary; that failure was fixed, not ignored or removed. All tests passed
before formal publication. The source run still consumed 0.2.1; the current
consumer script was updated after publishing 0.3.0.

Mooncakes `zbhzs1/moonbagit@0.3.0` was formally published with `200 OK` at
2026-10-26T08:09:37.614593Z. Its registry record is not yanked and declares MIT.
The registry SHA-256 matches the submitted ZIP:
`d29d2cddc45724120ee55751a18ad00dd5eb807636bede884a262d6a5d85ef68`.
A new temporary consumer installed this exact public registry version without
path overrides or temporary login credentials. Strict JS checking, JS and
WASM-GC execution passed, including the public URI validator, legacy algorithms,
declared-encoding creation and fetch preflight APIs. `scripts/consumer.py`
reproduces this version-specific test in subsequent main CI. These consumer
and evidence-note updates postdate the immutable published ZIP; the release
tag remains attached to the actual published source, not a later notes commit.

The [requirement audit](RFC8493-AUDIT.md) maps required behavior to implementation
and executable tests, and distinguishes mandatory format behavior from resource
and transport policy. Non-UTF-8 codec fixtures are explicitly adapted fixtures,
not falsely described as unmodified independent-producer output.

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

0.3.0 implements legacy MD5/SHA-1, declared tag encodings, RFC3986 absolute-URI
grammar and explicitly authorized HTTP(S) receipt. These are no longer deferred.
Further optional compatibility includes legacy BagIt versions, additional
transports, normalization-aware filename reconciliation and serialized-bag
adapters. Signatures, lock services, hostile mutation
isolation and crash durability are distinct security concerns, not guarantees
of the current checksum validator.
