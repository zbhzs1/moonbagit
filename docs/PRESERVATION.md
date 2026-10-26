# Preservation and receiving workflows

These optional MoonBit APIs support repeated real BagIt directory handoffs.
They do not change RFC 8493 or require another format to read an ordinary bag.
BagIt validity, receiving acceptance and historical preservation are separate
questions, with separate results. None authenticates a sender or signs evidence.

## Run the complete workflow

After `npm ci --ignore-scripts` and `moon build --target js`:

```powershell
node bin/moonbagit.mjs create examples/payload example-bag --both
node bin/moonbagit.mjs audit example-bag
node bin/moonbagit.mjs snapshot example-bag --label outgoing
node bin/moonbagit.mjs accept example-bag examples/receiving-policy.json
node bin/moonbagit.mjs verify-delivery example-bag example-bag
```

`snapshot` emits its JSON document on stdout. Store that output **outside** the
bag using your application's JSON writer. In PowerShell 7, for example:

```powershell
node bin/moonbagit.mjs snapshot example-bag | Set-Content -Encoding utf8NoBOM outgoing.json
node bin/moonbagit.mjs verify-snapshot example-bag outgoing.json
node bin/moonbagit.mjs snapshot example-bag | Set-Content -Encoding utf8NoBOM incoming.json
node bin/moonbagit.mjs compare outgoing.json incoming.json
```

PowerShell 5.1's `Out-File` defaults to UTF-16; do not silently substitute that
for a UTF-8 JSON writer. The commands read snapshots, never overwrite them.
Keep the authoritative snapshot in a trusted location: an attacker who can
replace both it and the bag can fabricate a consistent history.

## Incremental manifest input

`manifest_reader(name, max_line_units?, max_entries?)` accepts arbitrary decoded
chunks through `reader.feed(chunk)` and produces a `Manifest` with `finish()`.
CR, LF, CRLF split across chunks, a final unterminated row, empty manifests,
checksum/path errors and duplicate paths across chunks follow the whole-text
parser. Supplied limits must be positive and are deployment choices, not extra
BagIt requirements. Line length is measured in decoded UTF-16 code units.
The caller still performs strict byte decoding in the declared charset.

Buffers append without repeatedly copying the entire current line. Successful
entries and their duplicate index remain in memory; this is incremental input,
not a claim of constant memory for the resulting complete manifest model.
The first failure is latched with `filename:line:message`; later feeds and
finalization cannot recover into an apparently successful result. Finalized
readers are not reusable. Use a new instance for another manifest.

`inspect_manifest` instead recovers row-by-row and locates multiple syntax and
duplicate errors. Its `parsed_entries` are partial explanatory data, never a
replacement for full validation or a source of integrity credit.

## Explain checksum evidence

`audit_bag` returns the original `Report`, source-line diagnostics and sorted
per-file evidence: manifest, algorithm, expected/observed digest and status
(`verified`, `mismatch`, `missing`, `unavailable`). A malformed manifest receives
no partial checksum credit. `verified_algorithms` lists algorithms having at
least one verified entry, not universal coverage by every listed algorithm.
Unlisted optional tags and tag manifests themselves may be RFC-valid but are
not automatically protected. `group_diagnostics` produces stable code/path
groups without losing error/warning counts.

## Preserve and compare

`capture_snapshot` requires a fully valid bag and at least one supported
raw-byte digest per file, including otherwise unprotected tag manifests.
Snapshots deep-copy normalized digest maps. The explicit `snapshot_document`
and `parse_snapshot` wire schema is `moonbagit-snapshot/1`; unknown fields,
duplicate paths/directories, unsafe paths, missing parents, malformed digests,
negative/overflowing counts and unsupported schema versions fail closed.
All size fields are canonical decimal **strings**, preserving Int64 values
above JavaScript's safe-integer range. Labels do not participate in comparison.

`compare_snapshots` explains added/removed/modified/unverifiable files, digest
set changes, empty directory changes and repeated metadata values. Matching
length without a shared digest is never equality. Every common digest must
agree; a successful SHA-256 cannot hide a differing SHA-512. Removing a digest
while retaining matching shared evidence is reported without claiming the
bytes changed. `payload_identical` is separate from whole-directory identity.
Metadata field names are case-insensitive and repeated values retain order.
Path comparison is exact; no silent Unicode normalization or rename guessing.
Report arrays use explicit UTF-16 lexical ordering independent of locale.

`verify_snapshot_inventory` recomputes comparison against host-provided current
records, requiring **every** digest recorded in the trusted snapshot. Missing,
extra, duplicate and colliding records are diagnostics. This API alone says
nothing about current manifest syntax. `revalidate_snapshot` combines that
check with fresh RFC validation, declaration and decoded metadata checks;
the CLI `verify-snapshot` uses this combined API.

## Receiving policy is not an RFC rule

`receiving_policy(name)` defaults to verified SHA-512 payload coverage,
protected non-tagmanifest tag files and no legacy manifests. Empty payloads
and fetch files are allowed; quotas are absent until supplied. It aligns with
default creation's SHA-512. Required algorithms refer to **verified manifest
coverage**, not incidental digests the host happens to calculate.

`parse_receiving_policy` and `receiving_policy_document` use
`moonbagit-receiving-policy/1`. Unknown fields and contradictory or duplicate
algorithm rules are errors. Optional limits are null or canonical nonnegative
decimal strings. Zero is a real limit, not "unlimited". Supported constraints:

- Required payload/tag algorithms, legacy-manifest rejection, tag protection.
- Optional portability gate, empty-payload and fetch-file decisions.
- Payload file count, total payload bytes, per-payload-file bytes, total tag bytes.
- Path depth in components, entries per manifest and overlapping path budgets.

Every matching path budget applies; a broad passing quota cannot override a
narrow failing one. Budget `*` follows the existing profile glob API and matches
slashes. All files, including tag manifests, count toward matching budgets.
Tag manifests cannot cover themselves; tag-protection rules exempt them.
Policies make a post-scan decision; they are not substitutes for the adapter's
pre-scan caps or streamed network limits. `AcceptanceReport.bag.valid` remains
true for a valid bag rejected only because the receiver's quota is stricter.
BagIt Profiles 1.4 (`--profile`) remain independent of this local policy schema.

## Transfer planning and receipt

`plan_transfer` first executes existing-content fetch preflight, then rejects
destination/file-ancestor conflicts. It produces expected checksums, required
parent directories and deterministic sequential batches bounded by reserved
bytes and file count. `parse_transfer_options` uses
`moonbagit-transfer-options/1`; defaults permit only HTTPS and reserve at most
1 GiB total/per-file/per-batch, 16 files per batch. An unknown size is rejected
unless the caller supplies `unknown_size_reservation`.

`known_bytes` and `reserved_bytes` are deliberately distinct. Reservations do
not prove future body size or enforce a runtime limit. Scheme selection is not
origin authorization, DNS/SSRF protection, a downloader, or a resumable range
protocol. Use the actual receiver for authorized bounded HTTP(S) execution.

```powershell
node bin/moonbagit.mjs transfer-plan incomplete-bag examples/transfer-options.json
node bin/moonbagit.mjs verify-delivery incomplete-bag received-bag --complete-fetch
node bin/moonbagit.mjs fetch incomplete-bag received-bag --allow-origin https://trusted.example --policy examples/receiving-policy.json
```

`verify_delivery` requires shared SHA-256/SHA-512 raw-byte evidence for each
previously present file. Exact-copy mode requires both bags fully valid.
Fetch-completion mode permits only declared missing payload files and their
needed parent directories. Existing payload, tag bytes, decoded texts and empty
directories must survive unchanged; a newly valid but rewritten bag is not an
unchanged handoff. Final full integrity validation is always required. Real
HTTP receipt now runs this gate and optional policy before staged publication.

## Collections and trust

`evaluate_collection` gives each uniquely identified bag a separate acceptance
decision and checked aggregate counts. Empty collections do not pass. All
items are visited even when one bag is invalid. CLI `collection BAGS.json
POLICY.json` reads an array of `{ "identifier", "path" }` objects; relative
paths are resolved against the process working directory. Filesystem scanning
failures are operational errors, not fabricated per-bag validation results.
This is read-only collection evaluation, not transactional collection storage.

Core APIs trust the host's bytes, sizes and computed hashes. The Node adapter
provides streaming maintained hashes, while code supplied by another caller
must meet the same contract. Neither snapshots nor receipts provide signatures,
hostile-concurrency isolation or crash-durable publication. Keep source files
quiescent during an operation. All original format/security boundaries remain.

Reproduce the new real-filesystem checks with `python scripts/preservation.py`;
unit tests run on JS and WASM-GC. Original independent bagit-python and RFC
receipt suites remain mandatory CI steps rather than being replaced by this
implementation's own snapshots.
