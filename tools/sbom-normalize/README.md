# Bounded dependency SBOM normalization

This Rust release helper rewrites SPDX 2.3 document-local identifiers to short,
deterministic labels. It does not remove packages, files, relationships, licenses,
external package references or other metadata. An inverse mapping must reproduce
the complete parsed input document before any output is accepted. Arbitrary-
precision JSON numbers retain their original precision.

Input is one regular, non-symlink JSON file, bounded to 32 MiB of raw scanner
staging. Output must fit the unchanged 16 MiB release-asset limit. Unknown local
references, duplicate node IDs, external-document references and unsupported
document shapes fail closed. Output is written to an adjacent temporary file,
synced and atomically renamed only after validation succeeds.

The release workflow pins Syft 1.42.3 and obtains this helper from the exact
public workflow commit. The helper is a packaging tool, not a shipped application
runtime. Its Cargo dependencies are locked.

## Verification

Run cargo test --locked and cargo clippy --locked --all-targets -- -D warnings
in this directory. The repository-level regression extracts the real workflow
commands and tests source isolation, all SPDX local-reference fields, large
metadata, unresolved references, unchanged input on failure and output bounds.

From the repository root, run:
bash scripts/test-release-sbom-source.sh .github/workflows/release-sign.yml /absolute/path/to/raw.spdx.json

The final argument is optional; supplying actual scanner output exercises the
same Rust helper against that full artifact.

## Exact release reproduction

Syft 1.42.3 scanned the complete immutable application source at
74cf22760dc853bf7dadebba76b54c9a2d7d1d09 using scan dir:SOURCE -o spdx-json.
The official Linux archive matched published SHA256
0d6be741479eddd2c8644a288990c04f3df0d609bbc1599a005532a9dff63509.

The raw artifact was 18,482,689 bytes. Normalized output was 14,185,420 bytes:
8,231 packages, 38 files and 42,457 relationships, all retained. An independent
inverse mapping reproduced the original JSON, and both documents passed the
official SPDX 2.3 JSON schema. These are local reproduction results, not proof of
a subsequent successful signed release.

Raw SHA256: a88936a419a1bdbf66601f20e503a0dd343fb6019d220419a97258539d722b4a.
Rust output SHA256: 0f9af9d4a14ad5f38ffa4aa5898cff68aedbc5ad1bfbff5335b0ad472e86e3eb.
