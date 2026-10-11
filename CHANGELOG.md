# Changelog

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
