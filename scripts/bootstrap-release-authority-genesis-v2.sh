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
step: it creates the non-authorizing global lock and CAS-installs only the
exact signed provisioner and Genesis validator while the canonical release
root remains absent. `install` publishes the G1 release root and exact shipper
after successful Genesis validation. Both mutating actions require sudo on
claudevm and snapshot every operator-owned input into root-owned storage
before using it.
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
stage=/etc/syntaur/.release-authority.bootstrap-v2-g1
installed_generation_dir="$AUTHORITY_ROOT/release-authority/generation-1"
installed_genesis_dir="$AUTHORITY_ROOT/genesis"
shipper_stage=/usr/local/bin/.syntaur-ship.authority-bootstrap-v2-g1
provisioner_stage=/opt/.syntaur-build-authority-provision.bootstrap-v2-g1
validator_stage=/opt/.syntaur-genesis-validator.bootstrap-v2-g1

cleanup_staging() {
    local path
    for path in \
        "$snapshot" "$shipper_stage" "$provisioner_stage" "$validator_stage"; do
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
        "$snapshot_evidence" 400 16777216
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
    local canonical shipper_size
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
    jq -se \
        --arg version "$expected_authority_version" \
        --arg source "$expected_authority_commit" \
        --arg engine "$expected_genesis_engine_commit" \
        --arg shipper "$expected_shipper_sha256" \
        --arg provisioner "$expected_provisioner_sha256" \
        --arg rustsec "$expected_rustsec_db_commit" \
        --argjson shipper_size "$shipper_size" \
        '
        length == 1 and
        (.[0] |
        keys == ([
          "schema","authorizing","completed_at","host","version","source","engine",
          "source_date_epoch","shipper","build_authority","artifacts",
          "reproducibility_builds",
          "runtime_generation_id","runtime_generation_manifest_sha256",
          "production_generation_id","mac_target","mac_gateway_url","mac_smoke",
          "persistent_authority","release_authority_root_absent"
        ] | sort) and
        .schema == "syntaur.genesis-validation.v1" and
        .authorizing == false and
        (.completed_at | type == "string" and
          test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+Z$")) and
        .host == "claudevm" and
        .version == $version and
        (.source | keys == ([
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ] | sort)) and
        .source.commit == $source and
        (.source.tree | test("^[0-9a-f]{40}([0-9a-f]{24})?$")) and
        (.source.workspace | type == "string" and startswith("/")) and
        (.source.export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        (.source.sealed_export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        (.engine | keys == ([
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ] | sort)) and
        .engine.commit == $engine and
        (.engine.tree | test("^[0-9a-f]{40}([0-9a-f]{24})?$")) and
        (.engine.workspace | type == "string" and startswith("/")) and
        .engine.workspace != .source.workspace and
        (.engine.export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        (.engine.sealed_export_tree_sha256 | test("^[0-9a-f]{64}$")) and
        (.shipper | keys == ([
          "schema","executable_sha256","executable_size","build_source_commit",
          "control_plane_sha256","build_toolchain_sha256",
          "build_rustflags_sha256","build_target","build_profile","clean_build"
        ] | sort)) and
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
        (.build_authority | keys == ([
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
        ] | sort)) and
        .build_authority.schema == 4 and
        .build_authority.source_commit == $source and
        .build_authority.source_version == $version and
        (.source_date_epoch | type == "number" and . > 0 and floor == .) and
        .build_authority.source_date_epoch == .source_date_epoch and
        .build_authority.engine_commit == $engine and
        .build_authority.source_tree_sha256 == .source.export_tree_sha256 and
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
        (.artifacts | type == "array" and length == 12) and
        ([.artifacts[] | keys == (["id","path","sha256","size"] | sort)] | all) and
        ([.artifacts[] | {id, path}] == [
          {id:"rust-openclaw",path:"bin/rust-openclaw"},
          {id:"mace",path:"bin/mace"},
          {id:"syntaur-isolation-tests",path:"bin/syntaur-isolation-tests"},
          {id:"syntaur_browser",path:"bin/syntaur_browser"},
          {id:"rust-captcha-bridge",path:"bin/rust-captcha-bridge"},
          {id:"rust-social-manager",path:"bin/rust-social-manager"},
          {id:"runtime-compose",path:"runtime/docker-compose-prod.yml"},
          {id:"runtime-images",path:"runtime/release-images.env"},
          {id:"runtime-entrypoint",path:"runtime/entrypoint.sh"},
          {id:"runtime-tailscale-entrypoint",path:"runtime/tailscale-sidecar-entrypoint.sh"},
          {id:"runtime-searxng-settings",path:"runtime/searxng-settings.yml"},
          {id:"syntaur-frame",path:"frame/syntaur-frame"}
        ]) and
        ([.artifacts[].sha256 |
            test("^[0-9a-f]{64}$")] | all) and
        ([.artifacts[].size |
            type == "number" and . > 0 and floor == .] | all) and
        (.runtime_generation_id | test("^[0-9a-f]{64}$")) and
        (.runtime_generation_manifest_sha256 | test("^[0-9a-f]{64}$")) and
        (.production_generation_id | test("^[0-9a-f]{64}$")) and
        .mac_target == "sean@192.168.1.58" and
        .mac_gateway_url == "http://192.168.1.58:18789" and
        (.mac_smoke | keys == ([
          "completed_at","version","source_commit","gateway_sha256",
          "frame_sha256","frame_size","frame_elf_machine",
          "production_generation_id","runtime_generation_id",
          "runtime_generation_manifest_sha256","canary_seconds"
        ] | sort)) and
        (.mac_smoke.completed_at | type == "string" and
          test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+Z$")) and
        .mac_smoke.version == $version and
        .mac_smoke.source_commit == $source and
        .mac_smoke.gateway_sha256 ==
          ([.artifacts[] | select(.id == "rust-openclaw")][0].sha256) and
        .mac_smoke.frame_sha256 ==
          ([.artifacts[] | select(.id == "syntaur-frame")][0].sha256) and
        .mac_smoke.frame_size ==
          ([.artifacts[] | select(.id == "syntaur-frame")][0].size) and
        .mac_smoke.frame_elf_machine == 183 and
        .mac_smoke.runtime_generation_id == .runtime_generation_id and
        .mac_smoke.runtime_generation_manifest_sha256 ==
          .runtime_generation_manifest_sha256 and
        .mac_smoke.production_generation_id == .production_generation_id and
        .mac_smoke.canary_seconds == 45 and
        (.persistent_authority | keys == ([
          "build_authority_root_preexisting","exact_catalog_preexisting",
          "global_mutation_lock_preexisting","installed_provisioner_sha256",
          "build_authority_root_present_after","exact_catalog_present_after",
          "global_mutation_lock_present_after"
        ] | sort)) and
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
      keys == ([
        "schema","source_commit","engine_commit","rustsec_provenance_schema",
        "rustsec_db_remote","rustsec_db_ref","rustsec_db_commit",
        "platform_image_sha256","platform_manifest_sha256",
        "dependencies_image_sha256","dependencies_manifest_sha256",
        "source_image_sha256","source_manifest_sha256"
      ] | sort) and
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
    if [[ -e $temporary || -L $temporary ]]; then
        [[ -f $temporary && ! -L $temporary ]] \
            || die "stale executable stage is unsafe: $temporary"
        [[ $(stat -c '%u:%g:%a:%h' "$temporary") == 0:0:755:1 ]] \
            || die "stale executable stage identity differs: $temporary"
        [[ $(sha256sum "$temporary" | awk '{print $1}') == "$expected_digest" ]] \
            || die "stale executable stage digest differs: $temporary"
    else
        /usr/bin/install -o root -g root -m 0755 "$source" "$temporary"
    fi
    [[ $(sha256sum "$temporary" | awk '{print $1}') == "$expected_digest" ]] \
        || die "staged executable digest differs: $destination"
    /usr/bin/sync -f "$temporary"
    /usr/bin/mv -Tf "$temporary" "$destination"
    /usr/bin/sync -f "$(dirname "$destination")"
    [[ -f $destination && ! -L $destination ]] \
        || die "installed executable is unsafe: $destination"
    [[ $(stat -c '%u:%g:%a:%h' "$destination") == 0:0:755:1 ]] \
        || die "installed executable metadata differs: $destination"
}

installed_executable_is_exact() {
    local path=$1
    local expected_digest=$2
    [[ -f $path && ! -L $path ]] \
        && [[ $(stat -c '%u:%g:%a:%h' "$path") == 0:0:755:1 ]] \
        && [[ $(sha256sum "$path" | awk '{print $1}') == "$expected_digest" ]]
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
    validate_global_lock
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'pre-G1 staging must not publish the canonical release root'
    printf 'V2 pre-G1 tools staged: provisioner_sha256=%s validator_sha256=%s release_root=absent\n' \
        "$expected_provisioner_sha256" "$expected_shipper_sha256"
    exit 0
fi

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
        "$INSTALLED_SHIPPER" "$expected_shipper_sha256"; then
        install_exact_executable \
            "$snapshot_material/syntaur-ship-linux-x86_64" \
            "$shipper_stage" \
            "$INSTALLED_SHIPPER" \
            "$expected_shipper_sha256"
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
    "$expected_shipper_sha256"

run_operator_authority_status
remove_exact_genesis_validator
printf 'V2 authority genesis bootstrap installed: generation=1 manifest_sha256=%s\n' \
    "$expected_manifest_sha256"
