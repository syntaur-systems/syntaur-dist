#!/usr/bin/bash
set -euo pipefail
umask 077

operator_uid=1000
operator_gid=1000
scenario=${G10_G11_FIXTURE_SCENARIO:-normal}
helper=/bootstrap/release-authority-manifest.sh
source_script=/bootstrap/recover-release-authority-g10-g11-canary-root-v1.sh.source
fake_cosign=/usr/local/bin/cosign
material_root=/home/sean/authority-material
authority_root=/etc/syntaur/release-authority
artifact_root=$authority_root/release-authority
operator_state=/home/sean/.syntaur/ship
runtime=/etc/syntaur/release-authority-g10-g11-recovery-v1.runtime
recovery=$runtime/recover-release-authority-g10-g11-canary-root-v1.sh
verify_root=/home/sean/recovery-verify
verify_script=$verify_root/recover-release-authority-g10-g11-canary-root-v1.sh

die() {
    printf 'G10-G11 recovery fixture error: %s\n' "$*" >&2
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

provisioner=$material_root/provisioner
verifier=$material_root/verifier
g10_shipper=$material_root/shipper-g10
g11_shipper=$material_root/shipper-g11
printf '#!/usr/bin/bash\nset -euo pipefail\nexit 0\n# shared provisioner\n' \
    >"$provisioner"
cat >/run/fixture-verifier.c <<'EOF'
int main(void) {
    return 0;
}
EOF
cat >/run/fixture-shipper.c <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STRINGIFY_INNER(value) #value
#define STRINGIFY(value) STRINGIFY_INNER(value)

static const char generation_marker[] = "generation-" STRINGIFY(GENERATION);

int main(int argc, char **argv) {
    const char *lock = "/home/sean/.syntaur/ship/deploy.lock";
    int descriptor;

    if (argc != 2 || strcmp(argv[1], "authority-status") != 0) {
        return 64;
    }
    if (geteuid() != 1000) {
        return 65;
    }
    if (access("/run/syntaur-replace-deploy-lock", F_OK) == 0) {
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
/usr/bin/cc -O2 -Wall -Wextra -Werror -DGENERATION=10 \
    /run/fixture-shipper.c -o "$g10_shipper"
/usr/bin/cc -O2 -Wall -Wextra -Werror -DGENERATION=11 \
    /run/fixture-shipper.c -o "$g11_shipper"
chmod 0500 "$provisioner" "$verifier" "$g10_shipper" "$g11_shipper"

provisioner_sha=$(sha256_file "$provisioner")
verifier_sha=$(sha256_file "$verifier")
g10_shipper_sha=$(sha256_file "$g10_shipper")
g11_shipper_sha=$(sha256_file "$g11_shipper")

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
for generation in $(seq 1 11); do
    material=$material_root/generation-$generation
    install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$material"
    if (( generation == 11 )); then
        install -o "$operator_uid" -g "$operator_gid" -m 0500 \
            "$g11_shipper" "$material/syntaur-ship-linux-x86_64"
        shipper_sha=$g11_shipper_sha
    else
        install -o "$operator_uid" -g "$operator_gid" -m 0500 \
            "$g10_shipper" "$material/syntaur-ship-linux-x86_64"
        shipper_sha=$g10_shipper_sha
    fi
    install -o "$operator_uid" -g "$operator_gid" -m 0500 \
        "$verifier" "$material/syntaur-verify-linux-x86_64"
    install -o "$operator_uid" -g "$operator_gid" -m 0500 \
        "$provisioner" "$material/syntaur-build-authority-provision"
    workflow=$(printf '%040x' "$generation")
    authority_commit=$(printf '%040x' "$((4096 + generation))")
    authority_tree=$(printf 'authority-tree-%s' "$generation" \
        | sha256sum | awk '{print $1}')
    env \
        SHIPPER_SHA256="$shipper_sha" \
        VERIFIER_SHA256="$verifier_sha" \
        PROVISIONER_SHA256="$provisioner_sha" \
        AUTHORITY_COMMIT="$authority_commit" \
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
    previous_manifest=$(sha256_file "$material/release-authority-v2.json")
done

g10=$material_root/generation-10
g11=$material_root/generation-11
g10_manifest_sha=$(sha256_file "$g10/release-authority-v2.json")
g10_bundle_sha=$(sha256_file "$g10/release-authority-v2.json.cosign.bundle")
g11_manifest_sha=$(sha256_file "$g11/release-authority-v2.json")
g11_bundle_sha=$(sha256_file "$g11/release-authority-v2.json.cosign.bundle")
g10_workflow=$(printf '%040x' 10)
g11_workflow=$(printf '%040x' 11)
cosign_sha=$(sha256_file "$fake_cosign")

patched=/run/recover-release-authority-g10-g11-canary-root-v1.sh
sed \
    -e "s/^readonly COSIGN_SHA256=.*/readonly COSIGN_SHA256=$cosign_sha/" \
    -e "s/^readonly G10_MANIFEST_SHA256=.*/readonly G10_MANIFEST_SHA256=$g10_manifest_sha/" \
    -e "s/^readonly G10_BUNDLE_SHA256=.*/readonly G10_BUNDLE_SHA256=$g10_bundle_sha/" \
    -e "s/^readonly G10_WORKFLOW_COMMIT=.*/readonly G10_WORKFLOW_COMMIT=$g10_workflow/" \
    -e "s/^readonly G10_SHIPPER_SHA256=.*/readonly G10_SHIPPER_SHA256=$g10_shipper_sha/" \
    -e "s/^readonly G10_VERIFIER_SHA256=.*/readonly G10_VERIFIER_SHA256=$verifier_sha/" \
    -e "s/^readonly G10_PROVISIONER_SHA256=.*/readonly G10_PROVISIONER_SHA256=$provisioner_sha/" \
    -e "s/^readonly G11_MANIFEST_SHA256=.*/readonly G11_MANIFEST_SHA256=$g11_manifest_sha/" \
    -e "s/^readonly G11_BUNDLE_SHA256=.*/readonly G11_BUNDLE_SHA256=$g11_bundle_sha/" \
    -e "s/^readonly G11_WORKFLOW_COMMIT=.*/readonly G11_WORKFLOW_COMMIT=$g11_workflow/" \
    -e "s/^readonly G11_SHIPPER_SHA256=.*/readonly G11_SHIPPER_SHA256=$g11_shipper_sha/" \
    -e "s/^readonly G11_VERIFIER_SHA256=.*/readonly G11_VERIFIER_SHA256=$verifier_sha/" \
    -e "s/^readonly G11_PROVISIONER_SHA256=.*/readonly G11_PROVISIONER_SHA256=$provisioner_sha/" \
    "$source_script" >"$patched"

install -d -o root -g root -m 0700 "$runtime"
install -o root -g root -m 0500 "$patched" "$recovery"
install -o root -g root -m 0500 "$helper" "$runtime/release-authority-manifest.sh"
install -d -o "$operator_uid" -g "$operator_gid" -m 0500 "$verify_root"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$patched" "$verify_script"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$helper" "$verify_root/release-authority-manifest.sh"

install -d -o root -g root -m 0755 /etc/syntaur "$authority_root" "$artifact_root"
for generation in $(seq 1 10); do
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
    "$g10/release-authority-v2.json" "$authority_root/release-authority-v2.json"
install -o root -g root -m 0444 \
    "$g10/release-authority-v2.json.cosign.bundle" \
    "$authority_root/release-authority-v2.json.cosign.bundle"
printf '%s\n' "$g10_workflow" >"$authority_root/trusted-workflow-commit"
chown root:root "$authority_root/trusted-workflow-commit"
chmod 0444 "$authority_root/trusted-workflow-commit"
install -o root -g root -m 1755 "$g10/syntaur-ship-linux-x86_64" \
    /usr/local/bin/syntaur-ship
install -o root -g root -m 0755 "$g10/syntaur-build-authority-provision" \
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
    } | sha256sum | awk '{print $1}'
}

state_before=$(product_digest)

verify_exact() {
    setpriv --reuid "$operator_uid" --regid "$operator_gid" --clear-groups \
        /usr/bin/bash "$verify_script" verify --g10-dir "$g10" --g11-dir "$g11"
}

install_exact() {
    local source_g10=${1:-$g10} source_g11=${2:-$g11}
    SUDO_UID=$operator_uid SUDO_GID=$operator_gid \
        "$recovery" install \
        --g10-dir "$source_g10" --g11-dir "$source_g11" \
        --expected-current-shipper-sha256 "$g10_shipper_sha"
}

assert_g10_unchanged() {
    [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
        "$g10_manifest_sha" ]]
    [[ $(sha256_file /usr/local/bin/syntaur-ship) == "$g10_shipper_sha" ]]
    [[ ! -e $authority_root/authority-g10-g11-recovery-v1.json ]]
}

assert_complete() {
    local actual expected
    [[ $(sha256_file "$authority_root/release-authority-v2.json") == \
        "$g11_manifest_sha" ]]
    [[ $(sha256_file "$authority_root/release-authority-v2.json.cosign.bundle") == \
        "$g11_bundle_sha" ]]
    [[ $(<"$authority_root/trusted-workflow-commit") == "$g11_workflow" ]]
    [[ $(sha256_file /usr/local/bin/syntaur-ship) == "$g11_shipper_sha" ]]
    [[ $(sha256_file /opt/syntaur-build-authority-provision) == \
        "$provisioner_sha" ]]
    expected=$(seq 1 11 | sed 's/^/generation-/' | LC_ALL=C sort)
    actual=$(find "$artifact_root" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual == "$expected" ]]
    [[ $(stat -c '%u:%g:%a:%h' \
        /etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json) \
        == 0:0:444:1 ]]
    for transient in \
        "$authority_root/authority-g10-g11-recovery-v1.json" \
        "$authority_root/.authority-g10-g11-recovery-v1.json.tmp" \
        "$authority_root/.authority-g10-g11-recovery-v1.inputs" \
        "$authority_root/.authority-g10-g11-recovery-v1.inputs.staged" \
        "$authority_root/.authority-g10-g11-recovery-v1.inputs.retiring" \
        "$artifact_root/.generation-11-g10-g11-recovery-v1.staged"; do
        [[ ! -e $transient && ! -L $transient ]]
    done
    [[ $(product_digest) == "$state_before" ]]
}

snapshot_inputs() {
    local snapshot=$authority_root/.authority-g10-g11-recovery-v1.inputs
    local generation source target
    install -d -o root -g root -m 0700 \
        "$snapshot" "$snapshot/generation-10" "$snapshot/generation-11"
    for generation in 10 11; do
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

publish_generation_11_fixture() {
    local installed=$artifact_root/generation-11
    [[ -e $installed ]] && return 0
    install -d -o root -g root -m 0555 "$installed"
    install -o root -g root -m 0444 \
        "$g11/release-authority-v2.json" \
        "$g11/release-authority-v2.json.cosign.bundle" "$installed/"
    printf '%s\n' "$g11_workflow" >"$installed/trusted-workflow-commit"
    chown root:root "$installed/trusted-workflow-commit"
    chmod 0444 "$installed/trusted-workflow-commit"
    install -o root -g root -m 0555 \
        "$g11/syntaur-build-authority-provision" \
        "$g11/syntaur-ship-linux-x86_64" \
        "$g11/syntaur-verify-linux-x86_64" "$installed/"
}

seed_journal() {
    local phase=$1
    jq -cjn \
        --arg phase "$phase" \
        --arg g10_manifest "$g10_manifest_sha" \
        --arg g10_shipper "$g10_shipper_sha" \
        --arg g11_manifest "$g11_manifest_sha" \
        --arg g11_bundle "$g11_bundle_sha" \
        --arg g11_workflow "$g11_workflow" \
        --arg g11_shipper "$g11_shipper_sha" \
        --arg provisioner "$provisioner_sha" \
        --arg product "$state_before" \
        '{schema:"syntaur.authority-g10-g11-recovery.v1",phase:$phase,
          previous_generation:10,previous_manifest_sha256:$g10_manifest,
          previous_shipper_sha256:$g10_shipper,target_generation:11,
          target_manifest_sha256:$g11_manifest,target_bundle_sha256:$g11_bundle,
          target_workflow_commit:$g11_workflow,target_shipper_sha256:$g11_shipper,
          target_provisioner_sha256:$provisioner,product_state_sha256:$product}' \
        >"$authority_root/authority-g10-g11-recovery-v1.json"
    chown root:root "$authority_root/authority-g10-g11-recovery-v1.json"
    chmod 0600 "$authority_root/authority-g10-g11-recovery-v1.json"
}

seed_receipt() {
    jq -cjn \
        --arg previous_manifest "$g10_manifest_sha" \
        --arg target_manifest "$g11_manifest_sha" \
        --arg target_bundle "$g11_bundle_sha" \
        --arg target_workflow "$g11_workflow" \
        --arg target_shipper "$g11_shipper_sha" \
        --arg target_provisioner "$provisioner_sha" \
        --arg product "$state_before" \
        '{schema:"syntaur.authority-g10-g11-recovery-receipt.v1",completed:true,
          previous_generation:10,previous_manifest_sha256:$previous_manifest,
          target_generation:11,target_manifest_sha256:$target_manifest,
          target_bundle_sha256:$target_bundle,
          target_workflow_commit:$target_workflow,
          target_shipper_sha256:$target_shipper,
          target_provisioner_sha256:$target_provisioner,
          product_state_sha256:$product}' \
        >/etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json
    chown root:root \
        /etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json
    chmod 0444 \
        /etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json
}

seed_resume_state() {
    local phase=$1
    snapshot_inputs
    case $phase in
        prepared) ;;
        generation_published) publish_generation_11_fixture ;;
        shipper_published|provisioner_published)
            publish_generation_11_fixture
            install -o root -g root -m 1755 \
                "$g11/syntaur-ship-linux-x86_64" /usr/local/bin/syntaur-ship
            ;;
        trust_published)
            publish_generation_11_fixture
            install -o root -g root -m 1755 \
                "$g11/syntaur-ship-linux-x86_64" /usr/local/bin/syntaur-ship
            printf '%s\n' "$g11_workflow" \
                >"$authority_root/trusted-workflow-commit"
            chown root:root "$authority_root/trusted-workflow-commit"
            chmod 0444 "$authority_root/trusted-workflow-commit"
            ;;
        bundle_published)
            publish_generation_11_fixture
            install -o root -g root -m 1755 \
                "$g11/syntaur-ship-linux-x86_64" /usr/local/bin/syntaur-ship
            printf '%s\n' "$g11_workflow" \
                >"$authority_root/trusted-workflow-commit"
            chown root:root "$authority_root/trusted-workflow-commit"
            chmod 0444 "$authority_root/trusted-workflow-commit"
            install -o root -g root -m 0444 \
                "$g11/release-authority-v2.json.cosign.bundle" \
                "$authority_root/release-authority-v2.json.cosign.bundle"
            ;;
        manifest_published)
            publish_generation_11_fixture
            install -o root -g root -m 1755 \
                "$g11/syntaur-ship-linux-x86_64" /usr/local/bin/syntaur-ship
            printf '%s\n' "$g11_workflow" \
                >"$authority_root/trusted-workflow-commit"
            chown root:root "$authority_root/trusted-workflow-commit"
            chmod 0444 "$authority_root/trusted-workflow-commit"
            install -o root -g root -m 0444 \
                "$g11/release-authority-v2.json.cosign.bundle" \
                "$authority_root/release-authority-v2.json.cosign.bundle"
            install -o root -g root -m 0444 \
                "$g11/release-authority-v2.json" \
                "$authority_root/release-authority-v2.json"
            ;;
        *) die "unknown resume phase: $phase" ;;
    esac
    seed_journal "$phase"
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
        assert_g10_unchanged
        ;;
    tamper)
        tampered=/home/sean/tampered
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$tampered"
        cp -a "$g11/." "$tampered/"
        chown -R "$operator_uid:$operator_gid" "$tampered"
        chmod 0700 "$tampered"
        chmod 0600 "$tampered/syntaur-ship-linux-x86_64"
        printf 'tamper\n' >>"$tampered/syntaur-ship-linux-x86_64"
        chmod 0500 "$tampered/syntaur-ship-linux-x86_64" "$tampered"
        expect_failure tampered-digest setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g10-dir "$g10" --g11-dir "$tampered"

        hardlinked=/home/sean/hardlinked
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$hardlinked"
        cp -a "$g11/." "$hardlinked/"
        chown -R "$operator_uid:$operator_gid" "$hardlinked"
        chmod 0700 "$hardlinked"
        chmod 0700 "$hardlinked/syntaur-verify-linux-x86_64"
        ln "$hardlinked/syntaur-verify-linux-x86_64" /home/sean/verifier-second-link
        chmod 0500 "$hardlinked/syntaur-verify-linux-x86_64" "$hardlinked"
        expect_failure hardlinked-input setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g10-dir "$g10" --g11-dir "$hardlinked"

        symlinked=/home/sean/symlinked
        install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$symlinked"
        cp -a "$g11/." "$symlinked/"
        chown -R "$operator_uid:$operator_gid" "$symlinked"
        chmod 0700 "$symlinked"
        rm -f "$symlinked/release-authority-v2.json"
        ln -s "$g11/release-authority-v2.json" \
            "$symlinked/release-authority-v2.json"
        chmod 0500 "$symlinked"
        expect_failure symlinked-input setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g10-dir "$g10" --g11-dir "$symlinked"

        writable_parent=/home/sean/writable-parent
        install -d -o "$operator_uid" -g "$operator_gid" -m 0770 \
            "$writable_parent"
        cp -a "$g11" "$writable_parent/g11"
        chown -R "$operator_uid:$operator_gid" "$writable_parent/g11"
        expect_failure writable-ancestry setpriv --reuid "$operator_uid" \
            --regid "$operator_gid" --clear-groups /usr/bin/bash "$verify_script" \
            verify --g10-dir "$g10" --g11-dir "$writable_parent/g11"
        ;;
    resume-*)
        phase=${scenario#resume-}
        seed_resume_state "$phase"
        install_exact /home/sean/removed-g10 /home/sean/removed-g11
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
            /home/sean/removed-g10 /home/sean/removed-g11
        [[ $(product_digest) == "$changed_product_digest" ]]
        [[ $(jq -er '.phase' \
            "$authority_root/authority-g10-g11-recovery-v1.json") == \
            bundle_published ]]
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
        install_exact /home/sean/removed-g10 /home/sean/removed-g11
        assert_complete
        ;;
    retirement-crash-no-sources)
        seed_resume_state manifest_published
        seed_receipt
        rm -f "$authority_root/authority-g10-g11-recovery-v1.json"
        mv "$authority_root/.authority-g10-g11-recovery-v1.inputs" \
            "$authority_root/.authority-g10-g11-recovery-v1.inputs.retiring"
        rm -f "$authority_root/.authority-g10-g11-recovery-v1.inputs.retiring/generation-11/syntaur-verify-linux-x86_64"
        install_exact /home/sean/removed-g10 /home/sean/removed-g11
        assert_complete
        ;;
    phase-mismatch)
        seed_resume_state prepared
        install -o root -g root -m 0444 "$g11/release-authority-v2.json" \
            "$authority_root/release-authority-v2.json"
        expect_failure phase-mismatch-install install_exact \
            /home/sean/removed-g10 /home/sean/removed-g11
        ;;
    status-lock-replace)
        : >/run/syntaur-replace-deploy-lock
        expect_failure replaced-deploy-lock install_exact
        [[ ! -e $authority_root/authority-g10-g11-recovery-v1.json ]]
        rm -f /run/syntaur-replace-deploy-lock
        install_exact
        assert_complete
        ;;
    stale-temporaries)
        : >"$authority_root/.authority-g10-g11-recovery-v1.json.tmp"
        chmod 0600 "$authority_root/.authority-g10-g11-recovery-v1.json.tmp"
        : >/etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json.tmp
        chmod 0600 \
            /etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json.tmp
        for destination in \
            /usr/local/bin/syntaur-ship \
            "$authority_root/trusted-workflow-commit" \
            "$authority_root/release-authority-v2.json.cosign.bundle" \
            "$authority_root/release-authority-v2.json"; do
            temporary=$(/usr/bin/dirname "$destination")/.$(/usr/bin/basename "$destination").g10-g11-recovery-v1
            : >"$temporary"
            chmod 0600 "$temporary"
        done
        stage=$artifact_root/.generation-11-g10-g11-recovery-v1.staged
        install -d -o root -g root -m 0700 "$stage"
        install -o root -g root -m 0444 "$g11/release-authority-v2.json" \
            "$stage/release-authority-v2.json"
        chmod 0555 "$stage"
        snapshot_stage=$authority_root/.authority-g10-g11-recovery-v1.inputs.staged
        install -d -o root -g root -m 0700 \
            "$snapshot_stage" "$snapshot_stage/generation-10"
        install -o root -g root -m 0600 "$g10/release-authority-v2.json" \
            "$snapshot_stage/generation-10/release-authority-v2.json"
        install_exact
        assert_complete
        ;;
    *) die "unknown fixture scenario: $scenario" ;;
esac

printf 'G10-G11 active-root recovery fixture passed: %s\n' "$scenario"
