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
  bootstrap-release-authority-genesis-v2.sh verify|install \
    --source-dir DIR \
    --expected-manifest-sha256 HEX \
    --expected-workflow-commit COMMIT \
    --expected-authority-version X.Y.Z \
    --expected-authority-commit COMMIT \
    --expected-shipper-sha256 HEX \
    --expected-verifier-sha256 HEX \
    --expected-provisioner-sha256 HEX \
    --expected-helper-sha256 HEX

`verify` is non-mutating. `install` is the sole root bootstrap and must be
invoked with sudo on claudevm. It accepts only V2 generation-1 genesis and
snapshots every operator-owned input into root-owned storage before validation.
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
action=$1
shift
[[ $action == verify || $action == install ]] || usage

source_dir=
expected_manifest_sha256=
expected_workflow_commit=
expected_authority_version=
expected_authority_commit=
expected_shipper_sha256=
expected_verifier_sha256=
expected_provisioner_sha256=
expected_helper_sha256=
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
        *) usage ;;
    esac
    shift 2
done

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
if [[ $action == install ]]; then
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
[[ ! -L /etc/syntaur ]] || die '/etc/syntaur is a symlink'
/usr/bin/install -d -o root -g root -m 0755 /etc/syntaur
[[ -d /etc/syntaur && ! -L /etc/syntaur ]] \
    || die '/etc/syntaur is not an exact directory'
[[ $(stat -c '%u:%g:%a' /etc/syntaur) == 0:0:755 ]] \
    || die '/etc/syntaur is not exact root-owned mode 0755'

lock_path=/run/lock/syntaur-release-authority-bootstrap.lock
[[ ! -L $lock_path ]] || die 'bootstrap lock path is a symlink'
if [[ ! -e $lock_path ]]; then
    umask 077
    : >"$lock_path"
fi
[[ -f $lock_path && ! -L $lock_path ]] || die 'bootstrap lock path is unsafe'
/usr/bin/chown root:root "$lock_path"
/usr/bin/chmod 0600 "$lock_path"
[[ $(stat -c '%u:%g:%a:%h' "$lock_path") == 0:0:600:1 ]] \
    || die 'bootstrap lock identity is unsafe'
exec 9<>"$lock_path"
/usr/bin/flock -n 9 || die 'another bootstrap process holds the lock'

snapshot=/run/syntaur-release-authority-genesis-v2.snapshot
[[ ! -e $snapshot && ! -L $snapshot ]] \
    || die 'stale root snapshot requires independent inspection'
/usr/bin/install -d -o root -g root -m 0700 "$snapshot"
snapshot_material="$snapshot/material"
/usr/bin/install -d -o root -g root -m 0700 "$snapshot_material"
snapshot_helper="$snapshot/release-authority-manifest.sh"
stage=/etc/syntaur/.release-authority.bootstrap-v2-g1
shipper_stage=/usr/local/bin/.syntaur-ship.authority-bootstrap-v2-g1
provisioner_stage=/opt/.syntaur-build-authority-provision.bootstrap-v2-g1

cleanup_staging() {
    local path
    for path in "$snapshot" "$shipper_stage" "$provisioner_stage"; do
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
/usr/bin/sync -f "$snapshot"

validate_material \
    "$snapshot_material" \
    "$snapshot_helper" \
    0 \
    0 \
    400 \
    500

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
    [[ ! -e $temporary && ! -L $temporary ]] \
        || die "stale executable stage requires inspection: $temporary"
    /usr/bin/install -o root -g root -m 0755 "$source" "$temporary"
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

if [[ -e $AUTHORITY_ROOT || -L $AUTHORITY_ROOT ]]; then
    [[ -d $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'existing authority root is unsafe'
    [[ $(sha256sum "$AUTHORITY_ROOT/release-authority-v2.json" | awk '{print $1}') \
        == "$expected_manifest_sha256" ]] \
        || die 'a different authority root already exists'
    if ! installed_executable_is_exact \
        "$INSTALLED_PROVISIONER" "$expected_provisioner_sha256"; then
        install_exact_executable \
            "$snapshot_material/syntaur-build-authority-provision" \
            "$provisioner_stage" \
            "$INSTALLED_PROVISIONER" \
            "$expected_provisioner_sha256"
    fi
    if ! installed_executable_is_exact \
        "$INSTALLED_SHIPPER" "$expected_shipper_sha256"; then
        install_exact_executable \
            "$snapshot_material/syntaur-ship-linux-x86_64" \
            "$shipper_stage" \
            "$INSTALLED_SHIPPER" \
            "$expected_shipper_sha256"
    fi
    "$INSTALLED_SHIPPER" authority-status
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
/usr/bin/chmod 0555 "$generation_dir"

while IFS= read -r path; do
    /usr/bin/sync -f "$path"
done < <(/usr/bin/find "$stage" -depth -print)
/usr/bin/sync -f /etc/syntaur
/usr/bin/mv -T "$stage" "$AUTHORITY_ROOT"
/usr/bin/sync -f /etc/syntaur

install_exact_executable \
    "$snapshot_material/syntaur-build-authority-provision" \
    "$provisioner_stage" \
    "$INSTALLED_PROVISIONER" \
    "$expected_provisioner_sha256"
install_exact_executable \
    "$snapshot_material/syntaur-ship-linux-x86_64" \
    "$shipper_stage" \
    "$INSTALLED_SHIPPER" \
    "$expected_shipper_sha256"

"$INSTALLED_SHIPPER" authority-status
printf 'V2 authority genesis bootstrap installed: generation=1 manifest_sha256=%s\n' \
    "$expected_manifest_sha256"
