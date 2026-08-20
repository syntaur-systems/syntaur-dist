#!/usr/bin/bash
set -euo pipefail
umask 077

operator_uid=1000
operator_gid=1000
scenario=${G11_G12_FIXTURE_SCENARIO:-normal}
helper=/bootstrap/release-authority-manifest.sh
source_script=/bootstrap/recover-release-authority-g11-g12-canary-root-v1.sh.source
fake_cosign=/usr/local/bin/cosign
material_root=/home/sean/authority-material
authority_root=/etc/syntaur/release-authority
artifact_root=$authority_root/release-authority
operator_state=/home/sean/.syntaur/ship
runtime=/etc/syntaur/release-authority-g11-g12-recovery-v1.runtime
recovery=$runtime/recover-release-authority-g11-g12-canary-root-v1.sh
verify_root=/home/sean/recovery-verify
verify_script=$verify_root/recover-release-authority-g11-g12-canary-root-v1.sh

die() {
    printf 'G11-G12 recovery fixture error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

expect_failure() {
    local label=$1
    shift
    if "$@" >"/run/$label.out" 2>"/run/$label.err"; then
        die "$label unexpectedly succeeded"
    fi
}

install -d -o "$operator_uid" -g "$operator_gid" -m 0755 /home/sean
install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$material_root"

g11_provisioner=$material_root/provisioner-g11
g12_provisioner=$material_root/provisioner-g12
verifier=$material_root/verifier
g11_shipper=$material_root/shipper-g11
g12_shipper=$material_root/shipper-g12
printf '#!/usr/bin/bash\nset -euo pipefail\nexit 0\n# generation 11 provisioner\n' \
    >"$g11_provisioner"
printf '#!/usr/bin/bash\nset -euo pipefail\nexit 0\n# generation 12 provisioner\n' \
    >"$g12_provisioner"
cat >/run/fixture-verifier.c <<'EOF'
int main(void) {
    return 0;
}
EOF
cat >/run/fixture-shipper.c <<'EOF'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define STRINGIFY_INNER(value) #value
#define STRINGIFY(value) STRINGIFY_INNER(value)

static const char generation_marker[] = "generation-" STRINGIFY(GENERATION);

int main(int argc, char **argv) {
    const char *lock = "/home/sean/.syntaur/ship/deploy.lock";
    const char *promotion_journal =
        "/etc/syntaur/release-authority/authority-promotion-v1.json";
    const char *generation_lock_marker =
        GENERATION == 11 ? "/run/syntaur-replace-deploy-lock-g11" :
            "/run/syntaur-replace-deploy-lock-g12";
    struct stat metadata;
    int descriptor;

    if (argc != 2) {
        return 64;
    }
    if (strcmp(argv[1], "normal-mutation-probe") == 0) {
        if (lstat(promotion_journal, &metadata) == 0) {
            fprintf(stderr,
                "an authority promotion recovery journal is pending at %s; "
                "resume that exact authority-promote transaction before any "
                "other mutation\n",
                promotion_journal);
            return 75;
        }
        if (errno == ENOENT) {
            return 0;
        }
        perror("normal mutation promotion-journal probe");
        return 74;
    }
    if (strcmp(argv[1], "authority-status") != 0) {
        return 64;
    }
    if (geteuid() != 1000) {
        return 65;
    }
    if (access("/run/syntaur-replace-deploy-lock", F_OK) == 0 ||
        access(generation_lock_marker, F_OK) == 0) {
        if (unlink(lock) != 0) {
            return 66;
        }
        descriptor = open(lock, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (descriptor < 0 || close(descriptor) != 0) {
            return 67;
        }
    }
    if (getenv("SYNTAUR_FIXTURE_PRINT_GENERATION") != NULL) {
        puts(generation_marker);
    }
    return 0;
}
EOF
/usr/bin/cc -O2 -Wall -Wextra -Werror \
    /run/fixture-verifier.c -o "$verifier"
/usr/bin/cc -O2 -Wall -Wextra -Werror -DGENERATION=11 \
    /run/fixture-shipper.c -o "$g11_shipper"
/usr/bin/cc -O2 -Wall -Wextra -Werror -DGENERATION=12 \
    /run/fixture-shipper.c -o "$g12_shipper"
chmod 0500 "$g11_provisioner" "$g12_provisioner" "$verifier" \
    "$g11_shipper" "$g12_shipper"

g11_provisioner_sha=$(sha256_file "$g11_provisioner")
g12_provisioner_sha=$(sha256_file "$g12_provisioner")
verifier_sha=$(sha256_file "$verifier")
g11_shipper_sha=$(sha256_file "$g11_shipper")
g12_shipper_sha=$(sha256_file "$g12_shipper")

export AUTHORITY_VERSION=0.7.114
export VERIFIER_TOOLCHAIN_ID=rust-1.94.1-x86_64-unknown-linux-gnu
export VERIFIER_CARGO_SHA256
VERIFIER_CARGO_SHA256=$(printf fixture-cargo | sha256sum | awk '{print $1}')
export VERIFIER_RUSTC_SHA256
VERIFIER_RUSTC_SHA256=$(printf fixture-rustc | sha256sum | awk '{print $1}')
export VERIFIER_RUSTDOC_SHA256
VERIFIER_RUSTDOC_SHA256=$(printf fixture-rustdoc | sha256sum | awk '{print $1}')
export BASELINE_PROFILE=mac-isolated-v1
export BASELINE_GENERATION=generation-fixture
export BASELINE_TREE_SHA256
BASELINE_TREE_SHA256=$(printf fixture-baseline | sha256sum | awk '{print $1}')
export BROWSER_BUNDLE_SHA256
BROWSER_BUNDLE_SHA256=$(printf fixture-browser | sha256sum | awk '{print $1}')
export BROWSER_VERSION='Google Chrome for Testing 131.0.6778.264'
export BROWSER_LAUNCH_PROFILE_SHA256
BROWSER_LAUNCH_PROFILE_SHA256=$(printf fixture-launch | sha256sum | awk '{print $1}')
export VERIFIER_SCHEMA=5
export PRODUCTION_CONTRACT_SHA256
PRODUCTION_CONTRACT_SHA256=$(printf fixture-production | sha256sum | awk '{print $1}')
export PRODUCTION_MEMBER_COUNT=12
export RECEIPT_SCHEMA=6
export BUILD_AUTHORITY_SCHEMA=4
export PROMOTION_RECOVERY_SCHEMA=1
export PROMOTION_RECOVERY_SHA256
PROMOTION_RECOVERY_SHA256=$(printf fixture-recovery | sha256sum | awk '{print $1}')

previous_generation=0
previous_manifest=$(printf '0%.0s' {1..64})
previous_authority_commit=
for generation in $(seq 1 12); do
    material=$material_root/generation-$generation
    install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$material"
    if (( generation == 12 )); then
        install -o "$operator_uid" -g "$operator_gid" -m 0500 \
            "$g12_shipper" "$material/syntaur-ship-linux-x86_64"
        shipper_sha=$g12_shipper_sha
        provisioner=$g12_provisioner
        provisioner_sha=$g12_provisioner_sha
    else
        install -o "$operator_uid" -g "$operator_gid" -m 0500 \
            "$g11_shipper" "$material/syntaur-ship-linux-x86_64"
        shipper_sha=$g11_shipper_sha
        provisioner=$g11_provisioner
        provisioner_sha=$g11_provisioner_sha
    fi
    install -o "$operator_uid" -g "$operator_gid" -m 0500 \
        "$verifier" "$material/syntaur-verify-linux-x86_64"
    install -o "$operator_uid" -g "$operator_gid" -m 0500 \
        "$provisioner" "$material/syntaur-build-authority-provision"
    workflow=$(printf '%040x' "$generation")
    authority_commit=$(printf '%040x' "$((4096 + generation))")
    verification_policy_revision=$authority_commit
    if (( generation > 1 )); then
        verification_policy_revision=$previous_authority_commit
    fi
    authority_tree=$(printf 'authority-tree-%s' "$generation" \
        | sha256sum | awk '{print $1}')
    env \
        SHIPPER_SHA256="$shipper_sha" \
        VERIFIER_SHA256="$verifier_sha" \
        PROVISIONER_SHA256="$provisioner_sha" \
        AUTHORITY_COMMIT="$authority_commit" \
        VERIFICATION_POLICY_REVISION="$verification_policy_revision" \
        AUTHORITY_TREE_SHA256="$authority_tree" \
        GITHUB_SHA="$workflow" \
        AUTHORITY_GENERATION="$generation" \
        PREVIOUS_AUTHORITY_GENERATION="$previous_generation" \
        PREVIOUS_AUTHORITY_MANIFEST_SHA256="$previous_manifest" \
        "$helper" render-v2 "$material/release-authority-v2.json"
    printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","fixtureGeneration":%s}\n' \
        "$generation" >"$material/release-authority-v2.json.cosign.bundle"
    chown "$operator_uid:$operator_gid" \
        "$material/release-authority-v2.json" \
        "$material/release-authority-v2.json.cosign.bundle"
    chmod 0400 \
        "$material/release-authority-v2.json" \
        "$material/release-authority-v2.json.cosign.bundle"
    chmod 0500 "$material"
    previous_generation=$generation
    previous_authority_commit=$authority_commit
    previous_manifest=$(sha256_file "$material/release-authority-v2.json")
done

g11=$material_root/generation-11
g12=$material_root/generation-12
g11_manifest_sha=$(sha256_file "$g11/release-authority-v2.json")
g11_bundle_sha=$(sha256_file "$g11/release-authority-v2.json.cosign.bundle")
g12_manifest_sha=$(sha256_file "$g12/release-authority-v2.json")
g12_bundle_sha=$(sha256_file "$g12/release-authority-v2.json.cosign.bundle")
g11_workflow=$(printf '%040x' 11)
g12_workflow=$(printf '%040x' 12)
cosign_sha=$(sha256_file "$fake_cosign")

patched=/run/recover-release-authority-g11-g12-canary-root-v1.sh
sed \
    -e "s/^readonly COSIGN_SHA256=.*/readonly COSIGN_SHA256=$cosign_sha/" \
    -e "s/^readonly G11_MANIFEST_SHA256=.*/readonly G11_MANIFEST_SHA256=$g11_manifest_sha/" \
    -e "s/^readonly G11_BUNDLE_SHA256=.*/readonly G11_BUNDLE_SHA256=$g11_bundle_sha/" \
    -e "s/^readonly G11_WORKFLOW_COMMIT=.*/readonly G11_WORKFLOW_COMMIT=$g11_workflow/" \
    -e "s/^readonly G11_SHIPPER_SHA256=.*/readonly G11_SHIPPER_SHA256=$g11_shipper_sha/" \
    -e "s/^readonly G11_VERIFIER_SHA256=.*/readonly G11_VERIFIER_SHA256=$verifier_sha/" \
    -e "s/^readonly G11_PROVISIONER_SHA256=.*/readonly G11_PROVISIONER_SHA256=$g11_provisioner_sha/" \
    -e "s/^readonly G12_MANIFEST_SHA256=.*/readonly G12_MANIFEST_SHA256=$g12_manifest_sha/" \
    -e "s/^readonly G12_BUNDLE_SHA256=.*/readonly G12_BUNDLE_SHA256=$g12_bundle_sha/" \
    -e "s/^readonly G12_WORKFLOW_COMMIT=.*/readonly G12_WORKFLOW_COMMIT=$g12_workflow/" \
    -e "s/^readonly G12_SHIPPER_SHA256=.*/readonly G12_SHIPPER_SHA256=$g12_shipper_sha/" \
    -e "s/^readonly G12_VERIFIER_SHA256=.*/readonly G12_VERIFIER_SHA256=$verifier_sha/" \
    -e "s/^readonly G12_PROVISIONER_SHA256=.*/readonly G12_PROVISIONER_SHA256=$g12_provisioner_sha/" \
    "$source_script" >"$patched"

install -d -o root -g root -m 0700 "$runtime"
install -o root -g root -m 0500 "$patched" "$recovery"
install -o root -g root -m 0500 "$helper" "$runtime/release-authority-manifest.sh"
old_runtime=/etc/syntaur/release-authority-g10-g11-recovery-v1.runtime
old_receipt=/etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json
install -d -o root -g root -m 0700 "$old_runtime"
printf '%s' 'historical G10-G11 runtime marker' >"$old_runtime/marker"
chown root:root "$old_runtime/marker"
chmod 0500 "$old_runtime/marker"
printf '%s' '{"schema":"syntaur.authority-g10-g11-recovery-receipt.v1","completed":true}' \
    >"$old_receipt"
chown root:root "$old_receipt"
chmod 0444 "$old_receipt"
old_runtime_marker_sha=$(sha256_file "$old_runtime/marker")
old_receipt_sha=$(sha256_file "$old_receipt")
install -d -o "$operator_uid" -g "$operator_gid" -m 0500 "$verify_root"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$patched" "$verify_script"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$helper" "$verify_root/release-authority-manifest.sh"

install -d -o root -g root -m 0755 /etc/syntaur "$authority_root" "$artifact_root"
for generation in $(seq 1 11); do
    source_material=$material_root/generation-$generation
    installed=$artifact_root/generation-$generation
    workflow=$(printf '%040x' "$generation")
    install -d -o root -g root -m 0555 "$installed"
    install -o root -g root -m 0444 \
        "$source_material/release-authority-v2.json" \
        "$source_material/release-authority-v2.json.cosign.bundle" "$installed/"
    printf '%s\n' "$workflow" >"$installed/trusted-workflow-commit"
    chown root:root "$installed/trusted-workflow-commit"
    chmod 0444 "$installed/trusted-workflow-commit"
    install -o root -g root -m 0555 \
        "$source_material/syntaur-build-authority-provision" \
        "$source_material/syntaur-ship-linux-x86_64" \
        "$source_material/syntaur-verify-linux-x86_64" "$installed/"
done
install -o root -g root -m 0444 \
    "$g11/release-authority-v2.json" "$authority_root/release-authority-v2.json"
install -o root -g root -m 0444 \
    "$g11/release-authority-v2.json.cosign.bundle" \
    "$authority_root/release-authority-v2.json.cosign.bundle"
printf '%s\n' "$g11_workflow" >"$authority_root/trusted-workflow-commit"
chown root:root "$authority_root/trusted-workflow-commit"
chmod 0444 "$authority_root/trusted-workflow-commit"
install -o root -g root -m 1755 "$g11/syntaur-ship-linux-x86_64" \
    /usr/local/bin/syntaur-ship
install -o root -g root -m 0755 "$g11/syntaur-build-authority-provision" \
    /opt/syntaur-build-authority-provision
install -o root -g root -m 0600 /dev/null \
    "$authority_root/.authority-promotion.lock"
install -o root -g "$operator_gid" -m 0440 /dev/null \
    /etc/syntaur/syntaur-ship-mutation.lock

install -d -o "$operator_uid" -g "$operator_gid" -m 0700 \
    /home/sean/.syntaur "$operator_state" \
    "$operator_state/release-intent" "$operator_state/release-dispatch" \
    "$operator_state/release-run" "$operator_state/release-authority"
install -o "$operator_uid" -g "$operator_gid" -m 0600 /dev/null \
    "$operator_state/deploy.lock"
for relative in \
    current-release.json features.txt deploy-stamp.json \
    deploy-stamp.json.cosign.bundle release-intent/v0.7.114.json \
    release-dispatch/v0.7.114.json release-run/v0.7.114.json \
    release-authority/v0.7.114.json; do
    printf 'fixture product state: %s\n' "$relative" >"$operator_state/$relative"
    chown "$operator_uid:$operator_gid" "$operator_state/$relative"
    chmod 0600 "$operator_state/$relative"
done

product_digest() {
    local path
    {
        for path in \
            "$operator_state/current-release.json" \
            "$operator_state/features.txt" \
            "$operator_state/deploy-stamp.json" \
            "$operator_state/deploy-stamp.json.cosign.bundle" \
            "$operator_state/release-intent/v0.7.114.json" \
            "$operator_state/release-dispatch/v0.7.114.json" \
            "$operator_state/release-run/v0.7.114.json" \
            "$operator_state/release-authority/v0.7.114.json"; do
            printf 'present\0%s\0%s\0' "$path" "$(sha256_file "$path")"
        done
        for path in \
            "$operator_state/release-intent/v0.7.115.json" \
            "$operator_state/release-dispatch/v0.7.115.json" \
            "$operator_state/release-run/v0.7.115.json" \
            "$operator_state/release-authority/v0.7.115.json"; do
            printf 'absent\0%s\0' "$path"
        done
    } | sha256sum | awk '{print $1}'
}

state_before=$(product_digest)

verify_exact() {
    setpriv --reuid "$operator_uid" --regid "$operator_gid" --clear-groups \
        /usr/bin/bash "$verify_script" verify --g11-dir "$g11" --g12-dir "$g12"
}

install_exact() {
    local source_g11=${1:-$g11} source_g12=${2:-$g12}
    SUDO_UID=$operator_uid SUDO_GID=$operator_gid \
        "$recovery" install \
        --g11-dir "$source_g11" --g12-dir "$source_g12" \
        --expected-current-shipper-sha256 "$g11_shipper_sha"
}

assert_g11_unchanged() {
    [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
        "$g11_manifest_sha" ]]
    [[ $(sha256_file /usr/local/bin/syntaur-ship) == "$g11_shipper_sha" ]]
    [[ $(sha256_file /opt/syntaur-build-authority-provision) == \
        "$g11_provisioner_sha" ]]
    [[ ! -e $authority_root/authority-g11-g12-recovery-v1.json ]]
}

assert_complete() {
    local actual expected
    [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
        "$g12_manifest_sha" ]]
    [[ $(sha256_file "$authority_root/release-authority-v2.json.cosign.bundle") == \
        "$g12_bundle_sha" ]]
    [[ $(<"$authority_root/trusted-workflow-commit") == "$g12_workflow" ]]
    [[ $(sha256_file /usr/local/bin/syntaur-ship) == "$g12_shipper_sha" ]]
    [[ $(sha256_file /opt/syntaur-build-authority-provision) == \
        "$g12_provisioner_sha" ]]
    [[ $(sha256_file "$old_runtime/marker") == "$old_runtime_marker_sha" ]]
    [[ $(sha256_file "$old_receipt") == "$old_receipt_sha" ]]
    expected=$(seq 1 12 | sed 's/^/generation-/' | LC_ALL=C sort)
    actual=$(find "$artifact_root" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual == "$expected" ]]
    [[ $(stat -c '%u:%g:%a:%h' \
        /etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json) \
        == 0:0:444:1 ]]
    for transient in \
        "$authority_root/authority-promotion-v1.json" \
        "$authority_root/.authority-promotion-v1.json.tmp" \
        "$authority_root/authority-g11-g12-recovery-v1.json" \
        "$authority_root/.authority-g11-g12-recovery-v1.json.tmp" \
        "$authority_root/.authority-g11-g12-recovery-v1.fence.tmp" \
        "$authority_root/.authority-g11-g12-recovery-v1.inputs" \
        "$authority_root/.authority-g11-g12-recovery-v1.inputs.staged" \
        "$authority_root/.authority-g11-g12-recovery-v1.inputs.retiring" \
        "$artifact_root/.generation-12-g11-g12-recovery-v1.staged"; do
        [[ ! -e $transient && ! -L $transient ]]
    done
    [[ $(product_digest) == "$state_before" ]]
    /usr/local/bin/syntaur-ship normal-mutation-probe
}

assert_normal_mutation_blocked() {
    local before
    before=$(product_digest)
    expect_failure normal-mutation-blocked \
        /usr/local/bin/syntaur-ship normal-mutation-probe
    grep -Fq 'an authority promotion recovery journal is pending' \
        /run/normal-mutation-blocked.err \
        || die 'normal mutation did not fail for the durable recovery fence'
    [[ $(product_digest) == "$before" ]] \
        || die 'blocked normal mutation changed product state'
}

snapshot_inputs() {
    local snapshot=$authority_root/.authority-g11-g12-recovery-v1.inputs
    local generation source target
    install -d -o root -g root -m 0700 \
        "$snapshot" "$snapshot/generation-11" "$snapshot/generation-12"
    for generation in 11 12; do
        source=$material_root/generation-$generation
        target=$snapshot/generation-$generation
        install -o root -g root -m 0400 \
            "$source/release-authority-v2.json" \
            "$source/release-authority-v2.json.cosign.bundle" "$target/"
        install -o root -g root -m 0500 \
            "$source/syntaur-build-authority-provision" \
            "$source/syntaur-ship-linux-x86_64" \
            "$source/syntaur-verify-linux-x86_64" "$target/"
    done
    install -o root -g root -m 0500 "$helper" \
        "$snapshot/release-authority-manifest.sh"
}

publish_generation_12_fixture() {
    local installed=$artifact_root/generation-12
    [[ -e $installed ]] && return 0
    install -d -o root -g root -m 0555 "$installed"
    install -o root -g root -m 0444 \
        "$g12/release-authority-v2.json" \
        "$g12/release-authority-v2.json.cosign.bundle" "$installed/"
    printf '%s\n' "$g12_workflow" >"$installed/trusted-workflow-commit"
    chown root:root "$installed/trusted-workflow-commit"
    chmod 0444 "$installed/trusted-workflow-commit"
    install -o root -g root -m 0555 \
        "$g12/syntaur-build-authority-provision" \
        "$g12/syntaur-ship-linux-x86_64" \
        "$g12/syntaur-verify-linux-x86_64" "$installed/"
}

publish_target_shipper_fixture() {
    install -o root -g root -m 1755 \
        "$g12/syntaur-ship-linux-x86_64" /usr/local/bin/syntaur-ship
}

publish_target_provisioner_fixture() {
    install -o root -g root -m 0755 \
        "$g12/syntaur-build-authority-provision" \
        /opt/syntaur-build-authority-provision
}

publish_target_trust_fixture() {
    printf '%s\n' "$g12_workflow" \
        >"$authority_root/trusted-workflow-commit"
    chown root:root "$authority_root/trusted-workflow-commit"
    chmod 0444 "$authority_root/trusted-workflow-commit"
}

publish_target_bundle_fixture() {
    install -o root -g root -m 0444 \
        "$g12/release-authority-v2.json.cosign.bundle" \
        "$authority_root/release-authority-v2.json.cosign.bundle"
}

publish_target_manifest_fixture() {
    install -o root -g root -m 0444 \
        "$g12/release-authority-v2.json" \
        "$authority_root/release-authority-v2.json"
}

seed_journal() {
    local phase=$1
    jq -cjn \
        --arg phase "$phase" \
        --arg g11_manifest "$g11_manifest_sha" \
        --arg g11_shipper "$g11_shipper_sha" \
        --arg g11_provisioner "$g11_provisioner_sha" \
        --arg g12_manifest "$g12_manifest_sha" \
        --arg g12_bundle "$g12_bundle_sha" \
        --arg g12_workflow "$g12_workflow" \
        --arg g12_shipper "$g12_shipper_sha" \
        --arg g12_provisioner "$g12_provisioner_sha" \
        --arg product "$state_before" \
        '{schema:"syntaur.authority-g11-g12-recovery.v1",phase:$phase,
          previous_generation:11,previous_manifest_sha256:$g11_manifest,
          previous_shipper_sha256:$g11_shipper,
          previous_provisioner_sha256:$g11_provisioner,target_generation:12,
          target_manifest_sha256:$g12_manifest,target_bundle_sha256:$g12_bundle,
          target_workflow_commit:$g12_workflow,target_shipper_sha256:$g12_shipper,
          target_provisioner_sha256:$g12_provisioner,product_state_sha256:$product}' \
        >"$authority_root/authority-g11-g12-recovery-v1.json"
    chown root:root "$authority_root/authority-g11-g12-recovery-v1.json"
    chmod 0600 "$authority_root/authority-g11-g12-recovery-v1.json"
}

seed_fence() {
    jq -cjn \
        --arg recovery_journal authority-g11-g12-recovery-v1.json \
        --arg g11_manifest "$g11_manifest_sha" \
        --arg g11_shipper "$g11_shipper_sha" \
        --arg g11_provisioner "$g11_provisioner_sha" \
        --arg g12_manifest "$g12_manifest_sha" \
        --arg g12_bundle "$g12_bundle_sha" \
        --arg g12_workflow "$g12_workflow" \
        --arg g12_shipper "$g12_shipper_sha" \
        --arg g12_provisioner "$g12_provisioner_sha" \
        --arg product "$state_before" \
        '{schema:"syntaur.authority-g11-g12-normal-mutation-fence.v1",
          normal_mutations_blocked:true,recovery_journal:$recovery_journal,
          previous_generation:11,previous_manifest_sha256:$g11_manifest,
          previous_shipper_sha256:$g11_shipper,
          previous_provisioner_sha256:$g11_provisioner,target_generation:12,
          target_manifest_sha256:$g12_manifest,target_bundle_sha256:$g12_bundle,
          target_workflow_commit:$g12_workflow,target_shipper_sha256:$g12_shipper,
          target_provisioner_sha256:$g12_provisioner,
          product_state_sha256:$product}' \
        >"$authority_root/authority-promotion-v1.json"
    chown root:root "$authority_root/authority-promotion-v1.json"
    chmod 0600 "$authority_root/authority-promotion-v1.json"
}

seed_receipt() {
    jq -cjn \
        --arg previous_manifest "$g11_manifest_sha" \
        --arg target_manifest "$g12_manifest_sha" \
        --arg target_bundle "$g12_bundle_sha" \
        --arg target_workflow "$g12_workflow" \
        --arg target_shipper "$g12_shipper_sha" \
        --arg target_provisioner "$g12_provisioner_sha" \
        --arg product "$state_before" \
        '{schema:"syntaur.authority-g11-g12-recovery-receipt.v1",completed:true,
          previous_generation:11,previous_manifest_sha256:$previous_manifest,
          target_generation:12,target_manifest_sha256:$target_manifest,
          target_bundle_sha256:$target_bundle,
          target_workflow_commit:$target_workflow,
          target_shipper_sha256:$target_shipper,
          target_provisioner_sha256:$target_provisioner,
          product_state_sha256:$product}' \
        >/etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json
    chown root:root \
        /etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json
    chmod 0444 \
        /etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json
}

seed_resume_state() {
    local state=$1 phase=$1
    snapshot_inputs
    case $state in
        prepared) ;;
        generation_published)
            publish_generation_12_fixture
            ;;
        shipper_published)
            publish_generation_12_fixture
            publish_target_shipper_fixture
            ;;
        provisioner_published)
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            ;;
        trust_published)
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            ;;
        bundle_published)
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            publish_target_bundle_fixture
            ;;
        manifest_published)
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            publish_target_bundle_fixture
            publish_target_manifest_fixture
            ;;
        window-prepared-generation)
            phase=prepared
            publish_generation_12_fixture
            ;;
        window-generation-shipper)
            phase=generation_published
            publish_generation_12_fixture
            publish_target_shipper_fixture
            ;;
        window-shipper-provisioner)
            phase=shipper_published
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            ;;
        window-provisioner-trust)
            phase=provisioner_published
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            ;;
        window-trust-bundle)
            phase=trust_published
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            publish_target_bundle_fixture
            ;;
        window-bundle-manifest)
            phase=bundle_published
            publish_generation_12_fixture
            publish_target_shipper_fixture
            publish_target_provisioner_fixture
            publish_target_trust_fixture
            publish_target_bundle_fixture
            publish_target_manifest_fixture
            ;;
        *) die "unknown resume state: $state" ;;
    esac
    seed_fence
    seed_journal "$phase"
    assert_normal_mutation_blocked
}

case $scenario in
    normal)
        verify_exact
        install_exact
        assert_complete
        install_exact
        assert_complete
        ;;
    lock-root|lock-global|lock-deploy)
        case $scenario in
            lock-root) lock=$authority_root/.authority-promotion.lock ;;
            lock-global) lock=/etc/syntaur/syntaur-ship-mutation.lock ;;
            lock-deploy) lock=$operator_state/deploy.lock ;;
        esac
        exec 20<>"$lock"
        flock -n 20
        expect_failure "$scenario" install_exact
        assert_g11_unchanged
        ;;
    root-lock-bootstrap)
        rm -f "$authority_root/.authority-promotion.lock"
        install_exact
        assert_complete
        ;;
    acquisition-lock-replace)
        replacement=$operator_state/deploy.lock.replacement
        install -o "$operator_uid" -g "$operator_gid" -m 0600 /dev/null \
            "$replacement"
        SUDO_UID=$operator_uid SUDO_GID=$operator_gid \
            "$recovery" install \
            --g11-dir "$g11" --g12-dir "$g12" \
            --expected-current-shipper-sha256 "$g11_shipper_sha" \
            >/run/acquisition-lock-replace.out \
            2>/run/acquisition-lock-replace.err &
        recovery_pid=$!
        replaced=false
        for ((attempt = 0; attempt < 1000000; attempt++)); do
            if [[ -e /proc/$recovery_pid/fd/9 ]]; then
                mv -fT "$replacement" "$operator_state/deploy.lock"
                replaced=true
                break
            fi
            kill -0 "$recovery_pid" 2>/dev/null || break
        done
        [[ $replaced == true ]] \
            || die 'did not observe the recovery deployment-lock descriptor'
        if wait "$recovery_pid"; then
            die 'deployment-lock acquisition replacement unexpectedly succeeded'
        fi
        grep -Fq 'operator deployment lock descriptor differs' \
            /run/acquisition-lock-replace.err \
            || die 'deployment-lock descriptor/path split was not rejected'
        [[ ! -e $authority_root/authority-promotion-v1.json ]]
        [[ ! -e $authority_root/authority-g11-g12-recovery-v1.json ]]
        install_exact
        assert_complete
        ;;
    acquisition-lock-metadata)
        SUDO_UID=$operator_uid SUDO_GID=$operator_gid \
            "$recovery" install \
            --g11-dir "$g11" --g12-dir "$g12" \
            --expected-current-shipper-sha256 "$g11_shipper_sha" \
            >/run/acquisition-lock-metadata.out \
            2>/run/acquisition-lock-metadata.err &
        recovery_pid=$!
        mutated=false
        for ((attempt = 0; attempt < 1000000; attempt++)); do
            if [[ -e /proc/$recovery_pid/fd/9 ]]; then
                printf 'unsafe same-inode mutation\n' \
                    >"$operator_state/deploy.lock"
                chmod 0666 "$operator_state/deploy.lock"
                mutated=true
                break
            fi
            kill -0 "$recovery_pid" 2>/dev/null || break
        done
        [[ $mutated == true ]] \
            || die 'did not observe the recovery deployment-lock descriptor'
        if wait "$recovery_pid"; then
            die 'deployment-lock metadata mutation unexpectedly succeeded'
        fi
        grep -Eq 'operator deployment lock (expected identity is unsafe|expected size is unsafe|changed|descriptor differs)' \
            /run/acquisition-lock-metadata.err \
            || die 'same-inode deployment-lock metadata mutation was not rejected'
        [[ ! -e $authority_root/authority-promotion-v1.json ]]
        [[ ! -e $authority_root/authority-g11-g12-recovery-v1.json ]]
        : >"$operator_state/deploy.lock"
        chown "$operator_uid:$operator_gid" "$operator_state/deploy.lock"
        chmod 0600 "$operator_state/deploy.lock"
        install_exact
        assert_complete
        ;;
    tamper)
        tampered=/home/sean/tampered
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$tampered"
        cp -a "$g12/." "$tampered/"
        chown -R "$operator_uid:$operator_gid" "$tampered"
        chmod 0700 "$tampered"
        chmod 0600 "$tampered/syntaur-ship-linux-x86_64"
        printf 'tamper\n' >>"$tampered/syntaur-ship-linux-x86_64"
        chmod 0500 "$tampered/syntaur-ship-linux-x86_64" "$tampered"
        expect_failure tampered-digest setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g11-dir "$g11" --g12-dir "$tampered"

        hardlinked=/home/sean/hardlinked
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$hardlinked"
        cp -a "$g12/." "$hardlinked/"
        chown -R "$operator_uid:$operator_gid" "$hardlinked"
        chmod 0700 "$hardlinked"
        chmod 0700 "$hardlinked/syntaur-verify-linux-x86_64"
        ln "$hardlinked/syntaur-verify-linux-x86_64" /home/sean/verifier-second-link
        chmod 0500 "$hardlinked/syntaur-verify-linux-x86_64" "$hardlinked"
        expect_failure hardlinked-input setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g11-dir "$g11" --g12-dir "$hardlinked"

        symlinked=/home/sean/symlinked
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$symlinked"
        cp -a "$g12/." "$symlinked/"
        chown -R "$operator_uid:$operator_gid" "$symlinked"
        chmod 0700 "$symlinked"
        rm -f "$symlinked/release-authority-v2.json"
        ln -s "$g12/release-authority-v2.json" \
            "$symlinked/release-authority-v2.json"
        chmod 0500 "$symlinked"
        expect_failure symlinked-input setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g11-dir "$g11" --g12-dir "$symlinked"

        writable_parent=/home/sean/writable-parent
        install -d -o "$operator_uid" -g "$operator_gid" -m 0770 \
            "$writable_parent"
        cp -a "$g12" "$writable_parent/g12"
        chown -R "$operator_uid:$operator_gid" "$writable_parent/g12"
        expect_failure writable-ancestry setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g11-dir "$g11" --g12-dir "$writable_parent/g12"
        ;;
    resume-*)
        phase=${scenario#resume-}
        seed_resume_state "$phase"
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    fence-before-journal)
        snapshot_inputs
        seed_fence
        assert_normal_mutation_blocked
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    journal-without-fence)
        snapshot_inputs
        seed_journal prepared
        expect_failure journal-without-fence install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        [[ $(product_digest) == "$state_before" ]]
        [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
            "$g11_manifest_sha" ]]
        ;;
    normal-promotion-pending)
        printf '%s' '{"schema":"syntaur.authority-promotion.v1"}' \
            >"$authority_root/authority-promotion-v1.json"
        chown root:root "$authority_root/authority-promotion-v1.json"
        chmod 0600 "$authority_root/authority-promotion-v1.json"
        expect_failure normal-promotion-pending install_exact
        [[ $(product_digest) == "$state_before" ]]
        [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
            "$g11_manifest_sha" ]]
        ;;
    normal-promotion-temp-pending)
        printf '%s' '{"schema":"syntaur.authority-promotion.v1"}' \
            >"$authority_root/.authority-promotion-v1.json.tmp"
        chown root:root "$authority_root/.authority-promotion-v1.json.tmp"
        chmod 0600 "$authority_root/.authority-promotion-v1.json.tmp"
        expect_failure normal-promotion-temp-pending install_exact
        [[ $(product_digest) == "$state_before" ]]
        [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
            "$g11_manifest_sha" ]]
        ;;
    tampered-fence)
        snapshot_inputs
        seed_fence
        chmod 0600 "$authority_root/authority-promotion-v1.json"
        printf ' ' >>"$authority_root/authority-promotion-v1.json"
        expect_failure tampered-fence install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        [[ $(product_digest) == "$state_before" ]]
        [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
            "$g11_manifest_sha" ]]
        ;;
    crash-window-*)
        window=${scenario#crash-window-}
        seed_resume_state "window-$window"
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    pre-receipt-product-change)
        seed_resume_state bundle_published
        printf 'concurrent pre-receipt product update\n' \
            >"$operator_state/current-release.json"
        chown "$operator_uid:$operator_gid" \
            "$operator_state/current-release.json"
        chmod 0600 "$operator_state/current-release.json"
        changed_product_digest=$(product_digest)
        expect_failure pre-receipt-product-change install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        [[ $(product_digest) == "$changed_product_digest" ]]
        [[ $(jq -er '.phase' \
            "$authority_root/authority-g11-g12-recovery-v1.json") == \
            bundle_published ]]
        assert_normal_mutation_blocked
        ;;
    terminal-product-update)
        seed_resume_state manifest_published
        seed_receipt
        printf 'concurrent post-receipt product update\n' \
            >"$operator_state/current-release.json"
        chown "$operator_uid:$operator_gid" \
            "$operator_state/current-release.json"
        chmod 0600 "$operator_state/current-release.json"
        state_before=$(product_digest)
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    retirement-crash-no-sources)
        seed_resume_state manifest_published
        seed_receipt
        rm -f "$authority_root/authority-g11-g12-recovery-v1.json"
        mv "$authority_root/.authority-g11-g12-recovery-v1.inputs" \
            "$authority_root/.authority-g11-g12-recovery-v1.inputs.retiring"
        rm -f "$authority_root/.authority-g11-g12-recovery-v1.inputs.retiring/generation-12/syntaur-verify-linux-x86_64"
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    provisioner-state-mismatch)
        seed_resume_state shipper_published
        cp "$g11_provisioner" /run/unknown-provisioner
        printf '%s\n' '# unknown provisioner state' >>/run/unknown-provisioner
        install -o root -g root -m 0755 /run/unknown-provisioner \
            /opt/syntaur-build-authority-provision
        expect_failure provisioner-state-mismatch-install install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        [[ $(jq -er '.phase' \
            "$authority_root/authority-g11-g12-recovery-v1.json") == \
            shipper_published ]]
        assert_normal_mutation_blocked
        ;;
    predecessor-recovery-incomplete)
        printf '%s' '{"schema":"syntaur.authority-g10-g11-recovery.v1"}' \
            >"$authority_root/authority-g10-g11-recovery-v1.json"
        chown root:root "$authority_root/authority-g10-g11-recovery-v1.json"
        chmod 0600 "$authority_root/authority-g10-g11-recovery-v1.json"
        expect_failure predecessor-recovery-incomplete-install install_exact
        assert_g11_unchanged
        ;;
    phase-mismatch)
        seed_resume_state prepared
        install -o root -g root -m 0444 "$g12/release-authority-v2.json" \
            "$authority_root/release-authority-v2.json"
        expect_failure phase-mismatch-install install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        ;;
    status-lock-replace)
        : >/run/syntaur-replace-deploy-lock
        expect_failure replaced-deploy-lock install_exact
        [[ ! -e $authority_root/authority-g11-g12-recovery-v1.json ]]
        rm -f /run/syntaur-replace-deploy-lock
        install_exact
        assert_complete
        ;;
    status-lock-replace-final)
        seed_resume_state manifest_published
        : >/run/syntaur-replace-deploy-lock-g12
        expect_failure replaced-final-deploy-lock install_exact \
            /home/sean/removed-g11 /home/sean/removed-g12
        [[ $(jq -er '.phase' \
            "$authority_root/authority-g11-g12-recovery-v1.json") == \
            manifest_published ]]
        [[ -e $authority_root/authority-promotion-v1.json ]]
        [[ ! -e /etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json ]]
        assert_normal_mutation_blocked
        rm -f /run/syntaur-replace-deploy-lock-g12
        install_exact /home/sean/removed-g11 /home/sean/removed-g12
        assert_complete
        ;;
    stale-temporaries)
        : >"$authority_root/.authority-g11-g12-recovery-v1.json.tmp"
        chmod 0600 "$authority_root/.authority-g11-g12-recovery-v1.json.tmp"
        : >"$authority_root/.authority-g11-g12-recovery-v1.fence.tmp"
        chmod 0600 "$authority_root/.authority-g11-g12-recovery-v1.fence.tmp"
        : >/etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json.tmp
        chmod 0600 \
            /etc/syntaur/release-authority-g11-g12-recovery-v1.receipt.json.tmp
        for destination in \
            /usr/local/bin/syntaur-ship \
            /opt/syntaur-build-authority-provision \
            "$authority_root/trusted-workflow-commit" \
            "$authority_root/release-authority-v2.json.cosign.bundle" \
            "$authority_root/release-authority-v2.json"; do
            temporary=$(/usr/bin/dirname "$destination")/.$(/usr/bin/basename "$destination").g11-g12-recovery-v1
            : >"$temporary"
            chmod 0600 "$temporary"
        done
        stage=$artifact_root/.generation-12-g11-g12-recovery-v1.staged
        install -d -o root -g root -m 0700 "$stage"
        install -o root -g root -m 0444 "$g12/release-authority-v2.json" \
            "$stage/release-authority-v2.json"
        chmod 0555 "$stage"
        snapshot_stage=$authority_root/.authority-g11-g12-recovery-v1.inputs.staged
        install -d -o root -g root -m 0700 \
            "$snapshot_stage" "$snapshot_stage/generation-11"
        install -o root -g root -m 0600 "$g11/release-authority-v2.json" \
            "$snapshot_stage/generation-11/release-authority-v2.json"
        install_exact
        assert_complete
        ;;
    *) die "unknown fixture scenario: $scenario" ;;
esac

printf 'G11-G12 active-root recovery fixture passed: %s\n' "$scenario"
