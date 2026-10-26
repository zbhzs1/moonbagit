# Reproducible handoff workflows

Build first with MoonBit 0.1.20261012 or later and Node.js 22 or later:

```powershell
npm ci --ignore-scripts
moon build --target js
```

Run from the repository root. Every named output below must be absent before
creation; choose fresh paths when repeating. The three original workflows below
do not download payloads. The explicit authorized receipt workflow is documented
in RFC8493-AUDIT.md and exercised with a real HTTP server by scripts/rfc8493.py.

## Research dataset delivery

A producer has a measurement directory and a receiver's metadata/algorithm
agreement. Package it only if the required README, nested directory, dataset
type, organization and SHA-512 manifests are present.

```powershell
node bin/moonbagit.mjs create examples/payload research-handoff --both --metadata examples/research-metadata.json --profile examples/research-profile.json
node bin/moonbagit.mjs validate research-handoff --profile examples/research-profile.json
```

Expected: creation reports `published: true`; receiving reports `conforms: true`
and `bag.valid: true`, both exit 0. If required metadata is omitted, creation
exits 1 without publishing the requested output and reports retained staging.
The CLI regression suite tests both cases and verifies source preservation.

## Digital-library export receiving

A receiving operator obtains a BagIt directory containing opaque documents.
Check that transport has not dropped, added or changed files before ingesting.
The example uses the shipped payload instead of redistributing library data.

```powershell
node bin/moonbagit.mjs create examples/payload library-export --both
node bin/moonbagit.mjs validate library-export
node bin/moonbagit.mjs lint library-export
```

Expected: validation exits 0 with `complete: true`, `valid: true`, 2 payload
files and 116 bytes. `lint` reports portability warnings, not checksum validity.
Never mutate the input during validation. To reproduce missing-file and
same-size-corruption failures in disposable directories, run:

```powershell
python -m pip install bagit==1.9.0
python scripts/interop.py Interop.test_missing_payload Interop.test_extra_payload Interop.test_same_size_corruption_is_complete_not_valid
```

The tests assert exit 1 and distinguish incomplete bags from checksum failure;
the independent bagit-python tool also rejects missing/corrupted payloads.
Digests do not authenticate the sender or authorize library ingestion.

## Existing archive checksum migration

A preservation operator has a valid SHA-256 bag and now needs SHA-512 too.
Create a new bag retaining the original payload and metadata; refuse corrupted
input instead of recomputing its manifests as if it were valid.

```powershell
node bin/moonbagit.mjs create examples/payload archive-sha256 --sha256
node bin/moonbagit.mjs upgrade archive-sha256 archive-upgraded --sha512
node bin/moonbagit.mjs validate archive-upgraded
python scripts/interop.py Interop.test_upgrade_preserves_bytes_and_independent_validity Interop.test_upgrade_refuses_corruption_without_resigning
```

Expected: new bag contains both payload manifests, and every old/new tag
manifest covers both; validation exits 0. The tests compare source bytes before
and after, require independent-tool validity, and reject corrupt sources
without creating the requested output. This is migration, not data repair.

These are local directory workflows. Network transfer, archive extraction,
repository storage, authentication and durable ingest are separate adapters.
