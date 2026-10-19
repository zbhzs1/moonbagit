# Architecture and reproducible review map

This is a maintainer self-check, not an organizer acceptance certificate.
Use the latest main CI and the versioned registry artifact, not an old green
badge or a local dependency override, when repeating the checks.

## Purpose and adjacent capabilities

MoonBagIt reads and writes the existing RFC 8493 BagIt directory format.
It does not introduce another JSON evidence-pack format or snapshot database.
The deliverable is interoperable `bagit.txt`, `data/`, payload manifests,
optional metadata and tag manifests, plus receiving-profile checks.

There is real overlap in directory scanning and checksums with generic
evidence/manifest tools (for example
[MoonEvidence](https://github.com/wenlittle/MoonEvidence)) and backup tools
(for example [moonrestore](https://github.com/bzhangui/moonrestore)).
The reason to expose a separate library is the BagIt format contract:
per-manifest payload coverage, tag-manifest constraints, normative filename
escaping, complete/valid separation, local BagIt Profiles rules and verification
against independently produced BagIt bags. These are the claimed differences,
not exclusive ownership of hashing or a promise that no other project exists.
No code from those adjacent projects is included.

## MoonBit and host responsibilities

The MoonBit package owns parsing/writing (`text.mbt`), inventory consistency
(`inventory.mbt`), manifest coverage and integrity reports (`validate.mbt`),
creation (`create.mbt`), receiving rules (`profiles.mbt`), upgrade planning
(`upgrade.mbt`) and portability diagnostics (`portability.mbt`). The runnable
CLI orchestration is also MoonBit (`cmd/main/main.mbt`). The pure API runs on
JS and WASM-GC; real-directory CLI I/O currently requires Node.js.

The Node adapter (`bin/host.mjs`) performs file traversal, bounded UTF-8 reads,
streaming standard-library SHA-256/SHA-512 and staged filesystem publication.
It is not the implementation of BagIt rules. The core checks inventory
structure, but trusts the caller to supply accurate file bytes and hashes;
it is not a new cryptographic algorithm or a hostile-filesystem sandbox.

## Evidence by requirement

| Requirement | Reproducible evidence |
| --- | --- |
| Public source and traceable work | [Repository](https://github.com/zbhzs1/moonbagit), [commits](https://github.com/zbhzs1/moonbagit/commits/main/), CHANGELOG.md; real changes, not empty commits |
| Clear declared functions | Implementation modules above; docs/CONFORMANCE.md support matrix and explicit unsupported-input policy |
| Installation, usage, examples | README.md; docs/SCENARIOS.md provides three complete local workflows |
| CI checks, build, tests | .github/workflows/ci.yml; Linux/Windows, strict check, format, JS build, JS/WASM-GC core tests |
| Runnable library example | `moon run examples/core --target wasm-gc`; CLI examples require `moon build --target js` first |
| Core failure paths | Unit tests for syntax, paths, coverage, inventories, metadata and profiles; scripts/interop.py for corruption, no-overwrite, source preservation and independent-tool interoperability |
| External checks | scripts/conformance.py uses pinned unmodified external fixtures; scripts/interop.py uses bagit-python, not a second handwritten BagIt implementation |
| Registry delivery | [Mooncakes package](https://mooncakes.io/docs/zbhzs1/moonbagit); docs/VERIFICATION.md records version/hash; scripts/consumer.py installs from registry in a new temporary project |
| Open-source compliance | MIT LICENSE; THIRD_PARTY.md records specification and test-tool sources/licenses; external fixtures are not claimed as original implementation |

## Limits that still matter

The examples use synthetic datasets, not endorsements or production adoption
by a research institute or library. Positive independent-tool cases and known
upstream percent-filename failures are distinguished in CONFORMANCE.md.
Windows cannot exercise newline filenames or unprivileged symlink creation;
Linux CI must run those cases rather than counting skips as coverage.

The delivered subset is BagIt 1.0, UTF-8, SHA-256/SHA-512 and local directories.
General URI grammar, network fetch, legacy formats, other algorithms/encodings
and serialized-bag extraction remain compatibility work. Do not describe them
as completed capabilities. Source/output trees must remain quiescent; no crash
durability, malicious mutation isolation or authenticity guarantee is made.

Realistic next maintenance work is receiving-agreement feedback, more pinned
interoperability regressions and separately reviewed compatibility adapters.
These should become new tested releases if implemented, not retroactive claims
about the current package. Competition identity, original contribution,
proposal authorship and final acceptance are decisions outside this test suite.
