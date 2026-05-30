# Security & transparency policy

Syntaur is closed-source, but its supply chain is open to inspection. This document explains how to verify what you run and how to report problems.

## Verifying a release

Every released artifact (each binary, plus `install.sh`, `install.ps1`, and `checksums.txt`) is signed with [Sigstore cosign](https://docs.sigstore.dev/) keyless signing. The OIDC signing identity is **this repository's public build workflow**:

```
https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main
issuer: https://token.actions.githubusercontent.com
```

To verify (example for the Linux gateway):

```bash
sha256sum -c checksums.txt

cosign verify-blob \
  --bundle syntaur-gateway-linux-x86_64.cosign.bundle \
  --certificate-identity "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  syntaur-gateway-linux-x86_64
```

A passing verification proves the artifact was produced by a run of the public workflow in this repo and has not been altered since. The check consults the public Sigstore Rekor transparency log and Fulcio CA only — **no access to private source is needed to verify.**

## Build provenance

- The application source is private. The **build pipeline is public** — read [`.github/workflows/release-sign.yml`](.github/workflows/release-sign.yml) to see exactly how binaries are compiled, smoke-tested, signed, and published.
- The pipeline checks out the private source via a **read-only deploy key**, builds each platform on GitHub-hosted runners, signs keyless, and publishes a [SLSA build-provenance attestation](https://slsa.dev/) (`actions/attest-build-provenance`) alongside the binaries.
- `cosign.pub` is the public half of the **local** cosign key used to sign internal *deploy-stamps* (deployment provenance for the maintainer's own infrastructure). It is unrelated to release-binary signing, which is keyless.

## Source audit on request

We want legitimate reviewers to be able to confirm there is nothing improper in the code, even though it is not open source. Two mechanisms:

1. **Reviewer access:** vetted security researchers, prospective enterprise customers, or auditors may request **read access** to the private source repository (optionally under NDA). Open an issue here or email the address below.
2. **Point-in-time disclosure:** on request we can publish a signed source snapshot + full SBOM for a specific release so a third party can reproduce the build and confirm the shipped binary derives from the disclosed source.

A Software Bill of Materials (SBOM) is published with releases; cargo dependency audits (`cargo-audit`) and CodeQL scans run against the source and their summaries can be shared on request.

## Reporting a vulnerability

Two private channels, both monitored:

- **Email** **security@syntaur.app** — routed to a monitored inbox.
- **GitHub** — this repository's **Security → Report a vulnerability** tab (private vulnerability reporting).

Please include reproduction steps and the affected version. We aim to acknowledge within 72 hours. **Do not open a public issue for an unpatched vulnerability.**
