# Syntaur release authority

Production publication is authorized by a frozen, human-approved N-1
`syntaur-ship` and `syntaur-verify`, not by tools built from the candidate they
are judging. The public `release-authority.yml` workflow creates this trust
anchor. It is deliberately manual and uses the `release-authority` GitHub
Environment. Before the first run, an organization or repository administrator
must create that environment, configure required reviewers, enable **Prevent
self-review**, and disable administrator bypass. The same administrator must
enable immutable releases for `syntaur-dist` and add the environment secret
`SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN`, using a fine-grained token with
repository Administration **read-only** permission. The workflow uses that
read-only credential solely to prove the protection settings and fails closed
until they are active.

Every fresh dispatch uses its unique GitHub `GITHUB_RUN_ID` as the monotonic
generation and freezes an exact reviewed private source commit. Reruns are
rejected. A failed run burns its unique generation; never delete or reuse its
reserved tag. Only the latest published, immutable, release-attested, signed
authority can be a predecessor. The approved baseline generation/tree and
Chrome bundle, version, and launch-policy digests are explicit workflow inputs.
The workflow builds both frozen binaries, signs a canonical strict manifest
with keyless Cosign, and publishes a non-latest immutable `authority-v1-gN`
release. This cannot replace the product release selected by
`releases/latest`. Product release automation cannot invoke this workflow or
advance the authority generation. Promotions are serialized and hash-chain
each successful generation to the preceding manifest.

As of 2026-07-23, repository immutable releases are enabled and the
`release-authority` Environment is restricted to `main`, prevents self-review,
and disables administrator bypass. The organization currently has only one
member, who is also the required reviewer. The workflow therefore cannot be
approved until a distinct trusted reviewer with repository read access is
added. The environment also still needs
`SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN`, issued with repository
Administration read-only permission. Do not substitute a broad personal access
token or weaken the environment rules to bootstrap the first promotion.

## First checkpoint and later promotions

1. Review and merge the source checkpoint that introduces or advances the
   trusted verifier policy. Record its full private-source commit and the full
   public `syntaur-dist` workflow commit outside the downloaded authority
   bundle. Also record the exact version, baseline tuple, browser tuple,
   predecessor generation, and predecessor-manifest digest that were approved.
   On the machine
   holding the initialized isolated baseline and pinned browser bundle, build
   `syntaur-ship` from that exact reviewed source commit and run
   `syntaur-ship authority-inputs`. Independently inspect the one-line JSON
   tuple before entering it into the workflow; this helper derives the local
   values but does not replace the required human review or make a
   candidate-owned machine a trust anchor.
2. Start `Promote frozen release authority` from `syntaur-dist` `main`, enter
   the exact reviewed inputs, record that run's ID as its generation, and have
   a required environment reviewer approve it. Reruns are rejected. If a run
   fails, start a fresh dispatch with a new run-ID generation; do not reuse or
   delete the failed generation's reserved tag.
3. Before downloading, confirm the exact `authority-v1-gN` Release is
   published and immutable, its Git tag points to the independently recorded
   workflow commit, and its GitHub release attestation covers exactly the four
   expected assets. Download those four assets from that exact tag into a fresh
   private directory. Never resolve authority through a `latest` alias.
4. Verify the manifest before installation:

   ```sh
   EXPECTED_WORKFLOW_COMMIT='<independently recorded 40-hex dist commit>'
   EXPECTED_AUTHORITY_COMMIT='<independently reviewed 40-hex source commit>'
   EXPECTED_AUTHORITY_VERSION='<independently reviewed X.Y.Z>'
   EXPECTED_GENERATION=N
   EXPECTED_PREVIOUS_GENERATION='<independently recorded predecessor generation, or 0 when none exists>'
   EXPECTED_PREVIOUS_MANIFEST_SHA256='<independently recorded 64-hex predecessor, or 64 zeroes when none exists>'
   EXPECTED_BASELINE_PROFILE='<independently reviewed profile>'
   EXPECTED_BASELINE_GENERATION='<independently reviewed baseline generation>'
   EXPECTED_BASELINE_TREE_SHA256='<independently reviewed 64-hex baseline tree>'
   EXPECTED_BROWSER_BUNDLE_SHA256='<independently reviewed 64-hex browser bundle>'
   EXPECTED_BROWSER_VERSION='<independently reviewed Chrome-for-Testing version>'
   EXPECTED_BROWSER_LAUNCH_PROFILE_SHA256='<independently reviewed 64-hex launch policy>'
   EXPECTED_VERIFIER_SCHEMA='<independently reviewed positive schema integer>'
   TAG="authority-v1-g${EXPECTED_GENERATION}"
   test "$(gh api /repos/syntaur-systems/syntaur-dist/immutable-releases --jq '.enabled')" = true
   test "$(gh api "/repos/syntaur-systems/syntaur-dist/releases/tags/${TAG}" --jq '.draft')" = false
   test "$(gh api "/repos/syntaur-systems/syntaur-dist/releases/tags/${TAG}" --jq '.prerelease')" = false
   test "$(gh api "/repos/syntaur-systems/syntaur-dist/releases/tags/${TAG}" --jq '.immutable')" = true
   test "$(gh api "/repos/syntaur-systems/syntaur-dist/git/ref/tags/${TAG}" --jq '.object.type')" = commit
   test "$(gh api "/repos/syntaur-systems/syntaur-dist/git/ref/tags/${TAG}" --jq '.object.sha')" = "$EXPECTED_WORKFLOW_COMMIT"
   actual_assets=$(gh api "/repos/syntaur-systems/syntaur-dist/releases/tags/${TAG}" --jq '.assets[].name' | LC_ALL=C sort)
   expected_assets=$(printf '%s\n' release-authority-v1.json release-authority-v1.json.cosign.bundle syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64 | LC_ALL=C sort)
   test "$actual_assets" = "$expected_assets"
   gh release verify "$TAG" --repo syntaur-systems/syntaur-dist >/dev/null
   for asset in release-authority-v1.json release-authority-v1.json.cosign.bundle syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
     gh release verify-asset "$TAG" "$asset" --repo syntaur-systems/syntaur-dist >/dev/null
   done
   test "$(jq -er '.workflow_commit' release-authority-v1.json)" = "$EXPECTED_WORKFLOW_COMMIT"
   test "$(jq -er '.authority_commit' release-authority-v1.json)" = "$EXPECTED_AUTHORITY_COMMIT"
   test "$(jq -er '.authority_version' release-authority-v1.json)" = "$EXPECTED_AUTHORITY_VERSION"
   test "$(jq -er '.generation' release-authority-v1.json)" = "$EXPECTED_GENERATION"
   test "$(jq -er '.previous_generation' release-authority-v1.json)" = "$EXPECTED_PREVIOUS_GENERATION"
   test "$(jq -er '.previous_manifest_sha256' release-authority-v1.json)" = "$EXPECTED_PREVIOUS_MANIFEST_SHA256"
   test "$(jq -er '.approved_baseline_profile' release-authority-v1.json)" = "$EXPECTED_BASELINE_PROFILE"
   test "$(jq -er '.approved_baseline_generation' release-authority-v1.json)" = "$EXPECTED_BASELINE_GENERATION"
   test "$(jq -er '.approved_baseline_tree_sha256' release-authority-v1.json)" = "$EXPECTED_BASELINE_TREE_SHA256"
   test "$(jq -er '.approved_browser_bundle_sha256' release-authority-v1.json)" = "$EXPECTED_BROWSER_BUNDLE_SHA256"
   test "$(jq -er '.approved_browser_version' release-authority-v1.json)" = "$EXPECTED_BROWSER_VERSION"
   test "$(jq -er '.approved_browser_launch_profile_sha256' release-authority-v1.json)" = "$EXPECTED_BROWSER_LAUNCH_PROFILE_SHA256"
   test "$(jq -er '.verifier_schema' release-authority-v1.json)" = "$EXPECTED_VERIFIER_SCHEMA"
   cosign verify-blob \
     --bundle release-authority-v1.json.cosign.bundle \
     --certificate-identity 'https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main' \
     --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
     --certificate-github-workflow-sha "$EXPECTED_WORKFLOW_COMMIT" \
     release-authority-v1.json
   jq -e --argjson generation "$EXPECTED_GENERATION" --argjson previous "$EXPECTED_PREVIOUS_GENERATION" \
     '.schema == 1 and .generation == $generation and .previous_generation == $previous' \
     release-authority-v1.json
   printf '%s  %s\n' "$(jq -er '.shipper_sha256' release-authority-v1.json)" syntaur-ship-linux-x86_64 | sha256sum -c -
   printf '%s  %s\n' "$(jq -er '.verifier_sha256' release-authority-v1.json)" syntaur-verify-linux-x86_64 | sha256sum -c -
   ```

5. For the initial generation only, atomically install the verified generation
   into an empty fixed root-owned trust path. Stop if the path already exists;
   later promotions require a separate monotonic atomic promotion transaction
   and must never reuse this bootstrap procedure. The candidate user must not
   own any parent or authority file:

   ```sh
   test ! -e /etc/syntaur/release-authority
   sudo install -d -o root -g root -m 0755 /etc/syntaur
   stage=$(sudo mktemp -d "/etc/syntaur/release-authority.stage.${EXPECTED_GENERATION}.XXXXXX")
   sudo chmod 0755 "$stage"
   sudo install -d -o root -g root -m 0755 "$stage/release-authority/generation-${EXPECTED_GENERATION}"
   sudo install -o root -g root -m 0444 release-authority-v1.json release-authority-v1.json.cosign.bundle "$stage/"
   printf '%s\n' "$EXPECTED_WORKFLOW_COMMIT" | sudo tee "$stage/trusted-workflow-commit" >/dev/null
   sudo chown root:root "$stage/trusted-workflow-commit"
   sudo chmod 0444 "$stage/trusted-workflow-commit"
   sudo install -o root -g root -m 0555 syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64 "$stage/release-authority/generation-${EXPECTED_GENERATION}/"
   sudo mv "$stage" /etc/syntaur/release-authority
   sudo install -o root -g root -m 0555 syntaur-ship-linux-x86_64 /usr/local/bin/syntaur-ship
   /usr/local/bin/syntaur-ship authority-status
   ```

Set `EXPECTED_GENERATION` to the approved integer; do not leave the literal
`N`, and do not install a partially downloaded directory. `authority-status` rechecks root
ownership, canonical manifest bytes, the pinned public-workflow identity and
workflow commit, and exact shipper/verifier hashes.

The initial checkpoint is the one unavoidable human trust decision. It can
authorize only a later candidate commit, never itself. Each later policy-floor
or baseline-root promotion repeats the same reviewed environment approval;
ordinary product releases continue to use the already installed N-1 authority.
