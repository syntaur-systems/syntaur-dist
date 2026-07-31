# Syntaur release authority

Production publication is authorized by a frozen, independently approved
`syntaur-ship`, never by the candidate being judged. Authority checkpoints are
public immutable releases in `syntaur-systems/syntaur-dist`; product source
remains private.

The only genesis is an evidence-approved V2 generation 1 while the
authority release namespace is empty. Every later checkpoint is the exact
N+1 successor of the newest independently verified immutable checkpoint.
Genesis and ordinary product deployment are separate acts: generation 1 may
authorize only a distinct later source commit.

## Automated prerequisites

Configure every item below before adding source or signing secrets or
dispatching the workflow:

1. Bind `.github/CODEOWNERS` to the repository owner with exactly:

   ```text
   * @buddyholly007
   ```

2. Protect `main`, including administrators. Require an up-to-date branch,
   conversation resolution, no force pushes or deletion, and exactly these
   GitHub-Actions-bound required checks:

   ```text
   release-workflow
   windows-eula
   ```

   The lint workflow runs on every push and pull request, so either check can
   never be silently skipped by a path filter.

3. Create one active tag ruleset named `release-authority-tags`, targeting only
   `refs/tags/authority-v1-g*`. It must enforce creation, update, deletion, and
   non-fast-forward rules. Its only bypass actor is the repository Admin role,
   with `always` mode. The GitHub Actions App must not bypass it. The namespace
   retains `authority-v1-gN` for historical continuity even though new
   manifests are V2.

4. Enable immutable releases.

5. Create two protected environments:

   - `release-authority-source` gates private-source checkout and decryption;
   - `release-authority` gates approval of the exact compared candidate.

   Both environments must disable administrator bypass, use custom deployment
   branches, and allow only the branch `main`. They intentionally have no
   person-dependent reviewer gate; the workflow's exact automated evidence
   checks are the approval gate for a solo-owned repository.

6. Put these secrets only in `release-authority-source`:

   - `SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN`, with repository
     Administration read, repository Actions read, and organization Members
     read; it must have no write permission;
   - `SYNTAUR_SOURCE_DEPLOY_KEY`, read-only for the private source repository;
   - `SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY`, an age identity with no authority
     outside decrypting this workflow's short-lived source archive.

   Put a second copy of `SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN` in
   `release-authority`, together with
   `SYNTAUR_RELEASE_AUTHORITY_PUBLISH_TOKEN`, scoped to `syntaur-dist` with
   Contents write and Attestations read. The publication token is used only by
   the isolated `publish` job. Do not store any of these as unprotected
   repository secrets.

`verify-release-authority-policy.sh` checks the branch, both environments,
immutable-release setting, and tag ruleset before source access and again
after evidence approval. Missing or ambiguous API state fails closed.

The age recipient is public and pinned in the workflow. The identity protects
private-source confidentiality, not GitHub, signing, publication, or
production authority. It is a long-lived static recipient key: anyone can copy
the public ciphertext during retention, and a later identity compromise can
decrypt every copied historical artifact encrypted to that recipient.
Artifact expiration does not revoke copied ciphertext. Rotate for each
authority ceremony by generating a new identity, changing the environment
secret and pinned recipient together in a reviewed commit, and destroying the
old identity after all jobs and independent recovery windows finish. Never
print or upload the identity.

## Separated trust domains

The workflow deliberately separates credentials, candidate execution,
signing, and publication:

1. `predecessor` has contents-read only. For generation 1 it proves the
   authority namespace is empty. For a successor it verifies the newest
   immutable release, exact asset set, GitHub attestations, canonical
   manifest, Cosign identity, payload hashes, and predecessor digest. An exact
   already-published target is reconciled and exits successfully.
2. `repository_policy` runs behind `release-authority-source` and proves the
   live GitHub controls before any source credential is used.
3. `source_metadata`, also behind `release-authority-source`, is the only job
   with the read-only deploy key. It checks out the exact reviewed commit,
   proves credential removal, verifies the source identity and provisioner,
   and, for G1, proves exact one-parent ancestry and an authority-only delta
   while comparing all non-authority Cargo.lock data with a digest-pinned TOML
   parser. It rejects unsafe archive entries and uploads only an age-encrypted,
   one-day-retention source archive.
4. Two `isolated_build` jobs receive only the zero-authority age identity in
   one step. They verify its pinned recipient, decrypt, erase the identity,
   prove no credential remains, normalize the verified checkout to the
   unprivileged builder UID, fetch locked dependencies, then build and
   self-test inside a digest-pinned container. Candidate execution has no
   network, capabilities, host credentials, OIDC, or write token. Private
   compiler and candidate diagnostics are not emitted to public Actions logs.
5. `compare_builds` requires exact file sets, byte-identical binaries and
   metadata, the eight-key shipper protocol, the shipper self-test that binds
   its compiled version and embedded source commit, and the verifier protocol
   self-test. Its pre-approval summary binds every reviewed source, ancestry,
   binary, baseline, browser, schema, toolchain, approval-record, and canonical
   manifest digest.
6. `approval_policy` is protected by the separate `release-authority`
   environment and rechecks live policy after the exact comparison succeeds.
7. `sign` has OIDC but no contents-write permission. It reconstructs the
   reviewed manifest and never executes the candidate.
8. `publish` has no OIDC and its ordinary `GITHUB_TOKEN` is read-only. Behind
   `release-authority`, it is the only job that receives the environment-held
   publication token, rechecks policy, re-verifies the signed package,
   reconciles only an exact draft, rechecks the tag and draft immediately
   before publication, publishes, and proves immutability.

No job has both OIDC and publication authority. No job that holds the private
deploy key executes candidate code.

## Generations, drafts, and reruns

Generation is:

```text
reviewed previous generation + 1
```

For the sole genesis, previous generation is `0`, its digest is 64 zeroes, and
the result is generation `1`. Genesis is accepted only when the authority
namespace is empty. A successor must name the newest immutable predecessor and
its exact manifest digest. `GITHUB_RUN_ID` is used only to make artifact names
unique; it is never a generation.

No tag or release is created before reproducible builds, comparison, automated
approval, reconstruction, signing, and verification pass. The isolated
publisher job then creates the exact commit tag before staging the release as
a draft. A retry can reconcile only the exact tag, workflow commit, canonical
manifest, signature, five assets, and approval record. Each consumer selects
the newest immutable artifact for its producer and builder within the same
workflow run, accepting the download action's direct single-artifact layout
as well as its per-artifact multi-match layout, so failed-job and full reruns
do not confuse run attempts.
Unknown assets, a moved
tag, another target commit, an immutable collision, an unverified predecessor,
or a skipped generation fails closed. A complete full-workflow rerun recognizes
the exact immutable target and performs no new privileged work.

## Manifest contract

V2 has exactly these five release assets:

```text
release-authority-v2.json
release-authority-v2.json.cosign.bundle
syntaur-build-authority-provision
syntaur-ship-linux-x86_64
syntaur-verify-linux-x86_64
```

Legacy V1 predecessors remain readable only to verify historical migration
state; new genesis and every new release are V2. Mixed, missing, duplicated, or
extra assets fail closed.

The canonical V2 manifest has exactly 29 ordered fields. It binds ancestry,
source, all three payloads, toolchain, baseline, browser, verifier, workflow,
and the exact eight-key protocol returned by:

```sh
/usr/local/bin/syntaur-ship authority-protocol-inputs
```

The protocol keys are:

```text
schema
provisioner_sha256
production_contract_sha256
production_member_count
receipt_schema
build_authority_schema
promotion_recovery_schema
promotion_recovery_sha256
```

This signed future-product protocol fixes production member count `12`,
receipt schema `6`, build-authority schema `4`, and promotion-recovery schema
`1`. The verifier must emit the exact canonical
`syntaur-verify --authority-protocol-self-test` line for verifier schema `5`,
18 required gates, four viewport gates, and protocol
`syntaur-verify-attestation-v5`.

The one-time Genesis validation has a separate, non-authorizing contract. Its
exact ordered baseline contains five members from the source-closed
`b003360f63707d92fd0df1fd12384282f1c3004f` core:

```text
rust-openclaw
mace
syntaur_browser
runtime-compose
runtime-entrypoint
```

Five does not mean “everything that happened to be live” at that historical
point. `syntaur-isolation-tests` is a separate validation artifact. CAPTCHA,
Social, `release-images.env`, the Tailscale entrypoint, SearXNG settings, the
physical Frame payload, and every runtime/production generation are
future-product members and cannot appear in the Genesis baseline. The
build-authority schema still binds `frame_sysroot_tree_sha256`; that is future
toolchain authority, not a Genesis Frame artifact.

The verifier manifest’s `approved_baseline_*` fields describe the independently
approved visual/browser verification baseline. They are unrelated to the
five-member Genesis build baseline and must never be used as its inventory or
contract hash.

## One-time V2 generation-1 bootstrap

Generation 1 must be an authority-only source commit containing the reviewed
shipper, verifier, provisioner, crash-safe promotion transaction, and release
contract. It must not be the product candidate it later authorizes.

1. Complete all automated prerequisites above and merge the reviewed public
   workflow through protected `main`.
2. Independently reproduce the authority-only source tree, shipper, verifier,
   provisioner, the five-member Genesis contract, browser, toolchain, and the
   separate signed 12-member future-product protocol values. Prove the G1
   source is an exact one-parent descendant of `b003360f63707d92fd0df1fd12384282f1c3004f`.
3. Render and validate an approval record with previous generation `0` and a
   64-zero predecessor digest. Dispatch **Freeze or promote release authority**
   from `main`; the complete comparison and both protected environment stages
   must pass.
4. Independently verify the immutable generation-1 release. Download exactly
   its five assets into a new canonical operator-owned directory whose parents
   are not group/world writable. Set the directory to `0500`, the manifest and
   bundle to `0400`, and executables to `0500`.
5. From the independently reviewed public checkout, record the helper digest.
   Independently record the current provisioner and Genesis-validator digests;
   use the all-zero digest only after proving the corresponding path absent.
   Then run the non-authorizing verification and staging:

```sh
scripts/bootstrap-release-authority-genesis-v2.sh verify \
  --source-dir "$SOURCE_DIR" \
  --expected-manifest-sha256 "$G1_MANIFEST_SHA256" \
  --expected-workflow-commit "$G1_WORKFLOW_COMMIT" \
  --expected-authority-version "$G1_VERSION" \
  --expected-authority-commit "$G1_SOURCE_COMMIT" \
  --expected-shipper-sha256 "$G1_SHIPPER_SHA256" \
  --expected-verifier-sha256 "$G1_VERIFIER_SHA256" \
  --expected-provisioner-sha256 "$G1_PROVISIONER_SHA256" \
  --expected-helper-sha256 "$G1_HELPER_SHA256"

sudo scripts/bootstrap-release-authority-genesis-v2.sh stage-build-authority \
  --source-dir "$SOURCE_DIR" \
  --expected-manifest-sha256 "$G1_MANIFEST_SHA256" \
  --expected-workflow-commit "$G1_WORKFLOW_COMMIT" \
  --expected-authority-version "$G1_VERSION" \
  --expected-authority-commit "$G1_SOURCE_COMMIT" \
  --expected-shipper-sha256 "$G1_SHIPPER_SHA256" \
  --expected-verifier-sha256 "$G1_VERIFIER_SHA256" \
  --expected-provisioner-sha256 "$G1_PROVISIONER_SHA256" \
  --expected-helper-sha256 "$G1_HELPER_SHA256" \
  --expected-current-provisioner-sha256 "$CURRENT_PROVISIONER_SHA256" \
  --expected-current-validator-sha256 "$CURRENT_GENESIS_VALIDATOR_SHA256"

SYNTAUR_WORKSPACE="$EXACT_G1_SOURCE_WORKTREE" \
SYNTAUR_ENGINE_WORKSPACE="$EXACT_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit "$G1_SOURCE_COMMIT" \
    --engine-commit "$GENESIS_ENGINE_COMMIT" \
    >"$GENESIS_EVIDENCE"
chmod 0400 "$GENESIS_EVIDENCE"
```

**STOP. Do not run installation in this shell or as a continuation of the
producer command.** Review the one-record `syntaur.genesis-validation.v2`
JSON. Its `authority_source` is the later G1 authority-only commit, while the
gateway proof and five-member baseline are pinned to `b003360f`. Independently
verify the recomputed baseline inventory ID and manifest hash, the separate
isolation artifact, both fresh builds, Mac browser/gateway proof, root-owned
Mac host-key pin and explicit identity fingerprint, retained build-authority
catalog, source and Engine commits, and the generation-1 checkpoint's exact
`RUSTSEC_DB_COMMIT`. The record must contain no runtime generation, production
generation, deployment stamp, Frame payload/proof, release receipt, rollback,
or deployment authority. Retain the evidence outside the host and record its
digest and Engine/RustSec commits in the external ceremony record.

Only after that separate evidence review, start a separate installation shell and populate
`REVIEWED_GENESIS_EVIDENCE_SHA256`, `REVIEWED_GENESIS_ENGINE_COMMIT`, and
`REVIEWED_GENESIS_RUSTSEC_DB_COMMIT` from the independently retained record.
Do not derive those variables with command substitution from the live evidence
file. Then run:

```sh
sudo scripts/bootstrap-release-authority-genesis-v2.sh install \
  --source-dir "$SOURCE_DIR" \
  --expected-manifest-sha256 "$G1_MANIFEST_SHA256" \
  --expected-workflow-commit "$G1_WORKFLOW_COMMIT" \
  --expected-authority-version "$G1_VERSION" \
  --expected-authority-commit "$G1_SOURCE_COMMIT" \
  --expected-shipper-sha256 "$G1_SHIPPER_SHA256" \
  --expected-verifier-sha256 "$G1_VERIFIER_SHA256" \
  --expected-provisioner-sha256 "$G1_PROVISIONER_SHA256" \
  --expected-helper-sha256 "$G1_HELPER_SHA256" \
  --expected-rustsec-db-commit "$REVIEWED_GENESIS_RUSTSEC_DB_COMMIT" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$REVIEWED_GENESIS_EVIDENCE_SHA256" \
  --expected-genesis-engine-commit "$REVIEWED_GENESIS_ENGINE_COMMIT"
```

Both root actions are allowed only on `claudevm`. Staging creates the
non-authorizing host-global lock and CAS-installs the signed provisioner plus a
root-owned validator copied from the signed shipper while proving the canonical
release root remains absent. It also installs the exact root-owned
`/etc/syntaur/mac-mini-known-hosts` record and an exact content-addressed Mac
identity under `/etc/syntaur/`. The private identity is root-owned,
operator-readable, link-count/size/private-digest pinned, and independently
cross-checked against its reviewed public digest and fingerprint. Genesis
executes the root-owned validator as the ordinary operator, disables
ssh-agent/default identities, certificates, and ambient host-key trust, uses
only those protected files, and performs the exact immutable build and Mac
proof under the same host-global and canonical deployment locks.

The installer locks the same global and deployment files, snapshots every
operator-owned input into bounded root-owned storage, validates the approved
Genesis record, and only then atomically publishes the complete authority root
and installs the exact shipper. The live `/usr/local/bin/syntaur-ship` has the
distinct exact mode `01755`; the sticky bit is a role tag, not credential
authority. Retained generation executables remain `0555`. Bootstrap and
promotion prove root ownership, digest, and link count; the bounded launcher
then binds its inherited descriptor to the canonical installed path, inode,
and initial/self mount provenance. The immutable
`/etc/syntaur/release-authority/genesis/` proof namespace retains the reviewed
Genesis evidence and a separate install receipt binding its digest, Engine
commit, RustSec commit, manifest, shipper, and provisioner; exact reruns must
match that receipt. The validator itself never emits a release or deployment
receipt. Generation 1 retains only the exact six-file V2 promotion
contract so the installed shipper can consume it as a later predecessor. The
one-time validator is then removed. The provisioner must already be the staged
signed version and cannot be repaired after publication. An exact rerun repairs
a root-owned bounded snapshot, an exact staged provisioner or shipper, and the
private hard-link residue from interrupted lock publication. A different
authority root, unsafe residue, changed provisioner, or missing/mismatched
Genesis proof fails closed.

Generation 1 then runs the mandatory product pipeline for a distinct descendant
commit containing the queued security, camera, physical Frame, memory, and
other backlog changes:

```text
claudevm build → Mac Mini smoke/verification → GitHub push/publication
→ TrueNAS container binary swap → live TrueNAS and physical Frame proof
```

That product commit is the first candidate authorized by generation 1. It is
not necessary to create a generation-2 checkpoint merely to deploy it. A later
authority checkpoint is created only when authority itself changes, and the
installed predecessor must first have authorized and deployed that distinct
successor source.

## Fixed G1-G2-G3 recovery

The immutable G1 release cannot produce truthful Genesis evidence for its own
authority-only source commit. G2 corrects that source gate, while G3 contains
the integrated product control plane that must authorize the next distinct
product release. The versioned
`scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh` is the only
recovery for that exact published chain. It is not a generic promotion path
and has no caller-supplied authority, protocol, toolchain, or predecessor
override.

Download the five exact immutable assets from `authority-v1-g1`,
`authority-v1-g2`, and `authority-v1-g3` into three distinct canonical
operator-owned directories. Each directory must be `0500`; manifests and
bundles must be `0400`; executables must be `0500`. Then run the non-mutating
chain check:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR"
```

On `claudevm`, while the authority root is absent and the exact G1
provisioner, validator, global lock, and Mac trust are still installed, stage
the corrected G2 Genesis tools:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh \
  stage-g2-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR"
```

Run the staged G2 validator as the ordinary operator from the exact G2 source
and Engine worktrees. Capture stdout into a new one-record canonical evidence
file and stderr separately. Do not use `sudo` around the validator:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G2_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit 5642d7bc36a4913d42d9bce1120a3a2fe604aca8 \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

Independently validate the complete nested evidence contract, persistent
three-layer build catalog, source and Engine identities, RustSec provenance,
Mac smoke bindings, and continued authority-root absence. Set the final
evidence file to `0400`, record its SHA-256 and the exact pre-recovery
`/usr/local/bin/syntaur-ship` SHA-256, then install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1, 2, and 3; keeps the Genesis
receipt truthfully bound to G2; activates G3; installs the exact G3 shipper;
runs `authority-status` as the ordinary operator; and only then retires the G2
validator. A status failure preserves the validator and the exact published
root for a same-input retry. Exact reruns are idempotent. Missing predecessor
state, changed evidence or catalog bytes, an unknown current shipper, a
different authority root, or an inexact retained generation fails closed.

The next product release must be a distinct descendant of G3. The recovery
does not authorize G3 to release itself.

## Fixed G1-G2-G3-G4 recovery

When the authority root is still absent after G4 has been published, do not
run the earlier G1-G2-G3 recovery first. G4 Genesis rejects a pre-existing
authority root, so that ordering would permanently prevent the truthful G4
ceremony. Use only the versioned
`scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh` for this
exact four-release chain.

Download and independently verify the five immutable assets from each of
`authority-v1-g1` through `authority-v1-g4` in four distinct canonical
directories. Normalize directories to `0500`, manifests and bundles to
`0400`, and executables to `0500`. Verify the full signed successor chain:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR"
```

While the authority root remains absent, stage the exact G4 provisioner and
G4 shipper-as-validator:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh \
  stage-g4-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR"
```

Run the staged validator as the ordinary operator from exact G4 commit
`417e2f6b8e0518ccd314680ba9d68766378e4900` and exact Engine commit
`36f3348fc32c02d0a0091be9ea87b828306941cc`. The evidence must bind the G4
source to parent commit `8003e39735ebed5a326ee011001937be64bc340c`
and parent tree `998e1a949928d145b4186c79384c946c927b79ec`, in addition to the
full Genesis contract:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G4_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit 417e2f6b8e0518ccd314680ba9d68766378e4900 \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

After independently checking that one-record canonical evidence, its G4
catalog, the source and parent identities, and continued authority-root
absence, install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1 through 4, activates G4,
installs the exact G4 shipper and provisioner, and records a G4-bound Genesis
receipt. It retires the validator only after unprivileged `authority-status`
succeeds. Failed status checks preserve the validator and published root for
an exact idempotent retry. The next product release must be a distinct
descendant of G4.

## Fixed G1-G2-G3-G4-G5 recovery

When the authority root is still absent after G5 has been published, use only
the versioned
`scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh`.
Do not first install an earlier recovery: Genesis requires an absent authority
root. G5 is the controller authority, while its isolated build authority
truthfully reconstructs exact G2 source and exact Engine source in separate
worktrees.

Download and independently verify the five immutable assets from each of
`authority-v1-g1` through `authority-v1-g5` in five distinct canonical
directories. Normalize directories to `0500`, manifests and bundles to
`0400`, and executables to `0500`. Verify the complete signed successor chain:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR"
```

While the authority root remains absent and the exact G4 Genesis tools are
staged, install the G5 provisioner and G5 shipper-as-validator:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh \
  stage-g5-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR"
```

Run the staged validator as the ordinary operator. The controller workspace
must be exact G5 commit
`dc670026daf6765e01f5208b8b823ea47e4b63d5`; the distinct baseline workspace
must be exact G2 commit
`5642d7bc36a4913d42d9bce1120a3a2fe604aca8`; and the Engine workspace must be
exact commit `36f3348fc32c02d0a0091be9ea87b828306941cc`.
`SYNTAUR_GENESIS_BASELINE_WORKSPACE` is mandatory and must not resolve to
either other workspace:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G5_SOURCE_WORKTREE" \
  SYNTAUR_GENESIS_BASELINE_WORKSPACE="$G2_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit dc670026daf6765e01f5208b8b823ea47e4b63d5 \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

The canonical schema-v3 evidence binds G5 source and its G4 parent, but binds
`baseline_source`, `build_authority.source_*`, and the persistent catalog to
G2. Independently check those identities, both Cargo.lock digests, the
separate workspace paths, the complete nested Genesis contract, and continued
authority-root absence. Then install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1 through 5, activates G5,
installs the exact G5 shipper and provisioner, and records the G5 controller
with the G2 reconstruction catalog. It retires the validator only after
unprivileged `authority-status` succeeds. Failed status checks preserve the
validator and published root for an exact idempotent retry. The next product
release must be a distinct descendant of G5.

## Fixed G1-G2-G3-G4-G5-G6 recovery

When the authority root is still absent after G6 has been published, use only
the versioned
`scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh`.
Do not first install an earlier recovery. G6 is the controller authority; its
isolated build authority still reconstructs exact G2 source and exact Engine
source in separate worktrees.

Download the five immutable assets from each of `authority-v1-g1` through
`authority-v1-g6` into six distinct canonical directories. Normalize
directories to `0500`, manifests and bundles to `0400`, and executables to
`0500`, then verify the complete signed successor chain:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR"
```

With the exact G5 Genesis tools staged and the authority root still absent,
install the G6 provisioner and G6 shipper-as-validator:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh \
  stage-g6-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR"
```

Run the staged validator as the ordinary operator. The controller workspace
must be exact G6 commit
`3f57a12d405e793fc69d649146576c5989eea649`; the distinct baseline workspace
must be exact G2 commit
`5642d7bc36a4913d42d9bce1120a3a2fe604aca8`; and the Engine workspace must be
exact commit `36f3348fc32c02d0a0091be9ea87b828306941cc`:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G6_SOURCE_WORKTREE" \
  SYNTAUR_GENESIS_BASELINE_WORKSPACE="$G2_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit 3f57a12d405e793fc69d649146576c5989eea649 \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

The canonical schema-v3 evidence binds G6 source and its G5 parent while
binding `baseline_source`, `build_authority.source_*`, and the persistent
catalog to G2. Independently record its digest and the current shipper digest,
then install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh \
  install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1 through 6, activates G6,
installs the exact G6 shipper and provisioner, and records the G6 controller
with the G2 reconstruction catalog. It retires the validator only after
unprivileged `authority-status` succeeds.

## Fixed G1-G2-G3-G4-G5-G6-G7 recovery

When the authority root is still absent after G7 has been published, use only
the versioned
`scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh`.
Do not first install an earlier recovery. G7 is the controller authority; its
isolated build authority still reconstructs exact G2 source and exact Engine
source in separate worktrees.

Download the five immutable assets from each of `authority-v1-g1` through
`authority-v1-g7` into seven distinct canonical directories. Normalize
directories to `0500`, manifests and bundles to `0400`, and executables to
`0500`, then verify the complete signed successor chain:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR"
```

With the exact G6 Genesis tools staged and the authority root still absent,
install the G7 provisioner and G7 shipper-as-validator:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh \
  stage-g7-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR"
```

The G6 and G7 provisioners are intentionally byte-identical; staging accepts
that shared exact digest without requiring a false binary distinction. The G7
shipper-as-validator must have the distinct G7 digest.

Run the staged validator as the ordinary operator. The controller workspace
must be exact G7 commit
`bf9def327af774b4269972e209a7e2914f81d42d`; the distinct baseline workspace
must be exact G2 commit
`5642d7bc36a4913d42d9bce1120a3a2fe604aca8`; and the Engine workspace must be
exact commit `36f3348fc32c02d0a0091be9ea87b828306941cc`:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G7_SOURCE_WORKTREE" \
  SYNTAUR_GENESIS_BASELINE_WORKSPACE="$G2_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit bf9def327af774b4269972e209a7e2914f81d42d \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

The canonical schema-v3 evidence binds G7 source and its exact G6 parent while
binding `baseline_source`, `build_authority.source_*`, and the persistent
catalog to G2. Independently record its digest and the current shipper digest,
then install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh \
  install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1 through 7, activates G7,
installs the exact G7 shipper and provisioner, and records the G7 controller
with the G2 reconstruction catalog. It retires only the exact G7 validator,
and only after unprivileged `authority-status` succeeds.

## Fixed G1-G2-G3-G4-G5-G6-G7-G8 recovery

When the authority root is still absent after G8 has been published, use only
the versioned
`scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh`.
Do not first install an earlier recovery. G8 is the controller authority; its
isolated build authority still reconstructs exact G2 source and exact Engine
source in separate worktrees.

Download the five immutable assets from each of `authority-v1-g1` through
`authority-v1-g8` into eight distinct canonical directories. Normalize
directories to `0500`, manifests and bundles to `0400`, and executables to
`0500`, then verify the complete signed successor chain:

```sh
scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh verify \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR" \
  --g8-dir "$G8_DIR"
```

With the exact G7 Genesis tools staged and the authority root still absent,
install the G8 provisioner and G8 shipper-as-validator:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh \
  stage-g8-build-authority \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR" \
  --g8-dir "$G8_DIR"
```

The G7 and G8 provisioners are intentionally byte-identical; staging accepts
that shared exact digest without requiring a false binary distinction. The G8
shipper-as-validator must have the distinct G8 digest.

Run the staged validator as the ordinary operator. The controller workspace
must be exact G8 commit
`10486d641b2594f812b5a0eca4a483ded303337b`; the distinct baseline workspace
must be exact G2 commit
`5642d7bc36a4913d42d9bce1120a3a2fe604aca8`; and the Engine workspace must be
exact commit `36f3348fc32c02d0a0091be9ea87b828306941cc`:

```sh
env -i \
  HOME=/home/sean USER=sean LOGNAME=sean \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 RUST_LOG=info \
  SYNTAUR_WORKSPACE="$G8_SOURCE_WORKTREE" \
  SYNTAUR_GENESIS_BASELINE_WORKSPACE="$G2_SOURCE_WORKTREE" \
  SYNTAUR_ENGINE_WORKSPACE="$GENESIS_ENGINE_WORKTREE" \
  /opt/syntaur-genesis-validator genesis-validate \
    --commit 10486d641b2594f812b5a0eca4a483ded303337b \
    --engine-commit 36f3348fc32c02d0a0091be9ea87b828306941cc \
    >"$GENESIS_EVIDENCE_PARTIAL" \
    2>"$GENESIS_LOG"
```

The canonical schema-v3 evidence binds G8 source and its exact G7 parent while
binding `baseline_source`, `build_authority.source_*`, and the persistent
catalog to G2. Independently record its digest and the current shipper digest,
then install:

```sh
sudo scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh \
  install \
  --g1-dir "$G1_DIR" \
  --g2-dir "$G2_DIR" \
  --g3-dir "$G3_DIR" \
  --g4-dir "$G4_DIR" \
  --g5-dir "$G5_DIR" \
  --g6-dir "$G6_DIR" \
  --g7-dir "$G7_DIR" \
  --g8-dir "$G8_DIR" \
  --genesis-evidence "$GENESIS_EVIDENCE" \
  --expected-genesis-evidence-sha256 "$GENESIS_EVIDENCE_SHA256" \
  --expected-current-shipper-sha256 "$PRE_RECOVERY_SHIPPER_SHA256"
```

Installation atomically retains generations 1 through 8, activates G8,
installs the exact G8 shipper and provisioner, and records the G8 controller
with the G2 reconstruction catalog. It retires only the exact G8 validator,
and only after unprivileged `authority-status` succeeds.

## Independent dispatch verification

Record values from an independently reviewed checkout and isolated baseline,
not from the downloaded release:

```sh
/usr/local/bin/syntaur-ship authority-inputs
/usr/local/bin/syntaur-ship authority-protocol-inputs
```

Export the values accepted by `render-approval-record`, then create the single
canonical no-trailing-newline dispatch input:

```sh
scripts/release-authority-manifest.sh \
  render-approval-record authority-approval.json
scripts/release-authority-manifest.sh \
  validate-approval-record authority-approval.json
test "$(wc -l <authority-approval.json)" = 0
```

After publication, independently prove the tag is a direct commit ref to the
reviewed workflow commit; the release is immutable, non-draft, and
non-prerelease; its assets are exact; GitHub release and asset attestations
verify; the canonical manifest and Cosign identity verify; ancestry is exact;
and every reviewed source, binary, baseline, browser, verifier, toolchain, and
protocol value matches. Never resolve authority through `latest`.

## Exact successor promotion handoff

For a later V2 successor, create the operator-owned handoff:

```sh
scripts/release-authority-manifest.sh stage-v2 \
  release-authority-v2.json \
  release-authority-v2.json.cosign.bundle \
  "$DOWNLOAD_DIR" \
  "$SOURCE_DIR"
scripts/release-authority-manifest.sh validate-stage-v2 "$SOURCE_DIR"
```

Run `sudo /usr/local/bin/syntaur-ship authority-promote --dry-run` with every
independently recorded expected generation, predecessor, source, payload,
workflow, production-contract, receipt, provisioner, and promotion-recovery
field. Review it, then repeat the exact command without `--dry-run`.

Promotion holds the root promotion lock, operator deployment lock, and global
mutation fence. It requires exact live deploy proof, no pending release,
deployment, journal, rollback, outbox, or Frame transaction, and an exact
completed candidate release. It stages root-owned bytes before journaling,
publishes the manifest last, and retains the active generation plus three
signed ancestors.

If the process or host stops after journaling, do not delete files or invent a
rollback. Re-run the exact command with the same expected values. The installed
shipper revalidates the live proof and exact K/K+1 position, then resumes
forward. There is no bypass, recover-only, or force flag.

After bootstrap or promotion:

```sh
/usr/local/bin/syntaur-ship authority-status
/usr/local/bin/syntaur-ship doctor
```

Ordinary product releases continue to use the installed N-1 authority. A
checkpoint can authorize only a distinct later candidate.
