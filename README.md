# Syntaur — distribution & verification

This is the **public distribution repository** for [Syntaur](https://syntaur.app). It contains everything you need to **install** Syntaur and **independently verify** that the binaries you run were built from legitimate, unmodified source — without exposing the application source itself.

Syntaur is a paid, closed-source product, licensed under the [End User License Agreement](EULA.md) (accepted at install). The application source lives in a private repository. **The build and signing pipeline, however, is fully public** (see [`.github/workflows/release-sign.yml`](.github/workflows/release-sign.yml)) so that anyone can audit exactly how a published binary is produced and confirm its provenance. Source confidentiality and supply-chain transparency at the same time.

## Install

**Linux / macOS:**
```sh
wget https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.sh
sh install.sh --server      # gateway + service unit  (--connect for client-only)
# The installer asks you to accept the EULA; pass --accept-eula to pre-accept.
```
The Linux/macOS installer includes the native Syntaur browser engine when that asset is present, with `syntaur-viewer` and the system browser as fallbacks. It downloads `checksums.txt` + the cosign bundle from the release and **verifies every installed binary before installing it** (use `--skip-verify` to bypass — it warns loudly).

**Windows (PowerShell):**
```powershell
& ([scriptblock]::Create((irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1))) --server --accept-eula
```

## Verify a release yourself

Every artifact in a release is signed with [Sigstore cosign](https://docs.sigstore.dev/) (keyless, OIDC) and ships with a `.cosign.bundle`. The signing identity is **this repo's public workflow**, so the signature proves the binary came from our auditable pipeline.

```bash
# 1. SHA-256 (fast integrity check)
sha256sum -c checksums.txt

# 2. Cosign signature (authoritative — proves who built it)
cosign verify-blob \
  --bundle syntaur-gateway-linux-x86_64.cosign.bundle \
  --certificate-identity "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  syntaur-gateway-linux-x86_64
```

Verification queries the public [Sigstore Rekor transparency log](https://docs.sigstore.dev/logging/overview/) and Fulcio certificate — it does **not** require access to any private repository. A signature that verifies against the identity above could only have been produced by a run of the public workflow in this repo.

See [`SECURITY.md`](SECURITY.md) for the full verification, provenance, disclosure, and source-audit-on-request policy.

## What's in this repo

| Path | Purpose |
|---|---|
| `install.sh`, `install.ps1` | The verifiable installers customers run |
| `EULA.md` | The End User License Agreement (v1.0) accepted at install/purchase |
| `.github/workflows/release-sign.yml` | The public build → sign → publish pipeline (checks out private source via a read-only deploy key) |
| `cosign.pub` | Public key for the local-signed deploy-stamp path (see SECURITY.md) |
| `SECURITY.md` | Verification + vulnerability disclosure + source-audit policy |
| Releases | Signed binaries + `checksums.txt` + `*.cosign.bundle` |
