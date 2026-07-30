#!/usr/bin/bash
set -euo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

readonly COSIGN=/usr/local/bin/cosign
readonly COSIGN_SHA256=c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74
readonly COSIGN_IDENTITY=https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main
readonly COSIGN_ISSUER=https://token.actions.githubusercontent.com
readonly AUTHORITY_ROOT=/etc/syntaur/release-authority
readonly INSTALLED_SHIPPER=/usr/local/bin/syntaur-ship
readonly INSTALLED_PROVISIONER=/opt/syntaur-build-authority-provision
readonly GENESIS_VALIDATOR=/opt/syntaur-genesis-validator
readonly GLOBAL_MUTATION_LOCK=/etc/syntaur/syntaur-ship-mutation.lock
readonly GENESIS_MAC_KNOWN_HOSTS=/etc/syntaur/mac-mini-known-hosts
readonly GENESIS_MAC_KNOWN_HOSTS_SHA256=2a703ea347e6abc8e423df92ba4e2592656cf64fee467083104565a69478b1c1
readonly GENESIS_MAC_KNOWN_HOSTS_RECORD='192.168.1.58 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJECwhXDA0s53ZtLPhSm17CNSK1isL6OF+w0KXhA95ig'
readonly GENESIS_MAC_IDENTITY_SOURCE=/home/sean/.ssh/id_ed25519
readonly GENESIS_MAC_IDENTITY=/etc/syntaur/mac-mini-identity-b9b69e39abe1089c1fb5a8a307425003a2fc01585f5b67f35a674e814b5e8d7a
readonly GENESIS_MAC_IDENTITY_SHA256=9b107d62548047fa028a1ab588f00b0894d41bb0399114a5499bc4bfd06df40f
readonly GENESIS_MAC_IDENTITY_SIZE=411
readonly GENESIS_MAC_IDENTITY_PUBLIC_SHA256=b9b69e39abe1089c1fb5a8a307425003a2fc01585f5b67f35a674e814b5e8d7a
readonly GENESIS_MAC_IDENTITY_FINGERPRINT='SHA256:HAUyJtTA+8CYqXxLp9oBlYpRdVpctcb76+n0xTo5EWU'
# Replaced with the reviewed G1 tree before this branch is published.
readonly GENESIS_AUTHORITY_TREE=db67df308a8a363d9b907a90d52001184eca05d4
# Replaced with the finalized G1 commit timestamp before publication.
readonly GENESIS_AUTHORITY_SOURCE_DATE_EPOCH=1785416703
readonly OPERATOR_STATE=/home/sean/.syntaur/ship
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly SOURCE_MANIFEST_HELPER="$script_dir/release-authority-manifest.sh"

die() {
    printf 'V2 authority genesis bootstrap error: %s\n' "$*" >&2
    exit 1
}

usage() {
    /usr/bin/cat >&2 <<'EOF'
Usage:
  bootstrap-release-authority-genesis-v2.sh verify|stage-build-authority|install \
    --source-dir DIR \
    --expected-manifest-sha256 HEX \
    --expected-workflow-commit COMMIT \
    --expected-authority-version X.Y.Z \
    --expected-authority-commit COMMIT \
    --expected-shipper-sha256 HEX \
    --expected-verifier-sha256 HEX \
    --expected-provisioner-sha256 HEX \
    --expected-helper-sha256 HEX \
    [--expected-current-provisioner-sha256 HEX] \
    [--expected-current-validator-sha256 HEX] \
    [--expected-rustsec-db-commit COMMIT \
    [--genesis-evidence FILE \
     --expected-genesis-evidence-sha256 HEX \
     --expected-genesis-engine-commit COMMIT]]

`verify` is non-mutating. `stage-build-authority` is the reviewed pre-G1 root
step: it creates the non-authorizing global lock, CAS-installs the exact signed
provisioner and Genesis validator, and pins the reviewed Mac build trust and
SSH-identity inputs while the canonical release root remains absent. `install`
publishes the G1 release root and exact shipper after successful Genesis
validation. Both mutating actions require sudo on claudevm and snapshot every
operator-owned input into root-owned storage before using it.
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
action=$1
shift
[[ $action == verify || $action == stage-build-authority || $action == install ]] || usage

source_dir=
expected_manifest_sha256=
expected_workflow_commit=
expected_authority_version=
expected_authority_commit=
expected_shipper_sha256=
expected_verifier_sha256=
expected_provisioner_sha256=
expected_helper_sha256=
expected_rustsec_db_commit=
expected_current_provisioner_sha256=
expected_current_validator_sha256=
genesis_evidence=
expected_genesis_evidence_sha256=
expected_genesis_engine_commit=
while (($# > 0)); do
    [[ $# -ge 2 ]] || usage
    case $1 in
        --source-dir) source_dir=$2 ;;
        --expected-manifest-sha256) expected_manifest_sha256=$2 ;;
        --expected-workflow-commit) expected_workflow_commit=$2 ;;
        --expected-authority-version) expected_authority_version=$2 ;;
        --expected-authority-commit) expected_authority_commit=$2 ;;
        --expected-shipper-sha256) expected_shipper_sha256=$2 ;;
        --expected-verifier-sha256) expected_verifier_sha256=$2 ;;
        --expected-provisioner-sha256) expected_provisioner_sha256=$2 ;;
        --expected-helper-sha256) expected_helper_sha256=$2 ;;
        --expected-rustsec-db-commit) expected_rustsec_db_commit=$2 ;;
        --expected-current-provisioner-sha256)
            expected_current_provisioner_sha256=$2
            ;;
        --expected-current-validator-sha256)
            expected_current_validator_sha256=$2
            ;;
        --genesis-evidence) genesis_evidence=$2 ;;
        --expected-genesis-evidence-sha256)
            expected_genesis_evidence_sha256=$2
            ;;
        --expected-genesis-engine-commit)
            expected_genesis_engine_commit=$2
            ;;
        *) usage ;;
    esac
    shift 2
done

if [[ $action == stage-build-authority ]]; then
    [[ $expected_current_provisioner_sha256 =~ ^[0-9a-f]{64}$ ]] \
        || die 'pre-G1 staging requires an exact current provisioner digest'
    [[ $expected_current_validator_sha256 =~ ^[0-9a-f]{64}$ ]] \
        || die 'pre-G1 staging requires an exact current Genesis validator digest'
elif [[ -n $expected_current_provisioner_sha256 \
        || -n $expected_current_validator_sha256 ]]; then
    die 'executable CAS inputs are valid only for pre-G1 staging'
fi

if [[ $action == install ]]; then
    [[ $expected_rustsec_db_commit =~ ^[0-9a-f]{40}$ ]] \
        || die 'G1 install requires an exact independently recorded RustSec database commit'
    [[ $genesis_evidence == /* ]] \
        || die 'G1 install requires an absolute Genesis evidence path'
    [[ $(readlink -f -- "$genesis_evidence") == "$genesis_evidence" ]] \
        || die 'Genesis evidence path must be canonical'
    [[ $expected_genesis_evidence_sha256 =~ ^[0-9a-f]{64}$ ]] \
        || die 'G1 install requires an exact independently recorded Genesis evidence digest'
    [[ $expected_genesis_engine_commit =~ ^[0-9a-f]{40}$ ]] \
        || die 'G1 install requires an exact independently recorded Genesis Engine commit'
elif [[ -n $expected_rustsec_db_commit || -n $genesis_evidence \
        || -n $expected_genesis_evidence_sha256 \
        || -n $expected_genesis_engine_commit ]]; then
    die 'RustSec and Genesis evidence inputs are valid only for G1 installation'
fi

for value in \
    "$source_dir" \
    "$expected_manifest_sha256" \
    "$expected_workflow_commit" \
    "$expected_authority_version" \
    "$expected_authority_commit" \
    "$expected_shipper_sha256" \
    "$expected_verifier_sha256" \
    "$expected_provisioner_sha256" \
    "$expected_helper_sha256"; do
    [[ -n $value ]] || usage
done

for digest in \
    "$expected_manifest_sha256" \
    "$expected_shipper_sha256" \
    "$expected_verifier_sha256" \
    "$expected_provisioner_sha256" \
    "$expected_helper_sha256"; do
    [[ $digest =~ ^[0-9a-f]{64}$ ]] || die 'an expected digest is invalid'
done
[[ $expected_workflow_commit =~ ^[0-9a-f]{40}$ ]] \
    || die 'expected workflow commit is invalid'
[[ $expected_authority_commit =~ ^[0-9a-f]{40}$ ]] \
    || die 'expected authority commit is invalid'
[[ $expected_authority_version =~ ^(0|[1-9][0-9]{0,9})\.(0|[1-9][0-9]{0,9})\.(0|[1-9][0-9]{0,9})$ ]] \
    || die 'expected authority version is invalid'
[[ $expected_authority_version == 0.7.114 ]] \
    || die 'generation-1 authority version must be exactly 0.7.114'
[[ $source_dir == /* ]] || die 'source directory must be absolute'
[[ $(readlink -f -- "$source_dir") == "$source_dir" ]] \
    || die 'source directory must be canonical'

operator_uid=$(id -u)
operator_gid=$(id -g)
if [[ $action == stage-build-authority || $action == install ]]; then
    [[ $(id -u) -eq 0 && $(id -g) -eq 0 ]] \
        || die 'installation requires sudo and an all-root effective identity'
    [[ ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && ${SUDO_GID:-} =~ ^[1-9][0-9]*$ ]] \
        || die 'installation requires concrete non-root SUDO_UID and SUDO_GID'
    operator_uid=$SUDO_UID
    operator_gid=$SUDO_GID
fi

expected_names=$(printf '%s\n' \
    release-authority-v2.json \
    release-authority-v2.json.cosign.bundle \
    syntaur-build-authority-provision \
    syntaur-ship-linux-x86_64 \
    syntaur-verify-linux-x86_64 | LC_ALL=C sort)

validate_operator_source() {
    [[ -d $source_dir && ! -L $source_dir ]] || die 'source directory is unsafe'
    [[ $(stat -c '%u:%g:%a' "$source_dir") == "$operator_uid:$operator_gid:500" ]] \
        || die 'source directory ownership or mode differs'
    local actual_names
    actual_names=$(find "$source_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual_names == "$expected_names" ]] \
        || die 'source directory file set is inexact'
    local name path
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        path="$source_dir/$name"
        [[ -f $path && ! -L $path ]] || die "unsafe source file: $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") == "$operator_uid:$operator_gid:400:1" ]] \
            || die "source data ownership, mode, or links differ: $name"
    done
    for name in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        path="$source_dir/$name"
        [[ -f $path && ! -L $path ]] || die "unsafe source file: $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") == "$operator_uid:$operator_gid:500:1" ]] \
            || die "source executable ownership, mode, or links differ: $name"
    done
    local current mode owner
    current=$source_dir
    while [[ $current != / ]]; do
        current=$(dirname "$current")
        mode=$(stat -c '%a' "$current")
        owner=$(stat -c '%u' "$current")
        [[ ! -L $current && -d $current ]] || die "unsafe source parent: $current"
        (( (8#$mode & 8#022) == 0 )) || die "writable source parent: $current"
        [[ $owner == 0 || $owner == "$operator_uid" ]] \
            || die "untrusted source parent owner: $current"
    done
}

validate_cosign() {
    [[ -x $COSIGN && ! -L $COSIGN ]] || die 'pinned Cosign is missing'
    [[ $(stat -c '%u:%g:%a:%h' "$COSIGN") == 0:0:755:1 ]] \
        || die 'pinned Cosign ownership, mode, or link count is unsafe'
    [[ $(sha256sum "$COSIGN" | awk '{print $1}') == "$COSIGN_SHA256" ]] \
        || die 'pinned Cosign digest differs'
}

validate_material() {
    local material=$1
    local helper=$2
    local owner_uid=$3
    local owner_gid=$4
    local data_mode=$5
    local executable_mode=$6
    local actual_names name path
    actual_names=$(find "$material" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual_names == "$expected_names" ]] \
        || die 'validated material file set is inexact'
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        path="$material/$name"
        [[ -f $path && ! -L $path ]] || die "unsafe validated data: $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") \
            == "$owner_uid:$owner_gid:$data_mode:1" ]] \
            || die "validated data ownership, mode, or links differ: $name"
    done
    for name in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        path="$material/$name"
        [[ -f $path && ! -L $path ]] || die "unsafe validated executable: $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") \
            == "$owner_uid:$owner_gid:$executable_mode:1" ]] \
            || die "validated executable ownership, mode, or links differ: $name"
    done
    [[ -f $helper && ! -L $helper ]] || die 'manifest helper is unsafe'
    [[ $(sha256sum "$helper" | awk '{print $1}') == "$expected_helper_sha256" ]] \
        || die 'manifest helper digest differs from the independent record'

    local manifest bundle
    manifest="$material/release-authority-v2.json"
    bundle="$material/release-authority-v2.json.cosign.bundle"
    [[ $(sha256sum "$manifest" | awk '{print $1}') == "$expected_manifest_sha256" ]] \
        || die 'manifest digest differs from the independent record'
    [[ $(jq -er '.schema' "$manifest") == 2 ]] \
        || die 'bootstrap manifest is not V2'
    [[ $(jq -er '.generation' "$manifest") == 1 ]] \
        || die 'bootstrap manifest is not generation 1'
    [[ $(jq -er '.previous_generation' "$manifest") == 0 ]] \
        || die 'bootstrap manifest is not genesis'
    [[ $(jq -er '.previous_manifest_sha256' "$manifest") \
        == "$(printf '0%.0s' {1..64})" ]] \
        || die 'bootstrap predecessor digest is not the genesis sentinel'
    [[ $(jq -er '.workflow_commit' "$manifest") == "$expected_workflow_commit" ]] \
        || die 'manifest workflow commit differs'
    [[ $(jq -er '.authority_version' "$manifest") == "$expected_authority_version" ]] \
        || die 'manifest authority version differs'
    [[ $(jq -er '.authority_commit' "$manifest") == "$expected_authority_commit" ]] \
        || die 'manifest authority commit differs'
    [[ $(jq -er '.shipper_sha256' "$manifest") == "$expected_shipper_sha256" ]] \
        || die 'manifest shipper digest differs'
    [[ $(jq -er '.verifier_sha256' "$manifest") == "$expected_verifier_sha256" ]] \
        || die 'manifest verifier digest differs'
    [[ $(jq -er '.provisioner_sha256' "$manifest") == "$expected_provisioner_sha256" ]] \
        || die 'manifest provisioner digest differs'
    "$helper" validate "$manifest" 2 1 "$expected_workflow_commit" "$material"
    "$helper" assert-genesis "$manifest"
    "$COSIGN" verify-blob \
        --bundle "$bundle" \
        --certificate-identity "$COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$COSIGN_ISSUER" \
        --certificate-github-workflow-sha "$expected_workflow_commit" \
        "$manifest"
}

validate_operator_source
validate_cosign

if [[ $action == verify ]]; then
    validate_material \
        "$source_dir" \
        "$SOURCE_MANIFEST_HELPER" \
        "$operator_uid" \
        "$operator_gid" \
        400 \
        500
    printf 'V2 authority genesis source verified: generation=1 manifest_sha256=%s\n' \
        "$expected_manifest_sha256"
    exit 0
fi

[[ $(tr -d '\r\n' </etc/hostname) == claudevm ]] \
    || die 'V2 authority genesis bootstrap may run only on claudevm'
if [[ $action == install ]]; then
    [[ -f $genesis_evidence && ! -L $genesis_evidence ]] \
        || die 'Genesis evidence is not a regular file'
    [[ $(stat -c '%u:%g:%a:%h' "$genesis_evidence") == \
        "$operator_uid:$operator_gid:400:1" ]] \
        || die 'Genesis evidence ownership, mode, or link count differs'
    evidence_parent=$(dirname "$genesis_evidence")
    while [[ $evidence_parent != / ]]; do
        [[ -d $evidence_parent && ! -L $evidence_parent ]] \
            || die "unsafe Genesis evidence parent: $evidence_parent"
        evidence_parent_mode=$(stat -c '%a' "$evidence_parent")
        evidence_parent_owner=$(stat -c '%u' "$evidence_parent")
        (( (8#$evidence_parent_mode & 8#022) == 0 )) \
            || die "writable Genesis evidence parent: $evidence_parent"
        [[ $evidence_parent_owner == 0 || \
            $evidence_parent_owner == "$operator_uid" ]] \
            || die "untrusted Genesis evidence parent owner: $evidence_parent"
        evidence_parent=$(dirname "$evidence_parent")
    done
fi
[[ -d /home/sean && ! -L /home/sean ]] \
    || die 'canonical release-operator home is unsafe'
[[ $(stat -c '%u:%g' /home/sean) == "$operator_uid:$operator_gid" ]] \
    || die 'canonical release-operator home identity differs'
if [[ $action == stage-build-authority ]]; then
    [[ ! -L /etc/syntaur ]] || die '/etc/syntaur is a symlink'
    /usr/bin/install -d -o root -g root -m 0755 /etc/syntaur
else
    [[ -d /etc/syntaur && ! -L /etc/syntaur ]] \
        || die '/etc/syntaur must be created by the exact pre-G1 staging step'
fi
[[ -d /etc/syntaur && ! -L /etc/syntaur ]] \
    || die '/etc/syntaur is not an exact directory'
[[ $(stat -c '%u:%g:%a' /etc/syntaur) == 0:0:755 ]] \
    || die '/etc/syntaur is not exact root-owned mode 0755'

bootstrap_lock=/run/lock/syntaur-release-authority-bootstrap.lock
local_lock="$OPERATOR_STATE/deploy.lock"

create_exact_empty_lock() {
    local path=$1
    local owner=$2
    local group=$3
    local mode=$4
    local parent temporary path_identity candidate candidate_identity
    parent=$(dirname "$path")
    [[ -d $parent && ! -L $parent ]] \
        || die "lock parent is unsafe: $parent"
    if [[ ! -e $path && ! -L $path ]]; then
        temporary=$(/usr/bin/mktemp "$parent/.syntaur-lock.XXXXXXXX") \
            || die "cannot stage lock: $path"
        if ! /usr/bin/install -o "$owner" -g "$group" -m "$mode" \
            /dev/null "$temporary"; then
            /usr/bin/rm -f -- "$temporary"
            die "cannot prepare lock: $path"
        fi
        /usr/bin/sync -f "$temporary"
        /usr/bin/ln -- "$temporary" "$path" 2>/dev/null || true
        /usr/bin/rm -f -- "$temporary"
        /usr/bin/sync -f "$parent"
    fi
    if [[ -f $path && ! -L $path ]] \
        && [[ $(stat -c '%h' "$path") -gt 1 ]]; then
        path_identity=$(stat -c '%d:%i' "$path")
        while IFS= read -r -d '' candidate; do
            candidate_identity=$(stat -c '%d:%i' "$candidate")
            if [[ $candidate_identity == "$path_identity" ]]; then
                [[ $(stat -c '%u:%g:%a:%s' "$candidate") == \
                    "$owner:$group:$mode:0" ]] \
                    || die "crash-residue lock link is unsafe: $candidate"
                /usr/bin/rm -f -- "$candidate"
            fi
        done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 \
            -type f -name '.syntaur-lock.*' -print0)
        /usr/bin/sync -f "$parent"
    fi
    [[ -f $path && ! -L $path ]] \
        || die "lock path is unsafe: $path"
    [[ $(stat -c '%u:%g:%a:%h:%s' "$path") == \
        "$owner:$group:$mode:1:0" ]] \
        || die "empty lock identity differs: $path"
}

validate_global_lock() {
    [[ -f $GLOBAL_MUTATION_LOCK && ! -L $GLOBAL_MUTATION_LOCK ]] \
        || die 'pre-G1 global mutation lock is missing or unsafe'
    [[ $(stat -c '%u:%g:%a:%h:%s' "$GLOBAL_MUTATION_LOCK") == \
        "0:$operator_gid:440:1:0" ]] \
        || die 'pre-G1 global mutation lock identity differs'
}

prepare_operator_state() {
    [[ -d /home/sean/.syntaur && ! -L /home/sean/.syntaur ]] \
        || die 'canonical operator .syntaur directory is unsafe'
    [[ $(stat -c '%u:%g' /home/sean/.syntaur) == \
        "$operator_uid:$operator_gid" ]] \
        || die 'canonical operator .syntaur identity differs'
    if [[ ! -e $OPERATOR_STATE && ! -L $OPERATOR_STATE ]]; then
        /usr/bin/install -d -o "$operator_uid" -g "$operator_gid" -m 0700 \
            "$OPERATOR_STATE"
    fi
    [[ -d $OPERATOR_STATE && ! -L $OPERATOR_STATE ]] \
        || die 'canonical operator ship state is unsafe'
    [[ $(stat -c '%u:%g:%a' "$OPERATOR_STATE") == \
        "$operator_uid:$operator_gid:700" ]] \
        || die 'canonical operator ship state identity differs'
    if [[ ! -e $local_lock && ! -L $local_lock ]]; then
        create_exact_empty_lock "$local_lock" "$operator_uid" "$operator_gid" 600
    fi
    [[ -f $local_lock && ! -L $local_lock ]] \
        || die 'canonical deployment lock is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$local_lock") == \
        "$operator_uid:$operator_gid:600:1" ]] \
        || die 'canonical deployment lock identity differs'
    [[ $(stat -c '%s' "$local_lock") -le 32 ]] \
        || die 'canonical deployment lock metadata is oversized'
}

if [[ $action == stage-build-authority ]]; then
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'pre-G1 staging requires the canonical release root to remain absent'
    create_exact_empty_lock "$bootstrap_lock" 0 0 600
    exec 9<>"$bootstrap_lock"
    /usr/bin/flock -n 9 || die 'another bootstrap process holds the creation lock'
    create_exact_empty_lock "$GLOBAL_MUTATION_LOCK" 0 "$operator_gid" 440
    /usr/bin/flock -u 9
    exec 9>&-
fi

validate_global_lock
prepare_operator_state
create_exact_empty_lock "$bootstrap_lock" 0 0 600
exec 7<"$GLOBAL_MUTATION_LOCK"
/usr/bin/flock -n 7 || die 'another syntaur-ship process holds the global mutation lock'
exec 8<>"$local_lock"
/usr/bin/flock -n 8 || die 'another syntaur-ship process holds the canonical deployment lock'
exec 9<>"$bootstrap_lock"
/usr/bin/flock -n 9 || die 'another bootstrap process holds the publication lock'
validate_global_lock

snapshot=/run/syntaur-release-authority-genesis-v2.snapshot
if [[ -e $snapshot || -L $snapshot ]]; then
    [[ -d $snapshot && ! -L $snapshot ]] \
        || die 'stale root snapshot is unsafe'
    [[ $(stat -c '%u:%g:%a' "$snapshot") == 0:0:700 ]] \
        || die 'stale root snapshot identity differs'
    [[ $(/usr/bin/find "$snapshot" -xdev -print | wc -l) -le 16 ]] \
        || die 'stale root snapshot exceeds its recovery bound'
    /usr/bin/chmod -R u+rwX "$snapshot"
    /usr/bin/rm -rf --one-file-system -- "$snapshot"
    [[ ! -e $snapshot && ! -L $snapshot ]] \
        || die 'stale root snapshot recovery did not settle'
    /usr/bin/sync -f /run
fi
/usr/bin/install -d -o root -g root -m 0700 "$snapshot"
snapshot_material="$snapshot/material"
/usr/bin/install -d -o root -g root -m 0700 "$snapshot_material"
snapshot_helper="$snapshot/release-authority-manifest.sh"
snapshot_evidence="$snapshot/genesis-validation.json"
snapshot_identity="$snapshot/mac-mini-identity"
stage=/etc/syntaur/.release-authority.bootstrap-v2-g1
installed_generation_dir="$AUTHORITY_ROOT/release-authority/generation-1"
installed_genesis_dir="$AUTHORITY_ROOT/genesis"
shipper_stage=/usr/local/bin/.syntaur-ship.authority-bootstrap-v2-g1
provisioner_stage=/opt/.syntaur-build-authority-provision.bootstrap-v2-g1
validator_stage=/opt/.syntaur-genesis-validator.bootstrap-v2-g1
known_hosts_stage=/etc/syntaur/.mac-mini-known-hosts.bootstrap-v2-g1
identity_stage=/etc/syntaur/.mac-mini-identity.bootstrap-v2-g1

cleanup_staging() {
    local path
    for path in \
        "$snapshot" "$shipper_stage" "$provisioner_stage" "$validator_stage" \
        "$known_hosts_stage" "$identity_stage"; do
        if [[ -e $path && ! -L $path ]]; then
            /usr/bin/chmod -R u+rwX "$path" 2>/dev/null || true
            /usr/bin/rm -rf -- "$path"
        fi
    done
}
trap cleanup_staging EXIT

snapshot_file() {
    local source=$1
    local target=$2
    local mode=$3
    local maximum=$4
    /usr/bin/timeout 30 /usr/bin/dd \
        if="$source" \
        of="$target" \
        iflag=nofollow,nonblock,fullblock,count_bytes \
        count="$((maximum + 1))" \
        status=none
    [[ -f $target && ! -L $target ]] || die "snapshot is not regular: $source"
    [[ $(stat -c '%s' "$target") -le $maximum ]] \
        || die "snapshot exceeds its size bound: $source"
    /usr/bin/chown root:root "$target"
    /usr/bin/chmod "$mode" "$target"
    [[ $(stat -c '%u:%g:%a:%h' "$target") == "0:0:$mode:1" ]] \
        || die "snapshot metadata differs: $source"
    /usr/bin/sync -f "$target"
}

validate_genesis_mac_identity_material() {
    local path=$1
    local owner=$2
    local group=$3
    local mode=$4
    local public_sha256 fingerprint identity_report
    [[ -f $path && ! -L $path ]] \
        || die 'Genesis Mac SSH identity is missing or unsafe'
    [[ $(stat -c '%u:%g:%a:%h:%s' "$path") == \
        "$owner:$group:$mode:1:$GENESIS_MAC_IDENTITY_SIZE" ]] \
        || die 'Genesis Mac SSH identity metadata differs'
    [[ $(sha256sum "$path" | awk '{print $1}') == \
        "$GENESIS_MAC_IDENTITY_SHA256" ]] \
        || die 'Genesis Mac SSH private identity digest differs'
    identity_report=$(
        set -euo pipefail
        inspection=$(/usr/bin/mktemp \
            /run/.syntaur-mac-identity-inspection.XXXXXXXX)
        trap '/usr/bin/rm -f -- "$inspection"' EXIT
        /usr/bin/timeout 30 /usr/bin/dd \
            if="$path" \
            of="$inspection" \
            iflag=nofollow,nonblock,fullblock,count_bytes \
            count="$((GENESIS_MAC_IDENTITY_SIZE + 1))" \
            status=none
        /usr/bin/chown root:root "$inspection"
        /usr/bin/chmod 0400 "$inspection"
        [[ $(sha256sum "$inspection" | awk '{print $1}') == \
            "$GENESIS_MAC_IDENTITY_SHA256" ]]
        /usr/bin/ssh-keygen -y -f "$inspection" \
            | awk 'NF >= 2 {print $1, $2}' \
            | sha256sum \
            | awk '{print $1}'
        /usr/bin/ssh-keygen -lf "$inspection" | awk 'NR == 1 {print $2}'
    )
    public_sha256=$(sed -n '1p' <<<"$identity_report")
    [[ $public_sha256 == "$GENESIS_MAC_IDENTITY_PUBLIC_SHA256" ]] \
        || die 'Genesis Mac SSH public identity digest differs'
    fingerprint=$(sed -n '2p' <<<"$identity_report")
    [[ $fingerprint == "$GENESIS_MAC_IDENTITY_FINGERPRINT" ]] \
        || die 'Genesis Mac SSH identity fingerprint differs'
}

validate_genesis_mac_identity_source() {
    [[ -d /home/sean/.ssh && ! -L /home/sean/.ssh ]] \
        || die 'canonical operator SSH directory is unsafe'
    [[ $(stat -c '%u:%g:%a' /home/sean/.ssh) == \
        "$operator_uid:$operator_gid:700" ]] \
        || die 'canonical operator SSH directory identity differs'
    validate_genesis_mac_identity_material \
        "$GENESIS_MAC_IDENTITY_SOURCE" \
        "$operator_uid" \
        "$operator_gid" \
        600
}

snapshot_file "$source_dir/release-authority-v2.json" \
    "$snapshot_material/release-authority-v2.json" 400 1048576
snapshot_file "$source_dir/release-authority-v2.json.cosign.bundle" \
    "$snapshot_material/release-authority-v2.json.cosign.bundle" 400 4194304
snapshot_file "$source_dir/syntaur-build-authority-provision" \
    "$snapshot_material/syntaur-build-authority-provision" 500 16777216
snapshot_file "$source_dir/syntaur-ship-linux-x86_64" \
    "$snapshot_material/syntaur-ship-linux-x86_64" 500 268435456
snapshot_file "$source_dir/syntaur-verify-linux-x86_64" \
    "$snapshot_material/syntaur-verify-linux-x86_64" 500 268435456
snapshot_file "$SOURCE_MANIFEST_HELPER" \
    "$snapshot_helper" 500 1048576
if [[ $action == install ]]; then
    snapshot_file "$genesis_evidence" \
        "$snapshot_evidence" 400 4194304
elif [[ $action == stage-build-authority ]]; then
    validate_genesis_mac_identity_source
    snapshot_file "$GENESIS_MAC_IDENTITY_SOURCE" \
        "$snapshot_identity" 400 16384
    validate_genesis_mac_identity_material \
        "$snapshot_identity" 0 0 400
fi
/usr/bin/sync -f "$snapshot"

validate_material \
    "$snapshot_material" \
    "$snapshot_helper" \
    0 \
    0 \
    400 \
    500

validate_genesis_evidence() {
    local evidence=$1
    local expected_mode=${2:-400}
    local canonical shipper_size inventory_id inventory_manifest_sha256
    [[ -f $evidence && ! -L $evidence ]] \
        || die 'root-owned Genesis evidence snapshot is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$evidence") == "0:0:$expected_mode:1" ]] \
        || die 'root-owned Genesis evidence snapshot identity differs'
    [[ $(sha256sum "$evidence" | awk '{print $1}') == \
        "$expected_genesis_evidence_sha256" ]] \
        || die 'Genesis evidence digest differs from the independent record'
    [[ $(wc -l <"$evidence") -eq 1 ]] \
        || die 'Genesis evidence must be exactly one JSON record'
    canonical=$(jq -ce '.' "$evidence") \
        || die 'Genesis evidence is not valid JSON'
    [[ $(<"$evidence") == "$canonical" ]] \
        || die 'Genesis evidence is not the exact compact canonical producer record'
    shipper_size=$(stat -c '%s' "$snapshot_material/syntaur-ship-linux-x86_64")
    inventory_id=$(
        {
            printf 'syntaur.genesis-baseline-inventory.v1\0'
            jq -cj '
              .baseline_inventory |
              {
                schema,
                contract_sha256,
                members:[.members[] | {id,path,sha256,size,kind,mode}]
              }
            ' "$evidence"
        } | sha256sum | awk '{print $1}'
    )
    inventory_manifest_sha256=$(
        {
            printf 'syntaur.genesis-baseline-inventory-manifest.v1\0'
            jq -cj '
              .baseline_inventory |
              {
                schema,
                contract_sha256,
                inventory_id,
                members:[.members[] | {id,path,sha256,size,kind,mode}]
              }
            ' "$evidence"
        } | sha256sum | awk '{print $1}'
    )
    jq -se \
        --arg version "$expected_authority_version" \
        --arg source "$expected_authority_commit" \
        --arg source_tree "$GENESIS_AUTHORITY_TREE" \
        --arg engine "$expected_genesis_engine_commit" \
        --arg shipper "$expected_shipper_sha256" \
        --arg provisioner "$expected_provisioner_sha256" \
        --arg rustsec "$expected_rustsec_db_commit" \
        --arg inventory_id "$inventory_id" \
        --arg inventory_manifest_sha256 "$inventory_manifest_sha256" \
        --argjson source_epoch "$GENESIS_AUTHORITY_SOURCE_DATE_EPOCH" \
        --arg ssh_identity_path "$GENESIS_MAC_IDENTITY" \
        --arg ssh_identity_sha256 "$GENESIS_MAC_IDENTITY_SHA256" \
        --arg ssh_identity_public_sha256 \
            "$GENESIS_MAC_IDENTITY_PUBLIC_SHA256" \
        --arg ssh_identity_fingerprint \
            "$GENESIS_MAC_IDENTITY_FINGERPRINT" \
        --argjson shipper_size "$shipper_size" \
        --slurpfile manifest "$snapshot_material/release-authority-v2.json" \
        '
        def valid_utc_timestamp:
          type == "string" and
          test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,9})?Z$") and
          (try
            (sub("[.][0-9]{1,9}Z$"; "Z") |
              fromdateiso8601 | type == "number")
            catch false);
        length == 1 and
        (.[0] |
        keys_unsorted == [
          "schema","authorizing","completed_at","host","authority_version",
          "authority_source","engine","authority_source_date_epoch","baseline",
          "shipper","build_authority","reproducibility_builds",
          "baseline_inventory","baseline_inventory_manifest_sha256",
          "validation_artifacts","future_product_protocol",
          "mac_target","mac_gateway_url","mac_smoke",
          "persistent_authority","release_authority_root_absent"
        ] and
        .schema == "syntaur.genesis-validation.v2" and
        .authorizing == false and
        (.completed_at | valid_utc_timestamp) and
        .host == "claudevm" and
        .authority_version == $version and
        (.authority_source | keys_unsorted == [
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ]) and
        .authority_source.commit == $source and
        .authority_source.tree == $source_tree and
        (.authority_source.workspace |
          type == "string" and startswith("/")) and
        (.authority_source.export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.authority_source.sealed_export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.engine | keys_unsorted == [
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ]) and
        .engine.commit == $engine and
        .engine.tree == "2983054537a8fe4be36a3a8f7c73973722ed1dd1" and
        (.engine.workspace | type == "string" and startswith("/")) and
        .engine.workspace != .authority_source.workspace and
        (.engine.export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        (.engine.sealed_export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        $engine == "36f3348fc32c02d0a0091be9ea87b828306941cc" and
        (.baseline | keys_unsorted == [
          "schema","product_parent_commit","product_parent_tree",
          "product_version","product_source_date_epoch","product_built_at",
          "build_tool_count","date_shim_sha256","git_shim_sha256",
          "engine_commit","engine_tree","member_count","contract_sha256",
          "authorizing"
        ]) and
        .baseline.schema == 1 and
        .baseline.product_parent_commit ==
          "b003360f63707d92fd0df1fd12384282f1c3004f" and
        .baseline.product_parent_tree ==
          "1bf740acd5a7223e98370f668148f01ebfb6eff8" and
        .baseline.product_version == "0.7.114" and
        .baseline.product_source_date_epoch == 1784316447 and
        .baseline.product_built_at == "2026-07-17T19:27:27Z" and
        .baseline.build_tool_count == 2 and
        .baseline.date_shim_sha256 ==
          "8006ad3b0a1eaf63a5d8e80c04e9c7c259a435fdf44c2cd698ac6efbc335abe9" and
        .baseline.git_shim_sha256 ==
          "872bbdd70036c8b3992fa1f404a29ef74483004ca4baec90be8b03f4ea12b5b0" and
        .baseline.engine_commit == $engine and
        .baseline.engine_tree ==
          "2983054537a8fe4be36a3a8f7c73973722ed1dd1" and
        .baseline.member_count == 5 and
        .baseline.contract_sha256 ==
          "d93f9e3022dc3494434373473f461e2b2b6fba2b238f9335a407a83cd5d5f40c" and
        .baseline.authorizing == false and
        (.shipper | keys_unsorted == [
          "schema","executable_sha256","executable_size","build_source_commit",
          "control_plane_sha256","build_toolchain_sha256",
          "build_rustflags_sha256","build_target","build_profile","clean_build"
        ]) and
        .shipper.schema == 1 and
        .shipper.executable_sha256 == $shipper and
        .shipper.executable_size == $shipper_size and
        .shipper.build_source_commit == $source and
        (.shipper.control_plane_sha256 | test("^[0-9a-f]{64}$")) and
        (.shipper.build_toolchain_sha256 | test("^[0-9a-f]{64}$")) and
        (.shipper.build_rustflags_sha256 | test("^[0-9a-f]{64}$")) and
        .shipper.build_target == "x86_64-unknown-linux-gnu" and
        .shipper.build_profile == "release" and
        .shipper.clean_build == true and
        (.build_authority | keys_unsorted == [
          "schema","platform_image_sha256","platform_manifest_sha256",
          "dependencies_image_sha256","dependencies_manifest_sha256",
          "source_image_sha256","source_manifest_sha256","source_commit",
          "source_version","source_date_epoch","source_tree_sha256",
          "source_cargo_lock_sha256","engine_commit","engine_tree_sha256",
          "engine_cargo_lock_sha256","rust_toolchain_tree_sha256",
          "cargo_vendor_tree_sha256","system_usr_tree_sha256","tar_sha256",
          "system_etc_tree_sha256","cargo_config_sha256","ort_cache_tree_sha256",
          "frame_sysroot_tree_sha256","rustsec_tree_sha256",
          "rustsec_provenance_schema","rustsec_db_remote","rustsec_db_ref",
          "rustsec_db_commit","cargo_audit_sha256","rustc_vv_sha256","host_target"
        ]) and
        .build_authority.schema == 4 and
        .build_authority.source_commit == $source and
        .build_authority.source_version == $version and
        .authority_source_date_epoch == $source_epoch and
        $source_epoch > 0 and
        .build_authority.source_date_epoch == .authority_source_date_epoch and
        .build_authority.engine_commit == $engine and
        .build_authority.source_tree_sha256 ==
          .authority_source.export_tree_sha256 and
        .build_authority.engine_tree_sha256 == .engine.export_tree_sha256 and
        ([
          .build_authority.platform_image_sha256,
          .build_authority.platform_manifest_sha256,
          .build_authority.dependencies_image_sha256,
          .build_authority.dependencies_manifest_sha256,
          .build_authority.source_image_sha256,
          .build_authority.source_manifest_sha256,
          .build_authority.source_cargo_lock_sha256,
          .build_authority.engine_cargo_lock_sha256,
          .build_authority.rust_toolchain_tree_sha256,
          .build_authority.cargo_vendor_tree_sha256,
          .build_authority.system_usr_tree_sha256,
          .build_authority.tar_sha256,
          .build_authority.system_etc_tree_sha256,
          .build_authority.cargo_config_sha256,
          .build_authority.ort_cache_tree_sha256,
          .build_authority.frame_sysroot_tree_sha256,
          .build_authority.rustsec_tree_sha256,
          .build_authority.cargo_audit_sha256,
          .build_authority.rustc_vv_sha256
        ] | all(test("^[0-9a-f]{64}$"))) and
        .build_authority.rustsec_provenance_schema == 1 and
        .build_authority.rustsec_db_remote ==
          "https://github.com/RustSec/advisory-db.git" and
        .build_authority.rustsec_db_ref == "refs/heads/main" and
        .build_authority.rustsec_db_commit == $rustsec and
        .build_authority.tar_sha256 ==
          "3ee2c3c0b4dd9aacebfd2f0fbae44bad36348203acff78a44888dd58c05f811c" and
        .build_authority.host_target == "x86_64-unknown-linux-gnu" and
        .reproducibility_builds == 2 and
        (.baseline_inventory | keys_unsorted == [
          "schema","contract_sha256","inventory_id","members"
        ]) and
        .baseline_inventory.schema == .baseline.schema and
        .baseline_inventory.contract_sha256 ==
          .baseline.contract_sha256 and
        .baseline_inventory.inventory_id == $inventory_id and
        (.baseline_inventory.members | type == "array" and length == 5) and
        ([.baseline_inventory.members[] |
          keys_unsorted == ["id","path","sha256","size","kind","mode"]] |
          all) and
        ([.baseline_inventory.members[] | {id,path,kind,mode}] == [
          {id:"rust-openclaw",path:"bin/rust-openclaw",kind:"binary",mode:365},
          {id:"mace",path:"bin/mace",kind:"binary",mode:365},
          {id:"syntaur_browser",path:"bin/syntaur_browser",kind:"binary",mode:365},
          {id:"runtime-compose",path:"runtime/docker-compose-prod.yml",kind:"config",mode:420},
          {id:"runtime-entrypoint",path:"runtime/entrypoint.sh",kind:"script",mode:365}
        ]) and
        ([.baseline_inventory.members[].sha256 |
          test("^[0-9a-f]{64}$")] | all) and
        ([.baseline_inventory.members[].size |
          type == "number" and . > 0 and . <= 1073741824 and floor == .] |
          all) and
        ([.baseline_inventory.members[] |
          select(.id == "runtime-compose")][0] |
          .size == 4817 and
          .sha256 ==
            "2ae3b178f3b0c6cbb539cf61547cc3b26e5030db6a2fe378e64498325ef95390") and
        ([.baseline_inventory.members[] |
          select(.id == "runtime-entrypoint")][0] |
          .size == 2913 and
          .sha256 ==
            "177fc537cf32a42836ba4309a2d24dfa06a99cc1669f9dbc92bc449b9ce1eb8e") and
        .baseline_inventory_manifest_sha256 ==
          $inventory_manifest_sha256 and
        (.validation_artifacts | type == "array" and length == 1) and
        ([.validation_artifacts[] |
          keys_unsorted == ["id","path","sha256","size"]] | all) and
        .validation_artifacts[0].id == "syntaur-isolation-tests" and
        .validation_artifacts[0].path ==
          "validation/syntaur-isolation-tests" and
        (.validation_artifacts[0].sha256 |
          test("^[0-9a-f]{64}$")) and
        (.validation_artifacts[0].size |
          type == "number" and . > 0 and . <= 1073741824 and floor == .) and
        (.future_product_protocol | keys_unsorted == [
          "schema","release_authority_manifest_schema","protocol"
        ]) and
        .future_product_protocol.schema ==
          "syntaur.future-product-protocol.v2" and
        .future_product_protocol.release_authority_manifest_schema == 2 and
        (.future_product_protocol.protocol | keys_unsorted == [
          "schema","provisioner_sha256","production_contract_sha256",
          "production_member_count","receipt_schema","build_authority_schema",
          "promotion_recovery_schema","promotion_recovery_sha256"
        ]) and
        .future_product_protocol.protocol.schema == 1 and
        .future_product_protocol.protocol.provisioner_sha256 == $provisioner and
        .future_product_protocol.protocol.provisioner_sha256 ==
          $manifest[0].provisioner_sha256 and
        .future_product_protocol.protocol.production_contract_sha256 ==
          $manifest[0].production_contract_sha256 and
        .future_product_protocol.protocol.production_member_count ==
          $manifest[0].production_member_count and
        .future_product_protocol.protocol.production_member_count == 12 and
        .future_product_protocol.protocol.receipt_schema ==
          $manifest[0].receipt_schema and
        .future_product_protocol.protocol.receipt_schema == 6 and
        .future_product_protocol.protocol.build_authority_schema ==
          $manifest[0].build_authority_schema and
        .future_product_protocol.protocol.build_authority_schema == 4 and
        .future_product_protocol.protocol.promotion_recovery_schema ==
          $manifest[0].promotion_recovery_schema and
        .future_product_protocol.protocol.promotion_recovery_schema == 1 and
        .future_product_protocol.protocol.promotion_recovery_sha256 ==
          $manifest[0].promotion_recovery_sha256 and
        .mac_target == "sean@192.168.1.58" and
        .mac_gateway_url == "http://192.168.1.58:18789" and
        (.mac_smoke | keys_unsorted == [
          "schema","completed_at","baseline_contract_sha256",
          "baseline_inventory_id","baseline_inventory_manifest_sha256",
          "staged_member_count","gateway_sha256","gateway_size",
          "gateway_version","gateway_source_commit","gateway_built_at",
          "mace_sha256","mace_size","browser_sha256","browser_size",
          "browser_engine_commit","browser_audit_passed","isolation_sha256",
          "isolation_size","isolation_version","ssh_known_hosts_path",
          "ssh_known_hosts_sha256","ssh_host_key_algorithm",
          "ssh_host_key_fingerprint","ssh_identity_path",
          "ssh_identity_sha256","ssh_identity_public_sha256",
          "ssh_identity_fingerprint",
          "exact_stage_shape_verified","canary_seconds"
        ]) and
        .mac_smoke.schema ==
          "syntaur.genesis-baseline-mac-smoke.v1" and
        (.mac_smoke.completed_at | valid_utc_timestamp) and
        .mac_smoke.baseline_contract_sha256 ==
          .baseline.contract_sha256 and
        .mac_smoke.baseline_inventory_id ==
          .baseline_inventory.inventory_id and
        .mac_smoke.baseline_inventory_manifest_sha256 ==
          .baseline_inventory_manifest_sha256 and
        .mac_smoke.staged_member_count == 5 and
        .mac_smoke.gateway_sha256 ==
          .baseline_inventory.members[0].sha256 and
        .mac_smoke.gateway_size ==
          .baseline_inventory.members[0].size and
        .mac_smoke.gateway_version == .baseline.product_version and
        .mac_smoke.gateway_source_commit ==
          .baseline.product_parent_commit and
        .mac_smoke.gateway_built_at == .baseline.product_built_at and
        .mac_smoke.mace_sha256 ==
          .baseline_inventory.members[1].sha256 and
        .mac_smoke.mace_size ==
          .baseline_inventory.members[1].size and
        .mac_smoke.browser_sha256 ==
          .baseline_inventory.members[2].sha256 and
        .mac_smoke.browser_size ==
          .baseline_inventory.members[2].size and
        .mac_smoke.browser_engine_commit == .baseline.engine_commit and
        .mac_smoke.browser_audit_passed == true and
        .mac_smoke.isolation_sha256 ==
          .validation_artifacts[0].sha256 and
        .mac_smoke.isolation_size ==
          .validation_artifacts[0].size and
        .mac_smoke.isolation_version == .baseline.product_version and
        .mac_smoke.ssh_known_hosts_path ==
          "/etc/syntaur/mac-mini-known-hosts" and
        .mac_smoke.ssh_known_hosts_sha256 ==
          "2a703ea347e6abc8e423df92ba4e2592656cf64fee467083104565a69478b1c1" and
        .mac_smoke.ssh_host_key_algorithm == "ssh-ed25519" and
        .mac_smoke.ssh_host_key_fingerprint ==
          "SHA256:/SNqZRbZ8lcIPNZOvWRxvKDRgAtmYAEy4A4KX782ldU" and
        .mac_smoke.ssh_identity_path == $ssh_identity_path and
        .mac_smoke.ssh_identity_sha256 == $ssh_identity_sha256 and
        .mac_smoke.ssh_identity_public_sha256 ==
          $ssh_identity_public_sha256 and
        .mac_smoke.ssh_identity_fingerprint ==
          $ssh_identity_fingerprint and
        .mac_smoke.exact_stage_shape_verified == true and
        .mac_smoke.canary_seconds == 45 and
        (.persistent_authority | keys_unsorted == [
          "build_authority_root_preexisting","exact_catalog_preexisting",
          "global_mutation_lock_preexisting","installed_provisioner_sha256",
          "build_authority_root_present_after","exact_catalog_present_after",
          "global_mutation_lock_present_after"
        ]) and
        (.persistent_authority.build_authority_root_preexisting | type == "boolean") and
        (.persistent_authority.exact_catalog_preexisting | type == "boolean") and
        .persistent_authority.global_mutation_lock_preexisting == true and
        .persistent_authority.installed_provisioner_sha256 == $provisioner and
        .persistent_authority.build_authority_root_present_after == true and
        .persistent_authority.exact_catalog_present_after == true and
        .persistent_authority.global_mutation_lock_present_after == true and
        .release_authority_root_absent == true
        )
        ' "$evidence" >/dev/null \
        || die 'Genesis evidence does not satisfy the exact pre-G1 contract'
}

genesis_receipt_json() {
    jq -cn \
        --arg authority_commit "$expected_authority_commit" \
        --arg manifest_sha256 "$expected_manifest_sha256" \
        --arg evidence_sha256 "$expected_genesis_evidence_sha256" \
        --arg engine_commit "$expected_genesis_engine_commit" \
        --arg rustsec_commit "$expected_rustsec_db_commit" \
        --arg shipper_sha256 "$expected_shipper_sha256" \
        --arg provisioner_sha256 "$expected_provisioner_sha256" \
        '{
          schema:"syntaur.genesis-install-receipt.v1",
          authority_commit:$authority_commit,
          manifest_sha256:$manifest_sha256,
          genesis_evidence_sha256:$evidence_sha256,
          engine_commit:$engine_commit,
          rustsec_db_commit:$rustsec_commit,
          shipper_sha256:$shipper_sha256,
          provisioner_sha256:$provisioner_sha256
        }'
}

validate_genesis_receipt() {
    local evidence=$1
    local receipt=$2
    local canonical expected
    [[ -f $receipt && ! -L $receipt ]] \
        || die 'installed Genesis receipt is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$receipt") == 0:0:444:1 ]] \
        || die 'installed Genesis receipt identity differs'
    [[ $(wc -l <"$receipt") -eq 1 ]] \
        || die 'installed Genesis receipt must be exactly one record'
    canonical=$(jq -ce '.' "$receipt") \
        || die 'installed Genesis receipt is not valid JSON'
    [[ $(<"$receipt") == "$canonical" ]] \
        || die 'installed Genesis receipt is not canonical JSON'
    expected=$(genesis_receipt_json)
    [[ $canonical == "$expected" ]] \
        || die 'installed Genesis receipt differs from the independent record'
    [[ $(sha256sum "$evidence" | awk '{print $1}') == \
        "$expected_genesis_evidence_sha256" ]] \
        || die 'installed Genesis evidence differs from its durable receipt'
}

validate_persistent_build_authority() {
    local evidence=$1
    local canonical catalog catalog_rows image_digest manifest_digest
    local manifest_relative image mount_manifest row
    local -a catalog_layers
    [[ -d /opt/syntaur-build-authority \
        && ! -L /opt/syntaur-build-authority ]] \
        || die 'persistent Genesis build-authority root is unsafe'
    [[ $(stat -c '%u:%g:%a' /opt/syntaur-build-authority) == \
        "0:$operator_gid:750" ]] \
        || die 'persistent Genesis build-authority root identity differs'
    catalog="/opt/syntaur-build-authority/catalog/$expected_authority_commit-$expected_genesis_engine_commit.json"
    [[ -f $catalog && ! -L $catalog ]] \
        || die 'exact persistent Genesis catalog is missing or unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$catalog") == \
        "0:$operator_gid:440:1" ]] \
        || die 'exact persistent Genesis catalog identity differs'
    [[ $(stat -c '%s' "$catalog") -gt 0 \
        && $(stat -c '%s' "$catalog") -le 65536 ]] \
        || die 'exact persistent Genesis catalog size is invalid'
    [[ $(wc -l <"$catalog") -eq 1 ]] \
        || die 'persistent Genesis catalog must be exactly one JSON record'
    canonical=$(jq -ce '.' "$catalog") \
        || die 'persistent Genesis catalog is not valid JSON'
    [[ $(<"$catalog") == "$canonical" ]] \
        || die 'persistent Genesis catalog is not canonical JSON'
    jq -se --slurpfile evidence "$evidence" '
      length == 1 and
      (.[0] |
      keys_unsorted == [
        "schema","source_commit","engine_commit","rustsec_provenance_schema",
        "rustsec_db_remote","rustsec_db_ref","rustsec_db_commit",
        "platform_image_sha256","platform_manifest_sha256",
        "dependencies_image_sha256","dependencies_manifest_sha256",
        "source_image_sha256","source_manifest_sha256"
      ] and
      .schema == $evidence[0].build_authority.schema and
      .source_commit == $evidence[0].build_authority.source_commit and
      .engine_commit == $evidence[0].build_authority.engine_commit and
      .rustsec_provenance_schema ==
        $evidence[0].build_authority.rustsec_provenance_schema and
      .rustsec_db_remote == $evidence[0].build_authority.rustsec_db_remote and
      .rustsec_db_ref == $evidence[0].build_authority.rustsec_db_ref and
      .rustsec_db_commit == $evidence[0].build_authority.rustsec_db_commit and
      .platform_image_sha256 ==
        $evidence[0].build_authority.platform_image_sha256 and
      .platform_manifest_sha256 ==
        $evidence[0].build_authority.platform_manifest_sha256 and
      .dependencies_image_sha256 ==
        $evidence[0].build_authority.dependencies_image_sha256 and
      .dependencies_manifest_sha256 ==
        $evidence[0].build_authority.dependencies_manifest_sha256 and
      .source_image_sha256 ==
        $evidence[0].build_authority.source_image_sha256 and
      .source_manifest_sha256 ==
        $evidence[0].build_authority.source_manifest_sha256
      )
    ' "$catalog" >/dev/null \
        || die 'persistent Genesis catalog differs from the reviewed evidence'

    catalog_rows=$(jq -er '
      [
        [.platform_image_sha256,.platform_manifest_sha256,
          "opt/authority/manifests/platform.json"],
        [.dependencies_image_sha256,.dependencies_manifest_sha256,
          "opt/authority/manifests/dependencies.json"],
        [.source_image_sha256,.source_manifest_sha256,
          "opt/authority/manifests/source.json"]
      ][] | @tsv
    ' "$catalog") \
        || die 'cannot read persistent Genesis catalog layer inventory'
    mapfile -t catalog_layers <<<"$catalog_rows"
    [[ ${#catalog_layers[@]} -eq 3 ]] \
        || die 'persistent Genesis catalog must name exactly three layers'
    for row in "${catalog_layers[@]}"; do
        IFS=$'\t' read -r \
            image_digest manifest_digest manifest_relative <<<"$row"
        [[ -n $image_digest && -n $manifest_digest \
            && -n $manifest_relative ]] \
            || die 'persistent Genesis catalog contains an incomplete layer'
        image="/opt/syntaur-build-authority/images/$image_digest.squashfs"
        mount_manifest="/opt/syntaur-build-authority/mounts/$image_digest/$manifest_relative"
        [[ -f $image && ! -L $image ]] \
            || die "persistent build-authority image is unsafe: $image_digest"
        [[ $(stat -c '%u:%g:%a:%h' "$image") == \
            "0:$operator_gid:440:1" ]] \
            || die "persistent build-authority image identity differs: $image_digest"
        [[ $(sha256sum "$image" | awk '{print $1}') == "$image_digest" ]] \
            || die "persistent build-authority image digest differs: $image_digest"
        [[ -f $mount_manifest && ! -L $mount_manifest ]] \
            || die "persistent build-authority manifest is unavailable: $image_digest"
        [[ $(sha256sum "$mount_manifest" | awk '{print $1}') == "$manifest_digest" ]] \
            || die "persistent build-authority manifest digest differs: $image_digest"
    done
}

validate_installed_authority_layout() {
    local actual_names expected_layout_names name path
    [[ -d $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'installed authority root is unsafe'
    [[ $(stat -c '%u:%g:%a' "$AUTHORITY_ROOT") == 0:0:755 ]] \
        || die 'installed authority root identity differs'
    expected_layout_names=$(printf '%s\n' \
        genesis \
        release-authority \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit | LC_ALL=C sort)
    actual_names=$(find "$AUTHORITY_ROOT" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)
    [[ $actual_names == "$expected_layout_names" ]] \
        || die 'installed authority root file set is inexact'

    [[ -d $installed_genesis_dir && ! -L $installed_genesis_dir ]] \
        || die 'installed Genesis proof directory is unsafe'
    [[ $(stat -c '%u:%g:%a' "$installed_genesis_dir") == 0:0:555 ]] \
        || die 'installed Genesis proof directory identity differs'
    expected_layout_names=$(printf '%s\n' \
        genesis-install-receipt-v1.json \
        genesis-validation.json | LC_ALL=C sort)
    actual_names=$(find "$installed_genesis_dir" \
        -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
    [[ $actual_names == "$expected_layout_names" ]] \
        || die 'installed Genesis proof file set is inexact'

    [[ -d $AUTHORITY_ROOT/release-authority \
        && ! -L $AUTHORITY_ROOT/release-authority ]] \
        || die 'installed generation parent is unsafe'
    [[ $(stat -c '%u:%g:%a' "$AUTHORITY_ROOT/release-authority") == \
        0:0:755 ]] \
        || die 'installed generation parent identity differs'
    [[ $(find "$AUTHORITY_ROOT/release-authority" \
        -mindepth 1 -maxdepth 1 -printf '%f\n') == generation-1 ]] \
        || die 'installed generation set is inexact'
    [[ -d $installed_generation_dir && ! -L $installed_generation_dir ]] \
        || die 'installed generation-1 directory is unsafe'
    [[ $(stat -c '%u:%g:%a' "$installed_generation_dir") == 0:0:555 ]] \
        || die 'installed generation-1 directory identity differs'

    expected_layout_names=$(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C sort)
    actual_names=$(find "$installed_generation_dir" \
        -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
    [[ $actual_names == "$expected_layout_names" ]] \
        || die 'installed generation-1 file set is inexact'

    for name in \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit; do
        path="$AUTHORITY_ROOT/$name"
        [[ -f $path && ! -L $path \
            && $(stat -c '%u:%g:%a:%h' "$path") == 0:0:444:1 ]] \
            || die "installed top-level authority file is unsafe: $name"
        /usr/bin/cmp -s \
            "$path" "$installed_generation_dir/$name" \
            || die "installed authority copies differ: $name"
    done
    for name in \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle; do
        /usr/bin/cmp -s \
            "$AUTHORITY_ROOT/$name" "$snapshot_material/$name" \
            || die "installed authority differs from signed input: $name"
    done
    [[ $(sha256sum "$AUTHORITY_ROOT/release-authority-v2.json" \
        | awk '{print $1}') == "$expected_manifest_sha256" ]] \
        || die 'installed authority manifest digest differs'
    [[ $(wc -l <"$AUTHORITY_ROOT/trusted-workflow-commit") -eq 1 \
        && $(<"$AUTHORITY_ROOT/trusted-workflow-commit") == \
            "$expected_workflow_commit" ]] \
        || die 'installed trusted workflow commit differs'

    for name in \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit; do
        path="$installed_generation_dir/$name"
        [[ -f $path && ! -L $path \
            && $(stat -c '%u:%g:%a:%h' "$path") == 0:0:444:1 ]] \
            || die "installed generation data is unsafe: $name"
    done
    for name in genesis-validation.json genesis-install-receipt-v1.json; do
        path="$installed_genesis_dir/$name"
        [[ -f $path && ! -L $path \
            && $(stat -c '%u:%g:%a:%h' "$path") == 0:0:444:1 ]] \
            || die "installed Genesis proof data is unsafe: $name"
    done
    for name in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        path="$installed_generation_dir/$name"
        [[ -f $path && ! -L $path \
            && $(stat -c '%u:%g:%a:%h' "$path") == 0:0:555:1 ]] \
            || die "installed generation executable is unsafe: $name"
    done
    [[ $(sha256sum "$installed_generation_dir/syntaur-build-authority-provision" \
        | awk '{print $1}') == "$expected_provisioner_sha256" ]] \
        || die 'installed generation provisioner digest differs'
    [[ $(sha256sum "$installed_generation_dir/syntaur-ship-linux-x86_64" \
        | awk '{print $1}') == "$expected_shipper_sha256" ]] \
        || die 'installed generation shipper digest differs'
    [[ $(sha256sum "$installed_generation_dir/syntaur-verify-linux-x86_64" \
        | awk '{print $1}') == "$expected_verifier_sha256" ]] \
        || die 'installed generation verifier digest differs'

    validate_genesis_evidence \
        "$installed_genesis_dir/genesis-validation.json" 444
    validate_genesis_receipt \
        "$installed_genesis_dir/genesis-validation.json" \
        "$installed_genesis_dir/genesis-install-receipt-v1.json"
    validate_persistent_build_authority \
        "$installed_genesis_dir/genesis-validation.json"
}

if [[ $action == install ]]; then
    validate_genesis_evidence "$snapshot_evidence"
    validate_persistent_build_authority "$snapshot_evidence"
fi

for executable_parent in /usr/local/bin /opt; do
    [[ -d $executable_parent && ! -L $executable_parent ]] \
        || die "installed executable parent is unsafe: $executable_parent"
    [[ $(stat -c '%u:%g:%a' "$executable_parent") == 0:0:755 ]] \
        || die "installed executable parent metadata differs: $executable_parent"
done

install_exact_executable() {
    local source=$1
    local temporary=$2
    local destination=$3
    local expected_digest=$4
    local mode=${5:-755}
    if [[ -e $temporary || -L $temporary ]]; then
        [[ -f $temporary && ! -L $temporary ]] \
            || die "stale executable stage is unsafe: $temporary"
        [[ $(stat -c '%u:%g:%a:%h' "$temporary") == "0:0:$mode:1" ]] \
            || die "stale executable stage identity differs: $temporary"
        [[ $(sha256sum "$temporary" | awk '{print $1}') == "$expected_digest" ]] \
            || die "stale executable stage digest differs: $temporary"
    else
        /usr/bin/install -o root -g root -m "$mode" "$source" "$temporary"
    fi
    [[ $(sha256sum "$temporary" | awk '{print $1}') == "$expected_digest" ]] \
        || die "staged executable digest differs: $destination"
    /usr/bin/sync -f "$temporary"
    /usr/bin/mv -Tf "$temporary" "$destination"
    /usr/bin/sync -f "$(dirname "$destination")"
    [[ -f $destination && ! -L $destination ]] \
        || die "installed executable is unsafe: $destination"
    [[ $(stat -c '%u:%g:%a:%h' "$destination") == "0:0:$mode:1" ]] \
        || die "installed executable metadata differs: $destination"
}

installed_executable_is_exact() {
    local path=$1
    local expected_digest=$2
    local mode=${3:-755}
    [[ -f $path && ! -L $path ]] \
        && [[ $(stat -c '%u:%g:%a:%h' "$path") == "0:0:$mode:1" ]] \
        && [[ $(sha256sum "$path" | awk '{print $1}') == "$expected_digest" ]]
}

validate_genesis_mac_known_hosts() {
    [[ -f $GENESIS_MAC_KNOWN_HOSTS && ! -L $GENESIS_MAC_KNOWN_HOSTS ]] \
        || die 'Genesis Mac known-hosts trust is missing or unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$GENESIS_MAC_KNOWN_HOSTS") == 0:0:444:1 ]] \
        || die 'Genesis Mac known-hosts metadata differs'
    [[ $(wc -l <"$GENESIS_MAC_KNOWN_HOSTS") -eq 1 ]] \
        || die 'Genesis Mac known-hosts must contain exactly one record'
    [[ $(<"$GENESIS_MAC_KNOWN_HOSTS") == "$GENESIS_MAC_KNOWN_HOSTS_RECORD" ]] \
        || die 'Genesis Mac known-hosts record differs'
    [[ $(sha256sum "$GENESIS_MAC_KNOWN_HOSTS" | awk '{print $1}') == \
        "$GENESIS_MAC_KNOWN_HOSTS_SHA256" ]] \
        || die 'Genesis Mac known-hosts digest differs'
    [[ $(/usr/bin/ssh-keygen -lf "$GENESIS_MAC_KNOWN_HOSTS" \
        | awk 'NR == 1 {print $2}') == \
        'SHA256:/SNqZRbZ8lcIPNZOvWRxvKDRgAtmYAEy4A4KX782ldU' ]] \
        || die 'Genesis Mac host-key fingerprint differs'
}

install_genesis_mac_known_hosts() {
    if [[ -e $GENESIS_MAC_KNOWN_HOSTS || -L $GENESIS_MAC_KNOWN_HOSTS ]]; then
        validate_genesis_mac_known_hosts
        return
    fi
    [[ ! -e $known_hosts_stage && ! -L $known_hosts_stage ]] \
        || die 'stale Genesis Mac known-hosts stage is unsafe'
    printf '%s\n' "$GENESIS_MAC_KNOWN_HOSTS_RECORD" >"$known_hosts_stage"
    /usr/bin/chown root:root "$known_hosts_stage"
    /usr/bin/chmod 0444 "$known_hosts_stage"
    [[ $(sha256sum "$known_hosts_stage" | awk '{print $1}') == \
        "$GENESIS_MAC_KNOWN_HOSTS_SHA256" ]] \
        || die 'staged Genesis Mac known-hosts digest differs'
    /usr/bin/sync -f "$known_hosts_stage"
    /usr/bin/mv -T "$known_hosts_stage" "$GENESIS_MAC_KNOWN_HOSTS"
    /usr/bin/sync -f /etc/syntaur
    validate_genesis_mac_known_hosts
}

validate_genesis_mac_identity() {
    validate_genesis_mac_identity_material \
        "$GENESIS_MAC_IDENTITY" \
        0 \
        "$operator_gid" \
        440
}

install_genesis_mac_identity() {
    if [[ -e $GENESIS_MAC_IDENTITY || -L $GENESIS_MAC_IDENTITY ]]; then
        validate_genesis_mac_identity
        return
    fi
    [[ ! -e $identity_stage && ! -L $identity_stage ]] \
        || die 'stale Genesis Mac SSH identity stage is unsafe'
    /usr/bin/install \
        -o root \
        -g "$operator_gid" \
        -m 0440 \
        "$snapshot_identity" \
        "$identity_stage"
    validate_genesis_mac_identity_material \
        "$identity_stage" \
        0 \
        "$operator_gid" \
        440
    /usr/bin/sync -f "$identity_stage"
    /usr/bin/mv -T "$identity_stage" "$GENESIS_MAC_IDENTITY"
    /usr/bin/sync -f /etc/syntaur
    validate_genesis_mac_identity
}

remove_exact_genesis_validator() {
    if [[ ! -e $GENESIS_VALIDATOR && ! -L $GENESIS_VALIDATOR ]]; then
        return
    fi
    installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$expected_shipper_sha256" \
        || die 'Genesis validator changed before retirement'
    /usr/bin/rm -f -- "$GENESIS_VALIDATOR"
    /usr/bin/sync -f /opt
    [[ ! -e $GENESIS_VALIDATOR && ! -L $GENESIS_VALIDATOR ]] \
        || die 'Genesis validator retirement did not settle'
}

run_operator_authority_status() {
    (
        exec 7>&- 8>&- 9>&-
        # The production install parser requires a concrete non-root
        # SUDO_UID/SUDO_GID. The root branch is reachable only in the
        # single-UID, user-namespace fixture after its explicit parser rewrite;
        # that namespace forbids setgroups even for uid 0.
        if [[ $operator_uid == 0 && $operator_gid == 0 ]]; then
            exec /usr/bin/env -i \
                HOME=/home/sean \
                USER=sean \
                LOGNAME=sean \
                PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=C.UTF-8 \
                LC_ALL=C.UTF-8 \
                SYNTAUR_BOOTSTRAP_SINGLE_UID_FIXTURE=1 \
                "$INSTALLED_SHIPPER" authority-status
        fi
        exec /usr/bin/setpriv \
            --reuid "$operator_uid" \
            --regid "$operator_gid" \
            --clear-groups \
            /usr/bin/env -i \
                HOME=/home/sean \
                USER=sean \
                LOGNAME=sean \
                PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=C.UTF-8 \
                LC_ALL=C.UTF-8 \
                "$INSTALLED_SHIPPER" authority-status
    )
}

if [[ $action == stage-build-authority ]]; then
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'canonical release root appeared during pre-G1 staging'
    if ! installed_executable_is_exact \
        "$INSTALLED_PROVISIONER" "$expected_provisioner_sha256"; then
        absent_digest=$(printf '0%.0s' {1..64})
        if [[ $expected_current_provisioner_sha256 == "$absent_digest" ]]; then
            [[ ! -e $INSTALLED_PROVISIONER && ! -L $INSTALLED_PROVISIONER ]] \
                || die 'current provisioner exists but absence was independently expected'
        else
            installed_executable_is_exact \
                "$INSTALLED_PROVISIONER" \
                "$expected_current_provisioner_sha256" \
                || die 'installed provisioner differs from the independent CAS predecessor'
        fi
        install_exact_executable \
            "$snapshot_material/syntaur-build-authority-provision" \
            "$provisioner_stage" \
            "$INSTALLED_PROVISIONER" \
            "$expected_provisioner_sha256"
    fi
    installed_executable_is_exact \
        "$INSTALLED_PROVISIONER" "$expected_provisioner_sha256" \
        || die 'pre-G1 provisioner staging did not persist exact bytes'
    if ! installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$expected_shipper_sha256"; then
        absent_digest=$(printf '0%.0s' {1..64})
        if [[ $expected_current_validator_sha256 == "$absent_digest" ]]; then
            [[ ! -e $GENESIS_VALIDATOR && ! -L $GENESIS_VALIDATOR ]] \
                || die 'Genesis validator exists but absence was independently expected'
        else
            installed_executable_is_exact \
                "$GENESIS_VALIDATOR" \
                "$expected_current_validator_sha256" \
                || die 'Genesis validator differs from the independent CAS predecessor'
        fi
        install_exact_executable \
            "$snapshot_material/syntaur-ship-linux-x86_64" \
            "$validator_stage" \
            "$GENESIS_VALIDATOR" \
            "$expected_shipper_sha256"
    fi
    installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$expected_shipper_sha256" \
        || die 'pre-G1 Genesis validator staging did not persist exact bytes'
    install_genesis_mac_known_hosts
    install_genesis_mac_identity
    validate_global_lock
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'pre-G1 staging must not publish the canonical release root'
    printf 'V2 pre-G1 tools staged: provisioner_sha256=%s validator_sha256=%s release_root=absent\n' \
        "$expected_provisioner_sha256" "$expected_shipper_sha256"
    exit 0
fi

validate_genesis_mac_known_hosts
validate_genesis_mac_identity
installed_executable_is_exact \
    "$INSTALLED_PROVISIONER" "$expected_provisioner_sha256" \
    || die 'G1 install requires the exact pre-staged build-authority provisioner'
if [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]]; then
    installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$expected_shipper_sha256" \
        || die 'G1 install requires the exact pre-staged Genesis validator'
fi

if [[ -e $AUTHORITY_ROOT || -L $AUTHORITY_ROOT ]]; then
    [[ -d $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'existing authority root is unsafe'
    [[ $(sha256sum "$AUTHORITY_ROOT/release-authority-v2.json" | awk '{print $1}') \
        == "$expected_manifest_sha256" ]] \
        || die 'a different authority root already exists'
    validate_installed_authority_layout
    if ! installed_executable_is_exact \
        "$INSTALLED_SHIPPER" "$expected_shipper_sha256" 1755; then
        install_exact_executable \
            "$snapshot_material/syntaur-ship-linux-x86_64" \
            "$shipper_stage" \
            "$INSTALLED_SHIPPER" \
            "$expected_shipper_sha256" \
            1755
    fi
    run_operator_authority_status
    remove_exact_genesis_validator
    printf 'V2 authority genesis bootstrap recovered or was already exact\n'
    exit 0
fi

if [[ -e $stage || -L $stage ]]; then
    [[ -d $stage && ! -L $stage && $(stat -c '%u:%g' "$stage") == 0:0 ]] \
        || die 'stale authority stage is unsafe'
    /usr/bin/chmod -R u+rwX "$stage"
    /usr/bin/rm -rf -- "$stage"
fi
/usr/bin/install -d -o root -g root -m 0755 "$stage"
/usr/bin/install -d -o root -g root -m 0755 "$stage/genesis"
/usr/bin/install -d -o root -g root -m 0755 "$stage/release-authority"
/usr/bin/install -d -o root -g root -m 0755 \
    "$stage/release-authority/generation-1"
generation_dir="$stage/release-authority/generation-1"

/usr/bin/install -o root -g root -m 0444 \
    "$snapshot_material/release-authority-v2.json" \
    "$stage/release-authority-v2.json"
/usr/bin/install -o root -g root -m 0444 \
    "$snapshot_material/release-authority-v2.json.cosign.bundle" \
    "$stage/release-authority-v2.json.cosign.bundle"
printf '%s\n' "$expected_workflow_commit" >"$stage/trusted-workflow-commit"
/usr/bin/chown root:root "$stage/trusted-workflow-commit"
/usr/bin/chmod 0444 "$stage/trusted-workflow-commit"
/usr/bin/install -o root -g root -m 0444 \
    "$snapshot_material/release-authority-v2.json" \
    "$snapshot_material/release-authority-v2.json.cosign.bundle" \
    "$stage/trusted-workflow-commit" \
    "$generation_dir/"
/usr/bin/install -o root -g root -m 0555 \
    "$snapshot_material/syntaur-build-authority-provision" \
    "$snapshot_material/syntaur-ship-linux-x86_64" \
    "$snapshot_material/syntaur-verify-linux-x86_64" \
    "$generation_dir/"
/usr/bin/install -o root -g root -m 0444 \
    "$snapshot_evidence" \
    "$stage/genesis/genesis-validation.json"
genesis_receipt_json >"$stage/genesis/genesis-install-receipt-v1.json"
/usr/bin/chown root:root \
    "$stage/genesis/genesis-install-receipt-v1.json"
/usr/bin/chmod 0444 \
    "$stage/genesis/genesis-install-receipt-v1.json"
/usr/bin/chmod 0555 "$stage/genesis"
/usr/bin/chmod 0555 "$generation_dir"

stage_paths=$(/usr/bin/find "$stage" -depth -print) \
    || die 'cannot enumerate the staged authority tree for durability'
while IFS= read -r path; do
    /usr/bin/sync -f "$path"
done <<<"$stage_paths"
/usr/bin/sync -f /etc/syntaur
/usr/bin/mv -T "$stage" "$AUTHORITY_ROOT"
/usr/bin/sync -f /etc/syntaur

installed_executable_is_exact \
    "$INSTALLED_PROVISIONER" "$expected_provisioner_sha256" \
    || die 'pre-staged provisioner changed before G1 publication completed'
validate_installed_authority_layout
install_exact_executable \
    "$snapshot_material/syntaur-ship-linux-x86_64" \
    "$shipper_stage" \
    "$INSTALLED_SHIPPER" \
    "$expected_shipper_sha256" \
    1755

run_operator_authority_status
remove_exact_genesis_validator
printf 'V2 authority genesis bootstrap installed: generation=1 manifest_sha256=%s\n' \
    "$expected_manifest_sha256"
