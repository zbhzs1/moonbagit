# Observed verification

Date: 2026-10-19. Source tests and commands are in this repository; this document
does not promise full RFC conformance, production performance or committee approval.

## Local checks

- MoonBit 0.1.20260920 / moonc 0.10.14: strict JS check, JS build and format check.
- 84 distinct MoonBit unit tests on JS and WASM-GC (not 168 distinct tests).
- 35 CLI/independent-tool scenarios against both published bagit-python 1.9.0
  source and pinned upstream source. Windows skips newline filenames and
  unprivileged symlink creation; see CONFORMANCE.md for source identities.
- Five independently maintained v1.0 fixtures from LibraryOfCongress's
  conformance suite, pinned to `9ab48705c06664f9f419ca740c728c9f89a61e7c`.
  One valid fixture accepted and four invalid fixtures rejected. This small
  externally supplied suite is not proof of exhaustive RFC coverage.
- One 20 MiB binary payload exercised streaming hashing and independent validation.
- New cases cover invalid host directory inventories, lossless metadata writing,
  offline fetch writing, pre-staging configuration rejection, receiving-profile
  failures without output publication, and source preservation.

## Real filesystem measurement

`python scripts/benchmark.py --files 10000 --bytes 1024` created real files,
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

## Remote and release evidence

Version 0.2.0 local checks above are complete. Its remote CI, registry publication
and fresh-consumer results will be recorded only after they actually complete.
The evidence below is the previous 0.1.0 release, not proof of the new release.

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
is included in subsequent CI runs. No local credentials are necessary to
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
