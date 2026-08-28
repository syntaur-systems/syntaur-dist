#!/usr/bin/bash
set -euo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

readonly COSIGN=/usr/local/bin/cosign
readonly COSIGN_SHA256=c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74
readonly COSIGN_IDENTITY=https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main
readonly COSIGN_ISSUER=https://token.actions.githubusercontent.com
readonly AUTHORITY_ROOT=/etc/syntaur/release-authority
readonly INSTALLED_SHIPPER=/usr/local/bin/syntaur-ship
readonly REPLACEMENT_LOCK=$AUTHORITY_ROOT/.authority-replacement-v1.lock
readonly RESOLUTION_PARENT=$AUTHORITY_ROOT/replacement-resolution-v1
readonly MANIFEST=release-authority-v2.json
readonly BUNDLE=release-authority-v2.json.cosign.bundle
readonly RESOLUTION=release-authority-replacement-v1.json
readonly RESOLUTION_BUNDLE=release-authority-replacement-v1.json.cosign.bundle
readonly RECOVERY_TOOL=recover-release-authority-replacement-v1.sh
readonly MANIFEST_HELPER=release-authority-manifest.sh

die() {
    printf 'release authority replacement recovery error: %s\n' "$*" >&2
    exit 1
}

usage() {
    /usr/bin/cat >&2 <<'EOF'
Usage:
  recover-release-authority-replacement-v1.sh verify \
    --predecessor-dir DIR --rejected-dir DIR --selected-dir DIR \
    --resolution-dir DIR --expected-resolution-sha256 HEX \
    --expected-predecessor-manifest-sha256 HEX \
    --expected-rejected-manifest-sha256 HEX \
    --expected-selected-manifest-sha256 HEX \
    --authorize-reason authority_target_mismatch

  sudo recover-release-authority-replacement-v1.sh install [same exact tuple]

Before executing this script, verify the resolution signature with the pinned
Cosign identity and verify this script's SHA-256 against the signed resolution.
Install writes only a root-owned resolution receipt, then delegates the actual
authority swap and live-product proof to the installed predecessor shipper.
EOF
    exit 2
}

sha256_file() {
    /usr/bin/sha256sum "$1" | /usr/bin/awk '{print $1}'
}

valid_sha256() {
    [[ $1 =~ ^[0-9a-f]{64}$ ]]
}

valid_commit() {
    [[ $1 =~ ^[0-9a-f]{40}$ ]]
}

canonical_dir() {
    local path=$1 label=$2 resolved
    [[ $path == /* && -d $path && ! -L $path ]] || die "$label is not a real absolute directory"
    resolved=$(/usr/bin/readlink -f -- "$path")
    [[ $resolved == "$path" ]] || die "$label is not canonical"
    printf '%s\n' "$resolved"
}

require_safe_file() {
    local path=$1 maximum=$2 executable=$3 label=$4 metadata mode
    [[ -f $path && ! -L $path ]] || die "$label is not a regular non-link file"
    metadata=$(/usr/bin/stat -c '%u:%g:%h:%s' "$path")
    [[ $metadata =~ ^[0-9]+:[0-9]+:1:([0-9]+)$ ]] || die "$label identity is unsafe"
    ((BASH_REMATCH[1] > 0 && BASH_REMATCH[1] <= maximum)) || die "$label size is unsafe"
    mode=$(/usr/bin/stat -c '%a' "$path")
    (( (8#$mode & 8#022) == 0 )) || die "$label is group/world writable"
    if [[ $executable == true ]]; then
        (( (8#$mode & 8#111) != 0 )) || die "$label is not executable"
    fi
}

require_safe_ancestors() {
    local path=$1 label=$2 current owner mode
    current=$path
    while :; do
        [[ -d $current && ! -L $current ]] || die "$label ancestor is not a real directory"
        owner=$(/usr/bin/stat -c '%u' "$current")
        mode=$(/usr/bin/stat -c '%a' "$current")
        [[ $owner == 0 || $owner == "$(/usr/bin/id -u)" \
            || ( ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && $owner == "$SUDO_UID" ) ]] \
            || die "$label ancestor has an unrelated owner"
        (( (8#$mode & 8#022) == 0 )) || die "$label ancestor is group/world writable"
        [[ $current == / ]] && break
        current=$(/usr/bin/dirname "$current")
    done
}

require_exact_authority_dir() {
    local directory=$1 label=$2 actual expected name executable
    require_safe_ancestors "$directory" "$label"
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
        | LC_ALL=C /usr/bin/sort)
    expected=$(/usr/bin/printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die "$label has an inexact file set"
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        require_safe_file "$directory/$name" 4194304 false "$label $name"
    done
    for name in syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        executable=true
        require_safe_file "$directory/$name" 268435456 "$executable" "$label $name"
    done
}

verify_cosign() {
    local payload=$1 bundle=$2 workflow_commit=$3 label=$4 cosign_home
    valid_commit "$workflow_commit" || die "$label workflow commit is malformed"
    require_safe_file "$COSIGN" 268435456 true 'pinned Cosign verifier'
    [[ $(sha256_file "$COSIGN") == "$COSIGN_SHA256" ]] || die 'pinned Cosign verifier differs'
    cosign_home=$(/usr/bin/mktemp -d /tmp/syntaur-authority-cosign.XXXXXX)
    [[ $cosign_home =~ ^/tmp/syntaur-authority-cosign\.[A-Za-z0-9]+$ ]] \
        || die 'Cosign temporary home is unsafe'
    /usr/bin/chmod 0700 "$cosign_home"
    if ! /usr/bin/env HOME="$cosign_home" "$COSIGN" verify-blob \
        --bundle "$bundle" \
        --certificate-identity "$COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$COSIGN_ISSUER" \
        --certificate-github-workflow-sha "$workflow_commit" \
        "$payload" >/dev/null; then
        /usr/bin/rm -rf -- "$cosign_home"
        die "$label signature verification failed"
    fi
    /usr/bin/rm -rf -- "$cosign_home"
}

resolution_value() {
    /usr/bin/jq -er --arg field "$2" '.[$field]' "$1"
}

manifest_value() {
    /usr/bin/jq -er --arg field "$2" '.[$field]' "$1"
}

validate_resolution_inline() {
    local record=$1
    /usr/bin/jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        (.schema == 1) and
        (.reason == "authority_target_mismatch") and
        (.predecessor_generation | type == "number" and . > 0 and floor == .) and
        (.rejected_generation == (.predecessor_generation + 1)) and
        (.selected_generation == .rejected_generation) and
        (.predecessor_manifest_sha256 | digest) and
        (.rejected_manifest_sha256 | digest) and
        (.selected_manifest_sha256 | digest) and
        (.rejected_manifest_sha256 != .selected_manifest_sha256) and
        (.rejected_workflow_commit | commit) and
        (.selected_workflow_commit | commit) and
        (.resolution_workflow_commit | commit) and
        (.recovery_tool_sha256 | digest) and
        (.manifest_helper_sha256 | digest)
    ' "$record" >/dev/null || die 'signed replacement resolution is malformed'
}

verify_inputs() {
    predecessor_dir=$(canonical_dir "$predecessor_dir" 'predecessor directory')
    rejected_dir=$(canonical_dir "$rejected_dir" 'rejected directory')
    selected_dir=$(canonical_dir "$selected_dir" 'selected directory')
    resolution_dir=$(canonical_dir "$resolution_dir" 'resolution directory')
    require_safe_ancestors "$resolution_dir" 'resolution directory'
    local actual_resolution expected_resolution
    actual_resolution=$(/usr/bin/find "$resolution_dir" -mindepth 1 -maxdepth 1 \
        -type f -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected_resolution=$(/usr/bin/printf '%s\n' \
        "$RECOVERY_TOOL" "$MANIFEST_HELPER" "$RESOLUTION" "$RESOLUTION_BUNDLE" \
        | LC_ALL=C /usr/bin/sort)
    [[ $actual_resolution == "$expected_resolution" ]] \
        || die 'resolution directory has an inexact file set'
    require_safe_file "$resolution_dir/$RESOLUTION" 32768 false 'replacement resolution'
    require_safe_file "$resolution_dir/$RESOLUTION_BUNDLE" 4194304 false \
        'replacement resolution signature bundle'
    require_safe_file "$resolution_dir/$RECOVERY_TOOL" 1048576 true 'replacement recovery tool'
    require_safe_file "$resolution_dir/$MANIFEST_HELPER" 1048576 true \
        'replacement manifest helper'
    [[ $(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}") == \
        "$resolution_dir/$RECOVERY_TOOL" ]] \
        || die 'recovery tool must run from the exact resolution directory'
    [[ $(sha256_file "$resolution_dir/$RESOLUTION") == "$expected_resolution_sha256" ]] \
        || die 'replacement resolution differs from the operator-authorized hash'
    validate_resolution_inline "$resolution_dir/$RESOLUTION"
    local resolution_workflow
    resolution_workflow=$(resolution_value "$resolution_dir/$RESOLUTION" \
        resolution_workflow_commit)
    verify_cosign "$resolution_dir/$RESOLUTION" "$resolution_dir/$RESOLUTION_BUNDLE" \
        "$resolution_workflow" 'replacement resolution'
    [[ $(sha256_file "$resolution_dir/$RECOVERY_TOOL") == \
        "$(resolution_value "$resolution_dir/$RESOLUTION" recovery_tool_sha256)" ]] \
        || die 'recovery tool differs from the signed resolution'
    [[ $(sha256_file "$resolution_dir/$MANIFEST_HELPER") == \
        "$(resolution_value "$resolution_dir/$RESOLUTION" manifest_helper_sha256)" ]] \
        || die 'manifest helper differs from the signed resolution'
    "$resolution_dir/$MANIFEST_HELPER" validate-replacement-resolution \
        "$resolution_dir/$RESOLUTION"
    "$resolution_dir/$MANIFEST_HELPER" validate-replacement-resolution-assets \
        "$resolution_dir"

    require_exact_authority_dir "$predecessor_dir" 'predecessor authority'
    require_exact_authority_dir "$rejected_dir" 'rejected authority'
    require_exact_authority_dir "$selected_dir" 'selected authority'
    local predecessor_manifest rejected_manifest selected_manifest
    predecessor_manifest=$predecessor_dir/$MANIFEST
    rejected_manifest=$rejected_dir/$MANIFEST
    selected_manifest=$selected_dir/$MANIFEST
    [[ $(sha256_file "$predecessor_manifest") == "$expected_predecessor_sha256" ]] \
        || die 'predecessor manifest differs from the operator-authorized hash'
    [[ $(sha256_file "$rejected_manifest") == "$expected_rejected_sha256" ]] \
        || die 'rejected manifest differs from the operator-authorized hash'
    [[ $(sha256_file "$selected_manifest") == "$expected_selected_sha256" ]] \
        || die 'selected manifest differs from the operator-authorized hash'
    local predecessor_generation rejected_generation selected_generation
    local predecessor_workflow rejected_workflow selected_workflow
    predecessor_generation=$(manifest_value "$predecessor_manifest" generation)
    rejected_generation=$(manifest_value "$rejected_manifest" generation)
    selected_generation=$(manifest_value "$selected_manifest" generation)
    predecessor_workflow=$(manifest_value "$predecessor_manifest" workflow_commit)
    rejected_workflow=$(manifest_value "$rejected_manifest" workflow_commit)
    selected_workflow=$(manifest_value "$selected_manifest" workflow_commit)
    "$resolution_dir/$MANIFEST_HELPER" validate "$predecessor_manifest" 2 \
        "$predecessor_generation" "$predecessor_workflow" "$predecessor_dir"
    "$resolution_dir/$MANIFEST_HELPER" validate "$rejected_manifest" 2 \
        "$rejected_generation" "$rejected_workflow" "$rejected_dir"
    "$resolution_dir/$MANIFEST_HELPER" validate "$selected_manifest" 2 \
        "$selected_generation" "$selected_workflow" "$selected_dir"
    "$resolution_dir/$MANIFEST_HELPER" assert-successor \
        "$predecessor_manifest" "$rejected_manifest"
    "$resolution_dir/$MANIFEST_HELPER" assert-successor \
        "$predecessor_manifest" "$selected_manifest"
    verify_cosign "$predecessor_manifest" "$predecessor_dir/$BUNDLE" \
        "$predecessor_workflow" 'predecessor authority'
    verify_cosign "$rejected_manifest" "$rejected_dir/$BUNDLE" \
        "$rejected_workflow" 'rejected authority'
    verify_cosign "$selected_manifest" "$selected_dir/$BUNDLE" \
        "$selected_workflow" 'selected authority'

    local record=$resolution_dir/$RESOLUTION
    [[ $(resolution_value "$record" reason) == "$authorize_reason" ]] \
        || die 'signed replacement reason differs from operator authorization'
    "$resolution_dir/$MANIFEST_HELPER" assert-replacement \
        "$predecessor_manifest" "$rejected_manifest" "$selected_manifest" "$record"
    [[ $rejected_generation == "$selected_generation" \
        && "$expected_rejected_sha256" != "$expected_selected_sha256" ]] \
        || die 'replacement is not one distinct manifest for the rejected generation'
}

sync_path() {
    /usr/bin/sync -f "$1"
}

discard_incomplete_resolution_stage() {
    local stage=$1 actual name metadata mode
    require_root_directory "$stage" 'incomplete replacement receipt stage'
    actual=$(/usr/bin/find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            "$RESOLUTION"|"$RESOLUTION_BUNDLE") ;;
            *) die 'incomplete replacement receipt stage contains an unexpected entry' ;;
        esac
        [[ -f $stage/$name && ! -L $stage/$name ]] \
            || die 'incomplete replacement receipt entry is unsafe'
        metadata=$(/usr/bin/stat -c '%u:%g:%h' "$stage/$name")
        [[ $metadata == 0:0:1 ]] \
            || die 'incomplete replacement receipt entry identity is unsafe'
        mode=$(/usr/bin/stat -c '%a' "$stage/$name")
        (( (8#$mode & 8#022) == 0 )) \
            || die 'incomplete replacement receipt entry is group/world writable'
    done <<<"$actual"
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        /usr/bin/rm -f -- "$stage/$name"
    done <<<"$actual"
    /usr/bin/rmdir -- "$stage"
    sync_path "$AUTHORITY_ROOT"
}

install_resolution_receipt() {
    local generation final stage name
    generation=$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)
    final=$RESOLUTION_PARENT/generation-$generation
    stage=$AUTHORITY_ROOT/.replacement-resolution-v1-g${generation}.staged
    require_root_directory "$AUTHORITY_ROOT" 'authority root'
    if [[ -e $RESOLUTION_PARENT || -L $RESOLUTION_PARENT ]]; then
        require_root_directory "$RESOLUTION_PARENT" 'replacement receipt parent'
    else
        /usr/bin/install -d -o 0 -g 0 -m 0755 "$RESOLUTION_PARENT"
        sync_path "$AUTHORITY_ROOT"
    fi
    if [[ -d $final && ! -L $final ]]; then
        [[ $(/usr/bin/find "$final" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
            | LC_ALL=C /usr/bin/sort) == \
            $(/usr/bin/printf '%s\n' "$RESOLUTION" "$RESOLUTION_BUNDLE" | LC_ALL=C /usr/bin/sort) ]] \
            || die 'existing replacement receipt directory is inexact'
        require_root_directory "$final" 'existing replacement receipt directory'
        require_root_file "$final/$RESOLUTION" 444 'existing signed replacement receipt'
        require_root_file "$final/$RESOLUTION_BUNDLE" 444 \
            'existing replacement receipt bundle'
        /usr/bin/cmp -s "$final/$RESOLUTION" "$resolution_dir/$RESOLUTION" \
            || die 'existing signed replacement receipt conflicts'
        /usr/bin/cmp -s "$final/$RESOLUTION_BUNDLE" "$resolution_dir/$RESOLUTION_BUNDLE" \
            || die 'existing replacement receipt bundle conflicts'
        return
    fi
    [[ ! -e $final && ! -L $final ]] \
        || die 'replacement receipt publication path is unsafe'
    if [[ -e $stage || -L $stage ]]; then
        [[ -d $stage && ! -L $stage ]] \
            || die 'replacement receipt stage is unsafe'
        discard_incomplete_resolution_stage "$stage"
    fi
    /usr/bin/install -d -o 0 -g 0 -m 0700 "$stage"
    for name in "$RESOLUTION" "$RESOLUTION_BUNDLE"; do
        /usr/bin/dd if="$resolution_dir/$name" of="$stage/$name" \
            iflag=nofollow,nonblock,fullblock status=none
        /usr/bin/chown 0:0 "$stage/$name"
        /usr/bin/chmod 0444 "$stage/$name"
        sync_path "$stage/$name"
        /usr/bin/cmp -s "$stage/$name" "$resolution_dir/$name" \
            || die 'staged replacement receipt changed during publication'
    done
    sync_path "$stage"
    /usr/bin/mv -T "$stage" "$final"
    sync_path "$RESOLUTION_PARENT"
}

require_root_directory() {
    local path=$1 label=$2 metadata mode
    [[ -d $path && ! -L $path ]] || die "$label is not a real directory"
    metadata=$(/usr/bin/stat -c '%u:%g:%h' "$path")
    [[ $metadata == 0:0:1 ]] || die "$label identity is unsafe"
    mode=$(/usr/bin/stat -c '%a' "$path")
    (( (8#$mode & 8#022) == 0 )) || die "$label is group/world writable"
}

require_root_file() {
    local path=$1 expected_mode=$2 label=$3
    [[ -f $path && ! -L $path ]] || die "$label is not a regular non-link file"
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$path") == "0:0:$expected_mode:1" ]] \
        || die "$label identity is unsafe"
}

run_operator_authority_status() {
    local operator_home
    operator_home=$(/usr/bin/getent passwd "$SUDO_UID" | /usr/bin/awk -F: \
        -v uid="$SUDO_UID" -v name="$SUDO_USER" \
        '$1 == name && $3 == uid { if (seen++) exit 2; print $6 }') \
        || die 'sudo operator account lookup failed'
    [[ $operator_home == /* && -d $operator_home && ! -L $operator_home ]] \
        || die 'sudo operator home is unsafe'
    /usr/bin/setpriv \
        --reuid "$SUDO_UID" \
        --regid "$SUDO_GID" \
        --clear-groups \
        /usr/bin/env -i \
            HOME="$operator_home" USER="$SUDO_USER" LOGNAME="$SUDO_USER" \
            PATH=/usr/sbin:/usr/bin:/sbin:/bin \
            LANG=C.UTF-8 LC_ALL=C.UTF-8 \
            "$INSTALLED_SHIPPER" authority-status >/dev/null
}

promote_selected_authority() {
    local selected_manifest=$selected_dir/$MANIFEST
    local -a args
    args=(
        authority-promote
        --source-dir "$selected_dir"
        --expected-generation "$(manifest_value "$selected_manifest" generation)"
        --expected-manifest-sha256 "$expected_selected_sha256"
        --expected-previous-generation "$(manifest_value "$selected_manifest" previous_generation)"
        --expected-previous-manifest-sha256 "$(manifest_value "$selected_manifest" previous_manifest_sha256)"
        --expected-authority-version "$(manifest_value "$selected_manifest" authority_version)"
        --expected-authority-commit "$(manifest_value "$selected_manifest" authority_commit)"
        --expected-workflow-commit "$(manifest_value "$selected_manifest" workflow_commit)"
        --expected-shipper-sha256 "$(manifest_value "$selected_manifest" shipper_sha256)"
        --expected-verifier-sha256 "$(manifest_value "$selected_manifest" verifier_sha256)"
        --expected-provisioner-sha256 "$(manifest_value "$selected_manifest" provisioner_sha256)"
        --expected-production-contract-sha256 "$(manifest_value "$selected_manifest" production_contract_sha256)"
        --expected-production-member-count "$(manifest_value "$selected_manifest" production_member_count)"
        --expected-receipt-schema "$(manifest_value "$selected_manifest" receipt_schema)"
        --expected-build-authority-schema "$(manifest_value "$selected_manifest" build_authority_schema)"
        --expected-promotion-recovery-schema "$(manifest_value "$selected_manifest" promotion_recovery_schema)"
        --expected-promotion-recovery-sha256 "$(manifest_value "$selected_manifest" promotion_recovery_sha256)"
    )
    local -a clean_env
    clean_env=(
        /usr/bin/env -i
        HOME=/root USER=root LOGNAME=root PATH=/usr/sbin:/usr/bin:/sbin:/bin
        LANG=C.UTF-8 LC_ALL=C.UTF-8
        SUDO_UID="$SUDO_UID" SUDO_GID="$SUDO_GID" SUDO_USER="$SUDO_USER"
    )
    "${clean_env[@]}" "$INSTALLED_SHIPPER" --dry-run "${args[@]}"
    "${clean_env[@]}" "$INSTALLED_SHIPPER" "${args[@]}"
}

[[ $# -ge 1 ]] || usage
mode=$1
shift
[[ $mode == verify || $mode == install ]] || usage

predecessor_dir=
rejected_dir=
selected_dir=
resolution_dir=
expected_resolution_sha256=
expected_predecessor_sha256=
expected_rejected_sha256=
expected_selected_sha256=
authorize_reason=
while (($#)); do
    [[ $# -ge 2 ]] || usage
    case $1 in
        --predecessor-dir) [[ -z $predecessor_dir ]] || usage; predecessor_dir=$2 ;;
        --rejected-dir) [[ -z $rejected_dir ]] || usage; rejected_dir=$2 ;;
        --selected-dir) [[ -z $selected_dir ]] || usage; selected_dir=$2 ;;
        --resolution-dir) [[ -z $resolution_dir ]] || usage; resolution_dir=$2 ;;
        --expected-resolution-sha256)
            [[ -z $expected_resolution_sha256 ]] || usage
            expected_resolution_sha256=$2
            ;;
        --expected-predecessor-manifest-sha256)
            [[ -z $expected_predecessor_sha256 ]] || usage
            expected_predecessor_sha256=$2
            ;;
        --expected-rejected-manifest-sha256)
            [[ -z $expected_rejected_sha256 ]] || usage
            expected_rejected_sha256=$2
            ;;
        --expected-selected-manifest-sha256)
            [[ -z $expected_selected_sha256 ]] || usage
            expected_selected_sha256=$2
            ;;
        --authorize-reason) [[ -z $authorize_reason ]] || usage; authorize_reason=$2 ;;
        *) usage ;;
    esac
    shift 2
done
for value in "$predecessor_dir" "$rejected_dir" "$selected_dir" "$resolution_dir"; do
    [[ -n $value ]] || usage
done
for digest in "$expected_resolution_sha256" "$expected_predecessor_sha256" \
    "$expected_rejected_sha256" "$expected_selected_sha256"; do
    valid_sha256 "$digest" || usage
done
[[ $authorize_reason == authority_target_mismatch ]] || usage
if /usr/bin/env | /usr/bin/cut -d= -f1 | /usr/bin/grep -Eq '^SYNTAUR_'; then
    die 'ambient SYNTAUR_* overrides are forbidden'
fi

if [[ $mode == install ]]; then
    [[ $(/usr/bin/id -u) == 0 ]] || die 'install requires sudo and an all-root identity'
    [[ $(/usr/bin/hostname) == claudevm ]] || die 'install may run only on claudevm'
    [[ ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && ${SUDO_GID:-} =~ ^[0-9]+$ \
        && ${SUDO_USER:-} =~ ^[A-Za-z0-9_-]+$ ]] \
        || die 'install requires an exact non-root sudo operator identity'
    /usr/bin/grep -Eq '^Uid:[[:space:]]+0[[:space:]]+0[[:space:]]+0[[:space:]]+0$' \
        /proc/self/status || die 'install requires all-root real/effective/saved/filesystem UIDs'
    /usr/bin/grep -Eq '^Gid:[[:space:]]+0[[:space:]]+0[[:space:]]+0[[:space:]]+0$' \
        /proc/self/status || die 'install requires all-root real/effective/saved/filesystem GIDs'
fi

verify_inputs
if [[ $mode == verify ]]; then
    printf 'release authority replacement evidence verified: predecessor=%s rejected=%s selected=%s resolution=%s\n' \
        "$expected_predecessor_sha256" "$expected_rejected_sha256" \
        "$expected_selected_sha256" "$expected_resolution_sha256"
    exit 0
fi

require_safe_file "$INSTALLED_SHIPPER" 268435456 true 'installed predecessor shipper'
require_safe_file "$AUTHORITY_ROOT/$MANIFEST" 32768 false 'installed predecessor manifest'
require_root_directory "$AUTHORITY_ROOT" 'authority root'
if [[ -e $REPLACEMENT_LOCK || -L $REPLACEMENT_LOCK ]]; then
    require_root_file "$REPLACEMENT_LOCK" 600 'authority replacement lock'
fi
exec 7<>"$REPLACEMENT_LOCK"
/usr/bin/chown 0:0 "$REPLACEMENT_LOCK"
/usr/bin/chmod 0600 "$REPLACEMENT_LOCK"
require_root_file "$REPLACEMENT_LOCK" 600 'authority replacement lock'
/usr/bin/flock -n 7 || die 'another authority replacement recovery holds the lock'
active_manifest_sha256=$(sha256_file "$AUTHORITY_ROOT/$MANIFEST")
if [[ $active_manifest_sha256 == "$expected_selected_sha256" ]]; then
    install_resolution_receipt
    run_operator_authority_status
    printf 'release authority replacement already complete: generation=%s manifest_sha256=%s\n' \
        "$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)" \
        "$expected_selected_sha256"
    exit 0
fi
[[ $active_manifest_sha256 == "$expected_predecessor_sha256" ]] \
    || die 'installed authority is neither the exact predecessor nor selected replacement'
[[ $(sha256_file "$INSTALLED_SHIPPER") == \
    "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" ]] \
    || die 'installed predecessor shipper differs from the signed predecessor manifest'
install_resolution_receipt
promote_selected_authority
[[ $(sha256_file "$AUTHORITY_ROOT/$MANIFEST") == "$expected_selected_sha256" ]] \
    || die 'installed authority does not match the selected replacement after promotion'
printf 'release authority replacement complete: generation=%s manifest_sha256=%s\n' \
    "$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)" \
    "$expected_selected_sha256"
