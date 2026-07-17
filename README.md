# Syntaur — distribution & verification

This is the **public distribution repository** for [Syntaur](https://syntaur.app). It contains everything you need to **install** Syntaur and **independently verify** that the binaries you run were built from legitimate, unmodified source — without exposing the application source itself.

Syntaur is a paid, closed-source product, licensed under the [End User License Agreement](EULA.md) (accepted at install). The application source lives in a private repository. **The build and signing pipeline, however, is fully public** (see [`.github/workflows/release-sign.yml`](.github/workflows/release-sign.yml)) so that anyone can audit exactly how a published binary is produced and confirm its provenance. Source confidentiality and supply-chain transparency at the same time.

## Install

**Linux / macOS:**
```sh
wget https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.sh
sh install.sh --server      # gateway + service unit  (--connect for client-only)
# First install asks for EULA acceptance; the exact current acceptance is reused.
```
The Linux/macOS installer includes the native Syntaur browser engine when that asset is present, with `syntaur-viewer` and the system browser as fallbacks. An exact accepted EULA version and hash are durable; another prompt is required only when that authority changes or the record is unsafe. It requires [Cosign](https://docs.sigstore.dev/system_config/installation/), downloads `checksums.txt` plus its bundle, and **verifies every installed binary before installing it**. Managed Linux installs also authenticate a versioned, root-owned process inspector carrying only `CAP_SYS_PTRACE`; the main runtime remains unprivileged. Missing verification tooling or trust assets aborts the install; `--skip-verify` never bypasses the runtime or inspector hashes.

The two-line bootstrap above trusts GitHub HTTPS for the installer script itself. To verify the installer independently before execution, download a versioned `install.sh`, its bundle, `checksums.txt`, and the operation metadata from the same release, establish the accepted workflow commit as below, then verify the installer exactly like any other manifest entry before running it.

**Windows (PowerShell):**
```powershell
& ([scriptblock]::Create((irm https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.ps1))) --server --accept-eula
```

## Verify a release yourself

Every artifact in a release is signed with [Sigstore cosign](https://docs.sigstore.dev/) (keyless, OIDC) and ships with a `.cosign.bundle`. The signing identity is **this repo's public workflow**, so the signature proves the binary came from our auditable pipeline.

```bash
set -euo pipefail

# Resolve the release tag independently before trusting release-owned bytes.
# Organizations can additionally compare this SHA with an out-of-band release approval.
TAG=v0.7.112
VERIFY_REPO=$(mktemp -d)
git -C "$VERIFY_REPO" init -q
git -C "$VERIFY_REPO" fetch -q --depth=1 \
  https://github.com/syntaur-systems/syntaur-dist.git "refs/tags/$TAG"
DIST_COMMIT=$(git -C "$VERIFY_REPO" rev-parse 'FETCH_HEAD^{commit}')
printf '%s' "$DIST_COMMIT" | grep -Eq '^[0-9a-f]{40}$'

# The signed operation must name the already-accepted workflow commit.
test "$(jq -er '.dist_commit | select(type == "string" and test("^[0-9a-f]{40}$"))' \
  syntaur-release-operation.json)" = "$DIST_COMMIT"

# Authenticate the operation metadata, then the checksum manifest.
cosign verify-blob \
  --bundle syntaur-release-operation.json.cosign.bundle \
  --certificate-identity "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-github-workflow-sha "$DIST_COMMIT" \
  syntaur-release-operation.json
cosign verify-blob \
  --bundle checksums.txt.cosign.bundle \
  --certificate-identity "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-github-workflow-sha "$DIST_COMMIT" \
  checksums.txt

# Verify every manifest entry, plus the artifact-specific signature.
sha256sum -c checksums.txt
cosign verify-blob \
  --bundle syntaur-gateway-linux-x86_64.cosign.bundle \
  --certificate-identity "https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-github-workflow-sha "$DIST_COMMIT" \
  syntaur-gateway-linux-x86_64
```

Verification queries the public [Sigstore Rekor transparency log](https://docs.sigstore.dev/logging/overview/) and Fulcio certificate — it does **not** require access to any private repository. The identity and workflow-SHA constraints prove the bytes came from the independently accepted public workflow commit.

Release operation assets are immutable. Once dispatch is durably recorded, failure to bind the original repository-dispatch attempt consumes that version. Once the exact run and attempt are recorded, a missing or failed attempt, or any manual/rerun substitute, also requires a successor version. Only the same recorded attempt while it remains nonterminal may be resumed; the release process never replaces signed authority assets.

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
