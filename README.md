# MoonBagIt

[![CI](https://github.com/zbhzs1/moonbagit/actions/workflows/ci.yml/badge.svg)](https://github.com/zbhzs1/moonbagit/actions/workflows/ci.yml)

BagIt 1.0 archive-directory creation and validation for MoonBit, based on
[RFC 8493](https://www.rfc-editor.org/rfc/rfc8493.html).

The input is a directory of opaque files, such as a research dataset or a
digital-library export. The output is a standard BagIt directory, not a custom
JSON evidence pack, backup database, ZIP file, or network transfer service.

## Quick Start

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and Node.js
22 or later. Use MoonBit `moon 0.1.20260920` or later. This release was tested with
`moonc v0.10.14` and
Node.js 24.14.1.

```powershell
moon check --target js
moon test --target js
moon build --target js
node bin/moonbagit.mjs create examples/payload example-bag --both --metadata examples/metadata.json
node bin/moonbagit.mjs validate example-bag
```

`example-bag` must not already exist. Creation leaves the source unchanged.
Default creation uses SHA-512; `--sha256` and `--both` select other supported
manifest sets. Metadata is an ordered JSON array of `{ "label", "value" }`
objects, allowing repeated labels and multi-line values. `Payload-Oxum` is
computed by MoonBagIt and cannot be supplied by the caller.
Metadata rejects NUL, terminal escape and other control characters except TAB
and value LF. This is a conservative input policy, not a claim that every such
restriction is mandated by RFC 8493. Continuation indentation is syntax in
BagIt: the writer rejects values with leading spaces/tabs after LF rather than
silently losing those characters when read back. Normalize such values explicitly.

```text
example-bag/
  bagit.txt
  bag-info.txt
  manifest-sha256.txt
  manifest-sha512.txt
  tagmanifest-sha256.txt
  tagmanifest-sha512.txt
  data/
    readme.txt
    nested/measurement.csv
```

Validation returns JSON with `complete`, `valid`, payload counts, verified
checksum counts and diagnostics containing `code`, `path`, `message` and
`severity`. Int64 counts use decimal strings to preserve integer precision.
Exit codes: `0` valid/success, `1` invalid or unsupported bag, `2` I/O or CLI
failure. Invalid UTF-8 is an I/O decoding failure, not silently replaced text.

Changing payload bytes without changing its length leaves the structure
complete but makes it invalid. Adding an unlisted payload file makes the bag
incomplete. SHA digests detect corruption; they do not authenticate the sender
or protect against an attacker who can rewrite files and manifests together.

## Library

The root MoonBit package exports typed models, `parse_declaration`,
`parse_manifest`, `parse_metadata`, `parse_fetch`, `encode_path`, `decode_path`,
`create_tags`, `create_tag_manifests`, `payload_oxum`, and `validate`.
It also exports `parse_profile`, `validate_profile`, `plan_upgrade`, and
`lint_portability`.

Add the published library to an independent MoonBit project:

```powershell
moon add zbhzs1/moonbagit@0.1.0
```

Add `"zbhzs1/moonbagit" @bag` to the consumer package's `import` block. Then call
`@bag.parse_declaration(...)`, `@bag.create_tags(...)` or `@bag.validate(...)`.
The registry library does not install a global CLI: clone this repository and
build the JS target for real-filesystem commands.

`BagView` separates the rules engine from its filesystem. It contains file
records with relative paths, Int64 sizes and raw-byte digests, directory names,
and strictly decoded text tags. Callers must supply accurate records and hashes.
The directory list must include every parent directory, including empty
directories. Duplicate/unsafe directory names, file/directory collisions and
standard tag filenames used as directories are rejected rather than trusted.
`validate` does not read files or compute hashes itself. The CLI supplies these
through a small Node.js adapter using streaming `node:crypto` hashes; there is
no custom cryptographic implementation. The pure core also runs on WASM-GC.

Creation uses two stages: `create_tags` generates the declaration, metadata and
payload manifests; after the caller hashes these exact UTF-8 bytes,
`create_tag_manifests` generates tag manifests. See the runnable CLI and
generated interface for the full signatures.

Run the in-memory library example without Node filesystem integration:

```powershell
moon run examples/core --target wasm-gc
```

## Supported Scope

| Area | Current behavior |
| --- | --- |
| Declaration | BagIt 1.0, UTF-8 only; exact field order; no BOM |
| Payload manifests | SHA-256 and SHA-512; every manifest covers every payload file exactly once |
| Tag manifests | Required payload-manifest coverage; forbid payload and tag-manifest references; check listed arbitrary tags |
| Metadata | Ordered/repeated fields, continuations; unique and numeric Payload-Oxum |
| Paths | `/` separators, normative `%25`, `%0D`, `%0A`; no traversal, absolute, NUL, drive or backslash paths |
| Checksums | Verify every supported manifest, including all tag manifests |
| Fetch | Parse and check local coverage/length; missing remote files remain incomplete; no download or URI execution |
| Additional tags | Opaque content; verify if listed; unprotected tags produce warnings |
| Host safety | Reject symlinks and special files; no source overwrite; new output only |
| Receiving profiles | BagIt Profiles 1.4.0 rules for metadata, algorithms, fetch, files/directories and directory serialization constraints |
| Digest upgrade | Add supported manifests to a new output; retain payload, metadata and existing payload manifests; regenerate every tag manifest |
| Portability lint | Advisory device-name, trailing-character, case-collision and path-length diagnostics |

## Receiving and Upgrading

The included research-data scenario supplies receiving requirements, rather
than generic JSON schema validation. Profile JSON is read from a caller-selected
local file; profile identifiers and fetch URLs are never executed or fetched.

```powershell
node bin/moonbagit.mjs create examples/payload research-bag --both --metadata examples/research-metadata.json
node bin/moonbagit.mjs validate research-bag --profile examples/research-profile.json
node bin/moonbagit.mjs lint research-bag
node bin/moonbagit.mjs create examples/payload sha256-bag --sha256
node bin/moonbagit.mjs upgrade sha256-bag upgraded-bag --sha512
node bin/moonbagit.mjs validate upgraded-bag
```

Profile results expose `conforms`, the separate base `bag` report, and profile
diagnostics. A checksum-valid bag can fail a receiving profile. Unknown profile
keys and older profile specifications are rejected, not ignored. Only `*` is a
wildcard and matches zero or more characters, including `/`. Serialized input
is currently not opened: a profile requiring serialization rejects a directory
bag. `optional` permits this directory input; its accepted MIME types describe
serialized input, not the directory. See [profiles](docs/PROFILES.md).

Upgrade checks the original bag, copies it to sibling staging, rechecks the
copy, adds missing manifests and regenerates all old/new tag manifests so that
they cover every payload manifest. Existing corrupt bags are refused; upgrade
is not a repair or authenticity service. The original bag is never modified.
Existing valid manifests are preserved byte-for-byte; repeating an upgrade
produces the same manifest content when tag coverage was already complete.
Previously unprotected arbitrary tags are included in regenerated tag manifests.
The pure `plan_upgrade` API only prepares payload manifests: the host must hash
their exact bytes before calling `create_tag_manifests`.

## Compatibility Boundaries

This is a **defined subset**, not a claim of complete RFC conformance. Legacy
BagIt versions, MD5/SHA-1, non-UTF-8 tags, automatic fetch, Unicode normalization
matching, and general RFC 3986 URI validation are future compatibility work.
The fetch parser currently verifies an absolute URI scheme and token structure,
not every URI grammar rule. Case-only collisions produce warnings. Portable
path restrictions intentionally reject some otherwise legal Unix filenames.

The CLI supports 100,000 files and 100,000 directories, 16 MiB per standard text
tag and 64 MiB total standard text. Payload hashing is streaming. File sizes
must fit the Node.js safe-integer range; the core uses Int64. File mutation is
checked while reading, but this is not a hostile-filesystem sandbox or lock
service. Keep the source, destination and scanned bag quiescent during an
operation. Creation uses a sibling staging directory and renames it only after
validation; failed staging directories are retained for inspection. It does
not promise crash durability or race-free publication against another writer.

## Verification

```powershell
moon test --target js
moon test --target wasm-gc
python -m pip install bagit==1.9.0
python scripts/interop.py
git -c core.autocrlf=false clone https://github.com/LibraryOfCongress/bagit-conformance-suite.git ../bagit-conformance-suite
git -C ../bagit-conformance-suite checkout 9ab48705c06664f9f419ca740c728c9f89a61e7c
python scripts/conformance.py ../bagit-conformance-suite
python scripts/benchmark.py --files 10000 --bytes 1024
python scripts/consumer.py
```

The independent [Library of Congress bagit-python](https://github.com/LibraryOfCongress/bagit-python)
tool validates generated bags, and MoonBagIt validates bags generated by it.
The released tool creates BagIt 0.97, so the reverse test upgrades the declaration
to 1.0 and asks that independent tool to regenerate tag manifests. No MoonBagIt
creation or hashing is used to regenerate those independent manifests. The
same suite was also run against the pinned upstream snapshot listed in the
support document, which natively creates 1.0 bags and needs no such upgrade.

Known upstream compatibility issue: bagit-python does not decode `%25` in
manifest filenames. The percent-filename test records this limitation explicitly;
it is not counted as successful cross-tool interoperability. The normative
MoonBagIt encoding is retained. Newline-filename and symlink tests are skipped
where Windows permissions or filesystem restrictions prevent them; Linux CI
also runs the suite. See [support details](docs/CONFORMANCE.md).

## Competition Status

The public repository contains the implementation, CI workflow, executable
examples and independently reproducible tests. The current delivered scope is
the documented BagIt subset and local receiving/upgrade workflows, not a backup,
evidence-ledger or network-transfer service. [Verification details](docs/VERIFICATION.md)
separate observed checks from future work. Competition acceptance is decided
by the organizers, not by test count or a configured workflow.

## License

MIT. The implementation is written against RFC 8493, not copied from adjacent
MoonBit archive/evidence projects. `bagit-python` is a test-only independent
dependency distributed under CC0; its source is not part of this package.
The independently maintained conformance fixtures and BagIt Profiles
specification are also CC0. See [third-party references](THIRD_PARTY.md).
