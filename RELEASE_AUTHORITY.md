# Syntaur release authority

Production publication is authorized by a frozen, independently approved
`syntaur-ship`, never by the candidate being judged. Authority checkpoints are
public immutable releases in `syntaur-systems/syntaur-dist`; product source
remains private.

The only genesis is an offline-human-approved V2 generation 1 while the
authority release namespace is empty. Every later checkpoint is the exact
N+1 successor of the newest independently verified immutable checkpoint.
Genesis and ordinary product deployment are separate acts: generation 1 may
authorize only a distinct later source commit.

## Human prerequisites

Configure every item below before adding source or signing secrets or
dispatching the workflow:

1. Create the visible (not secret)
   `syntaur-systems/release-authority-reviewers` team with at least two
   distinct people and give it explicit write access to `syntaur-dist`.
   `.github/CODEOWNERS` must contain exactly:

   ```text
   * @syntaur-systems/release-authority-reviewers
   ```

2. Protect `main`, including administrators. Require an up-to-date branch,
   code-owner review, stale-review dismissal, approval of the last push,
   conversation resolution, linear history, no pull-request bypass actors, no
   force pushes or deletion, and exactly these GitHub-Actions-bound required
   checks:

   ```text
   release-workflow
   windows-eula
   ```

   The lint workflow runs on every push and pull request, so either check can
   never be silently skipped by a path filter.

3. Create a dedicated GitHub App named
   `syntaur-release-authority-publisher`, install it only on `syntaur-dist`,
   and grant only Metadata read, Attestations read, and Contents write. Create
   one active tag ruleset named `release-authority-tags`, targeting only
   `refs/tags/authority-v1-g*`. It must enforce creation, update, deletion, and
   non-fast-forward rules. Its only bypass actor is that dedicated App, with
   `always` mode. The general GitHub Actions App must not bypass it. The
   namespace retains `authority-v1-gN` for historical continuity even though
   new manifests are V2.

4. Enable immutable releases.

5. Create two protected environments:

   - `release-authority-source` gates private-source checkout and decryption;
   - `release-authority` gates approval of the exact compared candidate.

   Both environments must disable administrator bypass, prevent self-review,
   require the exact reviewer team, use custom deployment branches, and allow
   only the branch `main`.

6. Put these secrets only in `release-authority-source`:

   - `SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN`, with repository
     Administration read, repository Actions read, and organization Members
     read; it must have no write permission;
   - `SYNTAUR_SOURCE_DEPLOY_KEY`, read-only for the private source repository;
   - `SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY`, an age identity with no authority
     outside decrypting this workflow's short-lived source archive.

   Put a second copy of `SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN` in
   `release-authority`, plus
   `SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_CLIENT_ID` and
   `SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_PRIVATE_KEY` for the dedicated App.
   The App credentials must exist in no other environment or repository.
   Do not store any of these as unprotected repository secrets.

`verify-release-authority-policy.sh` checks the branch, reviewer team, both
environments, immutable-release setting, and tag ruleset before source access
and again after candidate approval. Missing or ambiguous API state fails
closed.

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
   rejects unsafe archive entries, and uploads only an age-encrypted,
   one-day-retention source archive.
4. Two `isolated_build` jobs receive only the zero-authority age identity in
   one step. They verify its pinned recipient, decrypt, erase the identity,
   prove no credential remains, fetch locked dependencies, then build and
   self-test inside a digest-pinned container. Candidate execution has no
   network, capabilities, host credentials, OIDC, or write token. Private
   compiler and candidate diagnostics are not emitted to public Actions logs.
5. `compare_builds` requires exact file sets, byte-identical binaries and
   metadata, the eight-key shipper protocol, and the verifier protocol
   self-test. Its pre-approval summary binds every reviewed source, ancestry,
   binary, baseline, browser, schema, toolchain, approval-record, and canonical
   manifest digest.
6. `approval_policy` is protected by the separate `release-authority`
   environment and rechecks live policy after a distinct reviewer approves the
   exact comparison.
7. `sign` has OIDC but no contents-write permission. It reconstructs the
   reviewed manifest and never executes the candidate.
8. `publish` has no OIDC and its ordinary `GITHUB_TOKEN` is read-only. Behind
   `release-authority`, it rechecks policy, mints a one-job installation token
   from the dedicated publisher App, re-verifies the signed package, reconciles
   only an exact draft, rechecks the tag and draft immediately before
   publication, publishes, and proves immutability. The token is revoked by
   the action at job end.

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

No tag or release is created before reproducible builds, comparison, protected
approval, reconstruction, signing, and verification pass. The dedicated
publisher then creates the exact commit tag before staging the release as a
draft. A retry can reconcile only the exact tag, workflow commit, canonical
manifest, signature, five assets, and approval record. Each consumer selects
the newest immutable artifact for its producer and builder within the same
workflow run, so failed-job and full reruns do not confuse run attempts.
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

This revision fixes production member count `12`, receipt schema `6`,
build-authority schema `4`, and promotion-recovery schema `1`. The verifier
must emit the exact canonical
`syntaur-verify --authority-protocol-self-test` line for verifier schema `5`,
18 required gates, four viewport gates, and protocol
`syntaur-verify-attestation-v5`.

## One-time V2 generation-1 bootstrap

Generation 1 must be an authority-only source commit containing the reviewed
shipper, verifier, provisioner, crash-safe promotion transaction, and release
contract. It must not be the product candidate it later authorizes.

1. Complete all human prerequisites above and merge the reviewed public
   workflow through protected `main`.
2. Independently reproduce the authority-only source tree, shipper, verifier,
   provisioner, baseline, browser, toolchain, and protocol values.
3. Render and validate an approval record with previous generation `0` and a
   64-zero predecessor digest. Dispatch **Freeze or promote release authority**
   from `main`, inspect the complete comparison, and approve both protected
   environment stages.
4. Independently verify the immutable generation-1 release. Download exactly
   its five assets into a new canonical operator-owned directory whose parents
   are not group/world writable. Set the directory to `0500`, the manifest and
   bundle to `0400`, and executables to `0500`.
5. From the independently reviewed public checkout, record the helper digest
   and run:

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

sudo scripts/bootstrap-release-authority-genesis-v2.sh install \
  --source-dir "$SOURCE_DIR" \
  --expected-manifest-sha256 "$G1_MANIFEST_SHA256" \
  --expected-workflow-commit "$G1_WORKFLOW_COMMIT" \
  --expected-authority-version "$G1_VERSION" \
  --expected-authority-commit "$G1_SOURCE_COMMIT" \
  --expected-shipper-sha256 "$G1_SHIPPER_SHA256" \
  --expected-verifier-sha256 "$G1_VERIFIER_SHA256" \
  --expected-provisioner-sha256 "$G1_PROVISIONER_SHA256" \
  --expected-helper-sha256 "$G1_HELPER_SHA256"
```

The root action is allowed only on `claudevm`. After acquiring its root lock it
copies every operator-owned input into bounded root-owned storage, then
validates and installs only those snapshots. It atomically publishes the
complete authority root before installing the exact root-owned provisioner and
shipper. An exact rerun repairs partial executable installation; a different
root or stale snapshot fails closed.

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
