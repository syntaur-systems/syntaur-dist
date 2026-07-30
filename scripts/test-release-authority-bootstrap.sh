#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_root=$(mktemp -d "$repo_root/.release-authority-bootstrap-test.XXXXXX")
image=
cleanup() {
    if [[ -n ${image:-} ]] && docker image inspect "$image" >/dev/null 2>&1; then
        docker image rm "$image" >/dev/null
    fi
    chmod -R u+rwX "$tmp_root" 2>/dev/null || true
    rm -rf "$tmp_root"
}
trap cleanup EXIT

context="$tmp_root/context"
fixture="$context/fixture"
fixture_g2="$context/fixture-g2"
fixture_g3="$context/fixture-g3"
expected_shipper="$context/expected-shipper"
recovery_predecessor="$context/recovery-predecessor"
operator_ssh="$context/operator-ssh"
mkdir -p \
    "$fixture" \
    "$fixture_g2" \
    "$fixture_g3" \
    "$expected_shipper" \
    "$recovery_predecessor" \
    "$operator_ssh"
chmod 0700 "$operator_ssh"
/usr/bin/ssh-keygen -q -t ed25519 -N '' -C fixture \
    -f "$operator_ssh/id_ed25519"
rm -f "$operator_ssh/id_ed25519.pub"
GENESIS_TEST_IDENTITY_SHA256=$(
    sha256sum "$operator_ssh/id_ed25519" | awk '{print $1}'
)
GENESIS_TEST_IDENTITY_SIZE=$(stat -c '%s' "$operator_ssh/id_ed25519")
GENESIS_TEST_IDENTITY_PUBLIC_SHA256=$(
    /usr/bin/ssh-keygen -y -f "$operator_ssh/id_ed25519" \
        | awk 'NF >= 2 {print $1, $2}' \
        | sha256sum \
        | awk '{print $1}'
)
GENESIS_TEST_IDENTITY_FINGERPRINT=$(
    /usr/bin/ssh-keygen -lf "$operator_ssh/id_ed25519" \
        | awk 'NR == 1 {print $2}'
)
GENESIS_TEST_IDENTITY_PATH="/etc/syntaur/mac-mini-identity-$GENESIS_TEST_IDENTITY_PUBLIC_SHA256"
GENESIS_TEST_AUTHORITY_TREE=$(
    sed -n 's/^readonly GENESIS_AUTHORITY_TREE=//p' \
        "$repo_root/scripts/bootstrap-release-authority-genesis-v2.sh"
)
GENESIS_TEST_SOURCE_EPOCH=1
export GENESIS_TEST_IDENTITY_SHA256 GENESIS_TEST_IDENTITY_SIZE
export GENESIS_TEST_IDENTITY_PUBLIC_SHA256
export GENESIS_TEST_IDENTITY_FINGERPRINT GENESIS_TEST_IDENTITY_PATH
export GENESIS_TEST_AUTHORITY_TREE GENESIS_TEST_SOURCE_EPOCH

cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"verifier"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g2"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g2/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g3"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=3 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g3/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"verifier-g3"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g3/syntaur-verify-linux-x86_64"
cp "$fixture/syntaur-ship-linux-x86_64" \
    "$expected_shipper/syntaur-ship-linux-x86_64"
cp "$fixture/syntaur-verify-linux-x86_64" \
    "$fixture_g2/syntaur-verify-linux-x86_64"
printf '#!/usr/bin/bash\nset -euo pipefail\n' \
    >"$fixture/syntaur-build-authority-provision"
printf '#!/usr/bin/bash\nset -euo pipefail\n# generation 2\n' \
    >"$fixture_g2/syntaur-build-authority-provision"
cp "$fixture_g2/syntaur-build-authority-provision" \
    "$fixture_g3/syntaur-build-authority-provision"
printf '#!/usr/bin/bash\nexit 64\n# fixed recovery predecessor\n' \
    >"$recovery_predecessor/syntaur-ship"

SHIPPER_SHA256=$(sha256sum \
    "$fixture/syntaur-ship-linux-x86_64" | awk '{print $1}')
VERIFIER_SHA256=$(sha256sum \
    "$fixture/syntaur-verify-linux-x86_64" | awk '{print $1}')
PROVISIONER_SHA256=$(sha256sum \
    "$fixture/syntaur-build-authority-provision" | awk '{print $1}')
G2_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g2/syntaur-ship-linux-x86_64" | awk '{print $1}')
G2_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g2/syntaur-verify-linux-x86_64" | awk '{print $1}')
G2_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g2/syntaur-build-authority-provision" | awk '{print $1}')
G3_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g3/syntaur-ship-linux-x86_64" | awk '{print $1}')
G3_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g3/syntaur-verify-linux-x86_64" | awk '{print $1}')
G3_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g3/syntaur-build-authority-provision" | awk '{print $1}')
RECOVERY_PREDECESSOR_SHIPPER_SHA256=$(sha256sum \
    "$recovery_predecessor/syntaur-ship" | awk '{print $1}')
[[ $SHIPPER_SHA256 != "$VERIFIER_SHA256" ]]
[[ $SHIPPER_SHA256 != "$G2_SHIPPER_SHA256" ]]
[[ $G2_SHIPPER_SHA256 != "$G3_SHIPPER_SHA256" ]]
[[ $G2_PROVISIONER_SHA256 == "$G3_PROVISIONER_SHA256" ]]
PRODUCTION_CONTRACT_SHA256=$(printf production-contract | sha256sum | awk '{print $1}')
PROMOTION_RECOVERY_SHA256=$(printf promotion-recovery | sha256sum | awk '{print $1}')
AUTHORITY_VERSION=0.7.114
AUTHORITY_COMMIT=$(printf 'a%.0s' {1..40})
AUTHORITY_TREE_SHA256=$(printf authority-tree | sha256sum | awk '{print $1}')
VERIFIER_TOOLCHAIN_ID=rust-1.94.1-x86_64-unknown-linux-gnu
VERIFIER_CARGO_SHA256=$(printf cargo | sha256sum | awk '{print $1}')
VERIFIER_RUSTC_SHA256=$(printf rustc | sha256sum | awk '{print $1}')
VERIFIER_RUSTDOC_SHA256=$(printf rustdoc | sha256sum | awk '{print $1}')
BASELINE_PROFILE=mac-isolated-v1
BASELINE_GENERATION=generation-1
BASELINE_TREE_SHA256=$(printf baseline | sha256sum | awk '{print $1}')
BROWSER_BUNDLE_SHA256=$(printf browser | sha256sum | awk '{print $1}')
BROWSER_VERSION='Google Chrome for Testing 131.0.6778.264'
BROWSER_LAUNCH_PROFILE_SHA256=$(printf launch | sha256sum | awk '{print $1}')
VERIFIER_SCHEMA=5
PRODUCTION_MEMBER_COUNT=12
RECEIPT_SCHEMA=6
BUILD_AUTHORITY_SCHEMA=4
PROMOTION_RECOVERY_SCHEMA=1
GITHUB_SHA=$(printf 'b%.0s' {1..40})
G2_AUTHORITY_COMMIT=$(printf 'c%.0s' {1..40})
G2_AUTHORITY_GIT_TREE=$(printf 'd%.0s' {1..40})
G2_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g2 | sha256sum | awk '{print $1}'
)
G2_WORKFLOW_COMMIT=$(printf 'e%.0s' {1..40})
G3_AUTHORITY_COMMIT=$(printf 'f%.0s' {1..40})
G3_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g3 | sha256sum | awk '{print $1}'
)
G3_WORKFLOW_COMMIT=$(printf '1%.0s' {1..40})
G2_SOURCE_DATE_EPOCH=1
RECOVERY_RUSTSEC_DB_COMMIT=$(printf 'd%.0s' {1..40})
RECOVERY_RUSTSEC_TREE_SHA256=$(
    printf rustsec-tree | sha256sum | awk '{print $1}'
)
RECOVERY_SYSTEM_USR_TREE_SHA256=$(
    printf system-usr-tree | sha256sum | awk '{print $1}'
)
AUTHORITY_GENERATION=1
PREVIOUS_AUTHORITY_GENERATION=0
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$(printf '0%.0s' {1..64})
export SHIPPER_SHA256 VERIFIER_SHA256 PROVISIONER_SHA256
export PRODUCTION_CONTRACT_SHA256 PROMOTION_RECOVERY_SHA256
export AUTHORITY_VERSION AUTHORITY_COMMIT AUTHORITY_TREE_SHA256
export VERIFIER_TOOLCHAIN_ID VERIFIER_CARGO_SHA256 VERIFIER_RUSTC_SHA256
export VERIFIER_RUSTDOC_SHA256 BASELINE_PROFILE BASELINE_GENERATION
export BASELINE_TREE_SHA256 BROWSER_BUNDLE_SHA256 BROWSER_VERSION
export BROWSER_LAUNCH_PROFILE_SHA256 VERIFIER_SCHEMA PRODUCTION_MEMBER_COUNT
export RECEIPT_SCHEMA BUILD_AUTHORITY_SCHEMA PROMOTION_RECOVERY_SCHEMA
export GITHUB_SHA AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
export G2_AUTHORITY_COMMIT G2_AUTHORITY_GIT_TREE G2_AUTHORITY_TREE_SHA256
export G2_WORKFLOW_COMMIT G3_AUTHORITY_COMMIT G3_AUTHORITY_TREE_SHA256
export G3_WORKFLOW_COMMIT G2_SOURCE_DATE_EPOCH
export G2_SHIPPER_SHA256 G2_VERIFIER_SHA256 G2_PROVISIONER_SHA256
export G3_SHIPPER_SHA256 G3_VERIFIER_SHA256 G3_PROVISIONER_SHA256
export RECOVERY_PREDECESSOR_SHIPPER_SHA256 RECOVERY_RUSTSEC_DB_COMMIT
export RECOVERY_RUSTSEC_TREE_SHA256 RECOVERY_SYSTEM_USR_TREE_SHA256

"$repo_root/scripts/release-authority-manifest.sh" \
    render-v2 "$fixture/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture/release-authority-v2.json.cosign.bundle"

g1_manifest_sha256=$(sha256sum \
    "$fixture/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G2_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G2_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G2_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G2_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G2_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G2_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=2 \
    PREVIOUS_AUTHORITY_GENERATION=1 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g1_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g2/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g2/release-authority-v2.json.cosign.bundle"
g2_manifest_sha256=$(sha256sum \
    "$fixture_g2/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G3_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G3_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G3_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G3_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G3_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G3_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=3 \
    PREVIOUS_AUTHORITY_GENERATION=2 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g2_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g3/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g3/release-authority-v2.json.cosign.bundle"

fake_cosign_sha256=$(sha256sum \
    "$repo_root/scripts/fixtures/release_authority_fake_cosign.sh" \
    | awk '{print $1}')
sed \
    -e "s/^readonly COSIGN_SHA256=.*/readonly COSIGN_SHA256=$fake_cosign_sha256/" \
    -e "s|^readonly GENESIS_MAC_IDENTITY=.*|readonly GENESIS_MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly GENESIS_MAC_IDENTITY_SHA256=.*/readonly GENESIS_MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly GENESIS_MAC_IDENTITY_SIZE=.*/readonly GENESIS_MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly GENESIS_MAC_IDENTITY_PUBLIC_SHA256=.*/readonly GENESIS_MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly GENESIS_MAC_IDENTITY_FINGERPRINT=.*|readonly GENESIS_MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    -e "s/^readonly GENESIS_AUTHORITY_SOURCE_DATE_EPOCH=.*/readonly GENESIS_AUTHORITY_SOURCE_DATE_EPOCH=$GENESIS_TEST_SOURCE_EPOCH/" \
    "$repo_root/scripts/bootstrap-release-authority-genesis-v2.sh" \
    >"$context/bootstrap-release-authority-genesis-v2.sh"
g1_bundle_sha256=$(sha256sum \
    "$fixture/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g2_bundle_sha256=$(sha256sum \
    "$fixture_g2/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g3_manifest_sha256=$(sha256sum \
    "$fixture_g3/release-authority-v2.json" | awk '{print $1}')
g3_bundle_sha256=$(sha256sum \
    "$fixture_g3/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
recovery_helper_sha256=$(sha256sum \
    "$repo_root/scripts/release-authority-manifest.sh" | awk '{print $1}')
sed \
    -e "s/^readonly COSIGN_SHA256=.*/readonly COSIGN_SHA256=$fake_cosign_sha256/" \
    -e "s/^readonly MANIFEST_HELPER_SHA256=.*/readonly MANIFEST_HELPER_SHA256=$recovery_helper_sha256/" \
    -e "s/^readonly G1_MANIFEST_SHA256=.*/readonly G1_MANIFEST_SHA256=$g1_manifest_sha256/" \
    -e "s/^readonly G1_BUNDLE_SHA256=.*/readonly G1_BUNDLE_SHA256=$g1_bundle_sha256/" \
    -e "s/^readonly G1_WORKFLOW_COMMIT=.*/readonly G1_WORKFLOW_COMMIT=$GITHUB_SHA/" \
    -e "s/^readonly G1_AUTHORITY_COMMIT=.*/readonly G1_AUTHORITY_COMMIT=$AUTHORITY_COMMIT/" \
    -e "s/^readonly G1_AUTHORITY_TREE_SHA256=.*/readonly G1_AUTHORITY_TREE_SHA256=$AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G1_SHIPPER_SHA256=.*/readonly G1_SHIPPER_SHA256=$SHIPPER_SHA256/" \
    -e "s/^readonly G1_VERIFIER_SHA256=.*/readonly G1_VERIFIER_SHA256=$VERIFIER_SHA256/" \
    -e "s/^readonly G1_PROVISIONER_SHA256=.*/readonly G1_PROVISIONER_SHA256=$PROVISIONER_SHA256/" \
    -e "s/^readonly G2_MANIFEST_SHA256=.*/readonly G2_MANIFEST_SHA256=$g2_manifest_sha256/" \
    -e "s/^readonly G2_BUNDLE_SHA256=.*/readonly G2_BUNDLE_SHA256=$g2_bundle_sha256/" \
    -e "s/^readonly G2_WORKFLOW_COMMIT=.*/readonly G2_WORKFLOW_COMMIT=$G2_WORKFLOW_COMMIT/" \
    -e "s/^readonly G2_AUTHORITY_COMMIT=.*/readonly G2_AUTHORITY_COMMIT=$G2_AUTHORITY_COMMIT/" \
    -e "s/^readonly G2_AUTHORITY_GIT_TREE=.*/readonly G2_AUTHORITY_GIT_TREE=$G2_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G2_SOURCE_DATE_EPOCH=.*/readonly G2_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G2_SHIPPER_SHA256=.*/readonly G2_SHIPPER_SHA256=$G2_SHIPPER_SHA256/" \
    -e "s/^readonly G2_VERIFIER_SHA256=.*/readonly G2_VERIFIER_SHA256=$G2_VERIFIER_SHA256/" \
    -e "s/^readonly G2_PROVISIONER_SHA256=.*/readonly G2_PROVISIONER_SHA256=$G2_PROVISIONER_SHA256/" \
    -e "s/^readonly G3_MANIFEST_SHA256=.*/readonly G3_MANIFEST_SHA256=$g3_manifest_sha256/" \
    -e "s/^readonly G3_BUNDLE_SHA256=.*/readonly G3_BUNDLE_SHA256=$g3_bundle_sha256/" \
    -e "s/^readonly G3_WORKFLOW_COMMIT=.*/readonly G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT/" \
    -e "s/^readonly G3_AUTHORITY_COMMIT=.*/readonly G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT/" \
    -e "s/^readonly G3_AUTHORITY_TREE_SHA256=.*/readonly G3_AUTHORITY_TREE_SHA256=$G3_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G3_SHIPPER_SHA256=.*/readonly G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256/" \
    -e "s/^readonly G3_VERIFIER_SHA256=.*/readonly G3_VERIFIER_SHA256=$G3_VERIFIER_SHA256/" \
    -e "s/^readonly G3_PROVISIONER_SHA256=.*/readonly G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh"
cp "$repo_root/scripts/release-authority-manifest.sh" \
    "$context/release-authority-manifest.sh"
cp "$repo_root/scripts/fixtures/release_authority_fake_cosign.sh" \
    "$context/release-authority-fake-cosign.sh"
cp "$repo_root/scripts/fixtures/release_authority_bootstrap_driver.sh" \
    "$context/release-authority-bootstrap-driver.sh"
cp "$repo_root/scripts/fixtures/release_authority_bootstrap.Dockerfile" \
    "$context/Dockerfile"
chmod 0555 \
    "$context/bootstrap-release-authority-genesis-v2.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh" \
    "$context/release-authority-manifest.sh" \
    "$context/release-authority-bootstrap-driver.sh"
chmod 0755 "$context/release-authority-fake-cosign.sh"
chmod 0500 "$fixture" "$fixture_g2" "$fixture_g3" "$recovery_predecessor"
chmod 0400 \
    "$fixture/release-authority-v2.json" \
    "$fixture/release-authority-v2.json.cosign.bundle" \
    "$fixture_g2/release-authority-v2.json" \
    "$fixture_g2/release-authority-v2.json.cosign.bundle" \
    "$fixture_g3/release-authority-v2.json" \
    "$fixture_g3/release-authority-v2.json.cosign.bundle"
chmod 0500 \
    "$fixture/syntaur-build-authority-provision" \
    "$fixture/syntaur-ship-linux-x86_64" \
    "$fixture/syntaur-verify-linux-x86_64" \
    "$fixture_g2/syntaur-build-authority-provision" \
    "$fixture_g2/syntaur-ship-linux-x86_64" \
    "$fixture_g2/syntaur-verify-linux-x86_64" \
    "$fixture_g3/syntaur-build-authority-provision" \
    "$fixture_g3/syntaur-ship-linux-x86_64" \
    "$fixture_g3/syntaur-verify-linux-x86_64" \
    "$expected_shipper/syntaur-ship-linux-x86_64" \
    "$recovery_predecessor/syntaur-ship"

manifest_sha256=$(sha256sum \
    "$fixture/release-authority-v2.json" | awk '{print $1}')
helper_sha256=$(sha256sum \
    "$context/release-authority-manifest.sh" | awk '{print $1}')
image="syntaur-release-authority-bootstrap-test:${GITHUB_RUN_ID:-local}-$$"
if command -v docker >/dev/null \
    && timeout 10 docker info >/dev/null 2>&1; then
    base_image=$(yq -er '.env.AUTHORITY_BUILDER_IMAGE' \
        "$repo_root/.github/workflows/release-authority.yml")
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$base_image" \
        --tag "$image" \
        "$context"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env "EXPECTED_MANIFEST_SHA256=$manifest_sha256" \
        --env "EXPECTED_WORKFLOW_COMMIT=$GITHUB_SHA" \
        --env "EXPECTED_AUTHORITY_VERSION=$AUTHORITY_VERSION" \
        --env "EXPECTED_AUTHORITY_COMMIT=$AUTHORITY_COMMIT" \
        --env "EXPECTED_SHIPPER_SHA256=$SHIPPER_SHA256" \
        --env "EXPECTED_VERIFIER_SHA256=$VERIFIER_SHA256" \
        --env "EXPECTED_PROVISIONER_SHA256=$PROVISIONER_SHA256" \
        --env "EXPECTED_HELPER_SHA256=$helper_sha256" \
        --env "GENESIS_TEST_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256" \
        --env "GENESIS_TEST_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256" \
        --env "GENESIS_TEST_IDENTITY_FINGERPRINT=$GENESIS_TEST_IDENTITY_FINGERPRINT" \
        --env "GENESIS_TEST_IDENTITY_PATH=$GENESIS_TEST_IDENTITY_PATH" \
        --env "GENESIS_TEST_AUTHORITY_TREE=$GENESIS_TEST_AUTHORITY_TREE" \
        --env "GENESIS_TEST_SOURCE_EPOCH=$GENESIS_TEST_SOURCE_EPOCH" \
        "$image"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery \
        --env "EXPECTED_MANIFEST_SHA256=$manifest_sha256" \
        --env "EXPECTED_WORKFLOW_COMMIT=$GITHUB_SHA" \
        --env "EXPECTED_AUTHORITY_VERSION=$AUTHORITY_VERSION" \
        --env "EXPECTED_AUTHORITY_COMMIT=$AUTHORITY_COMMIT" \
        --env "EXPECTED_SHIPPER_SHA256=$SHIPPER_SHA256" \
        --env "EXPECTED_VERIFIER_SHA256=$VERIFIER_SHA256" \
        --env "EXPECTED_PROVISIONER_SHA256=$PROVISIONER_SHA256" \
        --env "EXPECTED_HELPER_SHA256=$helper_sha256" \
        --env "GENESIS_TEST_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256" \
        --env "GENESIS_TEST_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256" \
        --env "GENESIS_TEST_IDENTITY_FINGERPRINT=$GENESIS_TEST_IDENTITY_FINGERPRINT" \
        --env "GENESIS_TEST_IDENTITY_PATH=$GENESIS_TEST_IDENTITY_PATH" \
        --env "GENESIS_TEST_AUTHORITY_TREE=$GENESIS_TEST_AUTHORITY_TREE" \
        --env "GENESIS_TEST_SOURCE_EPOCH=$GENESIS_TEST_SOURCE_EPOCH" \
        --env "RECOVERY_G2_AUTHORITY_COMMIT=$G2_AUTHORITY_COMMIT" \
        --env "RECOVERY_G2_AUTHORITY_GIT_TREE=$G2_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G2_MANIFEST_SHA256=$g2_manifest_sha256" \
        --env "RECOVERY_G2_PROVISIONER_SHA256=$G2_PROVISIONER_SHA256" \
        --env "RECOVERY_G2_SHIPPER_SHA256=$G2_SHIPPER_SHA256" \
        --env "RECOVERY_G2_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G2_WORKFLOW_COMMIT=$G2_WORKFLOW_COMMIT" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    docker image rm "$image" >/dev/null
    image=
else
    command -v bwrap >/dev/null
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-genesis-v2.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-genesis-v2.sh"
    chmod 0555 "$context/bootstrap-release-authority-genesis-v2.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh"
    printf 'claudevm\n' >"$context/hostname"
    chmod 0444 "$context/hostname"
    alternatives_bind=()
    if [[ -d /etc/alternatives ]]; then
        alternatives_bind=(--ro-bind /etc/alternatives /etc/alternatives)
    fi
    run_bwrap_fixture() {
        local scenario=$1
        local -a scenario_args=()
        if [[ $scenario == recovery ]]; then
            scenario_args=(
                --setenv BOOTSTRAP_FIXTURE_SCENARIO recovery
            )
        fi
        bwrap \
            --unshare-all \
            --share-net \
            --uid 0 \
            --gid 0 \
            --hostname claudevm \
            --ro-bind / / \
            --dev /dev \
            --proc /proc \
            --tmpfs /etc \
            "${alternatives_bind[@]}" \
            --ro-bind /etc/passwd /etc/passwd \
            --ro-bind /etc/group /etc/group \
            --ro-bind "$context/hostname" /etc/hostname \
            --tmpfs /run \
            --dir /run/lock \
            --tmpfs /home \
            --dir /home/sean \
            --ro-bind "$operator_ssh" /home/sean/.ssh \
            --tmpfs /tmp \
            --dir /tmp/fixture \
            --dir /tmp/fixture-g2 \
            --dir /tmp/fixture-g3 \
            --dir /tmp/bootstrap \
            --dir /tmp/expected \
            --dir /tmp/recovery-predecessor \
            --tmpfs /opt \
            --tmpfs /usr/local \
            --dir /usr/local/bin \
            --ro-bind "$context/release-authority-fake-cosign.sh" \
                /usr/local/bin/cosign \
            --bind "$fixture" /tmp/fixture \
            --bind "$fixture_g2" /tmp/fixture-g2 \
            --bind "$fixture_g3" /tmp/fixture-g3 \
            --ro-bind "$context" /tmp/bootstrap \
            --ro-bind "$expected_shipper" /tmp/expected \
            --ro-bind "$recovery_predecessor" /tmp/recovery-predecessor \
            --setenv BOOTSTRAP_FIXTURE_SOURCE_DIR /tmp/fixture \
            --setenv BOOTSTRAP_FIXTURE_G2_DIR /tmp/fixture-g2 \
            --setenv BOOTSTRAP_FIXTURE_G3_DIR /tmp/fixture-g3 \
            --setenv BOOTSTRAP_FIXTURE_BOOTSTRAP_ROOT /tmp/bootstrap \
            --setenv BOOTSTRAP_FIXTURE_EXPECTED_DIR /tmp/expected \
            --setenv BOOTSTRAP_FIXTURE_RECOVERY_PREDECESSOR \
                /tmp/recovery-predecessor/syntaur-ship \
            --setenv BOOTSTRAP_FIXTURE_OPERATOR_UID 0 \
            --setenv BOOTSTRAP_FIXTURE_OPERATOR_GID 0 \
            --setenv EXPECTED_MANIFEST_SHA256 "$manifest_sha256" \
            --setenv EXPECTED_WORKFLOW_COMMIT "$GITHUB_SHA" \
            --setenv EXPECTED_AUTHORITY_VERSION "$AUTHORITY_VERSION" \
            --setenv EXPECTED_AUTHORITY_COMMIT "$AUTHORITY_COMMIT" \
            --setenv EXPECTED_SHIPPER_SHA256 "$SHIPPER_SHA256" \
            --setenv EXPECTED_VERIFIER_SHA256 "$VERIFIER_SHA256" \
            --setenv EXPECTED_PROVISIONER_SHA256 "$PROVISIONER_SHA256" \
            --setenv EXPECTED_HELPER_SHA256 "$helper_sha256" \
            --setenv GENESIS_TEST_IDENTITY_SHA256 \
                "$GENESIS_TEST_IDENTITY_SHA256" \
            --setenv GENESIS_TEST_IDENTITY_PUBLIC_SHA256 \
                "$GENESIS_TEST_IDENTITY_PUBLIC_SHA256" \
            --setenv GENESIS_TEST_IDENTITY_FINGERPRINT \
                "$GENESIS_TEST_IDENTITY_FINGERPRINT" \
            --setenv GENESIS_TEST_IDENTITY_PATH \
                "$GENESIS_TEST_IDENTITY_PATH" \
            --setenv GENESIS_TEST_AUTHORITY_TREE \
                "$GENESIS_TEST_AUTHORITY_TREE" \
            --setenv GENESIS_TEST_SOURCE_EPOCH \
                "$GENESIS_TEST_SOURCE_EPOCH" \
            --setenv RECOVERY_G2_AUTHORITY_COMMIT \
                "$G2_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G2_AUTHORITY_GIT_TREE \
                "$G2_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G2_MANIFEST_SHA256 \
                "$g2_manifest_sha256" \
            --setenv RECOVERY_G2_PROVISIONER_SHA256 \
                "$G2_PROVISIONER_SHA256" \
            --setenv RECOVERY_G2_SHIPPER_SHA256 \
                "$G2_SHIPPER_SHA256" \
            --setenv RECOVERY_G2_SOURCE_DATE_EPOCH \
                "$G2_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G2_WORKFLOW_COMMIT \
                "$G2_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G3_PROVISIONER_SHA256 \
                "$G3_PROVISIONER_SHA256" \
            --setenv RECOVERY_G3_SHIPPER_SHA256 \
                "$G3_SHIPPER_SHA256" \
            --setenv RECOVERY_G3_WORKFLOW_COMMIT \
                "$G3_WORKFLOW_COMMIT" \
            --setenv RECOVERY_PREDECESSOR_SHIPPER_SHA256 \
                "$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
            "${scenario_args[@]}" \
            /tmp/bootstrap/release-authority-bootstrap-driver.sh
    }
    run_bwrap_fixture genesis
    run_bwrap_fixture recovery
fi
