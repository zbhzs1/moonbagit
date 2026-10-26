# Bidirectional verification with bagit-python

This is an executable acceptance check, not a claim of complete BagIt compatibility.
The independently maintained implementation is
[LibraryOfCongress/bagit-python](https://github.com/LibraryOfCongress/bagit-python),
CC0. No validation or manifest-generation code in that dependency is patched.
This matrix was introduced for 0.2.1 and is retained for 0.3.0. The latter also
adds the required-behavior/authorized-receipt suite documented in
[RFC8493-AUDIT.md](RFC8493-AUDIT.md).

## Two directions and their assertions

| Direction | Independent operation | Required observed result |
| --- | --- | --- |
| MoonBagIt -> bagit-python | MoonBagIt CLI creates a bag; `bagit.Bag(path).validate()` reads its actual files | Python returns true; MoonBagIt reports complete/valid; payload SHA-256 map matches input |
| bagit-python -> MoonBagIt | `bagit.make_bag(path, checksums=...)` creates manifests; MoonBagIt CLI validates them without rewriting | Python self-validation returns true; MoonBagIt exits 0 with complete/valid; payload SHA-256 map matches input |

Each direction runs SHA-256 only, SHA-512 only, and both algorithms: six positive
cases per dependency identity. Inputs include a nested path with spaces, a
Unicode filename, an empty file and binary bytes including CR/LF, NUL and 0xff.
Snapshots assert that validation leaves each valid bag unchanged and that the
original input is preserved. The report records commands, exit codes, JSON
diagnostics, producer version, dependency module hash and per-file SHA-256 maps.

For each positive bag, three separate copies introduce same-length payload
corruption, a missing payload, and protected tag corruption: eighteen negative
controls. Both validators must reject all eighteen. MoonBagIt must distinguish
complete-but-invalid corruption from incomplete missing payloads. These are
additional checks, not eighteen more successful interoperability exchanges.

## Version distinction: do not hide conversion

PyPI **1.9.0** creates BagIt **0.97** by default, outside MoonBagIt's 1.0 scope.
For that released-source reverse check only, the runner explicitly replaces
`bagit.txt` with a 1.0/UTF-8 declaration, reloads the Python bag and invokes
Python's own `save()` to regenerate tag manifests. This adaptation is recorded
per case. It is not native 0.97 support and is not counted as an unmodified 1.0
producer. MoonBagIt does not generate the independent manifests.

The separate upstream source pinned to
**`4bd2713cedbe1f8e634567c20ef0dded9622011d`** natively creates BagIt **1.0**.
`--require-native-1` makes the runner fail if that producer emits another
version; this run performs **no declaration or manifest adaptation**. CI installs
it into an isolated directory so it does not replace the released-source check.
The SCM version override used when building the shallow source archive only
supplies distribution metadata; source identity is the pinned revision.

## Reproduce

Prerequisites: Python 3.12, Node.js 22+, MoonBit as described in README, and Git.
Run from this checkout after `moon build --target js`. Each output path must be
new; the runner will not overwrite an earlier evidence directory.

```powershell
npm ci --ignore-scripts
python -m pip install bagit==1.9.0
python scripts/interop_report.py --source-id PyPI:bagit==1.9.0 --output interop-evidence/released
git -c core.autocrlf=false clone https://github.com/LibraryOfCongress/bagit-python.git .interop/bagit-python
git -C .interop/bagit-python checkout 4bd2713cedbe1f8e634567c20ef0dded9622011d
$env:SETUPTOOLS_SCM_PRETEND_VERSION="0.0.0"
python -m pip install --no-deps --target .interop/upstream ./.interop/bagit-python
python scripts/interop_report.py --bagit-path .interop/upstream --source-id LibraryOfCongress/bagit-python@4bd2713cedbe1f8e634567c20ef0dded9622011d --require-native-1 --output interop-evidence/native-1.0
```

On Bash, use `export SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0` for the environment
assignment. A passing run prints `PASS: 6 bidirectional positive cases and 18
independent negative controls`. Inspect each output's `report.json`: `status`
must be `passed`, with six `positive_cases` and eighteen `negative_cases`.
The native run's three Python-produced cases must show `producer_version: [1, 0]`
and `adaptation: null`. Failed runs preserve the partial report and return nonzero.

## CI and evidence retrieval

The [CI workflow](../.github/workflows/ci.yml) runs both dependency identities
on Linux and Windows, in addition to core tests and the existing 37 CLI scenarios.
Open a successful run of the current main revision in
[GitHub Actions](https://github.com/zbhzs1/moonbagit/actions/workflows/ci.yml),
then download `bagit-bidirectional-ubuntu-latest` and
`bagit-bidirectional-windows-latest` from **Artifacts**. Each contains the two
reports plus actual positive/damaged bags, original input and all manifests.
GitHub may require sign-in to download; reports are retained for 30 days, and
the committed runner remains reproducible after expiration. Workflow success
alone is not a substitute for inspecting the dependency identity and directions.

## Known compatibility boundary

The positive matrix excludes literal-percent and CR/LF filenames. The existing
`scripts/interop.py` separately exercises these edge cases. Upstream does not
decode `%25`; its rejection of MoonBagIt's normative percent encoding is a known
limitation, **not a successful interoperability case**. No claim is made about
all BagIt versions, all algorithms, remote fetch execution or full RFC coverage.
See [CONFORMANCE.md](CONFORMANCE.md) and the requirement audit for current behavior.
