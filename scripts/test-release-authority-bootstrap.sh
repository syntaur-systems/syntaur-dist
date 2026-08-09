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
fixture_g4="$context/fixture-g4"
fixture_g5="$context/fixture-g5"
fixture_g6="$context/fixture-g6"
fixture_g7="$context/fixture-g7"
fixture_g8="$context/fixture-g8"
fixture_g9="$context/fixture-g9"
fixture_g10="$context/fixture-g10"
expected_shipper="$context/expected-shipper"
recovery_predecessor="$context/recovery-predecessor"
operator_ssh="$context/operator-ssh"
mkdir -p \
    "$fixture" \
    "$fixture_g2" \
    "$fixture_g3" \
    "$fixture_g4" \
    "$fixture_g5" \
    "$fixture_g6" \
    "$fixture_g7" \
    "$fixture_g8" \
    "$fixture_g9" \
    "$fixture_g10" \
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
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g4"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=4 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g4/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"verifier-g4"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g4/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g5"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=5 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g5/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"verifier-g5"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g5/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g6"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=6 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g6/syntaur-ship-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"verifier-g6"' \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g6/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g7"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=7 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g7/syntaur-ship-linux-x86_64"
cp "$fixture_g6/syntaur-verify-linux-x86_64" \
    "$fixture_g7/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g8"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=8 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g8/syntaur-ship-linux-x86_64"
cp "$fixture_g7/syntaur-verify-linux-x86_64" \
    "$fixture_g8/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g9"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=9 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g9/syntaur-ship-linux-x86_64"
cp "$fixture_g8/syntaur-verify-linux-x86_64" \
    "$fixture_g9/syntaur-verify-linux-x86_64"
cc -std=c11 -O2 -Wall -Wextra -Werror \
    -DFIXTURE_ROLE_MARKER='"shipper-g10"' \
    -DFIXTURE_AUTHORITY_GENERATIONS=10 \
    "$repo_root/scripts/fixtures/release_authority_bootstrap.c" \
    -o "$fixture_g10/syntaur-ship-linux-x86_64"
cp "$fixture_g9/syntaur-verify-linux-x86_64" \
    "$fixture_g10/syntaur-verify-linux-x86_64"
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
printf '#!/usr/bin/bash\nset -euo pipefail\n# generation 4\n' \
    >"$fixture_g4/syntaur-build-authority-provision"
printf '#!/usr/bin/bash\nset -euo pipefail\n# generation 5\n' \
    >"$fixture_g5/syntaur-build-authority-provision"
printf '#!/usr/bin/bash\nset -euo pipefail\n# generation 6\n' \
    >"$fixture_g6/syntaur-build-authority-provision"
cp "$fixture_g6/syntaur-build-authority-provision" \
    "$fixture_g7/syntaur-build-authority-provision"
cp "$fixture_g7/syntaur-build-authority-provision" \
    "$fixture_g8/syntaur-build-authority-provision"
cp "$fixture_g8/syntaur-build-authority-provision" \
    "$fixture_g9/syntaur-build-authority-provision"
cp "$fixture_g9/syntaur-build-authority-provision" \
    "$fixture_g10/syntaur-build-authority-provision"
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
G4_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g4/syntaur-ship-linux-x86_64" | awk '{print $1}')
G4_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g4/syntaur-verify-linux-x86_64" | awk '{print $1}')
G4_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g4/syntaur-build-authority-provision" | awk '{print $1}')
G5_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g5/syntaur-ship-linux-x86_64" | awk '{print $1}')
G5_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g5/syntaur-verify-linux-x86_64" | awk '{print $1}')
G5_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g5/syntaur-build-authority-provision" | awk '{print $1}')
G6_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g6/syntaur-ship-linux-x86_64" | awk '{print $1}')
G6_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g6/syntaur-verify-linux-x86_64" | awk '{print $1}')
G6_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g6/syntaur-build-authority-provision" | awk '{print $1}')
G7_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g7/syntaur-ship-linux-x86_64" | awk '{print $1}')
G7_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g7/syntaur-verify-linux-x86_64" | awk '{print $1}')
G7_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g7/syntaur-build-authority-provision" | awk '{print $1}')
G8_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g8/syntaur-ship-linux-x86_64" | awk '{print $1}')
G8_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g8/syntaur-verify-linux-x86_64" | awk '{print $1}')
G8_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g8/syntaur-build-authority-provision" | awk '{print $1}')
G9_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g9/syntaur-ship-linux-x86_64" | awk '{print $1}')
G9_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g9/syntaur-verify-linux-x86_64" | awk '{print $1}')
G9_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g9/syntaur-build-authority-provision" | awk '{print $1}')
G10_SHIPPER_SHA256=$(sha256sum \
    "$fixture_g10/syntaur-ship-linux-x86_64" | awk '{print $1}')
G10_VERIFIER_SHA256=$(sha256sum \
    "$fixture_g10/syntaur-verify-linux-x86_64" | awk '{print $1}')
G10_PROVISIONER_SHA256=$(sha256sum \
    "$fixture_g10/syntaur-build-authority-provision" | awk '{print $1}')
RECOVERY_PREDECESSOR_SHIPPER_SHA256=$(sha256sum \
    "$recovery_predecessor/syntaur-ship" | awk '{print $1}')
[[ $SHIPPER_SHA256 != "$VERIFIER_SHA256" ]]
[[ $SHIPPER_SHA256 != "$G2_SHIPPER_SHA256" ]]
[[ $G2_SHIPPER_SHA256 != "$G3_SHIPPER_SHA256" ]]
[[ $G2_PROVISIONER_SHA256 == "$G3_PROVISIONER_SHA256" ]]
[[ $G3_SHIPPER_SHA256 != "$G4_SHIPPER_SHA256" ]]
[[ $G3_PROVISIONER_SHA256 != "$G4_PROVISIONER_SHA256" ]]
[[ $G4_SHIPPER_SHA256 != "$G5_SHIPPER_SHA256" ]]
[[ $G4_PROVISIONER_SHA256 != "$G5_PROVISIONER_SHA256" ]]
[[ $G5_SHIPPER_SHA256 != "$G6_SHIPPER_SHA256" ]]
[[ $G5_PROVISIONER_SHA256 != "$G6_PROVISIONER_SHA256" ]]
[[ $G6_SHIPPER_SHA256 != "$G7_SHIPPER_SHA256" ]]
[[ $G6_VERIFIER_SHA256 == "$G7_VERIFIER_SHA256" ]]
[[ $G6_PROVISIONER_SHA256 == "$G7_PROVISIONER_SHA256" ]]
[[ $G7_SHIPPER_SHA256 != "$G8_SHIPPER_SHA256" ]]
[[ $G7_VERIFIER_SHA256 == "$G8_VERIFIER_SHA256" ]]
[[ $G7_PROVISIONER_SHA256 == "$G8_PROVISIONER_SHA256" ]]
[[ $G8_SHIPPER_SHA256 != "$G9_SHIPPER_SHA256" ]]
[[ $G8_VERIFIER_SHA256 == "$G9_VERIFIER_SHA256" ]]
[[ $G8_PROVISIONER_SHA256 == "$G9_PROVISIONER_SHA256" ]]
[[ $G9_SHIPPER_SHA256 != "$G10_SHIPPER_SHA256" ]]
[[ $G9_VERIFIER_SHA256 == "$G10_VERIFIER_SHA256" ]]
[[ $G9_PROVISIONER_SHA256 == "$G10_PROVISIONER_SHA256" ]]
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
G3_AUTHORITY_GIT_TREE=$(printf '2%.0s' {1..40})
G3_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g3 | sha256sum | awk '{print $1}'
)
G3_WORKFLOW_COMMIT=$(printf '1%.0s' {1..40})
G4_AUTHORITY_COMMIT=$(printf '3%.0s' {1..40})
G4_AUTHORITY_GIT_TREE=$(printf '4%.0s' {1..40})
G4_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g4 | sha256sum | awk '{print $1}'
)
G4_WORKFLOW_COMMIT=$(printf '5%.0s' {1..40})
G4_SOURCE_DATE_EPOCH=2
G5_AUTHORITY_COMMIT=$(printf '6%.0s' {1..40})
G5_AUTHORITY_GIT_TREE=$(printf '7%.0s' {1..40})
G5_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g5 | sha256sum | awk '{print $1}'
)
G5_WORKFLOW_COMMIT=$(printf '8%.0s' {1..40})
G5_SOURCE_DATE_EPOCH=3
G6_AUTHORITY_COMMIT=$(printf '9%.0s' {1..40})
G6_AUTHORITY_GIT_TREE=$(printf '0%.0s' {1..40})
G6_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g6 | sha256sum | awk '{print $1}'
)
G6_WORKFLOW_COMMIT=$(printf 'ab%.0s' {1..20})
G6_SOURCE_DATE_EPOCH=4
G7_AUTHORITY_COMMIT=$(printf 'cd%.0s' {1..20})
G7_AUTHORITY_GIT_TREE=$(printf 'ef%.0s' {1..20})
G7_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g7 | sha256sum | awk '{print $1}'
)
G7_WORKFLOW_COMMIT=$(printf '12%.0s' {1..20})
G7_SOURCE_DATE_EPOCH=5
G8_AUTHORITY_COMMIT=$(printf '34%.0s' {1..20})
G8_AUTHORITY_GIT_TREE=$(printf '56%.0s' {1..20})
G8_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g8 | sha256sum | awk '{print $1}'
)
G8_WORKFLOW_COMMIT=$(printf '78%.0s' {1..20})
G8_SOURCE_DATE_EPOCH=6
G9_AUTHORITY_COMMIT=$(printf '9a%.0s' {1..20})
G9_AUTHORITY_GIT_TREE=$(printf 'bc%.0s' {1..20})
G9_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g9 | sha256sum | awk '{print $1}'
)
G9_WORKFLOW_COMMIT=$(printf 'de%.0s' {1..20})
G9_SOURCE_DATE_EPOCH=7
G10_AUTHORITY_COMMIT=$(printf 'f1%.0s' {1..20})
G10_AUTHORITY_GIT_TREE=$(printf '23%.0s' {1..20})
G10_AUTHORITY_TREE_SHA256=$(
    printf authority-tree-g10 | sha256sum | awk '{print $1}'
)
G10_WORKFLOW_COMMIT=$(printf '45%.0s' {1..20})
G10_SOURCE_DATE_EPOCH=8
G2_SOURCE_DATE_EPOCH=1
RECOVERY_SOURCE_CARGO_LOCK_SHA256=$(
    printf source-cargo-lock | sha256sum | awk '{print $1}'
)
RECOVERY_ENGINE_CARGO_LOCK_SHA256=$(
    printf engine-cargo-lock | sha256sum | awk '{print $1}'
)
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
export G3_AUTHORITY_GIT_TREE G3_WORKFLOW_COMMIT G2_SOURCE_DATE_EPOCH
export G4_AUTHORITY_COMMIT G4_AUTHORITY_GIT_TREE G4_AUTHORITY_TREE_SHA256
export G4_WORKFLOW_COMMIT G4_SOURCE_DATE_EPOCH
export G5_AUTHORITY_COMMIT G5_AUTHORITY_GIT_TREE G5_AUTHORITY_TREE_SHA256
export G5_WORKFLOW_COMMIT G5_SOURCE_DATE_EPOCH
export G6_AUTHORITY_COMMIT G6_AUTHORITY_GIT_TREE G6_AUTHORITY_TREE_SHA256
export G6_WORKFLOW_COMMIT G6_SOURCE_DATE_EPOCH
export G7_AUTHORITY_COMMIT G7_AUTHORITY_GIT_TREE G7_AUTHORITY_TREE_SHA256
export G7_WORKFLOW_COMMIT G7_SOURCE_DATE_EPOCH
export G8_AUTHORITY_COMMIT G8_AUTHORITY_GIT_TREE G8_AUTHORITY_TREE_SHA256
export G8_WORKFLOW_COMMIT G8_SOURCE_DATE_EPOCH
export G9_AUTHORITY_COMMIT G9_AUTHORITY_GIT_TREE G9_AUTHORITY_TREE_SHA256
export G9_WORKFLOW_COMMIT G9_SOURCE_DATE_EPOCH
export G10_AUTHORITY_COMMIT G10_AUTHORITY_GIT_TREE G10_AUTHORITY_TREE_SHA256
export G10_WORKFLOW_COMMIT G10_SOURCE_DATE_EPOCH
export G2_SHIPPER_SHA256 G2_VERIFIER_SHA256 G2_PROVISIONER_SHA256
export G3_SHIPPER_SHA256 G3_VERIFIER_SHA256 G3_PROVISIONER_SHA256
export G4_SHIPPER_SHA256 G4_VERIFIER_SHA256 G4_PROVISIONER_SHA256
export G5_SHIPPER_SHA256 G5_VERIFIER_SHA256 G5_PROVISIONER_SHA256
export G6_SHIPPER_SHA256 G6_VERIFIER_SHA256 G6_PROVISIONER_SHA256
export G7_SHIPPER_SHA256 G7_VERIFIER_SHA256 G7_PROVISIONER_SHA256
export G8_SHIPPER_SHA256 G8_VERIFIER_SHA256 G8_PROVISIONER_SHA256
export G9_SHIPPER_SHA256 G9_VERIFIER_SHA256 G9_PROVISIONER_SHA256
export G10_SHIPPER_SHA256 G10_VERIFIER_SHA256 G10_PROVISIONER_SHA256
export RECOVERY_PREDECESSOR_SHIPPER_SHA256 RECOVERY_RUSTSEC_DB_COMMIT
export RECOVERY_RUSTSEC_TREE_SHA256 RECOVERY_SYSTEM_USR_TREE_SHA256
export RECOVERY_SOURCE_CARGO_LOCK_SHA256 RECOVERY_ENGINE_CARGO_LOCK_SHA256

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
g3_manifest_sha256=$(sha256sum \
    "$fixture_g3/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G4_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G4_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G4_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G4_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G4_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G4_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=4 \
    PREVIOUS_AUTHORITY_GENERATION=3 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g3_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g4/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g4/release-authority-v2.json.cosign.bundle"
g4_manifest_sha256=$(sha256sum \
    "$fixture_g4/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G5_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G5_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G5_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G5_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G5_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G5_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=5 \
    PREVIOUS_AUTHORITY_GENERATION=4 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g4_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g5/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g5/release-authority-v2.json.cosign.bundle"
g5_manifest_sha256=$(sha256sum \
    "$fixture_g5/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G6_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G6_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G6_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G6_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G6_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G6_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=6 \
    PREVIOUS_AUTHORITY_GENERATION=5 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g5_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g6/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g6/release-authority-v2.json.cosign.bundle"
g6_manifest_sha256=$(sha256sum \
    "$fixture_g6/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G7_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G7_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G7_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G7_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G7_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G7_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=7 \
    PREVIOUS_AUTHORITY_GENERATION=6 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g6_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g7/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g7/release-authority-v2.json.cosign.bundle"
g7_manifest_sha256=$(sha256sum \
    "$fixture_g7/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G8_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G8_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G8_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G8_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G8_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G8_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=8 \
    PREVIOUS_AUTHORITY_GENERATION=7 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g7_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g8/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g8/release-authority-v2.json.cosign.bundle"
g8_manifest_sha256=$(sha256sum \
    "$fixture_g8/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G9_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G9_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G9_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G9_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G9_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G9_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=9 \
    PREVIOUS_AUTHORITY_GENERATION=8 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g8_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g9/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g9/release-authority-v2.json.cosign.bundle"
g9_manifest_sha256=$(sha256sum \
    "$fixture_g9/release-authority-v2.json" | awk '{print $1}')
env \
    SHIPPER_SHA256="$G10_SHIPPER_SHA256" \
    VERIFIER_SHA256="$G10_VERIFIER_SHA256" \
    PROVISIONER_SHA256="$G10_PROVISIONER_SHA256" \
    AUTHORITY_COMMIT="$G10_AUTHORITY_COMMIT" \
    AUTHORITY_TREE_SHA256="$G10_AUTHORITY_TREE_SHA256" \
    GITHUB_SHA="$G10_WORKFLOW_COMMIT" \
    AUTHORITY_GENERATION=10 \
    PREVIOUS_AUTHORITY_GENERATION=9 \
    PREVIOUS_AUTHORITY_MANIFEST_SHA256="$g9_manifest_sha256" \
    "$repo_root/scripts/release-authority-manifest.sh" \
        render-v2 "$fixture_g10/release-authority-v2.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$fixture_g10/release-authority-v2.json.cosign.bundle"

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
g3_bundle_sha256=$(sha256sum \
    "$fixture_g3/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g4_manifest_sha256=$(sha256sum \
    "$fixture_g4/release-authority-v2.json" | awk '{print $1}')
g4_bundle_sha256=$(sha256sum \
    "$fixture_g4/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g5_bundle_sha256=$(sha256sum \
    "$fixture_g5/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g6_bundle_sha256=$(sha256sum \
    "$fixture_g6/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g7_bundle_sha256=$(sha256sum \
    "$fixture_g7/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g8_bundle_sha256=$(sha256sum \
    "$fixture_g8/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g9_bundle_sha256=$(sha256sum \
    "$fixture_g9/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
g10_manifest_sha256=$(sha256sum \
    "$fixture_g10/release-authority-v2.json" | awk '{print $1}')
g10_bundle_sha256=$(sha256sum \
    "$fixture_g10/release-authority-v2.json.cosign.bundle" | awk '{print $1}')
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
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G2_SHIPPER_SHA256=.*/readonly G2_SHIPPER_SHA256=$G2_SHIPPER_SHA256/" \
    -e "s/^readonly G2_VERIFIER_SHA256=.*/readonly G2_VERIFIER_SHA256=$G2_VERIFIER_SHA256/" \
    -e "s/^readonly G2_PROVISIONER_SHA256=.*/readonly G2_PROVISIONER_SHA256=$G2_PROVISIONER_SHA256/" \
    -e "s/^readonly G3_MANIFEST_SHA256=.*/readonly G3_MANIFEST_SHA256=$g3_manifest_sha256/" \
    -e "s/^readonly G3_BUNDLE_SHA256=.*/readonly G3_BUNDLE_SHA256=$g3_bundle_sha256/" \
    -e "s/^readonly G3_WORKFLOW_COMMIT=.*/readonly G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT/" \
    -e "s/^readonly G3_AUTHORITY_COMMIT=.*/readonly G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT/" \
    -e "s/^readonly G3_AUTHORITY_GIT_TREE=.*/readonly G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G3_AUTHORITY_TREE_SHA256=.*/readonly G3_AUTHORITY_TREE_SHA256=$G3_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G3_SHIPPER_SHA256=.*/readonly G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256/" \
    -e "s/^readonly G3_VERIFIER_SHA256=.*/readonly G3_VERIFIER_SHA256=$G3_VERIFIER_SHA256/" \
    -e "s/^readonly G3_PROVISIONER_SHA256=.*/readonly G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256/" \
    -e "s/^readonly G4_MANIFEST_SHA256=.*/readonly G4_MANIFEST_SHA256=$g4_manifest_sha256/" \
    -e "s/^readonly G4_BUNDLE_SHA256=.*/readonly G4_BUNDLE_SHA256=$g4_bundle_sha256/" \
    -e "s/^readonly G4_WORKFLOW_COMMIT=.*/readonly G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_COMMIT=.*/readonly G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_GIT_TREE=.*/readonly G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G4_AUTHORITY_TREE_SHA256=.*/readonly G4_AUTHORITY_TREE_SHA256=$G4_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G4_SOURCE_DATE_EPOCH=.*/readonly G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G4_SHIPPER_SHA256=.*/readonly G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256/" \
    -e "s/^readonly G4_VERIFIER_SHA256=.*/readonly G4_VERIFIER_SHA256=$G4_VERIFIER_SHA256/" \
    -e "s/^readonly G4_PROVISIONER_SHA256=.*/readonly G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh"
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
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
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
    -e "s/^readonly G4_MANIFEST_SHA256=.*/readonly G4_MANIFEST_SHA256=$g4_manifest_sha256/" \
    -e "s/^readonly G4_BUNDLE_SHA256=.*/readonly G4_BUNDLE_SHA256=$g4_bundle_sha256/" \
    -e "s/^readonly G4_WORKFLOW_COMMIT=.*/readonly G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_COMMIT=.*/readonly G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_GIT_TREE=.*/readonly G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G4_AUTHORITY_TREE_SHA256=.*/readonly G4_AUTHORITY_TREE_SHA256=$G4_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G4_SHIPPER_SHA256=.*/readonly G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256/" \
    -e "s/^readonly G4_VERIFIER_SHA256=.*/readonly G4_VERIFIER_SHA256=$G4_VERIFIER_SHA256/" \
    -e "s/^readonly G4_PROVISIONER_SHA256=.*/readonly G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256/" \
    -e "s/^readonly G5_MANIFEST_SHA256=.*/readonly G5_MANIFEST_SHA256=$g5_manifest_sha256/" \
    -e "s/^readonly G5_BUNDLE_SHA256=.*/readonly G5_BUNDLE_SHA256=$g5_bundle_sha256/" \
    -e "s/^readonly G5_WORKFLOW_COMMIT=.*/readonly G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_COMMIT=.*/readonly G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_GIT_TREE=.*/readonly G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G5_AUTHORITY_TREE_SHA256=.*/readonly G5_AUTHORITY_TREE_SHA256=$G5_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G5_SOURCE_DATE_EPOCH=.*/readonly G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G5_SHIPPER_SHA256=.*/readonly G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256/" \
    -e "s/^readonly G5_VERIFIER_SHA256=.*/readonly G5_VERIFIER_SHA256=$G5_VERIFIER_SHA256/" \
    -e "s/^readonly G5_PROVISIONER_SHA256=.*/readonly G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_COMMIT=.*/readonly BASELINE_RECONSTRUCTION_COMMIT=$G2_AUTHORITY_COMMIT/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_GIT_TREE=.*/readonly BASELINE_RECONSTRUCTION_GIT_TREE=$G2_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=.*/readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=.*/readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly ENGINE_CARGO_LOCK_SHA256=.*/readonly ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh"
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
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
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
    -e "s/^readonly G4_MANIFEST_SHA256=.*/readonly G4_MANIFEST_SHA256=$g4_manifest_sha256/" \
    -e "s/^readonly G4_BUNDLE_SHA256=.*/readonly G4_BUNDLE_SHA256=$g4_bundle_sha256/" \
    -e "s/^readonly G4_WORKFLOW_COMMIT=.*/readonly G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_COMMIT=.*/readonly G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_GIT_TREE=.*/readonly G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G4_AUTHORITY_TREE_SHA256=.*/readonly G4_AUTHORITY_TREE_SHA256=$G4_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G4_SHIPPER_SHA256=.*/readonly G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256/" \
    -e "s/^readonly G4_VERIFIER_SHA256=.*/readonly G4_VERIFIER_SHA256=$G4_VERIFIER_SHA256/" \
    -e "s/^readonly G4_PROVISIONER_SHA256=.*/readonly G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256/" \
    -e "s/^readonly G5_MANIFEST_SHA256=.*/readonly G5_MANIFEST_SHA256=$g5_manifest_sha256/" \
    -e "s/^readonly G5_BUNDLE_SHA256=.*/readonly G5_BUNDLE_SHA256=$g5_bundle_sha256/" \
    -e "s/^readonly G5_WORKFLOW_COMMIT=.*/readonly G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_COMMIT=.*/readonly G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_GIT_TREE=.*/readonly G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G5_AUTHORITY_TREE_SHA256=.*/readonly G5_AUTHORITY_TREE_SHA256=$G5_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G5_SOURCE_DATE_EPOCH=.*/readonly G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G5_SHIPPER_SHA256=.*/readonly G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256/" \
    -e "s/^readonly G5_VERIFIER_SHA256=.*/readonly G5_VERIFIER_SHA256=$G5_VERIFIER_SHA256/" \
    -e "s/^readonly G5_PROVISIONER_SHA256=.*/readonly G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256/" \
    -e "s/^readonly G6_MANIFEST_SHA256=.*/readonly G6_MANIFEST_SHA256=$g6_manifest_sha256/" \
    -e "s/^readonly G6_BUNDLE_SHA256=.*/readonly G6_BUNDLE_SHA256=$g6_bundle_sha256/" \
    -e "s/^readonly G6_WORKFLOW_COMMIT=.*/readonly G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_COMMIT=.*/readonly G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_GIT_TREE=.*/readonly G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G6_AUTHORITY_TREE_SHA256=.*/readonly G6_AUTHORITY_TREE_SHA256=$G6_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G6_SOURCE_DATE_EPOCH=.*/readonly G6_SOURCE_DATE_EPOCH=$G6_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G6_SHIPPER_SHA256=.*/readonly G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256/" \
    -e "s/^readonly G6_VERIFIER_SHA256=.*/readonly G6_VERIFIER_SHA256=$G6_VERIFIER_SHA256/" \
    -e "s/^readonly G6_PROVISIONER_SHA256=.*/readonly G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_COMMIT=.*/readonly BASELINE_RECONSTRUCTION_COMMIT=$G2_AUTHORITY_COMMIT/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_GIT_TREE=.*/readonly BASELINE_RECONSTRUCTION_GIT_TREE=$G2_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=.*/readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=.*/readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly ENGINE_CARGO_LOCK_SHA256=.*/readonly ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh"
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
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
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
    -e "s/^readonly G4_MANIFEST_SHA256=.*/readonly G4_MANIFEST_SHA256=$g4_manifest_sha256/" \
    -e "s/^readonly G4_BUNDLE_SHA256=.*/readonly G4_BUNDLE_SHA256=$g4_bundle_sha256/" \
    -e "s/^readonly G4_WORKFLOW_COMMIT=.*/readonly G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_COMMIT=.*/readonly G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_TREE_SHA256=.*/readonly G4_AUTHORITY_TREE_SHA256=$G4_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G4_SHIPPER_SHA256=.*/readonly G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256/" \
    -e "s/^readonly G4_VERIFIER_SHA256=.*/readonly G4_VERIFIER_SHA256=$G4_VERIFIER_SHA256/" \
    -e "s/^readonly G4_PROVISIONER_SHA256=.*/readonly G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256/" \
    -e "s/^readonly G5_MANIFEST_SHA256=.*/readonly G5_MANIFEST_SHA256=$g5_manifest_sha256/" \
    -e "s/^readonly G5_BUNDLE_SHA256=.*/readonly G5_BUNDLE_SHA256=$g5_bundle_sha256/" \
    -e "s/^readonly G5_WORKFLOW_COMMIT=.*/readonly G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_COMMIT=.*/readonly G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_TREE_SHA256=.*/readonly G5_AUTHORITY_TREE_SHA256=$G5_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G5_SHIPPER_SHA256=.*/readonly G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256/" \
    -e "s/^readonly G5_VERIFIER_SHA256=.*/readonly G5_VERIFIER_SHA256=$G5_VERIFIER_SHA256/" \
    -e "s/^readonly G5_PROVISIONER_SHA256=.*/readonly G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256/" \
    -e "s/^readonly G6_MANIFEST_SHA256=.*/readonly G6_MANIFEST_SHA256=$g6_manifest_sha256/" \
    -e "s/^readonly G6_BUNDLE_SHA256=.*/readonly G6_BUNDLE_SHA256=$g6_bundle_sha256/" \
    -e "s/^readonly G6_WORKFLOW_COMMIT=.*/readonly G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_COMMIT=.*/readonly G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_GIT_TREE=.*/readonly G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G6_AUTHORITY_TREE_SHA256=.*/readonly G6_AUTHORITY_TREE_SHA256=$G6_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G6_SHIPPER_SHA256=.*/readonly G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256/" \
    -e "s/^readonly G6_VERIFIER_SHA256=.*/readonly G6_VERIFIER_SHA256=$G6_VERIFIER_SHA256/" \
    -e "s/^readonly G6_PROVISIONER_SHA256=.*/readonly G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256/" \
    -e "s/^readonly G7_MANIFEST_SHA256=.*/readonly G7_MANIFEST_SHA256=$g7_manifest_sha256/" \
    -e "s/^readonly G7_BUNDLE_SHA256=.*/readonly G7_BUNDLE_SHA256=$g7_bundle_sha256/" \
    -e "s/^readonly G7_WORKFLOW_COMMIT=.*/readonly G7_WORKFLOW_COMMIT=$G7_WORKFLOW_COMMIT/" \
    -e "s/^readonly G7_AUTHORITY_COMMIT=.*/readonly G7_AUTHORITY_COMMIT=$G7_AUTHORITY_COMMIT/" \
    -e "s/^readonly G7_AUTHORITY_GIT_TREE=.*/readonly G7_AUTHORITY_GIT_TREE=$G7_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G7_AUTHORITY_TREE_SHA256=.*/readonly G7_AUTHORITY_TREE_SHA256=$G7_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G7_SOURCE_DATE_EPOCH=.*/readonly G7_SOURCE_DATE_EPOCH=$G7_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G7_SHIPPER_SHA256=.*/readonly G7_SHIPPER_SHA256=$G7_SHIPPER_SHA256/" \
    -e "s/^readonly G7_VERIFIER_SHA256=.*/readonly G7_VERIFIER_SHA256=$G7_VERIFIER_SHA256/" \
    -e "s/^readonly G7_PROVISIONER_SHA256=.*/readonly G7_PROVISIONER_SHA256=$G7_PROVISIONER_SHA256/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_COMMIT=.*/readonly BASELINE_RECONSTRUCTION_COMMIT=$G2_AUTHORITY_COMMIT/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_GIT_TREE=.*/readonly BASELINE_RECONSTRUCTION_GIT_TREE=$G2_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=.*/readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=.*/readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly ENGINE_CARGO_LOCK_SHA256=.*/readonly ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh"
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
    -e "s/^readonly G2_AUTHORITY_TREE_SHA256=.*/readonly G2_AUTHORITY_TREE_SHA256=$G2_AUTHORITY_TREE_SHA256/" \
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
    -e "s/^readonly G4_MANIFEST_SHA256=.*/readonly G4_MANIFEST_SHA256=$g4_manifest_sha256/" \
    -e "s/^readonly G4_BUNDLE_SHA256=.*/readonly G4_BUNDLE_SHA256=$g4_bundle_sha256/" \
    -e "s/^readonly G4_WORKFLOW_COMMIT=.*/readonly G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_COMMIT=.*/readonly G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT/" \
    -e "s/^readonly G4_AUTHORITY_TREE_SHA256=.*/readonly G4_AUTHORITY_TREE_SHA256=$G4_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G4_SHIPPER_SHA256=.*/readonly G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256/" \
    -e "s/^readonly G4_VERIFIER_SHA256=.*/readonly G4_VERIFIER_SHA256=$G4_VERIFIER_SHA256/" \
    -e "s/^readonly G4_PROVISIONER_SHA256=.*/readonly G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256/" \
    -e "s/^readonly G5_MANIFEST_SHA256=.*/readonly G5_MANIFEST_SHA256=$g5_manifest_sha256/" \
    -e "s/^readonly G5_BUNDLE_SHA256=.*/readonly G5_BUNDLE_SHA256=$g5_bundle_sha256/" \
    -e "s/^readonly G5_WORKFLOW_COMMIT=.*/readonly G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_COMMIT=.*/readonly G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT/" \
    -e "s/^readonly G5_AUTHORITY_TREE_SHA256=.*/readonly G5_AUTHORITY_TREE_SHA256=$G5_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G5_SHIPPER_SHA256=.*/readonly G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256/" \
    -e "s/^readonly G5_VERIFIER_SHA256=.*/readonly G5_VERIFIER_SHA256=$G5_VERIFIER_SHA256/" \
    -e "s/^readonly G5_PROVISIONER_SHA256=.*/readonly G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256/" \
    -e "s/^readonly G6_MANIFEST_SHA256=.*/readonly G6_MANIFEST_SHA256=$g6_manifest_sha256/" \
    -e "s/^readonly G6_BUNDLE_SHA256=.*/readonly G6_BUNDLE_SHA256=$g6_bundle_sha256/" \
    -e "s/^readonly G6_WORKFLOW_COMMIT=.*/readonly G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_COMMIT=.*/readonly G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT/" \
    -e "s/^readonly G6_AUTHORITY_TREE_SHA256=.*/readonly G6_AUTHORITY_TREE_SHA256=$G6_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G6_SHIPPER_SHA256=.*/readonly G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256/" \
    -e "s/^readonly G6_VERIFIER_SHA256=.*/readonly G6_VERIFIER_SHA256=$G6_VERIFIER_SHA256/" \
    -e "s/^readonly G6_PROVISIONER_SHA256=.*/readonly G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256/" \
    -e "s/^readonly G7_MANIFEST_SHA256=.*/readonly G7_MANIFEST_SHA256=$g7_manifest_sha256/" \
    -e "s/^readonly G7_BUNDLE_SHA256=.*/readonly G7_BUNDLE_SHA256=$g7_bundle_sha256/" \
    -e "s/^readonly G7_WORKFLOW_COMMIT=.*/readonly G7_WORKFLOW_COMMIT=$G7_WORKFLOW_COMMIT/" \
    -e "s/^readonly G7_AUTHORITY_COMMIT=.*/readonly G7_AUTHORITY_COMMIT=$G7_AUTHORITY_COMMIT/" \
    -e "s/^readonly G7_AUTHORITY_GIT_TREE=.*/readonly G7_AUTHORITY_GIT_TREE=$G7_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G7_AUTHORITY_TREE_SHA256=.*/readonly G7_AUTHORITY_TREE_SHA256=$G7_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G7_SHIPPER_SHA256=.*/readonly G7_SHIPPER_SHA256=$G7_SHIPPER_SHA256/" \
    -e "s/^readonly G7_VERIFIER_SHA256=.*/readonly G7_VERIFIER_SHA256=$G7_VERIFIER_SHA256/" \
    -e "s/^readonly G7_PROVISIONER_SHA256=.*/readonly G7_PROVISIONER_SHA256=$G7_PROVISIONER_SHA256/" \
    -e "s/^readonly G8_MANIFEST_SHA256=.*/readonly G8_MANIFEST_SHA256=$g8_manifest_sha256/" \
    -e "s/^readonly G8_BUNDLE_SHA256=.*/readonly G8_BUNDLE_SHA256=$g8_bundle_sha256/" \
    -e "s/^readonly G8_WORKFLOW_COMMIT=.*/readonly G8_WORKFLOW_COMMIT=$G8_WORKFLOW_COMMIT/" \
    -e "s/^readonly G8_AUTHORITY_COMMIT=.*/readonly G8_AUTHORITY_COMMIT=$G8_AUTHORITY_COMMIT/" \
    -e "s/^readonly G8_AUTHORITY_GIT_TREE=.*/readonly G8_AUTHORITY_GIT_TREE=$G8_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G8_AUTHORITY_TREE_SHA256=.*/readonly G8_AUTHORITY_TREE_SHA256=$G8_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G8_SOURCE_DATE_EPOCH=.*/readonly G8_SOURCE_DATE_EPOCH=$G8_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G8_SHIPPER_SHA256=.*/readonly G8_SHIPPER_SHA256=$G8_SHIPPER_SHA256/" \
    -e "s/^readonly G8_VERIFIER_SHA256=.*/readonly G8_VERIFIER_SHA256=$G8_VERIFIER_SHA256/" \
    -e "s/^readonly G8_PROVISIONER_SHA256=.*/readonly G8_PROVISIONER_SHA256=$G8_PROVISIONER_SHA256/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_COMMIT=.*/readonly BASELINE_RECONSTRUCTION_COMMIT=$G2_AUTHORITY_COMMIT/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_GIT_TREE=.*/readonly BASELINE_RECONSTRUCTION_GIT_TREE=$G2_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=.*/readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=$G2_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=.*/readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly ENGINE_CARGO_LOCK_SHA256=.*/readonly ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256/" \
    -e "s/^readonly RUSTSEC_DB_COMMIT=.*/readonly RUSTSEC_DB_COMMIT=$RECOVERY_RUSTSEC_DB_COMMIT/" \
    -e "s/^readonly RUSTSEC_TREE_SHA256=.*/readonly RUSTSEC_TREE_SHA256=$RECOVERY_RUSTSEC_TREE_SHA256/" \
    -e "s/^readonly SYSTEM_USR_TREE_SHA256=.*/readonly SYSTEM_USR_TREE_SHA256=$RECOVERY_SYSTEM_USR_TREE_SHA256/" \
    -e "s/^readonly PRE_RECOVERY_SHIPPER_SHA256=.*/readonly PRE_RECOVERY_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256/" \
    -e "s|^readonly MAC_IDENTITY=.*|readonly MAC_IDENTITY=$GENESIS_TEST_IDENTITY_PATH|" \
    -e "s/^readonly MAC_IDENTITY_SHA256=.*/readonly MAC_IDENTITY_SHA256=$GENESIS_TEST_IDENTITY_SHA256/" \
    -e "s/^readonly MAC_IDENTITY_SIZE=.*/readonly MAC_IDENTITY_SIZE=$GENESIS_TEST_IDENTITY_SIZE/" \
    -e "s/^readonly MAC_IDENTITY_PUBLIC_SHA256=.*/readonly MAC_IDENTITY_PUBLIC_SHA256=$GENESIS_TEST_IDENTITY_PUBLIC_SHA256/" \
    -e "s|^readonly MAC_IDENTITY_FINGERPRINT=.*|readonly MAC_IDENTITY_FINGERPRINT='$GENESIS_TEST_IDENTITY_FINGERPRINT'|" \
    "$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh"
declare -A recovery_v6_readonly=()
while IFS= read -r readonly_line; do
    if [[ $readonly_line =~ ^readonly[[:space:]]+([A-Z0-9_]+)= ]]; then
        recovery_v6_readonly["${BASH_REMATCH[1]}"]=$readonly_line
    fi
done <"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh"
while IFS= read -r readonly_line; do
    if [[ $readonly_line =~ ^readonly[[:space:]]+([A-Z0-9_]+)= ]] \
        && [[ -v recovery_v6_readonly["${BASH_REMATCH[1]}"] ]]; then
        printf '%s\n' "${recovery_v6_readonly["${BASH_REMATCH[1]}"]}"
    else
        printf '%s\n' "$readonly_line"
    fi
done <"$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.common"
sed \
    -e "s/^readonly G9_MANIFEST_SHA256=.*/readonly G9_MANIFEST_SHA256=$g9_manifest_sha256/" \
    -e "s/^readonly G9_BUNDLE_SHA256=.*/readonly G9_BUNDLE_SHA256=$g9_bundle_sha256/" \
    -e "s/^readonly G9_WORKFLOW_COMMIT=.*/readonly G9_WORKFLOW_COMMIT=$G9_WORKFLOW_COMMIT/" \
    -e "s/^readonly G9_AUTHORITY_COMMIT=.*/readonly G9_AUTHORITY_COMMIT=$G9_AUTHORITY_COMMIT/" \
    -e "s/^readonly G9_AUTHORITY_GIT_TREE=.*/readonly G9_AUTHORITY_GIT_TREE=$G9_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G9_AUTHORITY_TREE_SHA256=.*/readonly G9_AUTHORITY_TREE_SHA256=$G9_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G9_SOURCE_DATE_EPOCH=.*/readonly G9_SOURCE_DATE_EPOCH=$G9_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G9_SHIPPER_SHA256=.*/readonly G9_SHIPPER_SHA256=$G9_SHIPPER_SHA256/" \
    -e "s/^readonly G9_VERIFIER_SHA256=.*/readonly G9_VERIFIER_SHA256=$G9_VERIFIER_SHA256/" \
    -e "s/^readonly G9_PROVISIONER_SHA256=.*/readonly G9_PROVISIONER_SHA256=$G9_PROVISIONER_SHA256/" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.common" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh"
rm -f \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.common"
declare -A recovery_v7_readonly=()
while IFS= read -r readonly_line; do
    if [[ $readonly_line =~ ^readonly[[:space:]]+([A-Z0-9_]+)= ]]; then
        recovery_v7_readonly["${BASH_REMATCH[1]}"]=$readonly_line
    fi
done <"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh"
while IFS= read -r readonly_line; do
    if [[ $readonly_line =~ ^readonly[[:space:]]+([A-Z0-9_]+)= ]] \
        && [[ -v recovery_v7_readonly["${BASH_REMATCH[1]}"] ]]; then
        printf '%s\n' "${recovery_v7_readonly["${BASH_REMATCH[1]}"]}"
    else
        printf '%s\n' "$readonly_line"
    fi
done <"$repo_root/scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.common"
sed \
    -e "s/^readonly G10_MANIFEST_SHA256=.*/readonly G10_MANIFEST_SHA256=$g10_manifest_sha256/" \
    -e "s/^readonly G10_BUNDLE_SHA256=.*/readonly G10_BUNDLE_SHA256=$g10_bundle_sha256/" \
    -e "s/^readonly G10_WORKFLOW_COMMIT=.*/readonly G10_WORKFLOW_COMMIT=$G10_WORKFLOW_COMMIT/" \
    -e "s/^readonly G10_AUTHORITY_COMMIT=.*/readonly G10_AUTHORITY_COMMIT=$G10_AUTHORITY_COMMIT/" \
    -e "s/^readonly G10_AUTHORITY_GIT_TREE=.*/readonly G10_AUTHORITY_GIT_TREE=$G10_AUTHORITY_GIT_TREE/" \
    -e "s/^readonly G10_AUTHORITY_TREE_SHA256=.*/readonly G10_AUTHORITY_TREE_SHA256=$G10_AUTHORITY_TREE_SHA256/" \
    -e "s/^readonly G10_SOURCE_DATE_EPOCH=.*/readonly G10_SOURCE_DATE_EPOCH=$G10_SOURCE_DATE_EPOCH/" \
    -e "s/^readonly G10_SHIPPER_SHA256=.*/readonly G10_SHIPPER_SHA256=$G10_SHIPPER_SHA256/" \
    -e "s/^readonly G10_VERIFIER_SHA256=.*/readonly G10_VERIFIER_SHA256=$G10_VERIFIER_SHA256/" \
    -e "s/^readonly G10_PROVISIONER_SHA256=.*/readonly G10_PROVISIONER_SHA256=$G10_PROVISIONER_SHA256/" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.common" \
    >"$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh"
rm -f \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.common"
cp "$repo_root/scripts/release-authority-manifest.sh" \
    "$context/release-authority-manifest.sh"
cp "$repo_root/scripts/fixtures/release_authority_fake_cosign.sh" \
    "$context/release-authority-fake-cosign.sh"
cp "$repo_root/scripts/fixtures/release_authority_bootstrap_driver.sh" \
    "$context/release-authority-bootstrap-driver.sh"
cp "$repo_root/scripts/fixtures/release_authority_g10_g11_driver.sh" \
    "$context/release-authority-g10-g11-driver.sh"
cp "$repo_root/scripts/recover-release-authority-g10-g11-canary-root-v1.sh" \
    "$context/recover-release-authority-g10-g11-canary-root-v1.sh"
cp "$repo_root/scripts/fixtures/release_authority_g11_g12_driver.sh" \
    "$context/release-authority-g11-g12-driver.sh"
cp "$repo_root/scripts/recover-release-authority-g11-g12-canary-root-v1.sh" \
    "$context/recover-release-authority-g11-g12-canary-root-v1.sh"
cp "$repo_root/scripts/fixtures/release_authority_g12_g13_driver.sh" \
    "$context/release-authority-g12-g13-driver.sh"
cp "$repo_root/scripts/recover-release-authority-g12-g13-canary-root-v1.sh" \
    "$context/recover-release-authority-g12-g13-canary-root-v1.sh"
cp "$repo_root/scripts/fixtures/release_authority_g13_g14_driver.sh" \
    "$context/release-authority-g13-g14-driver.sh"
cp "$repo_root/scripts/recover-release-authority-g13-g14-canary-root-v1.sh" \
    "$context/recover-release-authority-g13-g14-canary-root-v1.sh"
cp "$repo_root/scripts/fixtures/release_authority_bootstrap.Dockerfile" \
    "$context/Dockerfile"
chmod 0555 \
    "$context/bootstrap-release-authority-genesis-v2.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh" \
    "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh" \
    "$context/recover-release-authority-g10-g11-canary-root-v1.sh" \
    "$context/recover-release-authority-g11-g12-canary-root-v1.sh" \
    "$context/recover-release-authority-g12-g13-canary-root-v1.sh" \
    "$context/recover-release-authority-g13-g14-canary-root-v1.sh" \
    "$context/release-authority-manifest.sh" \
    "$context/release-authority-bootstrap-driver.sh" \
    "$context/release-authority-g10-g11-driver.sh" \
    "$context/release-authority-g11-g12-driver.sh" \
    "$context/release-authority-g12-g13-driver.sh" \
    "$context/release-authority-g13-g14-driver.sh"
chmod 0755 "$context/release-authority-fake-cosign.sh"
chmod 0500 "$fixture" "$fixture_g2" "$fixture_g3" "$fixture_g4" "$fixture_g5" \
    "$fixture_g6" "$fixture_g7" "$fixture_g8" "$fixture_g9" "$fixture_g10" \
    "$recovery_predecessor"
chmod 0400 \
    "$fixture/release-authority-v2.json" \
    "$fixture/release-authority-v2.json.cosign.bundle" \
    "$fixture_g2/release-authority-v2.json" \
    "$fixture_g2/release-authority-v2.json.cosign.bundle" \
    "$fixture_g3/release-authority-v2.json" \
    "$fixture_g3/release-authority-v2.json.cosign.bundle" \
    "$fixture_g4/release-authority-v2.json" \
    "$fixture_g4/release-authority-v2.json.cosign.bundle" \
    "$fixture_g5/release-authority-v2.json" \
    "$fixture_g5/release-authority-v2.json.cosign.bundle" \
    "$fixture_g6/release-authority-v2.json" \
    "$fixture_g6/release-authority-v2.json.cosign.bundle" \
    "$fixture_g7/release-authority-v2.json" \
    "$fixture_g7/release-authority-v2.json.cosign.bundle" \
    "$fixture_g8/release-authority-v2.json" \
    "$fixture_g8/release-authority-v2.json.cosign.bundle" \
    "$fixture_g9/release-authority-v2.json" \
    "$fixture_g9/release-authority-v2.json.cosign.bundle" \
    "$fixture_g10/release-authority-v2.json" \
    "$fixture_g10/release-authority-v2.json.cosign.bundle"
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
    "$fixture_g4/syntaur-build-authority-provision" \
    "$fixture_g4/syntaur-ship-linux-x86_64" \
    "$fixture_g4/syntaur-verify-linux-x86_64" \
    "$fixture_g5/syntaur-build-authority-provision" \
    "$fixture_g5/syntaur-ship-linux-x86_64" \
    "$fixture_g5/syntaur-verify-linux-x86_64" \
    "$fixture_g6/syntaur-build-authority-provision" \
    "$fixture_g6/syntaur-ship-linux-x86_64" \
    "$fixture_g6/syntaur-verify-linux-x86_64" \
    "$fixture_g7/syntaur-build-authority-provision" \
    "$fixture_g7/syntaur-ship-linux-x86_64" \
    "$fixture_g7/syntaur-verify-linux-x86_64" \
    "$fixture_g8/syntaur-build-authority-provision" \
    "$fixture_g8/syntaur-ship-linux-x86_64" \
    "$fixture_g8/syntaur-verify-linux-x86_64" \
    "$fixture_g9/syntaur-build-authority-provision" \
    "$fixture_g9/syntaur-ship-linux-x86_64" \
    "$fixture_g9/syntaur-verify-linux-x86_64" \
    "$fixture_g10/syntaur-build-authority-provision" \
    "$fixture_g10/syntaur-ship-linux-x86_64" \
    "$fixture_g10/syntaur-verify-linux-x86_64" \
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
    g10_g11_scenarios=(
        normal
        lock-root
        lock-global
        lock-deploy
        root-lock-bootstrap
        acquisition-lock-replace
        acquisition-lock-metadata
        tamper
        resume-prepared
        resume-generation_published
        resume-shipper_published
        resume-provisioner_published
        resume-trust_published
        resume-bundle_published
        resume-manifest_published
        fence-before-journal
        journal-without-fence
        normal-promotion-pending
        normal-promotion-temp-pending
        tampered-fence
        crash-window-prepared-generation
        crash-window-generation-shipper
        crash-window-provisioner-trust
        crash-window-trust-bundle
        crash-window-bundle-manifest
        pre-receipt-product-change
        terminal-product-update
        retirement-crash-no-sources
        phase-mismatch
        status-lock-replace
        status-lock-replace-final
        stale-temporaries
    )
    for g10_g11_scenario in "${g10_g11_scenarios[@]}"; do
        docker run --rm --hostname claudevm \
            --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
            --entrypoint /bootstrap/g10-g11-driver.sh \
            --env "G10_G11_FIXTURE_SCENARIO=$g10_g11_scenario" \
            "$image"
    done
    g11_g12_scenarios=(
        normal
        lock-root
        lock-global
        lock-deploy
        root-lock-bootstrap
        acquisition-lock-replace
        acquisition-lock-metadata
        tamper
        resume-prepared
        resume-generation_published
        resume-shipper_published
        resume-provisioner_published
        resume-trust_published
        resume-bundle_published
        resume-manifest_published
        fence-before-journal
        journal-without-fence
        normal-promotion-pending
        normal-promotion-temp-pending
        tampered-fence
        crash-window-prepared-generation
        crash-window-generation-shipper
        crash-window-shipper-provisioner
        crash-window-provisioner-trust
        crash-window-trust-bundle
        crash-window-bundle-manifest
        pre-receipt-product-change
        terminal-product-update
        retirement-crash-no-sources
        provisioner-state-mismatch
        predecessor-recovery-incomplete
        phase-mismatch
        status-lock-replace
        status-lock-replace-final
        stale-temporaries
    )
    for g11_g12_scenario in "${g11_g12_scenarios[@]}"; do
        docker run --rm --hostname claudevm \
            --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
            --entrypoint /bootstrap/g11-g12-driver.sh \
            --env "G11_G12_FIXTURE_SCENARIO=$g11_g12_scenario" \
            "$image"
    done
    g12_g13_scenarios=(
        "${g10_g11_scenarios[@]}"
        predecessor-recovery-incomplete
    )
    for g12_g13_scenario in "${g12_g13_scenarios[@]}"; do
        docker run --rm --hostname claudevm \
            --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
            --entrypoint /bootstrap/g12-g13-driver.sh \
            --env "G12_G13_FIXTURE_SCENARIO=$g12_g13_scenario" \
            "$image"
    done
    g13_g14_scenarios=(
        "${g12_g13_scenarios[@]}"
    )
    for g13_g14_scenario in "${g13_g14_scenarios[@]}"; do
        docker run --rm --hostname claudevm \
            --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
            --entrypoint /bootstrap/g13-g14-driver.sh \
            --env "G13_G14_FIXTURE_SCENARIO=$g13_g14_scenario" \
            "$image"
    done
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
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery-g4 \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery-g5 \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G5_MANIFEST_SHA256=$g5_manifest_sha256" \
        --env "RECOVERY_G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256" \
        --env "RECOVERY_G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256" \
        --env "RECOVERY_G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT" \
        --env "RECOVERY_SOURCE_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery-g6 \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G5_MANIFEST_SHA256=$g5_manifest_sha256" \
        --env "RECOVERY_G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256" \
        --env "RECOVERY_G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256" \
        --env "RECOVERY_G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G6_MANIFEST_SHA256=$g6_manifest_sha256" \
        --env "RECOVERY_G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256" \
        --env "RECOVERY_G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256" \
        --env "RECOVERY_G6_SOURCE_DATE_EPOCH=$G6_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT" \
        --env "RECOVERY_SOURCE_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery-g7 \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G5_MANIFEST_SHA256=$g5_manifest_sha256" \
        --env "RECOVERY_G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256" \
        --env "RECOVERY_G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256" \
        --env "RECOVERY_G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G6_MANIFEST_SHA256=$g6_manifest_sha256" \
        --env "RECOVERY_G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256" \
        --env "RECOVERY_G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256" \
        --env "RECOVERY_G6_SOURCE_DATE_EPOCH=$G6_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_COMMIT=$G7_AUTHORITY_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_GIT_TREE=$G7_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G7_MANIFEST_SHA256=$g7_manifest_sha256" \
        --env "RECOVERY_G7_PROVISIONER_SHA256=$G7_PROVISIONER_SHA256" \
        --env "RECOVERY_G7_SHIPPER_SHA256=$G7_SHIPPER_SHA256" \
        --env "RECOVERY_G7_SOURCE_DATE_EPOCH=$G7_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G7_WORKFLOW_COMMIT=$G7_WORKFLOW_COMMIT" \
        --env "RECOVERY_SOURCE_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env BOOTSTRAP_FIXTURE_SCENARIO=recovery-g8 \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G5_MANIFEST_SHA256=$g5_manifest_sha256" \
        --env "RECOVERY_G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256" \
        --env "RECOVERY_G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256" \
        --env "RECOVERY_G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G6_MANIFEST_SHA256=$g6_manifest_sha256" \
        --env "RECOVERY_G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256" \
        --env "RECOVERY_G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256" \
        --env "RECOVERY_G6_SOURCE_DATE_EPOCH=$G6_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_COMMIT=$G7_AUTHORITY_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_GIT_TREE=$G7_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G7_MANIFEST_SHA256=$g7_manifest_sha256" \
        --env "RECOVERY_G7_PROVISIONER_SHA256=$G7_PROVISIONER_SHA256" \
        --env "RECOVERY_G7_SHIPPER_SHA256=$G7_SHIPPER_SHA256" \
        --env "RECOVERY_G7_SOURCE_DATE_EPOCH=$G7_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G7_WORKFLOW_COMMIT=$G7_WORKFLOW_COMMIT" \
        --env "RECOVERY_G8_AUTHORITY_COMMIT=$G8_AUTHORITY_COMMIT" \
        --env "RECOVERY_G8_AUTHORITY_GIT_TREE=$G8_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G8_MANIFEST_SHA256=$g8_manifest_sha256" \
        --env "RECOVERY_G8_PROVISIONER_SHA256=$G8_PROVISIONER_SHA256" \
        --env "RECOVERY_G8_SHIPPER_SHA256=$G8_SHIPPER_SHA256" \
        --env "RECOVERY_G8_SOURCE_DATE_EPOCH=$G8_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G8_WORKFLOW_COMMIT=$G8_WORKFLOW_COMMIT" \
        --env "RECOVERY_SOURCE_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    for recovery_scenario in recovery-g9 recovery-g10; do
        docker run --rm --hostname claudevm \
        --tmpfs /run:rw,nosuid,nodev,noexec,mode=0755 \
        --env BOOTSTRAP_FIXTURE_REQUIRE_RUN_NOEXEC=1 \
        --env "BOOTSTRAP_FIXTURE_SCENARIO=$recovery_scenario" \
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
        --env "RECOVERY_G3_AUTHORITY_COMMIT=$G3_AUTHORITY_COMMIT" \
        --env "RECOVERY_G3_AUTHORITY_GIT_TREE=$G3_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G3_PROVISIONER_SHA256=$G3_PROVISIONER_SHA256" \
        --env "RECOVERY_G3_SHIPPER_SHA256=$G3_SHIPPER_SHA256" \
        --env "RECOVERY_G3_WORKFLOW_COMMIT=$G3_WORKFLOW_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_COMMIT=$G4_AUTHORITY_COMMIT" \
        --env "RECOVERY_G4_AUTHORITY_GIT_TREE=$G4_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G4_MANIFEST_SHA256=$g4_manifest_sha256" \
        --env "RECOVERY_G4_PROVISIONER_SHA256=$G4_PROVISIONER_SHA256" \
        --env "RECOVERY_G4_SHIPPER_SHA256=$G4_SHIPPER_SHA256" \
        --env "RECOVERY_G4_SOURCE_DATE_EPOCH=$G4_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G4_WORKFLOW_COMMIT=$G4_WORKFLOW_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_COMMIT=$G5_AUTHORITY_COMMIT" \
        --env "RECOVERY_G5_AUTHORITY_GIT_TREE=$G5_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G5_MANIFEST_SHA256=$g5_manifest_sha256" \
        --env "RECOVERY_G5_PROVISIONER_SHA256=$G5_PROVISIONER_SHA256" \
        --env "RECOVERY_G5_SHIPPER_SHA256=$G5_SHIPPER_SHA256" \
        --env "RECOVERY_G5_SOURCE_DATE_EPOCH=$G5_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G5_WORKFLOW_COMMIT=$G5_WORKFLOW_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_COMMIT=$G6_AUTHORITY_COMMIT" \
        --env "RECOVERY_G6_AUTHORITY_GIT_TREE=$G6_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G6_MANIFEST_SHA256=$g6_manifest_sha256" \
        --env "RECOVERY_G6_PROVISIONER_SHA256=$G6_PROVISIONER_SHA256" \
        --env "RECOVERY_G6_SHIPPER_SHA256=$G6_SHIPPER_SHA256" \
        --env "RECOVERY_G6_SOURCE_DATE_EPOCH=$G6_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G6_WORKFLOW_COMMIT=$G6_WORKFLOW_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_COMMIT=$G7_AUTHORITY_COMMIT" \
        --env "RECOVERY_G7_AUTHORITY_GIT_TREE=$G7_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G7_MANIFEST_SHA256=$g7_manifest_sha256" \
        --env "RECOVERY_G7_PROVISIONER_SHA256=$G7_PROVISIONER_SHA256" \
        --env "RECOVERY_G7_SHIPPER_SHA256=$G7_SHIPPER_SHA256" \
        --env "RECOVERY_G7_SOURCE_DATE_EPOCH=$G7_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G7_WORKFLOW_COMMIT=$G7_WORKFLOW_COMMIT" \
        --env "RECOVERY_G8_AUTHORITY_COMMIT=$G8_AUTHORITY_COMMIT" \
        --env "RECOVERY_G8_AUTHORITY_GIT_TREE=$G8_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G8_MANIFEST_SHA256=$g8_manifest_sha256" \
        --env "RECOVERY_G8_PROVISIONER_SHA256=$G8_PROVISIONER_SHA256" \
        --env "RECOVERY_G8_SHIPPER_SHA256=$G8_SHIPPER_SHA256" \
        --env "RECOVERY_G8_SOURCE_DATE_EPOCH=$G8_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G8_WORKFLOW_COMMIT=$G8_WORKFLOW_COMMIT" \
        --env "RECOVERY_G9_AUTHORITY_COMMIT=$G9_AUTHORITY_COMMIT" \
        --env "RECOVERY_G9_AUTHORITY_GIT_TREE=$G9_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G9_MANIFEST_SHA256=$g9_manifest_sha256" \
        --env "RECOVERY_G9_PROVISIONER_SHA256=$G9_PROVISIONER_SHA256" \
        --env "RECOVERY_G9_SHIPPER_SHA256=$G9_SHIPPER_SHA256" \
        --env "RECOVERY_G9_SOURCE_DATE_EPOCH=$G9_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G9_WORKFLOW_COMMIT=$G9_WORKFLOW_COMMIT" \
        --env "RECOVERY_G10_AUTHORITY_COMMIT=$G10_AUTHORITY_COMMIT" \
        --env "RECOVERY_G10_AUTHORITY_GIT_TREE=$G10_AUTHORITY_GIT_TREE" \
        --env "RECOVERY_G10_MANIFEST_SHA256=$g10_manifest_sha256" \
        --env "RECOVERY_G10_PROVISIONER_SHA256=$G10_PROVISIONER_SHA256" \
        --env "RECOVERY_G10_SHIPPER_SHA256=$G10_SHIPPER_SHA256" \
        --env "RECOVERY_G10_SOURCE_DATE_EPOCH=$G10_SOURCE_DATE_EPOCH" \
        --env "RECOVERY_G10_WORKFLOW_COMMIT=$G10_WORKFLOW_COMMIT" \
        --env "RECOVERY_SOURCE_CARGO_LOCK_SHA256=$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_ENGINE_CARGO_LOCK_SHA256=$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
        --env "RECOVERY_PREDECESSOR_SHIPPER_SHA256=$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
        "$image"
    done
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
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-genesis-v2.sh"
    chmod 0555 "$context/bootstrap-release-authority-genesis-v2.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh"
    # shellcheck disable=SC2016 # This test rewrite matches literal source text.
    sed -E 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]+$/g' \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh" \
        | sed \
            's/\[\[ $owner == 0 || $owner == "$operator_uid" \]\]/[[ $owner == 0 || $owner == 65534 || $owner == "$operator_uid" ]]/' \
        >"$context/bootstrap-single-uid"
    mv -f "$context/bootstrap-single-uid" \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh"
    chmod 0555 \
        "$context/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh"
    printf 'claudevm\n' >"$context/hostname"
    chmod 0444 "$context/hostname"
    alternatives_bind=()
    if [[ -d /etc/alternatives ]]; then
        alternatives_bind=(--ro-bind /etc/alternatives /etc/alternatives)
    fi
    run_bwrap_fixture() {
        local scenario=$1
        local -a scenario_args=()
        if [[ $scenario == recovery || $scenario == recovery-g4 \
            || $scenario == recovery-g5 || $scenario == recovery-g6 \
            || $scenario == recovery-g7 || $scenario == recovery-g8 \
            || $scenario == recovery-g9 || $scenario == recovery-g10 ]]; then
            scenario_args=(
                --setenv BOOTSTRAP_FIXTURE_SCENARIO "$scenario"
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
            --dir /tmp/fixture-g4 \
            --dir /tmp/fixture-g5 \
            --dir /tmp/fixture-g6 \
            --dir /tmp/fixture-g7 \
            --dir /tmp/fixture-g8 \
            --dir /tmp/fixture-g9 \
            --dir /tmp/fixture-g10 \
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
            --bind "$fixture_g4" /tmp/fixture-g4 \
            --bind "$fixture_g5" /tmp/fixture-g5 \
            --bind "$fixture_g6" /tmp/fixture-g6 \
            --bind "$fixture_g7" /tmp/fixture-g7 \
            --bind "$fixture_g8" /tmp/fixture-g8 \
            --bind "$fixture_g9" /tmp/fixture-g9 \
            --bind "$fixture_g10" /tmp/fixture-g10 \
            --ro-bind "$context" /tmp/bootstrap \
            --ro-bind "$expected_shipper" /tmp/expected \
            --ro-bind "$recovery_predecessor" /tmp/recovery-predecessor \
            --setenv BOOTSTRAP_FIXTURE_SOURCE_DIR /tmp/fixture \
            --setenv BOOTSTRAP_FIXTURE_G2_DIR /tmp/fixture-g2 \
            --setenv BOOTSTRAP_FIXTURE_G3_DIR /tmp/fixture-g3 \
            --setenv BOOTSTRAP_FIXTURE_G4_DIR /tmp/fixture-g4 \
            --setenv BOOTSTRAP_FIXTURE_G5_DIR /tmp/fixture-g5 \
            --setenv BOOTSTRAP_FIXTURE_G6_DIR /tmp/fixture-g6 \
            --setenv BOOTSTRAP_FIXTURE_G7_DIR /tmp/fixture-g7 \
            --setenv BOOTSTRAP_FIXTURE_G8_DIR /tmp/fixture-g8 \
            --setenv BOOTSTRAP_FIXTURE_G9_DIR /tmp/fixture-g9 \
            --setenv BOOTSTRAP_FIXTURE_G10_DIR /tmp/fixture-g10 \
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
            --setenv RECOVERY_G3_AUTHORITY_COMMIT \
                "$G3_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G3_AUTHORITY_GIT_TREE \
                "$G3_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G3_WORKFLOW_COMMIT \
                "$G3_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G4_AUTHORITY_COMMIT \
                "$G4_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G4_AUTHORITY_GIT_TREE \
                "$G4_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G4_MANIFEST_SHA256 \
                "$g4_manifest_sha256" \
            --setenv RECOVERY_G4_PROVISIONER_SHA256 \
                "$G4_PROVISIONER_SHA256" \
            --setenv RECOVERY_G4_SHIPPER_SHA256 \
                "$G4_SHIPPER_SHA256" \
            --setenv RECOVERY_G4_SOURCE_DATE_EPOCH \
                "$G4_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G4_WORKFLOW_COMMIT \
                "$G4_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G5_AUTHORITY_COMMIT \
                "$G5_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G5_AUTHORITY_GIT_TREE \
                "$G5_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G5_MANIFEST_SHA256 \
                "$g5_manifest_sha256" \
            --setenv RECOVERY_G5_PROVISIONER_SHA256 \
                "$G5_PROVISIONER_SHA256" \
            --setenv RECOVERY_G5_SHIPPER_SHA256 \
                "$G5_SHIPPER_SHA256" \
            --setenv RECOVERY_G5_SOURCE_DATE_EPOCH \
                "$G5_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G5_WORKFLOW_COMMIT \
                "$G5_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G6_AUTHORITY_COMMIT \
                "$G6_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G6_AUTHORITY_GIT_TREE \
                "$G6_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G6_MANIFEST_SHA256 \
                "$g6_manifest_sha256" \
            --setenv RECOVERY_G6_PROVISIONER_SHA256 \
                "$G6_PROVISIONER_SHA256" \
            --setenv RECOVERY_G6_SHIPPER_SHA256 \
                "$G6_SHIPPER_SHA256" \
            --setenv RECOVERY_G6_SOURCE_DATE_EPOCH \
                "$G6_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G6_WORKFLOW_COMMIT \
                "$G6_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G7_AUTHORITY_COMMIT \
                "$G7_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G7_AUTHORITY_GIT_TREE \
                "$G7_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G7_MANIFEST_SHA256 \
                "$g7_manifest_sha256" \
            --setenv RECOVERY_G7_PROVISIONER_SHA256 \
                "$G7_PROVISIONER_SHA256" \
            --setenv RECOVERY_G7_SHIPPER_SHA256 \
                "$G7_SHIPPER_SHA256" \
            --setenv RECOVERY_G7_SOURCE_DATE_EPOCH \
                "$G7_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G7_WORKFLOW_COMMIT \
                "$G7_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G8_AUTHORITY_COMMIT \
                "$G8_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G8_AUTHORITY_GIT_TREE \
                "$G8_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G8_MANIFEST_SHA256 \
                "$g8_manifest_sha256" \
            --setenv RECOVERY_G8_PROVISIONER_SHA256 \
                "$G8_PROVISIONER_SHA256" \
            --setenv RECOVERY_G8_SHIPPER_SHA256 \
                "$G8_SHIPPER_SHA256" \
            --setenv RECOVERY_G8_SOURCE_DATE_EPOCH \
                "$G8_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G8_WORKFLOW_COMMIT \
                "$G8_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G9_AUTHORITY_COMMIT \
                "$G9_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G9_AUTHORITY_GIT_TREE \
                "$G9_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G9_MANIFEST_SHA256 \
                "$g9_manifest_sha256" \
            --setenv RECOVERY_G9_PROVISIONER_SHA256 \
                "$G9_PROVISIONER_SHA256" \
            --setenv RECOVERY_G9_SHIPPER_SHA256 \
                "$G9_SHIPPER_SHA256" \
            --setenv RECOVERY_G9_SOURCE_DATE_EPOCH \
                "$G9_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G9_WORKFLOW_COMMIT \
                "$G9_WORKFLOW_COMMIT" \
            --setenv RECOVERY_G10_AUTHORITY_COMMIT \
                "$G10_AUTHORITY_COMMIT" \
            --setenv RECOVERY_G10_AUTHORITY_GIT_TREE \
                "$G10_AUTHORITY_GIT_TREE" \
            --setenv RECOVERY_G10_MANIFEST_SHA256 \
                "$g10_manifest_sha256" \
            --setenv RECOVERY_G10_PROVISIONER_SHA256 \
                "$G10_PROVISIONER_SHA256" \
            --setenv RECOVERY_G10_SHIPPER_SHA256 \
                "$G10_SHIPPER_SHA256" \
            --setenv RECOVERY_G10_SOURCE_DATE_EPOCH \
                "$G10_SOURCE_DATE_EPOCH" \
            --setenv RECOVERY_G10_WORKFLOW_COMMIT \
                "$G10_WORKFLOW_COMMIT" \
            --setenv RECOVERY_SOURCE_CARGO_LOCK_SHA256 \
                "$RECOVERY_SOURCE_CARGO_LOCK_SHA256" \
            --setenv RECOVERY_ENGINE_CARGO_LOCK_SHA256 \
                "$RECOVERY_ENGINE_CARGO_LOCK_SHA256" \
            --setenv RECOVERY_PREDECESSOR_SHIPPER_SHA256 \
                "$RECOVERY_PREDECESSOR_SHIPPER_SHA256" \
            "${scenario_args[@]}" \
            /tmp/bootstrap/release-authority-bootstrap-driver.sh
    }
    run_bwrap_fixture genesis
    run_bwrap_fixture recovery
    run_bwrap_fixture recovery-g4
    run_bwrap_fixture recovery-g5
    run_bwrap_fixture recovery-g6
    run_bwrap_fixture recovery-g7
    run_bwrap_fixture recovery-g8
    run_bwrap_fixture recovery-g9
    run_bwrap_fixture recovery-g10
fi
