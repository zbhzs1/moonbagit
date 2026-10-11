# Local receiving profiles

Reference: [BagIt Profiles 1.4.0](https://bagit-profiles.github.io/bagit-profiles-specification/), CC0.
This is a strict directory-oriented subset. It does not download identifiers,
complete remote bags, accept archive files, or support older profile versions.
Profile parsing validates types and internal required/allowed contradictions;
all unknown keys fail closed so that a receiving constraint cannot disappear.

| Constraint | Behavior |
| --- | --- |
| BagIt-Profile-Info | Required identity, description, organization, version and specification version 1.4.0; optional contacts |
| Bag-Info | Required fields, repeatability, exact allowed values; metadata labels compared case-insensitively |
| BagIt-Profile-Identifier | Matching identifier must appear in bag-info.txt; repeated identifiers are permitted |
| Manifests-Required/Allowed | Required algorithms and allowed sets checked independently; unsupported digest algorithms still fail base validation |
| Tag-Manifests-Required/Allowed | Same checks applied to tag manifests |
| Allow-Fetch.txt/Fetch.txt-Required | Explicit permitted/required presence; no download performed |
| Data-Empty | No files, or exactly one zero-byte file |
| Serialization/Accept-Serialization | Directory allowed for optional/forbidden; required serialization rejects this input; accepted MIME list required for optional/required |
| Accept-BagIt-Version | Nonempty accepted list; cannot override the core's supported BagIt version |
| Tag-Files-Required/Allowed | Exact required files and literal/star allowed path patterns |
| Payload-Files-Required | Exact files or directories ending in `/`; required directory must contain a file or subdirectory |
| Payload-Files-Allowed | Exact files or patterns; permitted directory patterns end in `/*`; empty directories are checked too |

The profile's path namespace is always relative to the bag root. `data/` is
payload; other file paths are tags. Path safety restrictions also apply to
profile paths. The `*` wildcard can cross separators; `?`, brackets and regular
expression syntax are not operators. Unicode is matched exactly. Directory
existence is based on the supplied host inventory, not inferred from fabricated
file records. Directly constructed `Profile` objects are trusted configuration;
use `parse_profile` for untrusted JSON.

`examples/research-profile.json` and `examples/research-metadata.json` define a
complete runnable measurement-dataset receiving scenario. It requires a dataset
type, organization, README, nonempty nested payload directory and SHA-512
payload/tag manifests. Copy the profile and change its identifier and rules for
your own receiving agreement; the example's main-branch URI is not an immutable
production contract.

`validate_profile` returns both the base integrity report and profile diagnostics.
`conforms` is true only when both are successful. A profile mismatch does not
change the base report into a checksum failure. A matching profile or
Payload-Oxum cannot make corrupt content valid. Serialized inputs should be
verified and safely unpacked by a separately reviewed adapter before using the
directory API; no archive extraction is hidden in this module.
