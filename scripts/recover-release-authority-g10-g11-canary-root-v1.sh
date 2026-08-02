#!/usr/bin/bash
set -euo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

readonly COSIGN=/usr/local/bin/cosign
readonly COSIGN_SHA256=c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74
readonly COSIGN_IDENTITY=https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main
readonly COSIGN_ISSUER=https://token.actions.githubusercontent.com
readonly MANIFEST_HELPER_SHA256=76b12e8b14d75e206ec2498448955e33dfc2fc23a315a7c126fdca9c141cfa8d

readonly G10_MANIFEST_SHA256=b44fb0d78648f769c7be4bb9192bf6ed7882d11c1568a73d42261791405648a1
readonly G10_BUNDLE_SHA256=bc1b102f5ecc4e6aaf5989d6abeba7333012d9d2f1c53729dd7aca324c68dd2b
readonly G10_WORKFLOW_COMMIT=b388db8ff9259483a8d5989ce20aa9d7264a0ccf
readonly G10_SHIPPER_SHA256=336640d1564b364cbbc783b8121ed6018f653666f0c6006d4040f86495285f19
readonly G10_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G10_PROVISIONER_SHA256=c6755245d7884153c9cbd073d26b6d5940fd13459be46a701d561752afda044e

readonly G11_MANIFEST_SHA256=95d68eab9220f84df813437a4bded4f46db84088ce39526d9c7db08c6be01090
readonly G11_BUNDLE_SHA256=a4e90dfdba44cbcff1755ee1e3405ee5f612aaf0b6782d5e04c4aa0857000fb5
readonly G11_WORKFLOW_COMMIT=0ba6d0196668c6b7818efd4b7e5a1f92d80166f7
readonly G11_SHIPPER_SHA256=bfa75a5c7aa1af9a3d03cfd800d5221c6e8fe2717a697f1046245d8648793cc5
readonly G11_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G11_PROVISIONER_SHA256=c6755245d7884153c9cbd073d26b6d5940fd13459be46a701d561752afda044e

readonly AUTHORITY_ROOT=/etc/syntaur/release-authority
readonly ARTIFACT_ROOT=$AUTHORITY_ROOT/release-authority
readonly ROOT_LOCK=$AUTHORITY_ROOT/.authority-promotion.lock
readonly NORMAL_PROMOTION_JOURNAL=$AUTHORITY_ROOT/authority-promotion-v1.json
readonly NORMAL_PROMOTION_JOURNAL_TEMP=$AUTHORITY_ROOT/.authority-promotion-v1.json.tmp
readonly RECOVERY_JOURNAL=$AUTHORITY_ROOT/authority-g10-g11-recovery-v1.json
readonly RECOVERY_JOURNAL_TEMP=$AUTHORITY_ROOT/.authority-g10-g11-recovery-v1.json.tmp
readonly RECOVERY_STAGE=$ARTIFACT_ROOT/.generation-11-g10-g11-recovery-v1.staged
readonly RECOVERY_SNAPSHOT=$AUTHORITY_ROOT/.authority-g10-g11-recovery-v1.inputs
readonly RECOVERY_SNAPSHOT_STAGE=$AUTHORITY_ROOT/.authority-g10-g11-recovery-v1.inputs.staged
readonly RECOVERY_SNAPSHOT_RETIRED=$AUTHORITY_ROOT/.authority-g10-g11-recovery-v1.inputs.retiring
readonly RECOVERY_RECEIPT=/etc/syntaur/release-authority-g10-g11-recovery-v1.receipt.json
readonly GLOBAL_MUTATION_LOCK=/etc/syntaur/syntaur-ship-mutation.lock
readonly OPERATOR_STATE=/home/sean/.syntaur/ship
readonly DEPLOYMENT_LOCK=$OPERATOR_STATE/deploy.lock
readonly INSTALLED_SHIPPER=/usr/local/bin/syntaur-ship
readonly INSTALLED_PROVISIONER=/opt/syntaur-build-authority-provision
readonly SEALED_RUNTIME_ROOT=/etc/syntaur/release-authority-g10-g11-recovery-v1.runtime

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly SOURCE_MANIFEST_HELPER=$script_dir/release-authority-manifest.sh
manifest_helper=$SOURCE_MANIFEST_HELPER

die() {
    printf 'release authority G10-G11 active-root recovery error: %s\n' "$*" >&2
    exit 1
}

usage() {
    /usr/bin/cat >&2 <<'EOF'
Usage:
  recover-release-authority-g10-g11-canary-root-v1.sh verify \
    --g10-dir DIR --g11-dir DIR

  sudo recover-release-authority-g10-g11-canary-root-v1.sh install \
    --g10-dir DIR --g11-dir DIR \
    --expected-current-shipper-sha256 HEX

This fixed recovery moves one already-installed exact G10 authority root to
its exact immutable G11 successor. It does not touch product source, release
state, TrueNAS, cameras, NVR, or Frame. Installation publishes the active G11
manifest last and is forward-resumable from its root-owned journal.
EOF
    exit 2
}

sha256_file() {
    /usr/bin/sha256sum "$1" | /usr/bin/awk '{print $1}'
}

valid_sha256() {
    [[ $1 =~ ^[0-9a-f]{64}$ ]]
}

sync_path() {
    /usr/bin/sync -f "$1"
}

require_regular() {
    local path=$1 uid=$2 gid=$3 mode=$4 links=$5 label=$6
    [[ -f $path && ! -L $path ]] || die "$label is not a regular non-link file"
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$path") == \
        "$uid:$gid:$mode:$links" ]] || die "$label identity differs"
}

require_directory() {
    local path=$1 uid=$2 gid=$3 mode=$4 label=$5
    [[ -d $path && ! -L $path ]] || die "$label is not a real directory"
    [[ $(/usr/bin/stat -c '%u:%g:%a' "$path") == \
        "$uid:$gid:$mode" ]] || die "$label identity differs"
}

require_sealed_runtime() {
    local actual expected
    [[ $script_dir == "$SEALED_RUNTIME_ROOT" ]] \
        || die 'installation must run from the sealed root-owned recovery runtime'
    require_directory "$SEALED_RUNTIME_ROOT" 0 0 700 'sealed recovery runtime'
    expected=$(/usr/bin/printf '%s\n' \
        recover-release-authority-g10-g11-canary-root-v1.sh \
        release-authority-manifest.sh | LC_ALL=C /usr/bin/sort)
    actual=$(/usr/bin/find "$SEALED_RUNTIME_ROOT" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'sealed recovery runtime is inexact'
    require_regular "${BASH_SOURCE[0]}" 0 0 500 1 'sealed recovery script'
    require_regular "$SOURCE_MANIFEST_HELPER" 0 0 500 1 \
        'sealed recovery manifest helper'
    [[ $(sha256_file "$SOURCE_MANIFEST_HELPER") == \
        "$MANIFEST_HELPER_SHA256" ]] || die 'sealed recovery helper differs'
}

discard_safe_root_temporary() {
    local path=$1 maximum=$2 label=$3 identity mode parent
    [[ -e $path || -L $path ]] || return 0
    [[ -f $path && ! -L $path ]] || die "$label is not a regular non-link file"
    identity=$(/usr/bin/stat -c '%u:%g:%h' "$path")
    mode=$(/usr/bin/stat -c '%a' "$path")
    [[ $identity == 0:0:1 ]] || die "$label identity differs"
    (( (8#$mode & 8#022) == 0 )) || die "$label is group/world writable"
    [[ $(/usr/bin/stat -c '%s' "$path") -le "$maximum" ]] \
        || die "$label is oversized"
    parent=$(/usr/bin/dirname "$path")
    /usr/bin/rm -f -- "$path"
    sync_path "$parent"
}

publication_temporary_path() {
    local destination=$1 parent
    parent=$(/usr/bin/dirname "$destination")
    /usr/bin/printf '%s/.%s.g10-g11-recovery-v1\n' \
        "$parent" "$(/usr/bin/basename "$destination")"
}

preflight_recovery_temporaries() {
    local temporary
    if [[ ( -e $RECOVERY_SNAPSHOT || -L $RECOVERY_SNAPSHOT ) \
        && ( -e $RECOVERY_SNAPSHOT_RETIRED \
            || -L $RECOVERY_SNAPSHOT_RETIRED ) ]]; then
        die 'recovery input snapshot and retiring snapshot both exist'
    fi
    discard_snapshot_tree "$RECOVERY_SNAPSHOT_RETIRED"
    discard_safe_root_temporary "$RECOVERY_JOURNAL_TEMP" 4096 \
        'recovery journal temporary file'
    discard_safe_root_temporary "$RECOVERY_RECEIPT.tmp" 4096 \
        'recovery receipt temporary file'
    temporary=$(publication_temporary_path "$INSTALLED_SHIPPER")
    discard_safe_root_temporary "$temporary" 268435456 \
        'shipper publication temporary file'
    temporary=$(publication_temporary_path "$AUTHORITY_ROOT/trusted-workflow-commit")
    discard_safe_root_temporary "$temporary" 128 \
        'workflow publication temporary file'
    temporary=$(publication_temporary_path \
        "$AUTHORITY_ROOT/release-authority-v2.json.cosign.bundle")
    discard_safe_root_temporary "$temporary" 4194304 \
        'bundle publication temporary file'
    temporary=$(publication_temporary_path \
        "$AUTHORITY_ROOT/release-authority-v2.json")
    discard_safe_root_temporary "$temporary" 1048576 \
        'manifest publication temporary file'
    discard_recovery_stage
}

retire_recovery_snapshot() {
    [[ -e $RECOVERY_SNAPSHOT || -L $RECOVERY_SNAPSHOT ]] \
        || die 'recovery input snapshot is missing at retirement'
    [[ ! -e $RECOVERY_SNAPSHOT_RETIRED \
        && ! -L $RECOVERY_SNAPSHOT_RETIRED ]] \
        || die 'recovery input retirement path exists'
    validate_recovery_snapshot
    /usr/bin/mv -T "$RECOVERY_SNAPSHOT" "$RECOVERY_SNAPSHOT_RETIRED"
    sync_path "$AUTHORITY_ROOT"
    discard_snapshot_tree "$RECOVERY_SNAPSHOT_RETIRED"
}

validate_source_ancestors() {
    local path=$1 operator_uid=$2 current owner mode
    [[ $path == /* && $(/usr/bin/readlink -f -- "$path") == "$path" ]] \
        || die 'release material path is not canonical and absolute'
    current=$path
    while :; do
        [[ -d $current && ! -L $current ]] \
            || die 'release material ancestor is not a real directory'
        owner=$(/usr/bin/stat -c '%u' "$current")
        mode=$(/usr/bin/stat -c '%a' "$current")
        [[ $owner == 0 || $owner == "$operator_uid" ]] \
            || die 'release material ancestor has an unrelated owner'
        (( (8#$mode & 8#022) == 0 )) \
            || die 'release material ancestor is group/world writable'
        [[ $current == / ]] && break
        current=$(/usr/bin/dirname "$current")
    done
}

validate_material_layout() {
    local material=$1 generation=$2 owner_uid=$3 owner_gid=$4
    local directory_mode=$5 data_mode=$6 executable_mode=$7
    local actual expected name
    validate_source_ancestors "$material" "$owner_uid"
    require_directory "$material" "$owner_uid" "$owner_gid" "$directory_mode" \
        "G$generation release directory"
    expected=$(/usr/bin/printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 | LC_ALL=C /usr/bin/sort)
    actual=$(/usr/bin/find "$material" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] \
        || die "G$generation release directory has an inexact file set"
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle; do
        require_regular "$material/$name" "$owner_uid" "$owner_gid" \
            "$data_mode" 1 "G$generation $name"
    done
    for name in syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
        require_regular "$material/$name" "$owner_uid" "$owner_gid" \
            "$executable_mode" 1 "G$generation $name"
    done
}

validate_material() {
    local material=$1 generation=$2 manifest_sha=$3 bundle_sha=$4
    local workflow=$5 shipper_sha=$6 verifier_sha=$7 provisioner_sha=$8
    local owner_uid=$9 owner_gid=${10} directory_mode=${11}
    local data_mode=${12} executable_mode=${13}
    validate_material_layout "$material" "$generation" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    [[ $(sha256_file "$material/release-authority-v2.json") == \
        "$manifest_sha" ]] || die "G$generation manifest digest differs"
    [[ $(sha256_file "$material/release-authority-v2.json.cosign.bundle") == \
        "$bundle_sha" ]] || die "G$generation bundle digest differs"
    [[ $(sha256_file "$material/syntaur-ship-linux-x86_64") == \
        "$shipper_sha" ]] || die "G$generation shipper digest differs"
    [[ $(sha256_file "$material/syntaur-verify-linux-x86_64") == \
        "$verifier_sha" ]] || die "G$generation verifier digest differs"
    [[ $(sha256_file "$material/syntaur-build-authority-provision") == \
        "$provisioner_sha" ]] || die "G$generation provisioner digest differs"
    "$manifest_helper" validate \
        "$material/release-authority-v2.json" 2 "$generation" \
        "$workflow" "$material"
    "$COSIGN" verify-blob \
        --bundle "$material/release-authority-v2.json.cosign.bundle" \
        --certificate-identity "$COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$COSIGN_ISSUER" \
        --certificate-github-workflow-sha "$workflow" \
        "$material/release-authority-v2.json" >/dev/null
}

verify_release_material() {
    local g10_dir=$1 g11_dir=$2 operator_uid=$3 operator_gid=$4
    local directory_mode=${5:-500} data_mode=${6:-400}
    local executable_mode=${7:-500}
    valid_sha256 "$G11_MANIFEST_SHA256" \
        || die 'G11 manifest digest was not fixed before publication'
    valid_sha256 "$G11_BUNDLE_SHA256" \
        || die 'G11 bundle digest was not fixed before publication'
    require_regular "$COSIGN" 0 0 755 1 'pinned Cosign binary'
    [[ $(sha256_file "$COSIGN") == "$COSIGN_SHA256" ]] \
        || die 'pinned Cosign binary digest differs'
    [[ -f $manifest_helper && ! -L $manifest_helper ]] \
        || die 'manifest helper is unsafe'
    [[ $(sha256_file "$manifest_helper") == "$MANIFEST_HELPER_SHA256" ]] \
        || die 'manifest helper digest differs'
    [[ $g10_dir != "$g11_dir" ]] || die 'G10 and G11 directories must differ'
    validate_material "$g10_dir" 10 \
        "$G10_MANIFEST_SHA256" "$G10_BUNDLE_SHA256" \
        "$G10_WORKFLOW_COMMIT" "$G10_SHIPPER_SHA256" \
        "$G10_VERIFIER_SHA256" "$G10_PROVISIONER_SHA256" \
        "$operator_uid" "$operator_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_material "$g11_dir" 11 \
        "$G11_MANIFEST_SHA256" "$G11_BUNDLE_SHA256" \
        "$G11_WORKFLOW_COMMIT" "$G11_SHIPPER_SHA256" \
        "$G11_VERIFIER_SHA256" "$G11_PROVISIONER_SHA256" \
        "$operator_uid" "$operator_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    "$manifest_helper" assert-successor \
        "$g10_dir/release-authority-v2.json" \
        "$g11_dir/release-authority-v2.json"
}

snapshot_file() {
    local source=$1 target=$2 mode=$3 maximum=$4
    /usr/bin/timeout 30 /usr/bin/dd \
        if="$source" of="$target" \
        iflag=nofollow,nonblock,fullblock,count_bytes \
        count="$((maximum + 1))" status=none
    [[ -f $target && ! -L $target ]] \
        || die 'recovery input snapshot is not regular'
    [[ $(/usr/bin/stat -c '%s' "$target") -le "$maximum" ]] \
        || die 'recovery input snapshot exceeds its fixed bound'
    /usr/bin/chown root:root "$target"
    /usr/bin/chmod "$mode" "$target"
    require_regular "$target" 0 0 "$mode" 1 'recovery input snapshot file'
    sync_path "$target"
}

snapshot_release() {
    local source=$1 target=$2
    snapshot_file "$source/release-authority-v2.json" \
        "$target/release-authority-v2.json" 400 1048576
    snapshot_file "$source/release-authority-v2.json.cosign.bundle" \
        "$target/release-authority-v2.json.cosign.bundle" 400 4194304
    snapshot_file "$source/syntaur-build-authority-provision" \
        "$target/syntaur-build-authority-provision" 500 16777216
    snapshot_file "$source/syntaur-ship-linux-x86_64" \
        "$target/syntaur-ship-linux-x86_64" 500 268435456
    snapshot_file "$source/syntaur-verify-linux-x86_64" \
        "$target/syntaur-verify-linux-x86_64" 500 268435456
}

partial_snapshot_file_is_safe() {
    local path=$1 maximum=$2 identity mode
    [[ -f $path && ! -L $path ]] || return 1
    identity=$(/usr/bin/stat -c '%u:%g:%h' "$path")
    mode=$(/usr/bin/stat -c '%a' "$path")
    [[ $identity == 0:0:1 ]] || return 1
    (( (8#$mode & 8#022) == 0 )) || return 1
    [[ $(/usr/bin/stat -c '%s' "$path") -le "$maximum" ]]
}

discard_snapshot_tree() {
    local root=$1 actual name generation directory path maximum
    [[ -e $root || -L $root ]] || return 0
    require_directory "$root" 0 0 700 'partial recovery input snapshot'
    actual=$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            generation-10|generation-11|release-authority-manifest.sh) ;;
            *) die 'partial recovery input snapshot has an unexpected entry' ;;
        esac
    done <<<"$actual"
    for generation in 10 11; do
        directory=$root/generation-$generation
        if [[ -e $directory || -L $directory ]]; then
            require_directory "$directory" 0 0 700 \
                'partial recovery input generation'
            actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
                -printf '%f\n' | LC_ALL=C /usr/bin/sort)
            while IFS= read -r name; do
                [[ -z $name ]] && continue
                case $name in
                    release-authority-v2.json) maximum=1048577 ;;
                    release-authority-v2.json.cosign.bundle) maximum=4194305 ;;
                    syntaur-build-authority-provision) maximum=16777217 ;;
                    syntaur-ship-linux-x86_64|syntaur-verify-linux-x86_64)
                        maximum=268435457
                        ;;
                    *) die 'partial recovery input generation has an unexpected entry' ;;
                esac
                path=$directory/$name
                partial_snapshot_file_is_safe "$path" "$maximum" \
                    || die 'partial recovery input generation contains unsafe material'
                /usr/bin/rm -f -- "$path"
            done <<<"$actual"
            /usr/bin/rmdir "$directory"
        fi
    done
    path=$root/release-authority-manifest.sh
    if [[ -e $path || -L $path ]]; then
        partial_snapshot_file_is_safe "$path" 1048577 \
            || die 'partial recovery helper snapshot is unsafe'
        /usr/bin/rm -f -- "$path"
    fi
    /usr/bin/rmdir "$root"
    sync_path "$AUTHORITY_ROOT"
}

validate_recovery_snapshot() {
    local root=${1:-$RECOVERY_SNAPSHOT} actual expected
    require_directory "$root" 0 0 700 'recovery input snapshot'
    expected=$(/usr/bin/printf '%s\n' \
        generation-10 generation-11 release-authority-manifest.sh \
        | LC_ALL=C /usr/bin/sort)
    actual=$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] \
        || die 'recovery input snapshot has an inexact entry set'
    require_regular "$root/release-authority-manifest.sh" \
        0 0 500 1 'recovery manifest helper snapshot'
    [[ $(sha256_file "$root/release-authority-manifest.sh") == \
        "$MANIFEST_HELPER_SHA256" ]] || die 'recovery helper snapshot differs'
    manifest_helper=$root/release-authority-manifest.sh
    verify_release_material \
        "$root/generation-10" "$root/generation-11" 0 0 700 400 500
}

require_sources_match_snapshot() {
    local g10_dir=$1 g11_dir=$2 operator_uid=$3 operator_gid=$4
    local generation source name
    validate_material_layout "$g10_dir" 10 \
        "$operator_uid" "$operator_gid" 500 400 500
    validate_material_layout "$g11_dir" 11 \
        "$operator_uid" "$operator_gid" 500 400 500
    for generation in 10 11; do
        if [[ $generation == 10 ]]; then source=$g10_dir; else source=$g11_dir; fi
        for name in release-authority-v2.json \
            release-authority-v2.json.cosign.bundle \
            syntaur-build-authority-provision \
            syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
            /usr/bin/cmp -s "$source/$name" \
                "$RECOVERY_SNAPSHOT/generation-$generation/$name" \
                || die "G$generation source changed or differs from sealed inputs"
        done
    done
    /usr/bin/cmp -s "$SOURCE_MANIFEST_HELPER" \
        "$RECOVERY_SNAPSHOT/release-authority-manifest.sh" \
        || die 'source manifest helper differs from sealed inputs'
}

prepare_recovery_snapshot() {
    local g10_dir=$1 g11_dir=$2 operator_uid=$3 operator_gid=$4
    local resume=$5 path
    if [[ -e $RECOVERY_SNAPSHOT || -L $RECOVERY_SNAPSHOT ]]; then
        [[ ! -e $RECOVERY_SNAPSHOT_STAGE && ! -L $RECOVERY_SNAPSHOT_STAGE ]] \
            || die 'recovery input snapshot and staging path both exist'
        validate_recovery_snapshot
        if [[ $resume != true ]]; then
            require_sources_match_snapshot \
                "$g10_dir" "$g11_dir" "$operator_uid" "$operator_gid"
        fi
        return 0
    fi
    [[ $resume != true ]] \
        || die 'journaled recovery is missing its sealed input snapshot'
    if [[ -e $RECOVERY_SNAPSHOT_STAGE || -L $RECOVERY_SNAPSHOT_STAGE ]]; then
        discard_snapshot_tree "$RECOVERY_SNAPSHOT_STAGE"
    fi
    validate_material_layout "$g10_dir" 10 \
        "$operator_uid" "$operator_gid" 500 400 500
    validate_material_layout "$g11_dir" 11 \
        "$operator_uid" "$operator_gid" 500 400 500
    /usr/bin/install -d -o root -g root -m 0700 \
        "$RECOVERY_SNAPSHOT_STAGE" \
        "$RECOVERY_SNAPSHOT_STAGE/generation-10" \
        "$RECOVERY_SNAPSHOT_STAGE/generation-11"
    snapshot_release "$g10_dir" "$RECOVERY_SNAPSHOT_STAGE/generation-10"
    snapshot_release "$g11_dir" "$RECOVERY_SNAPSHOT_STAGE/generation-11"
    snapshot_file "$SOURCE_MANIFEST_HELPER" \
        "$RECOVERY_SNAPSHOT_STAGE/release-authority-manifest.sh" 500 1048576
    while IFS= read -r path; do sync_path "$path"; done \
        < <(/usr/bin/find "$RECOVERY_SNAPSHOT_STAGE" -depth -print)
    validate_recovery_snapshot "$RECOVERY_SNAPSHOT_STAGE"
    /usr/bin/mv -T "$RECOVERY_SNAPSHOT_STAGE" "$RECOVERY_SNAPSHOT"
    sync_path "$AUTHORITY_ROOT"
    validate_recovery_snapshot
    require_sources_match_snapshot \
        "$g10_dir" "$g11_dir" "$operator_uid" "$operator_gid"
}

workflow_file_sha256() {
    /usr/bin/printf '%s\n' "$1" | /usr/bin/sha256sum | /usr/bin/awk '{print $1}'
}

installed_executable_is_exact() {
    local path=$1 digest=$2 mode=$3
    [[ -f $path && ! -L $path ]] || return 1
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$path") == "0:0:$mode:1" ]] \
        || return 1
    [[ $(sha256_file "$path") == "$digest" ]]
}

validate_installed_generation() {
    local generation=$1 material=$2 workflow=$3 directory name actual expected
    directory=$ARTIFACT_ROOT/generation-$generation
    require_directory "$directory" 0 0 555 "installed G$generation directory"
    expected=$(/usr/bin/printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C /usr/bin/sort)
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] \
        || die "installed G$generation has an inexact file set"
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle trusted-workflow-commit; do
        require_regular "$directory/$name" 0 0 444 1 \
            "installed G$generation $name"
    done
    for name in syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
        require_regular "$directory/$name" 0 0 555 1 \
            "installed G$generation $name"
    done
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        /usr/bin/cmp -s "$directory/$name" "$material/$name" \
            || die "installed G$generation bytes differ: $name"
    done
    [[ $(<"$directory/trusted-workflow-commit") == "$workflow" \
        && $(/usr/bin/wc -l <"$directory/trusted-workflow-commit") -eq 1 ]] \
        || die "installed G$generation workflow trust differs"
}

validate_retained_chain() {
    local maximum=$1 generation directory workflow previous=
    local actual expected name
    expected=$(/usr/bin/seq 1 "$maximum" | /usr/bin/sed 's/^/generation-/' \
        | LC_ALL=C /usr/bin/sort)
    actual=$(/usr/bin/find "$ARTIFACT_ROOT" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'installed retained generation set differs'
    for generation in $(/usr/bin/seq 1 "$maximum"); do
        directory=$ARTIFACT_ROOT/generation-$generation
        require_directory "$directory" 0 0 555 \
            "installed retained generation $generation"
        expected=$(/usr/bin/printf '%s\n' \
            release-authority-v2.json \
            release-authority-v2.json.cosign.bundle \
            syntaur-build-authority-provision \
            syntaur-ship-linux-x86_64 \
            syntaur-verify-linux-x86_64 \
            trusted-workflow-commit | LC_ALL=C /usr/bin/sort)
        actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C /usr/bin/sort)
        [[ $actual == "$expected" ]] \
            || die "installed generation $generation has an inexact file set"
        for name in release-authority-v2.json \
            release-authority-v2.json.cosign.bundle trusted-workflow-commit; do
            require_regular "$directory/$name" 0 0 444 1 \
                "installed generation $generation $name"
        done
        for name in syntaur-build-authority-provision \
            syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
            require_regular "$directory/$name" 0 0 555 1 \
                "installed generation $generation $name"
        done
        workflow=$(<"$directory/trusted-workflow-commit")
        [[ $workflow =~ ^[0-9a-f]{40}$ \
            && $(/usr/bin/wc -l <"$directory/trusted-workflow-commit") -eq 1 ]] \
            || die "installed generation $generation workflow trust is malformed"
        "$manifest_helper" validate \
            "$directory/release-authority-v2.json" 2 "$generation" \
            "$workflow" "$directory"
        "$COSIGN" verify-blob \
            --bundle "$directory/release-authority-v2.json.cosign.bundle" \
            --certificate-identity "$COSIGN_IDENTITY" \
            --certificate-oidc-issuer "$COSIGN_ISSUER" \
            --certificate-github-workflow-sha "$workflow" \
            "$directory/release-authority-v2.json" >/dev/null
        if [[ -n $previous ]]; then
            "$manifest_helper" assert-successor \
                "$previous/release-authority-v2.json" \
                "$directory/release-authority-v2.json"
        fi
        previous=$directory
    done
}

validate_active_copy() {
    local generation=$1 material=$2 workflow=$3 name
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle; do
        require_regular "$AUTHORITY_ROOT/$name" 0 0 444 1 \
            "active G$generation $name"
        /usr/bin/cmp -s "$AUTHORITY_ROOT/$name" "$material/$name" \
            || die "active G$generation $name differs"
    done
    require_regular "$AUTHORITY_ROOT/trusted-workflow-commit" 0 0 444 1 \
        "active G$generation workflow trust"
    [[ $(<"$AUTHORITY_ROOT/trusted-workflow-commit") == "$workflow" \
        && $(/usr/bin/wc -l <"$AUTHORITY_ROOT/trusted-workflow-commit") -eq 1 ]] \
        || die "active G$generation workflow trust differs"
}

validate_fixed_installed_generation() {
    local generation=$1 manifest_sha=$2 bundle_sha=$3 workflow=$4
    local shipper_sha=$5 verifier_sha=$6 provisioner_sha=$7 directory
    directory=$ARTIFACT_ROOT/generation-$generation
    validate_installed_generation "$generation" "$directory" "$workflow"
    [[ $(sha256_file "$directory/release-authority-v2.json") == \
        "$manifest_sha" ]] || die "installed G$generation manifest digest differs"
    [[ $(sha256_file \
        "$directory/release-authority-v2.json.cosign.bundle") == \
        "$bundle_sha" ]] || die "installed G$generation bundle digest differs"
    [[ $(sha256_file "$directory/syntaur-ship-linux-x86_64") == \
        "$shipper_sha" ]] || die "installed G$generation shipper digest differs"
    [[ $(sha256_file "$directory/syntaur-verify-linux-x86_64") == \
        "$verifier_sha" ]] || die "installed G$generation verifier digest differs"
    [[ $(sha256_file "$directory/syntaur-build-authority-provision") == \
        "$provisioner_sha" ]] \
        || die "installed G$generation provisioner digest differs"
}

validate_complete_installed_g11() {
    require_regular "$COSIGN" 0 0 755 1 'pinned Cosign binary'
    [[ $(sha256_file "$COSIGN") == "$COSIGN_SHA256" ]] \
        || die 'pinned Cosign binary digest differs'
    require_regular "$manifest_helper" 0 0 500 1 \
        'sealed recovery manifest helper'
    [[ $(sha256_file "$manifest_helper") == "$MANIFEST_HELPER_SHA256" ]] \
        || die 'sealed recovery manifest helper digest differs'
    validate_fixed_installed_generation 10 \
        "$G10_MANIFEST_SHA256" "$G10_BUNDLE_SHA256" \
        "$G10_WORKFLOW_COMMIT" "$G10_SHIPPER_SHA256" \
        "$G10_VERIFIER_SHA256" "$G10_PROVISIONER_SHA256"
    validate_fixed_installed_generation 11 \
        "$G11_MANIFEST_SHA256" "$G11_BUNDLE_SHA256" \
        "$G11_WORKFLOW_COMMIT" "$G11_SHIPPER_SHA256" \
        "$G11_VERIFIER_SHA256" "$G11_PROVISIONER_SHA256"
    validate_retained_chain 11
    validate_active_copy 11 "$ARTIFACT_ROOT/generation-11" \
        "$G11_WORKFLOW_COMMIT"
    installed_executable_is_exact "$INSTALLED_SHIPPER" \
        "$G11_SHIPPER_SHA256" 1755 || die 'final G11 shipper differs'
    installed_executable_is_exact "$INSTALLED_PROVISIONER" \
        "$G11_PROVISIONER_SHA256" 755 || die 'final G11 provisioner differs'
}

exact_generation_for_file() {
    local path=$1 mode=$2 g10_sha=$3 g11_sha=$4 label=$5 digest
    require_regular "$path" 0 0 "$mode" 1 "$label"
    digest=$(sha256_file "$path")
    if [[ $digest == "$g10_sha" ]]; then
        /usr/bin/printf '10\n'
    elif [[ $digest == "$g11_sha" ]]; then
        /usr/bin/printf '11\n'
    else
        die "$label has an unknown digest"
    fi
}

validate_phase_state() {
    local phase=$1 generation_state shipper_state trust_state bundle_state
    local manifest_state vector g10_workflow_sha g11_workflow_sha
    validate_installed_generation 10 \
        "$RECOVERY_SNAPSHOT/generation-10" "$G10_WORKFLOW_COMMIT"
    if [[ -e $ARTIFACT_ROOT/generation-11 || -L $ARTIFACT_ROOT/generation-11 ]]; then
        validate_installed_generation 11 \
            "$RECOVERY_SNAPSHOT/generation-11" "$G11_WORKFLOW_COMMIT"
        generation_state=11
    else
        generation_state=0
    fi
    shipper_state=$(exact_generation_for_file \
        "$INSTALLED_SHIPPER" 1755 "$G10_SHIPPER_SHA256" \
        "$G11_SHIPPER_SHA256" 'installed shipper')
    g10_workflow_sha=$(workflow_file_sha256 "$G10_WORKFLOW_COMMIT")
    g11_workflow_sha=$(workflow_file_sha256 "$G11_WORKFLOW_COMMIT")
    trust_state=$(exact_generation_for_file \
        "$AUTHORITY_ROOT/trusted-workflow-commit" 444 \
        "$g10_workflow_sha" "$g11_workflow_sha" 'active workflow trust')
    bundle_state=$(exact_generation_for_file \
        "$AUTHORITY_ROOT/release-authority-v2.json.cosign.bundle" 444 \
        "$G10_BUNDLE_SHA256" "$G11_BUNDLE_SHA256" 'active authority bundle')
    manifest_state=$(exact_generation_for_file \
        "$AUTHORITY_ROOT/release-authority-v2.json" 444 \
        "$G10_MANIFEST_SHA256" "$G11_MANIFEST_SHA256" 'active authority manifest')
    vector=$generation_state:$shipper_state:$trust_state:$bundle_state:$manifest_state
    case $phase:$vector in
        prepared:0:10:10:10:10|prepared:11:10:10:10:10|\
        generation_published:11:10:10:10:10|\
        generation_published:11:11:10:10:10|\
        shipper_published:11:11:10:10:10|\
        provisioner_published:11:11:10:10:10|\
        provisioner_published:11:11:11:10:10|\
        trust_published:11:11:11:10:10|\
        trust_published:11:11:11:11:10|\
        bundle_published:11:11:11:11:10|\
        bundle_published:11:11:11:11:11|\
        manifest_published:11:11:11:11:11) ;;
        *) die "recovery journal phase and authority state disagree: $phase $vector" ;;
    esac
}

product_state_digest() {
    local path
    {
        for path in \
            "$OPERATOR_STATE/current-release.json" \
            "$OPERATOR_STATE/features.txt" \
            "$OPERATOR_STATE/deploy-stamp.json" \
            "$OPERATOR_STATE/deploy-stamp.json.cosign.bundle" \
            "$OPERATOR_STATE/release-intent/v0.7.114.json" \
            "$OPERATOR_STATE/release-dispatch/v0.7.114.json" \
            "$OPERATOR_STATE/release-run/v0.7.114.json" \
            "$OPERATOR_STATE/release-authority/v0.7.114.json"; do
            if [[ -f $path && ! -L $path ]]; then
                /usr/bin/printf 'present\0%s\0%s\0' "$path" "$(sha256_file "$path")"
            elif [[ ! -e $path && ! -L $path ]]; then
                /usr/bin/printf 'absent\0%s\0' "$path"
            else
                die 'product-state sentinel is unsafe'
            fi
        done
    } | /usr/bin/sha256sum | /usr/bin/awk '{print $1}'
}

journal_json() {
    local phase=$1 product_digest=$2
    /usr/bin/jq -cjn \
        --arg schema syntaur.authority-g10-g11-recovery.v1 \
        --arg phase "$phase" \
        --arg g10_manifest "$G10_MANIFEST_SHA256" \
        --arg g10_shipper "$G10_SHIPPER_SHA256" \
        --arg g11_manifest "$G11_MANIFEST_SHA256" \
        --arg g11_bundle "$G11_BUNDLE_SHA256" \
        --arg g11_workflow "$G11_WORKFLOW_COMMIT" \
        --arg g11_shipper "$G11_SHIPPER_SHA256" \
        --arg g11_provisioner "$G11_PROVISIONER_SHA256" \
        --arg product_state "$product_digest" \
        '{schema:$schema,phase:$phase,
          previous_generation:10,previous_manifest_sha256:$g10_manifest,
          previous_shipper_sha256:$g10_shipper,
          target_generation:11,target_manifest_sha256:$g11_manifest,
          target_bundle_sha256:$g11_bundle,
          target_workflow_commit:$g11_workflow,
          target_shipper_sha256:$g11_shipper,
          target_provisioner_sha256:$g11_provisioner,
          product_state_sha256:$product_state}'
}

validate_journal() {
    local product_digest=$1 canonical phase
    require_regular "$RECOVERY_JOURNAL" 0 0 600 1 'recovery journal'
    [[ $(/usr/bin/stat -c '%s' "$RECOVERY_JOURNAL") -le 4096 ]] \
        || die 'recovery journal is oversized'
    phase=$(/usr/bin/jq -er '.phase' "$RECOVERY_JOURNAL")
    [[ $phase == prepared || $phase == generation_published \
        || $phase == shipper_published || $phase == provisioner_published \
        || $phase == trust_published || $phase == bundle_published \
        || $phase == manifest_published ]] \
        || die 'recovery journal phase is invalid'
    canonical=$(journal_json "$phase" "$product_digest")
    [[ $(<"$RECOVERY_JOURNAL") == "$canonical" \
        && $(/usr/bin/wc -l <"$RECOVERY_JOURNAL") -eq 0 ]] \
        || die 'recovery journal differs from the fixed transaction'
}

journal_recorded_product_digest() {
    local digest
    require_regular "$RECOVERY_JOURNAL" 0 0 600 1 'recovery journal'
    digest=$(/usr/bin/jq -er '.product_state_sha256' "$RECOVERY_JOURNAL")
    valid_sha256 "$digest" || die 'recovery journal product digest is malformed'
    validate_journal "$digest"
    /usr/bin/printf '%s\n' "$digest"
}

phase_rank() {
    case $1 in
        prepared) /usr/bin/printf '0\n' ;;
        generation_published) /usr/bin/printf '1\n' ;;
        shipper_published) /usr/bin/printf '2\n' ;;
        provisioner_published) /usr/bin/printf '3\n' ;;
        trust_published) /usr/bin/printf '4\n' ;;
        bundle_published) /usr/bin/printf '5\n' ;;
        manifest_published) /usr/bin/printf '6\n' ;;
        *) die 'unknown recovery journal phase' ;;
    esac
}

write_journal() {
    local phase=$1 product_digest=$2 current current_rank target_rank
    target_rank=$(phase_rank "$phase")
    if [[ -e $RECOVERY_JOURNAL || -L $RECOVERY_JOURNAL ]]; then
        validate_journal "$product_digest"
        current=$(/usr/bin/jq -er '.phase' "$RECOVERY_JOURNAL")
        current_rank=$(phase_rank "$current")
        if (( current_rank > target_rank )); then
            return 0
        fi
        if (( current_rank == target_rank )); then
            return 0
        fi
        (( target_rank == current_rank + 1 )) \
            || die 'recovery journal phase advance is non-sequential'
    else
        [[ $phase == prepared ]] \
            || die 'recovery journal must begin at prepared'
    fi
    [[ ! -e $RECOVERY_JOURNAL_TEMP && ! -L $RECOVERY_JOURNAL_TEMP ]] \
        || die 'recovery journal temporary path exists'
    journal_json "$phase" "$product_digest" >"$RECOVERY_JOURNAL_TEMP"
    /usr/bin/chown root:root "$RECOVERY_JOURNAL_TEMP"
    /usr/bin/chmod 0600 "$RECOVERY_JOURNAL_TEMP"
    sync_path "$RECOVERY_JOURNAL_TEMP"
    /usr/bin/mv -fT "$RECOVERY_JOURNAL_TEMP" "$RECOVERY_JOURNAL"
    sync_path "$AUTHORITY_ROOT"
    validate_journal "$product_digest"
}

validate_current_journal_state() {
    local product_digest=$1 phase
    validate_journal "$product_digest"
    phase=$(/usr/bin/jq -er '.phase' "$RECOVERY_JOURNAL")
    validate_phase_state "$phase"
}

recovery_receipt_json() {
    local product_digest=$1
    /usr/bin/jq -cjn \
        --arg schema syntaur.authority-g10-g11-recovery-receipt.v1 \
        --arg previous_manifest "$G10_MANIFEST_SHA256" \
        --arg target_manifest "$G11_MANIFEST_SHA256" \
        --arg target_bundle "$G11_BUNDLE_SHA256" \
        --arg target_workflow "$G11_WORKFLOW_COMMIT" \
        --arg target_shipper "$G11_SHIPPER_SHA256" \
        --arg target_provisioner "$G11_PROVISIONER_SHA256" \
        --arg product_state "$product_digest" \
        '{schema:$schema,completed:true,
          previous_generation:10,previous_manifest_sha256:$previous_manifest,
          target_generation:11,target_manifest_sha256:$target_manifest,
          target_bundle_sha256:$target_bundle,
          target_workflow_commit:$target_workflow,
          target_shipper_sha256:$target_shipper,
          target_provisioner_sha256:$target_provisioner,
          product_state_sha256:$product_state}'
}

validate_receipt() {
    local product_digest=$1 expected
    expected=$(recovery_receipt_json "$product_digest")
    require_regular "$RECOVERY_RECEIPT" 0 0 444 1 'recovery receipt'
    [[ $(<"$RECOVERY_RECEIPT") == "$expected" \
        && $(/usr/bin/wc -l <"$RECOVERY_RECEIPT") -eq 0 ]] \
        || die 'existing recovery receipt differs'
}

receipt_recorded_product_digest() {
    local digest
    require_regular "$RECOVERY_RECEIPT" 0 0 444 1 'recovery receipt'
    digest=$(/usr/bin/jq -er '.product_state_sha256' "$RECOVERY_RECEIPT")
    valid_sha256 "$digest" || die 'recovery receipt product digest is malformed'
    /usr/bin/printf '%s\n' "$digest"
}

publish_receipt() {
    local product_digest=$1 expected temporary
    expected=$(recovery_receipt_json "$product_digest")
    if [[ -e $RECOVERY_RECEIPT || -L $RECOVERY_RECEIPT ]]; then
        validate_receipt "$product_digest"
        return 0
    fi
    temporary=$RECOVERY_RECEIPT.tmp
    [[ ! -e $temporary && ! -L $temporary ]] \
        || die 'recovery receipt temporary path exists'
    /usr/bin/printf '%s' "$expected" >"$temporary"
    /usr/bin/chown root:root "$temporary"
    /usr/bin/chmod 0444 "$temporary"
    sync_path "$temporary"
    /usr/bin/mv -T "$temporary" "$RECOVERY_RECEIPT"
    sync_path /etc/syntaur
}

discard_recovery_stage() {
    local name path actual identity mode
    [[ -e $RECOVERY_STAGE || -L $RECOVERY_STAGE ]] || return 0
    [[ -d $RECOVERY_STAGE && ! -L $RECOVERY_STAGE ]] \
        || die 'partial recovery stage is not a real directory'
    identity=$(/usr/bin/stat -c '%u:%g' "$RECOVERY_STAGE")
    mode=$(/usr/bin/stat -c '%a' "$RECOVERY_STAGE")
    [[ $identity == 0:0 && ( $mode == 700 || $mode == 555 ) ]] \
        || die 'partial recovery stage identity differs'
    /usr/bin/chmod 0700 "$RECOVERY_STAGE"
    actual=$(/usr/bin/find "$RECOVERY_STAGE" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            release-authority-v2.json|release-authority-v2.json.cosign.bundle|\
            syntaur-build-authority-provision|syntaur-ship-linux-x86_64|\
            syntaur-verify-linux-x86_64|trusted-workflow-commit) ;;
            *) die 'partial recovery stage has an unexpected entry' ;;
        esac
        path=$RECOVERY_STAGE/$name
        [[ -f $path && ! -L $path \
            && $(/usr/bin/stat -c '%u:%g:%h' "$path") == 0:0:1 ]] \
            || die 'partial recovery stage contains unsafe material'
        /usr/bin/rm -f -- "$path"
    done <<<"$actual"
    /usr/bin/rmdir "$RECOVERY_STAGE"
    sync_path "$ARTIFACT_ROOT"
}

publish_generation_11() {
    local g11_dir=$1 destination=$ARTIFACT_ROOT/generation-11
    if [[ -e $destination || -L $destination ]]; then
        validate_installed_generation 11 "$g11_dir" "$G11_WORKFLOW_COMMIT"
        return 0
    fi
    if [[ -e $RECOVERY_STAGE || -L $RECOVERY_STAGE ]]; then
        discard_recovery_stage
    fi
    /usr/bin/install -d -o root -g root -m 0700 "$RECOVERY_STAGE"
    /usr/bin/install -o root -g root -m 0444 \
        "$g11_dir/release-authority-v2.json" \
        "$g11_dir/release-authority-v2.json.cosign.bundle" \
        "$RECOVERY_STAGE/"
    /usr/bin/install -o root -g root -m 0555 \
        "$g11_dir/syntaur-build-authority-provision" \
        "$g11_dir/syntaur-ship-linux-x86_64" \
        "$g11_dir/syntaur-verify-linux-x86_64" \
        "$RECOVERY_STAGE/"
    /usr/bin/printf '%s\n' "$G11_WORKFLOW_COMMIT" \
        >"$RECOVERY_STAGE/trusted-workflow-commit"
    /usr/bin/chown root:root "$RECOVERY_STAGE/trusted-workflow-commit"
    /usr/bin/chmod 0444 "$RECOVERY_STAGE/trusted-workflow-commit"
    /usr/bin/chmod 0555 "$RECOVERY_STAGE"
    while IFS= read -r path; do sync_path "$path"; done \
        < <(/usr/bin/find "$RECOVERY_STAGE" -depth -print)
    /usr/bin/mv -T "$RECOVERY_STAGE" "$destination"
    sync_path "$ARTIFACT_ROOT"
    validate_installed_generation 11 "$g11_dir" "$G11_WORKFLOW_COMMIT"
}

publish_exact_file() {
    local source=$1 destination=$2 target_sha=$3 target_mode=$4
    local predecessor_sha=$5 predecessor_mode=$6 temporary parent source_size
    [[ -e $destination || -L $destination ]] \
        || die 'publication destination is unexpectedly absent'
    if [[ -f $destination && ! -L $destination \
        && $(/usr/bin/stat -c '%u:%g:%a:%h' "$destination") == \
            "0:0:$target_mode:1" ]]; then
        if [[ $(sha256_file "$destination") == "$target_sha" ]]; then
            return 0
        fi
    fi
    require_regular "$destination" 0 0 "$predecessor_mode" 1 \
        'predecessor publication file'
    [[ $(sha256_file "$destination") == "$predecessor_sha" ]] \
        || die 'publication predecessor digest differs'
    parent=$(/usr/bin/dirname "$destination")
    temporary=$(publication_temporary_path "$destination")
    source_size=$(/usr/bin/stat -c '%s' "$source")
    discard_safe_root_temporary "$temporary" "$source_size" \
        'publication temporary file'
    /usr/bin/install -o root -g root -m "$target_mode" "$source" "$temporary"
    [[ $(sha256_file "$temporary") == "$target_sha" ]] \
        || die 'publication staging digest differs'
    sync_path "$temporary"
    /usr/bin/mv -fT "$temporary" "$destination"
    sync_path "$parent"
    require_regular "$destination" 0 0 "$target_mode" 1 \
        'published target file'
    [[ $(sha256_file "$destination") == "$target_sha" ]] \
        || die 'published target digest differs'
}

run_operator_authority_status() {
    local operator_uid=$1 operator_gid=$2
    (
        exec 7>&- 8>&- 9>&-
        exec /usr/bin/setpriv \
            --reuid "$operator_uid" \
            --regid "$operator_gid" \
            --clear-groups \
            /usr/bin/env -i \
                HOME=/home/sean USER=sean LOGNAME=sean \
                PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=C.UTF-8 LC_ALL=C.UTF-8 \
                "$INSTALLED_SHIPPER" authority-status
    )
}

assert_locks() {
    local root_identity=$1 global_identity=$2 deploy_identity=$3
    [[ $(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$ROOT_LOCK") == \
        "$root_identity" ]] || die 'root promotion lock changed'
    [[ $(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$GLOBAL_MUTATION_LOCK") == \
        "$global_identity" ]] || die 'global mutation lock changed'
    [[ $(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$DEPLOYMENT_LOCK") == \
        "$deploy_identity" ]] || die 'operator deployment lock changed'
    /usr/bin/flock -n 7 || die 'root promotion lock was lost'
    /usr/bin/flock -n 8 || die 'global mutation lock was lost'
    /usr/bin/flock -n 9 || die 'operator deployment lock was lost'
}

[[ $# -ge 1 ]] || usage
action=$1
shift
[[ $action == verify || $action == install ]] || usage
g10_dir=
g11_dir=
expected_current_shipper_sha256=
while (($# > 0)); do
    [[ $# -ge 2 ]] || usage
    case $1 in
        --g10-dir) g10_dir=$2 ;;
        --g11-dir) g11_dir=$2 ;;
        --expected-current-shipper-sha256)
            expected_current_shipper_sha256=$2
            ;;
        *) usage ;;
    esac
    shift 2
done
[[ -n $g10_dir && -n $g11_dir ]] || usage

if [[ $action == verify ]]; then
    [[ -z $expected_current_shipper_sha256 ]] || usage
    verify_release_material "$g10_dir" "$g11_dir" "$(/usr/bin/id -u)" "$(/usr/bin/id -g)"
    /usr/bin/printf 'G10-G11 signed successor verified: generation=11 manifest_sha256=%s\n' \
        "$G11_MANIFEST_SHA256"
    exit 0
fi

[[ $(/usr/bin/hostname) == claudevm ]] \
    || die 'installation is permitted only on canonical host claudevm'
[[ $(/usr/bin/id -u) -eq 0 && $(/usr/bin/id -g) -eq 0 ]] \
    || die 'installation requires sudo and an all-root effective identity'
[[ ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && ${SUDO_GID:-} =~ ^[1-9][0-9]*$ ]] \
    || die 'installation requires concrete non-root SUDO_UID and SUDO_GID'
operator_uid=$SUDO_UID
operator_gid=$SUDO_GID
require_sealed_runtime
[[ $expected_current_shipper_sha256 == "$G10_SHIPPER_SHA256" ]] \
    || die 'independently recorded current shipper is not exact G10'

require_directory "$AUTHORITY_ROOT" 0 0 755 'installed authority root'
require_directory "$ARTIFACT_ROOT" 0 0 755 'installed authority artifact root'
require_directory "$OPERATOR_STATE" "$operator_uid" "$operator_gid" 700 \
    'operator ship state'
[[ ! -e $NORMAL_PROMOTION_JOURNAL && ! -L $NORMAL_PROMOTION_JOURNAL \
    && ! -e $NORMAL_PROMOTION_JOURNAL_TEMP \
    && ! -L $NORMAL_PROMOTION_JOURNAL_TEMP ]] \
    || die 'normal authority promotion is pending'

if [[ ! -e $ROOT_LOCK && ! -L $ROOT_LOCK ]]; then
    /usr/bin/install -o root -g root -m 0600 /dev/null "$ROOT_LOCK"
    sync_path "$AUTHORITY_ROOT"
fi
require_regular "$ROOT_LOCK" 0 0 600 1 'root promotion lock'
exec 7<>"$ROOT_LOCK"
/usr/bin/flock -n 7 || die 'another authority promotion holds the root lock'

require_regular "$GLOBAL_MUTATION_LOCK" 0 "$operator_gid" 440 1 \
    'global mutation lock'
[[ $(/usr/bin/stat -c '%s' "$GLOBAL_MUTATION_LOCK") -eq 0 ]] \
    || die 'global mutation lock is not empty'
exec 8<"$GLOBAL_MUTATION_LOCK"
/usr/bin/flock -n 8 || die 'another host mutation holds the global lock'

require_regular "$DEPLOYMENT_LOCK" "$operator_uid" "$operator_gid" 600 1 \
    'operator deployment lock'
[[ $(/usr/bin/stat -c '%s' "$DEPLOYMENT_LOCK") -le 64 ]] \
    || die 'operator deployment lock is oversized'
exec 9<>"$DEPLOYMENT_LOCK"
/usr/bin/flock -n 9 || die 'another deployment holds the operator lock'

root_lock_identity=$(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$ROOT_LOCK")
global_lock_identity=$(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$GLOBAL_MUTATION_LOCK")
deploy_lock_identity=$(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$DEPLOYMENT_LOCK")
assert_locks "$root_lock_identity" "$global_lock_identity" "$deploy_lock_identity"

journal_present=false
if [[ -e $RECOVERY_JOURNAL || -L $RECOVERY_JOURNAL ]]; then
    journal_present=true
fi
receipt_present=false
if [[ -e $RECOVERY_RECEIPT || -L $RECOVERY_RECEIPT ]]; then
    receipt_present=true
fi
product_digest=$(product_state_digest)
require_regular "$AUTHORITY_ROOT/release-authority-v2.json" \
    0 0 444 1 'active authority manifest'
active_manifest=$(sha256_file "$AUTHORITY_ROOT/release-authority-v2.json")

if [[ $receipt_present == true \
    && $active_manifest == "$G11_MANIFEST_SHA256" ]] \
    && installed_executable_is_exact "$INSTALLED_SHIPPER" \
        "$G11_SHIPPER_SHA256" 1755; then
    transaction_product_digest=$(receipt_recorded_product_digest)
    validate_receipt "$transaction_product_digest"
    if [[ $journal_present == true ]]; then
        [[ $(journal_recorded_product_digest) == \
            "$transaction_product_digest" ]] \
            || die 'terminal journal and recovery receipt product digests differ'
        [[ $(/usr/bin/jq -er '.phase' "$RECOVERY_JOURNAL") == \
            manifest_published ]] \
            || die 'recovery receipt exists before the terminal journal phase'
    fi
    validate_complete_installed_g11
    run_operator_authority_status "$operator_uid" "$operator_gid"
    [[ $(product_state_digest) == "$product_digest" ]] \
        || die 'G11 authority status changed product or deployment state'
    assert_locks "$root_lock_identity" "$global_lock_identity" \
        "$deploy_lock_identity"
    preflight_recovery_temporaries
    if [[ $journal_present == true ]]; then
        /usr/bin/rm -f -- "$RECOVERY_JOURNAL"
        sync_path "$AUTHORITY_ROOT"
        [[ ! -e $RECOVERY_JOURNAL && ! -L $RECOVERY_JOURNAL ]] \
            || die 'completed recovery journal was not retired'
    fi
    if [[ -e $RECOVERY_SNAPSHOT || -L $RECOVERY_SNAPSHOT ]]; then
        retire_recovery_snapshot
    fi
    assert_locks "$root_lock_identity" "$global_lock_identity" \
        "$deploy_lock_identity"
    [[ $(product_state_digest) == "$product_digest" ]] \
        || die 'completed recovery cleanup changed product or deployment state'
    /usr/bin/printf 'G10-G11 authority recovery already installed: active_generation=11 manifest_sha256=%s transaction_product_state_sha256=%s current_product_state_sha256=%s\n' \
        "$G11_MANIFEST_SHA256" "$transaction_product_digest" \
        "$product_digest"
    exit 0
fi

preflight_recovery_temporaries
snapshot_resume=$journal_present
if [[ $journal_present == false \
    && ( -e $RECOVERY_SNAPSHOT || -L $RECOVERY_SNAPSHOT ) \
    && ( -e $RECOVERY_RECEIPT || -L $RECOVERY_RECEIPT ) ]]; then
    snapshot_resume=true
fi
prepare_recovery_snapshot \
    "$g10_dir" "$g11_dir" "$operator_uid" "$operator_gid" "$snapshot_resume"
g10_material=$RECOVERY_SNAPSHOT/generation-10
g11_material=$RECOVERY_SNAPSHOT/generation-11

installed_executable_is_exact "$INSTALLED_PROVISIONER" \
    "$G11_PROVISIONER_SHA256" 755 \
    || die 'G10/G11 shared provisioner differs before recovery'
transaction_product_digest=$product_digest
if [[ $journal_present == true ]]; then
    transaction_product_digest=$(journal_recorded_product_digest)
fi
if [[ $journal_present == true && $receipt_present == false ]]; then
    [[ $product_digest == "$transaction_product_digest" ]] \
        || die 'product or deployment state changed during incomplete recovery'
fi

if [[ $journal_present == false ]]; then
    if [[ $active_manifest == "$G11_MANIFEST_SHA256" ]] \
        && installed_executable_is_exact "$INSTALLED_SHIPPER" \
            "$G11_SHIPPER_SHA256" 1755; then
        [[ $receipt_present == true ]] \
            || die 'complete un-journaled G11 is missing its recovery receipt'
        recorded_product_digest=$(receipt_recorded_product_digest)
        validate_receipt "$recorded_product_digest"
        validate_phase_state manifest_published
        validate_retained_chain 11
        validate_active_copy 11 "$g11_material" "$G11_WORKFLOW_COMMIT"
        run_operator_authority_status "$operator_uid" "$operator_gid"
        [[ $(product_state_digest) == "$product_digest" ]] \
            || die 'G11 authority status changed product or deployment state'
        assert_locks "$root_lock_identity" "$global_lock_identity" \
            "$deploy_lock_identity"
        retire_recovery_snapshot
        /usr/bin/printf 'G10-G11 authority recovery already installed: active_generation=11 manifest_sha256=%s\n' \
            "$G11_MANIFEST_SHA256"
        exit 0
    fi
    [[ $receipt_present == false ]] \
        || die 'recovery receipt exists while exact G11 is not complete'
    [[ $active_manifest == "$G10_MANIFEST_SHA256" ]] \
        || die 'un-journaled active manifest is neither exact G10 nor complete G11'
    installed_executable_is_exact "$INSTALLED_SHIPPER" \
        "$G10_SHIPPER_SHA256" 1755 \
        || die 'un-journaled authority state is neither exact G10 nor complete G11'
    validate_installed_generation 10 "$g10_material" "$G10_WORKFLOW_COMMIT"
    validate_retained_chain 10
    validate_active_copy 10 "$g10_material" "$G10_WORKFLOW_COMMIT"
    run_operator_authority_status "$operator_uid" "$operator_gid"
    [[ $(product_state_digest) == "$product_digest" ]] \
        || die 'G10 authority status changed product or deployment state'
    assert_locks "$root_lock_identity" "$global_lock_identity" \
        "$deploy_lock_identity"
    write_journal prepared "$transaction_product_digest"
    validate_current_journal_state "$transaction_product_digest"
else
    validate_current_journal_state "$transaction_product_digest"
    if [[ $receipt_present == true ]]; then
        validate_receipt "$transaction_product_digest"
        [[ $(/usr/bin/jq -er '.phase' "$RECOVERY_JOURNAL") == \
            manifest_published ]] \
            || die 'recovery receipt exists before the terminal journal phase'
    fi
fi

assert_locks "$root_lock_identity" "$global_lock_identity" "$deploy_lock_identity"
publish_generation_11 "$g11_material"
write_journal generation_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

publish_exact_file \
    "$ARTIFACT_ROOT/generation-11/syntaur-ship-linux-x86_64" \
    "$INSTALLED_SHIPPER" "$G11_SHIPPER_SHA256" 1755 \
    "$G10_SHIPPER_SHA256" 1755
write_journal shipper_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

write_journal provisioner_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

g10_workflow_sha=$(workflow_file_sha256 "$G10_WORKFLOW_COMMIT")
g11_workflow_sha=$(workflow_file_sha256 "$G11_WORKFLOW_COMMIT")
publish_exact_file \
    "$ARTIFACT_ROOT/generation-11/trusted-workflow-commit" \
    "$AUTHORITY_ROOT/trusted-workflow-commit" \
    "$g11_workflow_sha" 444 "$g10_workflow_sha" 444
write_journal trust_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

publish_exact_file \
    "$ARTIFACT_ROOT/generation-11/release-authority-v2.json.cosign.bundle" \
    "$AUTHORITY_ROOT/release-authority-v2.json.cosign.bundle" \
    "$G11_BUNDLE_SHA256" 444 "$G10_BUNDLE_SHA256" 444
write_journal bundle_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

assert_locks "$root_lock_identity" "$global_lock_identity" "$deploy_lock_identity"
publish_exact_file \
    "$ARTIFACT_ROOT/generation-11/release-authority-v2.json" \
    "$AUTHORITY_ROOT/release-authority-v2.json" \
    "$G11_MANIFEST_SHA256" 444 "$G10_MANIFEST_SHA256" 444
write_journal manifest_published "$transaction_product_digest"
validate_current_journal_state "$transaction_product_digest"

assert_locks "$root_lock_identity" "$global_lock_identity" "$deploy_lock_identity"
validate_installed_generation 10 "$g10_material" "$G10_WORKFLOW_COMMIT"
validate_installed_generation 11 "$g11_material" "$G11_WORKFLOW_COMMIT"
validate_retained_chain 11
validate_active_copy 11 "$g11_material" "$G11_WORKFLOW_COMMIT"
installed_executable_is_exact "$INSTALLED_SHIPPER" \
    "$G11_SHIPPER_SHA256" 1755 || die 'final G11 shipper differs'
installed_executable_is_exact "$INSTALLED_PROVISIONER" \
    "$G11_PROVISIONER_SHA256" 755 || die 'final G11 provisioner differs'
run_operator_authority_status "$operator_uid" "$operator_gid"
[[ $(product_state_digest) == "$product_digest" ]] \
    || die 'product or deployment state changed during authority recovery'
assert_locks "$root_lock_identity" "$global_lock_identity" \
    "$deploy_lock_identity"
publish_receipt "$transaction_product_digest"
validate_receipt "$transaction_product_digest"
/usr/bin/rm -f -- "$RECOVERY_JOURNAL"
sync_path "$AUTHORITY_ROOT"
[[ ! -e $RECOVERY_JOURNAL && ! -L $RECOVERY_JOURNAL ]] \
    || die 'completed recovery journal was not retired'
retire_recovery_snapshot
/usr/bin/printf 'G10-G11 authority recovery installed: active_generation=11 manifest_sha256=%s transaction_product_state_sha256=%s current_product_state_sha256=%s\n' \
    "$G11_MANIFEST_SHA256" "$transaction_product_digest" "$product_digest"
