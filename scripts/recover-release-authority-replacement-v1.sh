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
readonly ARTIFACT_ROOT=$AUTHORITY_ROOT/release-authority
readonly INSTALLED_SHIPPER=/usr/local/bin/syntaur-ship
readonly INSTALLED_PROVISIONER=/opt/syntaur-build-authority-provision
readonly GLOBAL_MUTATION_LOCK=/etc/syntaur/syntaur-ship-mutation.lock
readonly NORMAL_PROMOTION_JOURNAL=$AUTHORITY_ROOT/authority-promotion-v1.json
readonly NORMAL_PROMOTION_JOURNAL_TEMP=$AUTHORITY_ROOT/.authority-promotion-v1.json.tmp
readonly REPLACEMENT_LOCK=$AUTHORITY_ROOT/.authority-replacement-v1.lock
readonly INSTALL_JOURNAL=$AUTHORITY_ROOT/authority-replacement-v1-install.json
readonly INSTALL_JOURNAL_TEMP=$AUTHORITY_ROOT/.authority-replacement-v1-install.json.tmp
readonly ROLLBACK_JOURNAL=$AUTHORITY_ROOT/authority-replacement-v1-rollback.json
readonly ROLLBACK_JOURNAL_TEMP=$AUTHORITY_ROOT/.authority-replacement-v1-rollback.json.tmp
readonly INSTALL_RECEIPT=/etc/syntaur/release-authority-replacement-v1.receipt.json
readonly ROLLBACK_RECEIPT=/etc/syntaur/release-authority-replacement-v1.rollback-receipt.json
readonly PRODUCT_STATE_PROOF_TEMP=$AUTHORITY_ROOT/.authority-replacement-product-state-v1.tmp
readonly RESOLUTION_PARENT=$AUTHORITY_ROOT/replacement-resolution-v1
readonly SEALED_RUNTIME_ROOT=/etc/syntaur/release-authority-replacement-v1-r3.runtime
readonly SUPERSEDED_SEALED_RUNTIME_ROOT=/etc/syntaur/release-authority-replacement-v1.runtime
readonly PROOF_HELPER_PARENT=/usr/local/libexec
readonly PROOF_HELPER_ROOT=$PROOF_HELPER_PARENT/syntaur-authority-replacement-proof-v1
readonly PROOF_HELPER_STAGE=$PROOF_HELPER_PARENT/.syntaur-authority-replacement-proof-v1.staged
readonly PROOF_HELPER_NAME=syntaur-ship
readonly PROOF_HELPER_ASSET=syntaur-authority-replacement-proof-linux-x86_64
readonly CORRECTION_AUTHORIZATION_NAME=release-authority-resolution-authorization-v1.json
readonly SEALED_CORRECTION_AUTHORIZATION=$SEALED_RUNTIME_ROOT/$CORRECTION_AUTHORIZATION_NAME
readonly SEALED_INPUTS=$SEALED_RUNTIME_ROOT/inputs
readonly SEALED_INPUTS_STAGE=$SEALED_RUNTIME_ROOT/inputs.staged
readonly MANIFEST=release-authority-v2.json
readonly BUNDLE=release-authority-v2.json.cosign.bundle
readonly SELECTION_REVIEW=release-authority-selection-review-v1.json
readonly CORRECTION_REVIEW=release-authority-resolution-correction-v1.json
readonly RESOLUTION=release-authority-replacement-v1.json
readonly RESOLUTION_BUNDLE=release-authority-replacement-v1.json.cosign.bundle
readonly RECOVERY_TOOL=recover-release-authority-replacement-v1.sh
readonly MANIFEST_HELPER=release-authority-manifest.sh

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir

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
    --expected-recovery-tool-sha256 HEX \
    --expected-predecessor-manifest-sha256 HEX \
    --expected-rejected-manifest-sha256 HEX \
    --expected-selected-manifest-sha256 HEX \
    [--correction-authorization FILE] \
    --authorize-reason authority_target_mismatch

  sudo recover-release-authority-replacement-v1.sh install [same exact tuple]

  sudo recover-release-authority-replacement-v1.sh rollback [same exact tuple]

Before install, verify the resolution signature and record its signed recovery
tool hash. Copy this script with /usr/bin/install into the fixed root-owned
/etc/syntaur/release-authority-replacement-v1.runtime path, hash-compare that
root-owned copy against --expected-recovery-tool-sha256, and execute only that
copy. It seals every remaining input into root-owned storage, reopens and
revalidates the sealed bytes, then performs the journaled exceptional authority
swap itself. The selected authority is installed ahead of the separately
reviewed product transition; the normal product pipeline must follow it.
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
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' \
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

resolution_revision() {
    /usr/bin/jq -er '
        if .schema == 1 then 1
        elif .schema == 2 then .resolution_revision
        else error("unsupported replacement resolution schema")
        end
    ' "$1"
}

resolution_data_names() {
    local record=$1 schema
    schema=$(resolution_value "$record" schema)
    /usr/bin/printf '%s\n' "$SELECTION_REVIEW" "$RESOLUTION" "$RESOLUTION_BUNDLE"
    if [[ $schema == 2 ]]; then
        /usr/bin/printf '%s\n' "$CORRECTION_REVIEW"
        if [[ $(resolution_revision "$record") == 3 ]]; then
            /usr/bin/printf '%s\n' "$PROOF_HELPER_ASSET"
        fi
    fi
}

resolution_all_names() {
    local record=$1
    resolution_data_names "$record"
    /usr/bin/printf '%s\n' "$RECOVERY_TOOL" "$MANIFEST_HELPER"
}

manifest_value() {
    /usr/bin/jq -er --arg field "$2" '.[$field]' "$1"
}

validate_resolution_inline() {
    local record=$1
    /usr/bin/jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        (.schema == 1 or .schema == 2) and
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
        (.rejected_workflow_commit != .selected_workflow_commit) and
        (.rejected_workflow_commit != .resolution_workflow_commit) and
        (.selected_workflow_commit != .resolution_workflow_commit) and
        (.settled_product_version | type == "string" and
          test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
        (.settled_product_gateway_commit | commit) and
        (.settled_product_engine_commit | commit) and
        (.settled_product_state_sha256 | digest) and
        (.settled_promotion_policy_sha256 | digest) and
        (.selected_engine_commit | commit) and
        (.planned_product_version | type == "string" and
          test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
        (.planned_product_base_commit | commit) and
        (.settled_product_version == .selected_authority_version) and
        (.settled_product_gateway_commit != .selected_authority_commit) and
        (if .schema == 2 and .resolution_revision == 3 then
           .planned_product_base_commit == .proof_helper_source_commit
         else
           .planned_product_base_commit == .selected_authority_commit
         end) and
        ((.selected_authority_version | split(".") | map(tonumber)) as $selected |
         (.planned_product_version | split(".") | map(tonumber)) as $planned |
         ($planned[0] == $selected[0]) and
         ($planned[1] == $selected[1]) and
         ($planned[2] == ($selected[2] + 1))) and
        (.selection_review_sha256 | digest) and
        (.recovery_tool_sha256 | digest) and
        (.manifest_helper_sha256 | digest) and
        (if .schema == 1 then
           ((has("resolution_revision") or has("supersedes_resolution_tag") or
             has("supersedes_resolution_sha256") or
             has("superseded_recovery_tool_sha256") or
             has("correction_reason") or has("correction_review_sha256")) | not)
         else
           (.resolution_revision | type == "number" and . >= 2 and . <= 3 and floor == .) and
           (.supersedes_resolution_tag ==
             ("authority-resolution-v1-g" + (.selected_generation | tostring) +
              (if .resolution_revision == 2 then ""
               else "-r" + ((.resolution_revision - 1) | tostring) end))) and
           (.supersedes_resolution_sha256 | digest) and
           (.superseded_recovery_tool_sha256 | digest) and
           (.correction_review_sha256 | digest) and
           (if .resolution_revision == 2 then
              (.correction_reason == "recovery_tool_execution_failure") and
              ((has("proof_helper_source_commit") or
                has("proof_helper_source_tree_sha256") or
                has("proof_helper_sha256") or
                has("proof_helper_control_plane_sha256") or
                has("proof_helper_toolchain_sha256") or
                has("proof_helper_rustflags_sha256") or
                has("proof_helper_build_target") or
                has("proof_helper_build_profile") or
                has("proof_helper_build_clean") or
                has("proof_helper_execution_path") or
                has("proof_helper_protocol_sha256")) | not)
            else
              (.correction_reason == "product_state_proof_execution_failure") and
              (.proof_helper_source_commit | commit) and
              (.proof_helper_source_tree_sha256 | digest) and
              (.proof_helper_sha256 | digest) and
              (.proof_helper_control_plane_sha256 | digest) and
              (.proof_helper_toolchain_sha256 | digest) and
              (.proof_helper_rustflags_sha256 | digest) and
              (.proof_helper_build_target == "x86_64-unknown-linux-gnu") and
              (.proof_helper_build_profile == "release") and
              (.proof_helper_build_clean == "clean") and
              (.proof_helper_execution_path ==
                "/usr/local/libexec/syntaur-authority-replacement-proof-v1/syntaur-ship") and
              (.proof_helper_protocol_sha256 | digest)
            end)
         end)
    ' "$record" >/dev/null || die 'signed replacement resolution is malformed'
}

verify_correction_authorization() {
    local operation=$1 record=$resolution_dir/$RESOLUTION schema
    schema=$(resolution_value "$record" schema)
    if [[ $schema == 1 ]]; then
        [[ -z $correction_authorization ]] \
            || die 'an original resolution must not use correction authorization'
        return
    fi
    [[ -n $correction_authorization ]] \
        || die 'corrected resolution requires explicit operator authorization'
    local authorization_parent
    authorization_parent=$(canonical_dir \
        "$(/usr/bin/dirname "$correction_authorization")" \
        'correction authorization parent')
    correction_authorization=$authorization_parent/$(/usr/bin/basename \
        "$correction_authorization")
    require_safe_ancestors "$authorization_parent" 'correction authorization parent'
    require_safe_file "$correction_authorization" 32768 false \
        'correction authorization'
    if [[ $operation == verify ]]; then
        [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$correction_authorization") == \
            "$(/usr/bin/id -u):$(/usr/bin/id -g):400:1" ]] \
            || die 'verification correction authorization identity differs'
    else
        [[ $correction_authorization == "$SEALED_CORRECTION_AUTHORIZATION" ]] \
            || die 'installation correction authorization is outside the sealed runtime'
        require_root_file "$correction_authorization" 400 \
            'sealed correction authorization'
    fi
    "$resolution_dir/$MANIFEST_HELPER" validate-resolution-correction-authorization \
        "$correction_authorization"
    local revision resolution_tag correction_sha authorization_schema
    revision=$(resolution_revision "$record")
    resolution_tag=authority-resolution-v1-g$(resolution_value \
        "$record" selected_generation)-r${revision}
    correction_sha=$(sha256_file "$resolution_dir/$CORRECTION_REVIEW")
    authorization_schema=1
    [[ $revision == 3 ]] && authorization_schema=2
    /usr/bin/jq -e \
        --argjson schema "$authorization_schema" \
        --argjson revision "$revision" \
        --arg resolution_tag "$resolution_tag" \
        --arg resolution_sha256 "$expected_resolution_sha256" \
        --arg workflow_commit "$(resolution_value "$record" resolution_workflow_commit)" \
        --arg recovery_tool_sha256 "$expected_recovery_tool_sha256" \
        --arg manifest_helper_sha256 "$(sha256_file "$resolution_dir/$MANIFEST_HELPER")" \
        --arg correction_review_sha256 "$correction_sha" \
        --arg supersedes_resolution_sha256 \
            "$(resolution_value "$record" supersedes_resolution_sha256)" \
        --arg selected_manifest_sha256 "$expected_selected_sha256" \
        --arg active_install_journal_sha256 \
            "$(resolution_value "$resolution_dir/$CORRECTION_REVIEW" active_install_journal_sha256 2>/dev/null || true)" \
        --arg active_product_proof_temp_sha256 \
            "$(resolution_value "$resolution_dir/$CORRECTION_REVIEW" active_product_proof_temp_sha256 2>/dev/null || true)" \
        --arg sealed_inputs_resolution_sha256 \
            "$(resolution_value "$resolution_dir/$CORRECTION_REVIEW" sealed_inputs_resolution_sha256 2>/dev/null || true)" \
        --arg planned_product_base_commit \
            "$(resolution_value "$record" planned_product_base_commit)" \
        --arg proof_helper_source_commit \
            "$(resolution_value "$record" proof_helper_source_commit 2>/dev/null || true)" \
        --arg proof_helper_source_tree_sha256 \
            "$(resolution_value "$record" proof_helper_source_tree_sha256 2>/dev/null || true)" \
        --arg proof_helper_sha256 \
            "$(resolution_value "$record" proof_helper_sha256 2>/dev/null || true)" \
        --arg proof_helper_control_plane_sha256 \
            "$(resolution_value "$record" proof_helper_control_plane_sha256 2>/dev/null || true)" \
        --arg proof_helper_toolchain_sha256 \
            "$(resolution_value "$record" proof_helper_toolchain_sha256 2>/dev/null || true)" \
        --arg proof_helper_rustflags_sha256 \
            "$(resolution_value "$record" proof_helper_rustflags_sha256 2>/dev/null || true)" \
        --arg proof_helper_build_target \
            "$(resolution_value "$record" proof_helper_build_target 2>/dev/null || true)" \
        --arg proof_helper_build_profile \
            "$(resolution_value "$record" proof_helper_build_profile 2>/dev/null || true)" \
        --arg proof_helper_build_clean \
            "$(resolution_value "$record" proof_helper_build_clean 2>/dev/null || true)" \
        --arg proof_helper_execution_path \
            "$(resolution_value "$record" proof_helper_execution_path 2>/dev/null || true)" \
        --arg proof_helper_protocol_sha256 \
            "$(resolution_value "$record" proof_helper_protocol_sha256 2>/dev/null || true)" \
        '.schema == $schema and
         .resolution_revision == $revision and
         .resolution_tag == $resolution_tag and
         .resolution_sha256 == $resolution_sha256 and
         .resolution_workflow_commit == $workflow_commit and
         .recovery_tool_sha256 == $recovery_tool_sha256 and
         .manifest_helper_sha256 == $manifest_helper_sha256 and
         .correction_review_sha256 == $correction_review_sha256 and
         .supersedes_resolution_sha256 == $supersedes_resolution_sha256 and
         .selected_manifest_sha256 == $selected_manifest_sha256 and
         (if $revision == 2 then
            .authorize_reason == "recovery_tool_execution_failure"
          else
            .authorize_reason == "product_state_proof_execution_failure" and
            .active_install_journal_sha256 == $active_install_journal_sha256 and
            .active_product_proof_temp_sha256 == $active_product_proof_temp_sha256 and
            .sealed_inputs_resolution_sha256 == $sealed_inputs_resolution_sha256 and
            .planned_product_base_commit == $planned_product_base_commit and
            .proof_helper_source_commit == $proof_helper_source_commit and
            .proof_helper_source_tree_sha256 == $proof_helper_source_tree_sha256 and
            .proof_helper_sha256 == $proof_helper_sha256 and
            .proof_helper_control_plane_sha256 == $proof_helper_control_plane_sha256 and
            .proof_helper_toolchain_sha256 == $proof_helper_toolchain_sha256 and
            .proof_helper_rustflags_sha256 == $proof_helper_rustflags_sha256 and
            .proof_helper_build_target == $proof_helper_build_target and
            .proof_helper_build_profile == $proof_helper_build_profile and
            .proof_helper_build_clean == $proof_helper_build_clean and
            .proof_helper_execution_path == $proof_helper_execution_path and
            .proof_helper_protocol_sha256 == $proof_helper_protocol_sha256
          end)' \
        "$correction_authorization" >/dev/null \
        || die 'correction authorization does not bind the exact corrected resolution'
}

verify_inputs() {
    local operation=$1
    predecessor_dir=$(canonical_dir "$predecessor_dir" 'predecessor directory')
    rejected_dir=$(canonical_dir "$rejected_dir" 'rejected directory')
    selected_dir=$(canonical_dir "$selected_dir" 'selected directory')
    resolution_dir=$(canonical_dir "$resolution_dir" 'resolution directory')
    require_safe_ancestors "$resolution_dir" 'resolution directory'
    require_safe_file "$resolution_dir/$RESOLUTION" 32768 false 'replacement resolution'
    validate_resolution_inline "$resolution_dir/$RESOLUTION"
    local actual_resolution expected_resolution resolution_schema
    resolution_schema=$(resolution_value "$resolution_dir/$RESOLUTION" schema)
    actual_resolution=$(/usr/bin/find "$resolution_dir" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected_resolution=$(resolution_all_names "$resolution_dir/$RESOLUTION" \
        | LC_ALL=C /usr/bin/sort)
    [[ $actual_resolution == "$expected_resolution" ]] \
        || die 'resolution directory has an inexact file set'
    require_safe_file "$resolution_dir/$RESOLUTION_BUNDLE" 4194304 false \
        'replacement resolution signature bundle'
    require_safe_file "$resolution_dir/$SELECTION_REVIEW" 32768 false \
        'replacement selection review'
    if [[ $resolution_schema == 2 ]]; then
        require_safe_file "$resolution_dir/$CORRECTION_REVIEW" 32768 false \
            'replacement resolution correction review'
    fi
    require_safe_file "$resolution_dir/$RECOVERY_TOOL" 1048576 true 'replacement recovery tool'
    require_safe_file "$resolution_dir/$MANIFEST_HELPER" 1048576 true \
        'replacement manifest helper'
    if [[ $operation != verify ]]; then
        [[ $(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}") == \
            "$SEALED_RUNTIME_ROOT/$RECOVERY_TOOL" ]] \
            || die 'installation recovery tool is outside the sealed runtime'
        /usr/bin/cmp -s "${BASH_SOURCE[0]}" "$resolution_dir/$RECOVERY_TOOL" \
            || die 'sealed resolution recovery tool differs from the executing tool'
    else
        [[ $(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}") == \
            "$resolution_dir/$RECOVERY_TOOL" ]] \
            || die 'verification recovery tool must run from the exact resolution directory'
    fi
    [[ $(sha256_file "$resolution_dir/$RESOLUTION") == "$expected_resolution_sha256" ]] \
        || die 'replacement resolution differs from the operator-authorized hash'
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
    [[ $(sha256_file "$resolution_dir/$SELECTION_REVIEW") == \
        "$(resolution_value "$resolution_dir/$RESOLUTION" selection_review_sha256)" ]] \
        || die 'selection review differs from the signed resolution'
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
    verify_correction_authorization "$operation"
}

sync_path() {
    /usr/bin/sync -f "$1"
}

discard_safe_root_temporary() {
    local path=$1 maximum=$2 label=$3 metadata mode parent
    [[ -e $path || -L $path ]] || return 0
    [[ -f $path && ! -L $path ]] \
        || die "$label is not a regular non-link file"
    metadata=$(/usr/bin/stat -c '%u:%g:%h:%s' "$path")
    [[ $metadata =~ ^0:0:1:([0-9]+)$ \
        && ${BASH_REMATCH[1]} -le maximum ]] \
        || die "$label identity or size differs"
    mode=$(/usr/bin/stat -c '%a' "$path")
    (( (8#$mode & 8#022) == 0 )) \
        || die "$label is group/world writable"
    parent=$(/usr/bin/dirname "$path")
    /usr/bin/rm -f -- "$path"
    sync_path "$parent"
}

discard_incomplete_resolution_stage() {
    local stage=$1 actual name metadata mode
    require_root_directory "$stage" 'incomplete replacement receipt stage'
    actual=$(/usr/bin/find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            "$SELECTION_REVIEW"|"$CORRECTION_REVIEW"|\
            "$RESOLUTION"|"$RESOLUTION_BUNDLE"|"$PROOF_HELPER_ASSET") ;;
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
    local generation revision final stage name expected actual
    generation=$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)
    revision=$(resolution_revision "$resolution_dir/$RESOLUTION")
    final=$(resolution_receipt_directory)
    stage=$AUTHORITY_ROOT/.replacement-resolution-v1-g${generation}.staged
    if [[ $revision != 1 ]]; then
        stage=$AUTHORITY_ROOT/.replacement-resolution-v1-g${generation}-r${revision}.staged
    fi
    expected=$(resolution_data_names "$resolution_dir/$RESOLUTION" | LC_ALL=C /usr/bin/sort)
    require_root_directory "$AUTHORITY_ROOT" 'authority root'
    if [[ -e $RESOLUTION_PARENT || -L $RESOLUTION_PARENT ]]; then
        require_root_directory "$RESOLUTION_PARENT" 'replacement receipt parent'
    else
        /usr/bin/install -d -o 0 -g 0 -m 0755 "$RESOLUTION_PARENT"
        sync_path "$AUTHORITY_ROOT"
    fi
    if [[ -d $final && ! -L $final ]]; then
        actual=$(/usr/bin/find "$final" -mindepth 1 -maxdepth 1 -printf '%f\n' \
            | LC_ALL=C /usr/bin/sort)
        [[ $actual == "$expected" ]] \
            || die 'existing replacement receipt directory is inexact'
        require_root_directory "$final" 'existing replacement receipt directory'
        require_root_file "$final/$RESOLUTION" 444 'existing signed replacement receipt'
        require_root_file "$final/$RESOLUTION_BUNDLE" 444 \
            'existing replacement receipt bundle'
        require_root_file "$final/$SELECTION_REVIEW" 444 \
            'existing replacement selection review'
        while IFS= read -r name; do
            require_root_file "$final/$name" 444 "existing replacement receipt $name"
            /usr/bin/cmp -s "$final/$name" "$resolution_dir/$name" \
                || die "existing replacement receipt $name conflicts"
        done < <(resolution_data_names "$resolution_dir/$RESOLUTION")
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
    while IFS= read -r name; do
        /usr/bin/dd if="$resolution_dir/$name" of="$stage/$name" \
            iflag=nofollow,nonblock,fullblock status=none
        /usr/bin/chown 0:0 "$stage/$name"
        /usr/bin/chmod 0444 "$stage/$name"
        sync_path "$stage/$name"
        /usr/bin/cmp -s "$stage/$name" "$resolution_dir/$name" \
            || die 'staged replacement receipt changed during publication'
    done < <(resolution_data_names "$resolution_dir/$RESOLUTION")
    sync_path "$stage"
    /usr/bin/mv -T "$stage" "$final"
    sync_path "$RESOLUTION_PARENT"
}

resolution_receipt_directory() {
    local generation revision
    generation=$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)
    revision=$(resolution_revision "$resolution_dir/$RESOLUTION")
    if [[ $revision == 1 ]]; then
        /usr/bin/printf '%s/generation-%s\n' "$RESOLUTION_PARENT" "$generation"
    else
        /usr/bin/printf '%s/generation-%s-r%s\n' \
            "$RESOLUTION_PARENT" "$generation" "$revision"
    fi
}

require_root_directory() {
    local path=$1 label=$2 metadata mode
    [[ -d $path && ! -L $path ]] || die "$label is not a real directory"
    metadata=$(/usr/bin/stat -c '%u:%g' "$path")
    [[ $metadata == 0:0 ]] || die "$label identity is unsafe"
    mode=$(/usr/bin/stat -c '%a' "$path")
    (( (8#$mode & 8#022) == 0 )) || die "$label is group/world writable"
}

require_root_file() {
    local path=$1 expected_mode=$2 label=$3
    [[ -f $path && ! -L $path ]] || die "$label is not a regular non-link file"
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$path") == "0:0:$expected_mode:1" ]] \
        || die "$label identity is unsafe"
}

require_sealed_runtime() {
    local actual expected
    [[ $script_dir == "$SEALED_RUNTIME_ROOT" ]] \
        || die 'installation must run from the fixed sealed root-owned runtime'
    require_root_directory "$SEALED_RUNTIME_ROOT" 'sealed replacement runtime'
    [[ $(/usr/bin/stat -c '%a' "$SEALED_RUNTIME_ROOT") == 700 ]] \
        || die 'sealed replacement runtime mode differs'
    require_root_file "${BASH_SOURCE[0]}" 500 'sealed replacement recovery tool'
    [[ $(sha256_file "${BASH_SOURCE[0]}") == "$expected_recovery_tool_sha256" ]] \
        || die 'sealed replacement recovery tool differs from the operator-authorized hash'
    actual=$(/usr/bin/find "$SEALED_RUNTIME_ROOT" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(/usr/bin/printf '%s\n' "$RECOVERY_TOOL" | LC_ALL=C /usr/bin/sort)
    if [[ -e $SEALED_CORRECTION_AUTHORIZATION \
        || -L $SEALED_CORRECTION_AUTHORIZATION ]]; then
        require_root_file "$SEALED_CORRECTION_AUTHORIZATION" 400 \
            'sealed correction authorization'
        expected=$(/usr/bin/printf '%s\n' "$expected" \
            "$CORRECTION_AUTHORIZATION_NAME" | LC_ALL=C /usr/bin/sort)
    fi
    if [[ -e $SEALED_INPUTS || -L $SEALED_INPUTS ]]; then
        expected=$(/usr/bin/printf '%s\n' "$expected" inputs \
            | LC_ALL=C /usr/bin/sort)
    elif [[ -e $SEALED_INPUTS_STAGE || -L $SEALED_INPUTS_STAGE ]]; then
        expected=$(/usr/bin/printf '%s\n' "$expected" inputs.staged \
            | LC_ALL=C /usr/bin/sort)
    fi
    [[ $actual == "$expected" ]] || die 'sealed replacement runtime is inexact'
}

require_resolution_source() {
    local directory=$1 actual expected name executable
    directory=$(canonical_dir "$directory" 'resolution source directory')
    require_safe_file "$directory/$RESOLUTION" 32768 false \
        'resolution source replacement resolution'
    validate_resolution_inline "$directory/$RESOLUTION"
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(resolution_all_names "$directory/$RESOLUTION" | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'resolution source has an inexact entry set'
    while IFS= read -r name; do
        require_safe_file "$directory/$name" 4194304 false "resolution source $name"
    done < <(resolution_data_names "$directory/$RESOLUTION")
    for name in "$RECOVERY_TOOL" "$MANIFEST_HELPER"; do
        executable=true
        require_safe_file "$directory/$name" 1048576 "$executable" \
            "resolution source $name"
    done
}

prepare_stage_leaf() {
    local directory=$1 label=$2 actual name
    if [[ -e $directory || -L $directory ]]; then
        require_root_directory "$directory" "$label"
        [[ $(/usr/bin/stat -c '%a' "$directory") == 700 ]] \
            || die "$label mode differs"
    else
        /usr/bin/install -d -o 0 -g 0 -m 0700 "$directory"
    fi
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $label:$name in
            *authority:release-authority-v2.json|\
            *authority:release-authority-v2.json.cosign.bundle|\
            *authority:syntaur-build-authority-provision|\
            *authority:syntaur-ship-linux-x86_64|\
            *authority:syntaur-verify-linux-x86_64|\
            'sealed resolution':recover-release-authority-replacement-v1.sh|\
            'sealed resolution':release-authority-manifest.sh|\
            'sealed resolution':release-authority-selection-review-v1.json|\
            'sealed resolution':release-authority-resolution-correction-v1.json|\
            'sealed resolution':release-authority-replacement-v1.json|\
            'sealed resolution':release-authority-replacement-v1.json.cosign.bundle|\
            'sealed resolution':syntaur-authority-replacement-proof-linux-x86_64) ;;
            *) die "$label contains an unexpected staged entry" ;;
        esac
        [[ -f $directory/$name && ! -L $directory/$name ]] \
            || die "$label staged entry is not a regular non-link file"
        [[ $(/usr/bin/stat -c '%u:%g:%h' "$directory/$name") == 0:0:1 ]] \
            || die "$label staged entry identity differs"
        /usr/bin/rm -f -- "$directory/$name"
    done <<<"$actual"
}

copy_to_stage() {
    local source=$1 target=$2 mode=$3 maximum=$4 label=$5
    require_safe_file "$source" "$maximum" false "$label source"
    /usr/bin/dd if="$source" of="$target" \
        iflag=nofollow,nonblock,fullblock status=none
    /usr/bin/chown 0:0 "$target"
    /usr/bin/chmod "$mode" "$target"
    require_root_file "$target" "$mode" "$label staged copy"
    [[ $(/usr/bin/stat -c '%s' "$target") -gt 0 \
        && $(/usr/bin/stat -c '%s' "$target") -le $maximum ]] \
        || die "$label staged copy size is unsafe"
    sync_path "$target"
}

set_sealed_input_paths() {
    local root=$1
    predecessor_dir=$root/predecessor
    rejected_dir=$root/rejected
    selected_dir=$root/selected
    resolution_dir=$root/resolution
}

require_sealed_input_root() {
    local root=$1 label=$2 actual expected name
    require_root_directory "$root" "$label"
    [[ $(/usr/bin/stat -c '%a' "$root") == 700 ]] || die "$label mode differs"
    actual=$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(/usr/bin/printf '%s\n' predecessor rejected resolution selected \
        | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die "$label has an inexact directory set"
    for name in predecessor rejected resolution selected; do
        require_root_directory "$root/$name" "$label $name"
        [[ $(/usr/bin/stat -c '%a' "$root/$name") == 700 ]] \
            || die "$label $name mode differs"
    done
}

seal_install_inputs() {
    local operation=$1
    local source_predecessor source_rejected source_selected source_resolution
    local leaf name actual source
    if [[ -e $SEALED_INPUTS || -L $SEALED_INPUTS ]]; then
        [[ ! -e $SEALED_INPUTS_STAGE && ! -L $SEALED_INPUTS_STAGE ]] \
            || die 'sealed final and staged inputs both exist'
        require_sealed_input_root "$SEALED_INPUTS" 'sealed replacement inputs'
        set_sealed_input_paths "$SEALED_INPUTS"
        verify_inputs "$operation"
        return
    fi

    source_predecessor=$(canonical_dir "$predecessor_dir" 'predecessor source directory')
    source_rejected=$(canonical_dir "$rejected_dir" 'rejected source directory')
    source_selected=$(canonical_dir "$selected_dir" 'selected source directory')
    source_resolution=$(canonical_dir "$resolution_dir" 'resolution source directory')
    require_exact_authority_dir "$source_predecessor" 'predecessor source authority'
    require_exact_authority_dir "$source_rejected" 'rejected source authority'
    require_exact_authority_dir "$source_selected" 'selected source authority'
    require_resolution_source "$source_resolution"

    if [[ -e $SEALED_INPUTS_STAGE || -L $SEALED_INPUTS_STAGE ]]; then
        require_root_directory "$SEALED_INPUTS_STAGE" 'sealed replacement input stage'
    else
        /usr/bin/install -d -o 0 -g 0 -m 0700 "$SEALED_INPUTS_STAGE"
        sync_path "$SEALED_RUNTIME_ROOT"
    fi
    actual=$(/usr/bin/find "$SEALED_INPUTS_STAGE" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in predecessor|rejected|resolution|selected) ;;
            *) die 'sealed replacement input stage has an unexpected entry' ;;
        esac
        [[ -d $SEALED_INPUTS_STAGE/$name && ! -L $SEALED_INPUTS_STAGE/$name ]] \
            || die 'sealed replacement input stage entry is not a real directory'
    done <<<"$actual"

    for leaf in predecessor rejected selected; do
        prepare_stage_leaf "$SEALED_INPUTS_STAGE/$leaf" "sealed $leaf authority"
        case $leaf in
            predecessor) source=$source_predecessor ;;
            rejected) source=$source_rejected ;;
            selected) source=$source_selected ;;
        esac
        for name in "$MANIFEST" "$BUNDLE"; do
            copy_to_stage "$source/$name" "$SEALED_INPUTS_STAGE/$leaf/$name" \
                400 4194304 "$leaf $name"
        done
        for name in syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
            syntaur-verify-linux-x86_64; do
            copy_to_stage "$source/$name" "$SEALED_INPUTS_STAGE/$leaf/$name" \
                500 268435456 "$leaf $name"
        done
        sync_path "$SEALED_INPUTS_STAGE/$leaf"
    done

    prepare_stage_leaf "$SEALED_INPUTS_STAGE/resolution" 'sealed resolution'
    copy_to_stage "${BASH_SOURCE[0]}" \
        "$SEALED_INPUTS_STAGE/resolution/$RECOVERY_TOOL" 500 1048576 \
        'resolution recovery tool'
    copy_to_stage "$source_resolution/$MANIFEST_HELPER" \
        "$SEALED_INPUTS_STAGE/resolution/$MANIFEST_HELPER" 500 1048576 \
        'resolution manifest helper'
    while IFS= read -r name; do
        copy_to_stage "$source_resolution/$name" \
            "$SEALED_INPUTS_STAGE/resolution/$name" 400 4194304 \
            "resolution $name"
    done < <(resolution_data_names "$source_resolution/$RESOLUTION")
    sync_path "$SEALED_INPUTS_STAGE/resolution"
    sync_path "$SEALED_INPUTS_STAGE"

    require_sealed_input_root "$SEALED_INPUTS_STAGE" \
        'sealed replacement input stage'
    set_sealed_input_paths "$SEALED_INPUTS_STAGE"
    verify_inputs "$operation"
    /usr/bin/mv -T "$SEALED_INPUTS_STAGE" "$SEALED_INPUTS"
    sync_path "$SEALED_RUNTIME_ROOT"
    require_sealed_input_root "$SEALED_INPUTS" 'sealed replacement inputs'
    set_sealed_input_paths "$SEALED_INPUTS"
    verify_inputs "$operation"
}

verify_resolution_correction_initial_prestate() {
    local active_manifest_sha256=$1 product_digest=$2 resolution_receipt=$3
    local correction=$resolution_dir/$CORRECTION_REVIEW active_generation path
    [[ $active_manifest_sha256 == \
        "$(resolution_value "$correction" active_manifest_sha256)" ]] \
        || die 'corrected resolution active authority differs from the reviewed prestate'
    active_generation=$(manifest_value "$AUTHORITY_ROOT/$MANIFEST" generation)
    [[ $active_generation == "$(resolution_value "$correction" active_generation)" ]] \
        || die 'corrected resolution active generation differs from the reviewed prestate'
    [[ $product_digest == \
        "$(resolution_value "$correction" active_product_state_sha256)" ]] \
        || die 'corrected resolution product state differs from the reviewed prestate'
    for path in \
        "$NORMAL_PROMOTION_JOURNAL" "$NORMAL_PROMOTION_JOURNAL_TEMP" \
        "$INSTALL_JOURNAL" "$INSTALL_JOURNAL_TEMP" \
        "$ROLLBACK_JOURNAL" "$ROLLBACK_JOURNAL_TEMP" \
        "$INSTALL_RECEIPT" "$ROLLBACK_RECEIPT" "$resolution_receipt"; do
        [[ ! -e $path && ! -L $path ]] \
            || die 'corrected resolution initial prestate contains mutation state'
    done
}

verify_resolution_correction_r3_state() {
    local operation=$1 active_manifest_sha256=$2 product_digest=$3 correction=$4
    local record=$resolution_dir/$RESOLUTION generation origin_root origin_record
    local origin_receipt r3_receipt actual expected name
    [[ $operation == install ]] \
        || die 'r3 product-proof correction authorizes forward completion only'
    [[ $active_manifest_sha256 == "$expected_selected_sha256" \
        && $active_manifest_sha256 == \
            "$(resolution_value "$correction" active_manifest_sha256)" ]] \
        || die 'r3 correction active authority differs from the reviewed G60 state'
    [[ $(manifest_value "$AUTHORITY_ROOT/$MANIFEST" generation) == \
        "$(resolution_value "$correction" active_generation)" ]] \
        || die 'r3 correction active generation differs from the reviewed G60 state'
    [[ $product_digest == \
        "$(resolution_value "$correction" active_product_state_sha256)" ]] \
        || die 'r3 correction product state moved from its reviewed prestate'
    [[ $(sha256_file "$INSTALL_JOURNAL") == \
        "$(resolution_value "$correction" active_install_journal_sha256)" ]] \
        || die 'r3 correction install journal differs from the reviewed failure'
    [[ $(/usr/bin/jq -er '.phase' "$INSTALL_JOURNAL") == \
        "$(resolution_value "$correction" active_install_journal_phase)" ]] \
        || die 'r3 correction install phase differs from the reviewed failure'
    [[ -e $NORMAL_PROMOTION_JOURNAL && ! -L $NORMAL_PROMOTION_JOURNAL \
        && -e $INSTALL_JOURNAL && ! -L $INSTALL_JOURNAL ]] \
        || die 'r3 correction lacks the reviewed mutation fence and install journal'
    for name in "$NORMAL_PROMOTION_JOURNAL_TEMP" "$INSTALL_JOURNAL_TEMP" \
        "$ROLLBACK_JOURNAL" "$ROLLBACK_JOURNAL_TEMP" \
        "$ROLLBACK_RECEIPT"; do
        [[ ! -e $name && ! -L $name ]] \
            || die 'r3 correction encountered unreviewed mutation state'
    done

    generation=$(resolution_value "$record" selected_generation)
    origin_root=$SUPERSEDED_SEALED_RUNTIME_ROOT/inputs/resolution
    origin_record=$origin_root/$RESOLUTION
    require_root_directory "$SUPERSEDED_SEALED_RUNTIME_ROOT" \
        'superseded sealed replacement runtime'
    [[ $(/usr/bin/stat -c '%a' "$SUPERSEDED_SEALED_RUNTIME_ROOT") == 700 ]] \
        || die 'superseded sealed replacement runtime mode differs'
    require_root_directory "$SUPERSEDED_SEALED_RUNTIME_ROOT/inputs" \
        'superseded sealed replacement inputs'
    require_root_directory "$origin_root" 'superseded sealed resolution'
    require_root_file "$origin_record" 400 'superseded sealed signed resolution'
    require_root_file "$origin_root/$RESOLUTION_BUNDLE" 400 \
        'superseded sealed signed resolution bundle'
    [[ $(sha256_file "$origin_record") == \
            "$(resolution_value "$correction" sealed_inputs_resolution_sha256)" \
        && $(sha256_file "$origin_record") == \
            "$(resolution_value "$record" supersedes_resolution_sha256)" ]] \
        || die 'r3 correction superseded sealed resolution differs'
    validate_resolution_inline "$origin_record"
    [[ $(resolution_revision "$origin_record") == 2 \
        && $(resolution_value "$origin_record" selected_generation) == "$generation" \
        && $(resolution_value "$origin_record" selected_manifest_sha256) == \
            "$expected_selected_sha256" ]] \
        || die 'r3 correction superseded resolution is not exact G60 r2'
    verify_cosign "$origin_record" "$origin_root/$RESOLUTION_BUNDLE" \
        "$(resolution_value "$origin_record" resolution_workflow_commit)" \
        'superseded sealed G60 r2 resolution'

    origin_receipt=$RESOLUTION_PARENT/generation-$generation-r2
    require_root_directory "$origin_receipt" 'G60 r2 resolution receipt'
    [[ $(/usr/bin/stat -c '%a' "$origin_receipt") == 700 ]] \
        || die 'G60 r2 resolution receipt mode differs'
    actual=$(/usr/bin/find "$origin_receipt" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(resolution_data_names "$origin_record" | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'G60 r2 resolution receipt is inexact'
    while IFS= read -r name; do
        require_root_file "$origin_receipt/$name" 444 "G60 r2 receipt $name"
        /usr/bin/cmp -s "$origin_receipt/$name" "$origin_root/$name" \
            || die "G60 r2 receipt $name differs from sealed signed input"
    done < <(resolution_data_names "$origin_record")

    r3_receipt=$RESOLUTION_PARENT/generation-$generation-r3
    if [[ -e $r3_receipt || -L $r3_receipt ]]; then
        install_resolution_receipt
        if [[ -e $INSTALL_RECEIPT || -L $INSTALL_RECEIPT ]]; then
            validate_install_receipt "$product_digest"
        fi
        if [[ -e $PRODUCT_STATE_PROOF_TEMP || -L $PRODUCT_STATE_PROOF_TEMP ]]; then
            require_root_file "$PRODUCT_STATE_PROOF_TEMP" 600 \
                'resumed r3 product-state proof temporary'
            [[ $(/usr/bin/stat -c '%s' "$PRODUCT_STATE_PROOF_TEMP") -le 16384 ]] \
                || die 'resumed r3 product-state proof temporary is oversized'
        fi
    else
        [[ ! -e $INSTALL_RECEIPT && ! -L $INSTALL_RECEIPT ]] \
            || die 'r3 install receipt exists before its signed resolution receipt'
        require_root_file "$PRODUCT_STATE_PROOF_TEMP" 600 \
            'reviewed failed product-state proof temporary'
        [[ $(sha256_file "$PRODUCT_STATE_PROOF_TEMP") == \
                "$(resolution_value "$correction" active_product_proof_temp_sha256)" \
            && $(/usr/bin/stat -c '%s' "$PRODUCT_STATE_PROOF_TEMP") == \
                "$(resolution_value "$correction" active_product_proof_temp_size)" ]] \
            || die 'r3 correction product-state proof failure evidence differs'
    fi
    validate_mutation_fence "$product_digest"
    validate_current_install_state "$product_digest"
    validate_selected_active
}

verify_resolution_correction_state() {
    local operation=$1 active_manifest_sha256=$2
    local record=$resolution_dir/$RESOLUTION schema correction product_digest
    local resolution_receipt normal_journal install_journal rollback_journal
    local install_receipt rollback_receipt path
    schema=$(resolution_value "$record" schema)
    [[ $schema == 2 ]] || return 0
    correction=$resolution_dir/$CORRECTION_REVIEW
    product_digest=$(product_state_digest)
    [[ $product_digest == \
        "$(resolution_value "$correction" active_product_state_sha256)" ]] \
        || die 'corrected resolution product state moved from its reviewed prestate'
    if [[ $(resolution_revision "$record") == 3 ]]; then
        verify_resolution_correction_r3_state \
            "$operation" "$active_manifest_sha256" "$product_digest" "$correction"
        return
    fi
    resolution_receipt=$(resolution_receipt_directory)
    normal_journal=false
    install_journal=false
    rollback_journal=false
    install_receipt=false
    rollback_receipt=false
    [[ -e $NORMAL_PROMOTION_JOURNAL || -L $NORMAL_PROMOTION_JOURNAL ]] \
        && normal_journal=true
    [[ -e $INSTALL_JOURNAL || -L $INSTALL_JOURNAL ]] && install_journal=true
    [[ -e $ROLLBACK_JOURNAL || -L $ROLLBACK_JOURNAL ]] && rollback_journal=true
    [[ -e $INSTALL_RECEIPT || -L $INSTALL_RECEIPT ]] && install_receipt=true
    [[ -e $ROLLBACK_RECEIPT || -L $ROLLBACK_RECEIPT ]] && rollback_receipt=true

    if [[ $operation == install ]]; then
        [[ $rollback_journal == false && $rollback_receipt == false ]] \
            || die 'corrected install conflicts with rollback state'
        if [[ $active_manifest_sha256 == "$expected_predecessor_sha256" ]]; then
            [[ $install_receipt == false ]] \
                || die 'corrected install receipt conflicts with active predecessor'
            if [[ $normal_journal == false && $install_journal == false ]]; then
                if [[ -e $resolution_receipt || -L $resolution_receipt ]]; then
                    install_resolution_receipt
                    for path in \
                        "$NORMAL_PROMOTION_JOURNAL_TEMP" "$INSTALL_JOURNAL_TEMP" \
                        "$ROLLBACK_JOURNAL_TEMP"; do
                        [[ ! -e $path && ! -L $path ]] \
                            || die 'corrected receipt-only continuation has unexplained temporary state'
                    done
                else
                    verify_resolution_correction_initial_prestate \
                        "$active_manifest_sha256" "$product_digest" \
                        "$resolution_receipt"
                fi
                return
            fi
            [[ -e $resolution_receipt && ! -L $resolution_receipt ]] \
                || die 'corrected install continuation lacks its exact resolution receipt'
            install_resolution_receipt
            [[ $normal_journal == true ]] \
                || die 'corrected install journal exists without its mutation fence'
            validate_mutation_fence "$product_digest"
            if [[ $install_journal == true ]]; then
                validate_current_install_state "$product_digest"
            else
                validate_predecessor_active
            fi
            return
        fi
        [[ $active_manifest_sha256 == "$expected_selected_sha256" ]] \
            || die 'corrected install active authority is outside its signed transaction'
        [[ -e $resolution_receipt && ! -L $resolution_receipt ]] \
            || die 'corrected selected authority lacks its exact resolution receipt'
        install_resolution_receipt
        if [[ $install_receipt == true ]]; then
            validate_install_receipt "$product_digest"
            if [[ $install_journal == true ]]; then
                [[ $normal_journal == true ]] \
                    || die 'corrected terminal install journal lacks its mutation fence'
                validate_mutation_fence "$product_digest"
                validate_current_install_state "$product_digest"
            elif [[ $normal_journal == true ]]; then
                validate_mutation_fence "$product_digest"
            fi
            return
        fi
        [[ $normal_journal == true && $install_journal == true ]] \
            || die 'corrected selected authority lacks a resumable install journal'
        validate_mutation_fence "$product_digest"
        validate_current_install_state "$product_digest"
        return
    fi

    [[ $install_journal == false && $install_receipt == true ]] \
        || die 'corrected rollback requires a completed exceptional install'
    [[ -e $resolution_receipt && ! -L $resolution_receipt ]] \
        || die 'corrected rollback lacks its exact resolution receipt'
    install_resolution_receipt
    validate_install_receipt "$product_digest"
    if [[ $active_manifest_sha256 == "$expected_selected_sha256" ]]; then
        [[ $rollback_receipt == false ]] \
            || die 'corrected rollback receipt conflicts with active selected authority'
        if [[ $rollback_journal == true ]]; then
            [[ $normal_journal == true ]] \
                || die 'corrected rollback journal exists without its mutation fence'
            validate_mutation_fence "$product_digest"
            validate_current_rollback_state "$product_digest"
        elif [[ $normal_journal == true ]]; then
            validate_mutation_fence "$product_digest"
            validate_selected_active
        fi
        return
    fi
    [[ $active_manifest_sha256 == "$expected_predecessor_sha256" \
        && ( $rollback_journal == true || $rollback_receipt == true ) ]] \
        || die 'corrected rollback active authority is outside its signed transaction'
    if [[ $rollback_journal == true ]]; then
        [[ $normal_journal == true ]] \
            || die 'corrected rollback journal exists without its mutation fence'
        validate_mutation_fence "$product_digest"
        validate_current_rollback_state "$product_digest"
    fi
    if [[ $rollback_receipt == true ]]; then
        validate_rollback_receipt "$product_digest"
    fi
}

resolve_operator_home() {
    operator_home=$(/usr/bin/getent passwd "$SUDO_UID" | /usr/bin/awk -F: \
        -v uid="$SUDO_UID" -v name="$SUDO_USER" \
        '$1 == name && $3 == uid { if (seen++) exit 2; print $6 }') \
        || die 'sudo operator account lookup failed'
    [[ $operator_home == /* && -d $operator_home && ! -L $operator_home ]] \
        || die 'sudo operator home is unsafe'
    [[ $(/usr/bin/stat -c '%u:%g:%a' "$operator_home") == \
        "$SUDO_UID:$SUDO_GID:700" ]] \
        || die 'sudo operator home identity differs'
    operator_state=$operator_home/.syntaur/ship
    deployment_lock=$operator_state/deploy.lock
    require_root_directory "$AUTHORITY_ROOT" 'authority root'
    [[ -f $GLOBAL_MUTATION_LOCK && ! -L $GLOBAL_MUTATION_LOCK ]] \
        || die 'global mutation lock is not a regular non-link file'
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h:%s' "$GLOBAL_MUTATION_LOCK") == \
        "0:$SUDO_GID:440:1:0" ]] || die 'global mutation lock identity differs'
    require_safe_file "$deployment_lock" 64 false 'operator deployment lock'
    [[ $(/usr/bin/stat -c '%u:%g:%a:%h' "$deployment_lock") == \
        "$SUDO_UID:$SUDO_GID:600:1" ]] \
        || die 'operator deployment lock identity differs'
    exec 8<"$GLOBAL_MUTATION_LOCK"
    /usr/bin/flock -n 8 || die 'another host mutation holds the global lock'
    exec 9<"$deployment_lock"
    /usr/bin/flock -n 9 || die 'another deployment holds the operator lock'
    global_lock_identity=$(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' \
        "$GLOBAL_MUTATION_LOCK")
    deployment_lock_identity=$(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' \
        "$deployment_lock")
}

assert_host_locks() {
    [[ $(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$GLOBAL_MUTATION_LOCK") == \
        "$global_lock_identity" ]] || die 'global mutation lock changed identity'
    [[ $(/usr/bin/stat -c '%d:%i:%u:%g:%a:%h' "$deployment_lock") == \
        "$deployment_lock_identity" ]] || die 'operator deployment lock changed identity'
    /usr/bin/flock -n 8 || die 'global mutation lock is no longer held'
    /usr/bin/flock -n 9 || die 'operator deployment lock is no longer held'
}

require_operator_private_directory() {
    local path=$1 label=$2
    [[ -d $path && ! -L $path ]] || die "$label is not a real directory"
    [[ $(/usr/bin/stat -c '%u:%g:%a' "$path") == \
        "$SUDO_UID:$SUDO_GID:700" ]] || die "$label identity differs"
}

require_operator_private_file() {
    local path=$1 maximum=$2 label=$3 metadata
    [[ -f $path && ! -L $path ]] \
        || die "$label is not a regular non-link file"
    metadata=$(/usr/bin/stat -c '%u:%g:%a:%h:%s' "$path")
    [[ $metadata =~ ^${SUDO_UID}:${SUDO_GID}:400:1:([0-9]+)$ \
        && ${BASH_REMATCH[1]} -gt 0 \
        && ${BASH_REMATCH[1]} -le maximum ]] \
        || die "$label identity or size differs"
}

require_operator_symlink() {
    local path=$1 expected_target=$2 label=$3
    [[ -L $path && $(/usr/bin/stat -c '%u:%g:%h' "$path") == \
        "$SUDO_UID:$SUDO_GID:1" ]] || die "$label identity differs"
    [[ $(/usr/bin/readlink -- "$path") == "$expected_target" ]] \
        || die "$label target differs"
}

product_state_digest_values() {
    [[ $# -eq 7 ]] || die 'product-state digest tuple arity differs'
    {
        /usr/bin/printf '%s\0' syntaur-exact-terminal-production-state-v1
        /usr/bin/printf '%s\0' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    } | /usr/bin/sha256sum | /usr/bin/awk '{print $1}'
}

product_state_digest() {
    local record current_target generation_root actual expected stamp
    local version source_commit engine_commit gateway_sha browser_sha production_id
    local deploy_stamp_generation
    record=$resolution_dir/$RESOLUTION
    [[ -L $operator_state/deploy-stamp.current ]] \
        || die 'current deploy-stamp pointer is not a symlink'
    current_target=$(/usr/bin/readlink -- "$operator_state/deploy-stamp.current") \
        || die 'current deploy-stamp pointer is missing'
    [[ $current_target =~ ^deploy-stamp\.generations/(g-b-[0-9a-f]{64}-[0-9a-f]{64})$ ]] \
        || die 'current deploy-stamp pointer target is noncanonical'
    deploy_stamp_generation=${BASH_REMATCH[1]}
    require_operator_symlink "$operator_state/deploy-stamp.current" \
        "$current_target" 'current deploy-stamp pointer'
    require_operator_symlink "$operator_state/deploy-stamp.json" \
        deploy-stamp.current/deploy-stamp.json 'deploy-stamp alias'
    require_operator_symlink "$operator_state/deploy-stamp.json.cosign.bundle" \
        deploy-stamp.current/deploy-stamp.json.cosign.bundle \
        'deploy-stamp bundle alias'
    require_operator_private_directory "$operator_state" 'operator deployment state'
    require_operator_private_directory "$operator_state/deploy-stamp.generations" \
        'deploy-stamp generation store'
    generation_root=$operator_state/$current_target
    require_operator_private_directory "$generation_root" 'current deploy-stamp generation'
    actual=$(/usr/bin/find "$generation_root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(/usr/bin/printf '%s\n' AUTHORIZED.json deploy-stamp.json \
        deploy-stamp.json.cosign.bundle | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'current deploy-stamp generation is inexact'
    require_operator_private_file "$generation_root/AUTHORIZED.json" 32768 \
        'current deploy-stamp authorization'
    require_operator_private_file "$generation_root/deploy-stamp.json" 4194304 \
        'current deploy stamp'
    require_operator_private_file "$generation_root/deploy-stamp.json.cosign.bundle" \
        4194304 'current deploy-stamp bundle'
    /usr/bin/cmp -s "$operator_state/deploy-stamp.json" \
        "$generation_root/deploy-stamp.json" \
        || die 'deploy-stamp alias differs from its current generation'
    /usr/bin/cmp -s "$operator_state/deploy-stamp.json.cosign.bundle" \
        "$generation_root/deploy-stamp.json.cosign.bundle" \
        || die 'deploy-stamp bundle alias differs from its current generation'

    stamp=$generation_root/deploy-stamp.json
    version=$(/usr/bin/jq -er '.version' "$stamp")
    source_commit=$(/usr/bin/jq -er '.git_head' "$stamp")
    engine_commit=$(/usr/bin/jq -er '.browser_git_head' "$stamp")
    gateway_sha=$(/usr/bin/jq -er '.gateway_sha256' "$stamp")
    browser_sha=$(/usr/bin/jq -er '.browser_sha256' "$stamp")
    production_id=$(/usr/bin/jq -er \
        '.production_generation.production_generation_id' "$stamp")
    [[ $version == "$(resolution_value "$record" settled_product_version)" \
        && $source_commit == \
            "$(resolution_value "$record" settled_product_gateway_commit)" \
        && $engine_commit == \
            "$(resolution_value "$record" settled_product_engine_commit)" ]] \
        || die 'current deploy stamp names a different settled product tuple'
    if ! valid_commit "$source_commit" || ! valid_commit "$engine_commit"; then
        die 'current deploy-stamp commit tuple is malformed'
    fi
    if ! valid_sha256 "$gateway_sha" || ! valid_sha256 "$browser_sha" \
        || ! valid_sha256 "$production_id"; then
        die 'current deploy-stamp digest tuple is malformed'
    fi
    product_state_digest_values "$version" "$source_commit" "$engine_commit" \
        "$deploy_stamp_generation" "$gateway_sha" "$browser_sha" "$production_id"
}

require_proof_helper_parent() {
    local path metadata mode
    for path in /usr /usr/local "$PROOF_HELPER_PARENT"; do
        [[ -d $path && ! -L $path ]] \
            || die 'proof-helper parent chain is not a real directory'
        metadata=$(/usr/bin/stat -c '%u:%g' "$path")
        [[ $metadata == 0:0 ]] || die 'proof-helper parent chain is not root owned'
        mode=$(/usr/bin/stat -c '%a' "$path")
        (( (8#$mode & 8#022) == 0 )) \
            || die 'proof-helper parent chain is group/world writable'
    done
}

validate_installed_proof_helper() {
    local actual expected record=$resolution_dir/$RESOLUTION
    require_proof_helper_parent
    require_root_directory "$PROOF_HELPER_ROOT" 'installed replacement proof helper root'
    [[ $(/usr/bin/stat -c '%a' "$PROOF_HELPER_ROOT") == 755 ]] \
        || die 'installed replacement proof helper root mode differs'
    actual=$(/usr/bin/find "$PROOF_HELPER_ROOT" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    expected=$(/usr/bin/printf '%s\n' \
        "$PROOF_HELPER_NAME" "$RESOLUTION" "$RESOLUTION_BUNDLE" \
        | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$expected" ]] || die 'installed replacement proof helper is inexact'
    require_root_file "$PROOF_HELPER_ROOT/$PROOF_HELPER_NAME" 555 \
        'installed replacement proof helper'
    require_root_file "$PROOF_HELPER_ROOT/$RESOLUTION" 444 \
        'installed replacement proof resolution'
    require_root_file "$PROOF_HELPER_ROOT/$RESOLUTION_BUNDLE" 444 \
        'installed replacement proof resolution bundle'
    [[ $(sha256_file "$PROOF_HELPER_ROOT/$PROOF_HELPER_NAME") == \
            "$(resolution_value "$record" proof_helper_sha256)" \
        && $(sha256_file "$PROOF_HELPER_ROOT/$RESOLUTION") == \
            "$expected_resolution_sha256" ]] \
        || die 'installed replacement proof helper differs from the signed r3 resolution'
    /usr/bin/cmp -s "$PROOF_HELPER_ROOT/$RESOLUTION" \
        "$resolution_dir/$RESOLUTION" \
        || die 'installed replacement proof resolution bytes differ'
    /usr/bin/cmp -s "$PROOF_HELPER_ROOT/$RESOLUTION_BUNDLE" \
        "$resolution_dir/$RESOLUTION_BUNDLE" \
        || die 'installed replacement proof resolution bundle differs'
}

discard_proof_helper_stage() {
    local actual name mode
    [[ -e $PROOF_HELPER_STAGE || -L $PROOF_HELPER_STAGE ]] || return 0
    require_root_directory "$PROOF_HELPER_STAGE" 'replacement proof helper stage'
    mode=$(/usr/bin/stat -c '%a' "$PROOF_HELPER_STAGE")
    [[ $mode == 700 || $mode == 755 ]] \
        || die 'replacement proof helper stage mode differs'
    /usr/bin/chmod 0700 "$PROOF_HELPER_STAGE"
    actual=$(/usr/bin/find "$PROOF_HELPER_STAGE" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            "$PROOF_HELPER_NAME"|"$RESOLUTION"|"$RESOLUTION_BUNDLE") ;;
            *) die 'replacement proof helper stage contains an unexpected entry' ;;
        esac
        [[ -f $PROOF_HELPER_STAGE/$name && ! -L $PROOF_HELPER_STAGE/$name \
            && $(/usr/bin/stat -c '%u:%g:%h' "$PROOF_HELPER_STAGE/$name") == 0:0:1 ]] \
            || die 'replacement proof helper stage entry is unsafe'
        /usr/bin/rm -f -- "$PROOF_HELPER_STAGE/$name"
    done <<<"$actual"
    /usr/bin/rmdir -- "$PROOF_HELPER_STAGE"
    sync_path "$PROOF_HELPER_PARENT"
}

install_proof_helper() {
    local record=$resolution_dir/$RESOLUTION
    [[ $(resolution_revision "$record") == 3 ]] \
        || die 'proof helper installation requires an r3 signed resolution'
    require_proof_helper_parent
    if [[ -e $PROOF_HELPER_ROOT || -L $PROOF_HELPER_ROOT ]]; then
        [[ ! -e $PROOF_HELPER_STAGE && ! -L $PROOF_HELPER_STAGE ]] \
            || die 'proof-helper final and stage both exist'
        validate_installed_proof_helper
        return
    fi
    discard_proof_helper_stage
    /usr/bin/install -d -o 0 -g 0 -m 0700 "$PROOF_HELPER_STAGE"
    copy_to_stage "$resolution_dir/$PROOF_HELPER_ASSET" \
        "$PROOF_HELPER_STAGE/$PROOF_HELPER_NAME" 555 268435456 \
        'replacement proof helper'
    copy_to_stage "$resolution_dir/$RESOLUTION" \
        "$PROOF_HELPER_STAGE/$RESOLUTION" 444 32768 \
        'replacement proof resolution'
    copy_to_stage "$resolution_dir/$RESOLUTION_BUNDLE" \
        "$PROOF_HELPER_STAGE/$RESOLUTION_BUNDLE" 444 4194304 \
        'replacement proof resolution bundle'
    /usr/bin/chmod 0755 "$PROOF_HELPER_STAGE"
    sync_path "$PROOF_HELPER_STAGE"
    /usr/bin/mv -T "$PROOF_HELPER_STAGE" "$PROOF_HELPER_ROOT"
    sync_path "$PROOF_HELPER_PARENT"
    validate_installed_proof_helper
}

retire_proof_helper() {
    validate_installed_proof_helper
    [[ ! -e $PROOF_HELPER_STAGE && ! -L $PROOF_HELPER_STAGE ]] \
        || die 'proof-helper retirement stage already exists'
    /usr/bin/mv -T "$PROOF_HELPER_ROOT" "$PROOF_HELPER_STAGE"
    sync_path "$PROOF_HELPER_PARENT"
    discard_proof_helper_stage
}

run_operator_product_state_proof() {
    local signed_digest=$1 record output_size canonical revision
    local installed_generation installed_manifest installed_commit
    local version source_commit engine_commit deploy_generation
    local gateway_sha browser_sha production_id product_digest policy_digest
    record=$resolution_dir/$RESOLUTION
    revision=$(resolution_revision "$record")
    if [[ $revision == 3 ]]; then
        install_proof_helper
    fi
    discard_safe_root_temporary "$PRODUCT_STATE_PROOF_TEMP" 16384 \
        'authority replacement product-state proof temporary'
    (
        ulimit -f 32
        if [[ $revision == 3 ]]; then
            /usr/bin/setpriv \
                --reuid "$SUDO_UID" \
                --regid "$SUDO_GID" \
                --clear-groups \
                /usr/bin/env -i \
                    HOME="$operator_home" USER="$SUDO_USER" LOGNAME="$SUDO_USER" \
                    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
                    /usr/bin/timeout 300 \
                    "$PROOF_HELPER_ROOT/$PROOF_HELPER_NAME" \
                    authority-replacement-product-state-helper
        else
            /usr/bin/setpriv \
                --reuid "$SUDO_UID" \
                --regid "$SUDO_GID" \
                --clear-groups \
                /usr/bin/env -i \
                    HOME="$operator_home" USER="$SUDO_USER" LOGNAME="$SUDO_USER" \
                    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
                    /usr/bin/timeout 300 \
                    "$INSTALLED_SHIPPER" authority-replacement-product-state \
                    --expected-installed-generation \
                    "$(resolution_value "$record" selected_generation)" \
                    --expected-installed-manifest-sha256 "$expected_selected_sha256" \
                    --expected-product-version \
                    "$(resolution_value "$record" settled_product_version)" \
                    --expected-product-source-commit \
                    "$(resolution_value "$record" settled_product_gateway_commit)" \
                    --expected-product-engine-commit \
                    "$(resolution_value "$record" settled_product_engine_commit)"
        fi
    ) >"$PRODUCT_STATE_PROOF_TEMP" \
        || die 'installed selected authority did not prove the exact settled product state'
    require_root_file "$PRODUCT_STATE_PROOF_TEMP" 600 \
        'authority replacement product-state proof temporary'
    output_size=$(/usr/bin/stat -c '%s' "$PRODUCT_STATE_PROOF_TEMP")
    (( output_size > 0 && output_size <= 16384 )) \
        || die 'authority replacement product-state proof size is unsafe'
    [[ $(/usr/bin/wc -l <"$PRODUCT_STATE_PROOF_TEMP") -eq 1 ]] \
        || die 'authority replacement product-state proof is not exactly one line'
    /usr/bin/jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        (.schema == 1) and
        (.state == "exact_terminal_production") and
        (.installed_authority_generation | type == "number" and . > 0 and floor == .) and
        (.installed_authority_manifest_sha256 | digest) and
        (.installed_authority_commit | commit) and
        (.product_version | type == "string" and
          test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
        (.product_source_commit | commit) and
        (.product_engine_commit | commit) and
        (.deploy_stamp_generation | type == "string" and
          test("^g-b-[0-9a-f]{64}-[0-9a-f]{64}$")) and
        (.gateway_sha256 | digest) and
        (.browser_sha256 | digest) and
        (.production_generation_id | digest) and
        (.product_state_sha256 | digest) and
        (.promotion_policy_sha256 | digest) and
        (keys | sort) == ([
          "browser_sha256", "deploy_stamp_generation", "gateway_sha256",
          "installed_authority_commit", "installed_authority_generation",
          "installed_authority_manifest_sha256", "product_engine_commit",
          "product_source_commit", "product_state_sha256", "product_version",
          "production_generation_id", "promotion_policy_sha256", "schema", "state"
        ] | sort)
    ' "$PRODUCT_STATE_PROOF_TEMP" >/dev/null \
        || die 'authority replacement product-state proof shape is invalid'
    installed_generation=$(/usr/bin/jq -er '.installed_authority_generation' \
        "$PRODUCT_STATE_PROOF_TEMP")
    installed_manifest=$(/usr/bin/jq -er '.installed_authority_manifest_sha256' \
        "$PRODUCT_STATE_PROOF_TEMP")
    installed_commit=$(/usr/bin/jq -er '.installed_authority_commit' \
        "$PRODUCT_STATE_PROOF_TEMP")
    version=$(/usr/bin/jq -er '.product_version' "$PRODUCT_STATE_PROOF_TEMP")
    source_commit=$(/usr/bin/jq -er '.product_source_commit' \
        "$PRODUCT_STATE_PROOF_TEMP")
    engine_commit=$(/usr/bin/jq -er '.product_engine_commit' \
        "$PRODUCT_STATE_PROOF_TEMP")
    deploy_generation=$(/usr/bin/jq -er '.deploy_stamp_generation' \
        "$PRODUCT_STATE_PROOF_TEMP")
    gateway_sha=$(/usr/bin/jq -er '.gateway_sha256' "$PRODUCT_STATE_PROOF_TEMP")
    browser_sha=$(/usr/bin/jq -er '.browser_sha256' "$PRODUCT_STATE_PROOF_TEMP")
    production_id=$(/usr/bin/jq -er '.production_generation_id' \
        "$PRODUCT_STATE_PROOF_TEMP")
    product_digest=$(/usr/bin/jq -er '.product_state_sha256' \
        "$PRODUCT_STATE_PROOF_TEMP")
    policy_digest=$(/usr/bin/jq -er '.promotion_policy_sha256' \
        "$PRODUCT_STATE_PROOF_TEMP")
    [[ $installed_generation == \
            "$(resolution_value "$record" selected_generation)" \
        && $installed_manifest == "$expected_selected_sha256" \
        && $installed_commit == \
            "$(resolution_value "$record" selected_authority_commit)" \
        && $version == "$(resolution_value "$record" settled_product_version)" \
        && $source_commit == \
            "$(resolution_value "$record" settled_product_gateway_commit)" \
        && $engine_commit == \
            "$(resolution_value "$record" settled_product_engine_commit)" \
        && $policy_digest == \
            "$(resolution_value "$record" settled_promotion_policy_sha256)" ]] \
        || die 'authority replacement product-state proof differs from the signed tuple'
    [[ $(product_state_digest_values "$version" "$source_commit" "$engine_commit" \
            "$deploy_generation" "$gateway_sha" "$browser_sha" "$production_id") == \
            "$product_digest" \
        && $product_digest == "$signed_digest" ]] \
        || die 'authority replacement product-state proof digest differs from the signed state'
    canonical=$(/usr/bin/jq -cjn \
        --argjson schema 1 \
        --arg state exact_terminal_production \
        --argjson installed_authority_generation "$installed_generation" \
        --arg installed_authority_manifest_sha256 "$installed_manifest" \
        --arg installed_authority_commit "$installed_commit" \
        --arg product_version "$version" \
        --arg product_source_commit "$source_commit" \
        --arg product_engine_commit "$engine_commit" \
        --arg deploy_stamp_generation "$deploy_generation" \
        --arg gateway_sha256 "$gateway_sha" \
        --arg browser_sha256 "$browser_sha" \
        --arg production_generation_id "$production_id" \
        --arg product_state_sha256 "$product_digest" \
        --arg promotion_policy_sha256 "$policy_digest" \
        '{schema:$schema,state:$state,
          installed_authority_generation:$installed_authority_generation,
          installed_authority_manifest_sha256:$installed_authority_manifest_sha256,
          installed_authority_commit:$installed_authority_commit,
          product_version:$product_version,
          product_source_commit:$product_source_commit,
          product_engine_commit:$product_engine_commit,
          deploy_stamp_generation:$deploy_stamp_generation,
          gateway_sha256:$gateway_sha256,browser_sha256:$browser_sha256,
          production_generation_id:$production_generation_id,
          product_state_sha256:$product_state_sha256,
          promotion_policy_sha256:$promotion_policy_sha256}')
    [[ $(<"$PRODUCT_STATE_PROOF_TEMP") == "$canonical" \
        && $output_size -eq $((${#canonical} + 1)) ]] \
        || die 'authority replacement product-state proof is not canonical JSON'
    /usr/bin/rm -f -- "$PRODUCT_STATE_PROOF_TEMP"
    sync_path "$AUTHORITY_ROOT"
    if [[ $revision == 3 ]]; then
        retire_proof_helper
    fi
}

require_no_product_mutation_journals() {
    local relative
    for relative in deploy-stamp.publication.json manual-rollback.publication.json \
        deploy-journal-outbox.json; do
        [[ ! -e $operator_state/$relative && ! -L $operator_state/$relative ]] \
            || die "product mutation journal $relative is pending"
    done
    [[ ! -e $NORMAL_PROMOTION_JOURNAL_TEMP \
        && ! -L $NORMAL_PROMOTION_JOURNAL_TEMP ]] \
        || die 'normal authority promotion temporary journal is pending'
}

workflow_trust_sha256() {
    /usr/bin/printf '%s\n' "$1" | /usr/bin/sha256sum | /usr/bin/awk '{print $1}'
}

generation_names() {
    /usr/bin/printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C /usr/bin/sort
}

validate_installed_generation() {
    local directory=$1 material=$2 workflow_commit=$3 label=$4 actual name mode
    require_root_directory "$directory" "$label"
    [[ $(/usr/bin/stat -c '%a' "$directory") == 555 ]] || die "$label mode differs"
    actual=$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    [[ $actual == "$(generation_names)" ]] || die "$label has an inexact entry set"
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit; do
        require_root_file "$directory/$name" 444 "$label $name"
    done
    for name in syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        require_root_file "$directory/$name" 555 "$label $name"
    done
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        /usr/bin/cmp -s "$directory/$name" "$material/$name" \
            || die "$label $name differs from sealed material"
    done
    [[ $(<"$directory/trusted-workflow-commit") == "$workflow_commit" \
        && $(/usr/bin/wc -l <"$directory/trusted-workflow-commit") -eq 1 ]] \
        || die "$label workflow trust differs"
}

stage_generation() {
    local material=$1 workflow_commit=$2 generation=$3 final stage name mode
    final=$ARTIFACT_ROOT/generation-$generation
    stage=$ARTIFACT_ROOT/.generation-${generation}-authority-replacement-v1.staged
    if [[ -e $final || -L $final ]]; then
        validate_installed_generation "$final" "$material" "$workflow_commit" \
            "retained generation $generation"
        return
    fi
    discard_generation_stage "$stage" "$generation"
    /usr/bin/install -d -o 0 -g 0 -m 0700 "$stage"
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        copy_to_stage "$material/$name" "$stage/$name" 444 4194304 \
            "generation $generation $name"
    done
    for name in syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        copy_to_stage "$material/$name" "$stage/$name" 555 268435456 \
            "generation $generation $name"
    done
    /usr/bin/printf '%s\n' "$workflow_commit" >"$stage/trusted-workflow-commit"
    /usr/bin/chown 0:0 "$stage/trusted-workflow-commit"
    /usr/bin/chmod 0444 "$stage/trusted-workflow-commit"
    sync_path "$stage/trusted-workflow-commit"
    /usr/bin/chmod 0555 "$stage"
    sync_path "$stage"
    /usr/bin/mv -T "$stage" "$final"
    sync_path "$ARTIFACT_ROOT"
    validate_installed_generation "$final" "$material" "$workflow_commit" \
        "retained generation $generation"
}

discard_generation_stage() {
    local stage=$1 generation=$2 actual name path maximum metadata mode
    [[ -e $stage || -L $stage ]] || return 0
    [[ -d $stage && ! -L $stage ]] \
        || die "partial generation $generation stage is not a real directory"
    metadata=$(/usr/bin/stat -c '%u:%g:%a' "$stage")
    [[ $metadata == 0:0:700 || $metadata == 0:0:555 ]] \
        || die "partial generation $generation stage identity differs"
    /usr/bin/chmod 0700 "$stage"
    actual=$(/usr/bin/find "$stage" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C /usr/bin/sort)
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        case $name in
            release-authority-v2.json|release-authority-v2.json.cosign.bundle)
                maximum=4194304
                ;;
            syntaur-build-authority-provision|syntaur-ship-linux-x86_64|\
            syntaur-verify-linux-x86_64)
                maximum=268435456
                ;;
            trusted-workflow-commit)
                maximum=64
                ;;
            *) die "partial generation $generation stage has an unexpected entry" ;;
        esac
        path=$stage/$name
        [[ -f $path && ! -L $path ]] \
            || die "partial generation $generation stage entry is unsafe"
        metadata=$(/usr/bin/stat -c '%u:%g:%h:%s' "$path")
        [[ $metadata =~ ^0:0:1:([0-9]+)$ \
            && ${BASH_REMATCH[1]} -le maximum ]] \
            || die "partial generation $generation stage entry identity differs"
        mode=$(/usr/bin/stat -c '%a' "$path")
        (( (8#$mode & 8#022) == 0 )) \
            || die "partial generation $generation stage entry is group/world writable"
        /usr/bin/rm -f -- "$path"
    done <<<"$actual"
    /usr/bin/rmdir -- "$stage"
    sync_path "$ARTIFACT_ROOT"
}

publish_active_file() {
    local source=$1 target=$2 selected_sha=$3 predecessor_sha=$4 mode=$5 label=$6
    local current temporary source_size
    require_root_file "$target" "$mode" "$label"
    source_size=$(/usr/bin/stat -c '%s' "$source")
    (( source_size > 0 && source_size <= 268435456 )) \
        || die "$label publication source size is unsafe"
    temporary=$target.authority-replacement-v1.tmp
    discard_safe_root_temporary "$temporary" "$source_size" \
        "$label publication temporary"
    current=$(sha256_file "$target")
    if [[ $current == "$selected_sha" ]]; then
        require_root_file "$target" "$mode" "$label"
        return
    fi
    [[ $current == "$predecessor_sha" ]] || die "$label has an unknown digest"
    /usr/bin/dd if="$source" of="$temporary" \
        iflag=nofollow,nonblock,fullblock status=none
    /usr/bin/chown 0:0 "$temporary"
    /usr/bin/chmod "$mode" "$temporary"
    sync_path "$temporary"
    [[ $(sha256_file "$temporary") == "$selected_sha" ]] \
        || die "$label publication temporary differs"
    /usr/bin/mv -T "$temporary" "$target"
    sync_path "$(/usr/bin/dirname "$target")"
    require_root_file "$target" "$mode" "$label"
    [[ $(sha256_file "$target") == "$selected_sha" ]] || die "$label publication failed"
}

journal_resolution_record() {
    local record=$resolution_dir/$RESOLUTION
    if [[ $(resolution_revision "$record") == 3 ]]; then
        /usr/bin/printf '%s\n' \
            "$SUPERSEDED_SEALED_RUNTIME_ROOT/inputs/resolution/$RESOLUTION"
    else
        /usr/bin/printf '%s\n' "$record"
    fi
}

install_record_json() {
    local schema=$1 phase=$2 product_digest=$3
    local record=$resolution_dir/$RESOLUTION journal_record
    journal_record=$(journal_resolution_record)
    /usr/bin/jq -cjn \
        --arg schema "$schema" \
        --arg phase "$phase" \
        --arg resolution_sha256 "$(sha256_file "$journal_record")" \
        --arg selection_review_sha256 \
            "$(resolution_value "$journal_record" selection_review_sha256)" \
        --argjson previous_generation \
            "$(resolution_value "$record" predecessor_generation)" \
        --arg previous_manifest_sha256 "$expected_predecessor_sha256" \
        --argjson target_generation \
            "$(resolution_value "$record" selected_generation)" \
        --arg target_manifest_sha256 "$expected_selected_sha256" \
        --arg target_workflow_commit \
            "$(resolution_value "$record" selected_workflow_commit)" \
        --arg target_shipper_sha256 \
            "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" \
        --arg target_provisioner_sha256 \
            "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" \
        --arg settled_product_version \
            "$(resolution_value "$record" settled_product_version)" \
        --arg settled_product_gateway_commit \
            "$(resolution_value "$record" settled_product_gateway_commit)" \
        --arg settled_product_engine_commit \
            "$(resolution_value "$record" settled_product_engine_commit)" \
        --arg settled_promotion_policy_sha256 \
            "$(resolution_value "$record" settled_promotion_policy_sha256)" \
        --arg selected_gateway_commit \
            "$(resolution_value "$record" selected_authority_commit)" \
        --arg selected_engine_commit \
            "$(resolution_value "$record" selected_engine_commit)" \
        --arg product_state_sha256 "$product_digest" \
        '{schema:$schema,phase:$phase,
          resolution_sha256:$resolution_sha256,
          selection_review_sha256:$selection_review_sha256,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          target_generation:$target_generation,
          target_manifest_sha256:$target_manifest_sha256,
          target_workflow_commit:$target_workflow_commit,
          target_shipper_sha256:$target_shipper_sha256,
          target_provisioner_sha256:$target_provisioner_sha256,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_gateway_commit:$selected_gateway_commit,
          selected_engine_commit:$selected_engine_commit,
          product_state_sha256:$product_state_sha256}'
}

install_phase_rank() {
    case $1 in
        prepared) /usr/bin/printf '0\n' ;;
        generation_published) /usr/bin/printf '1\n' ;;
        shipper_published) /usr/bin/printf '2\n' ;;
        provisioner_published) /usr/bin/printf '3\n' ;;
        trust_published) /usr/bin/printf '4\n' ;;
        bundle_published) /usr/bin/printf '5\n' ;;
        manifest_published) /usr/bin/printf '6\n' ;;
        *) die 'unknown exceptional install journal phase' ;;
    esac
}

validate_install_journal() {
    local product_digest=$1 phase expected
    require_root_file "$INSTALL_JOURNAL" 600 'exceptional install journal'
    [[ $(/usr/bin/stat -c '%s' "$INSTALL_JOURNAL") -le 8192 ]] \
        || die 'exceptional install journal is oversized'
    phase=$(/usr/bin/jq -er '.phase' "$INSTALL_JOURNAL")
    install_phase_rank "$phase" >/dev/null
    expected=$(install_record_json syntaur.authority-replacement-install.v1 \
        "$phase" "$product_digest")
    [[ $(<"$INSTALL_JOURNAL") == "$expected" \
        && $(/usr/bin/wc -l <"$INSTALL_JOURNAL") -eq 0 ]] \
        || die 'exceptional install journal differs from the signed transaction'
}

write_install_journal() {
    local phase=$1 product_digest=$2 current current_rank target_rank
    target_rank=$(install_phase_rank "$phase")
    if [[ -e $INSTALL_JOURNAL || -L $INSTALL_JOURNAL ]]; then
        validate_install_journal "$product_digest"
        current=$(/usr/bin/jq -er '.phase' "$INSTALL_JOURNAL")
        current_rank=$(install_phase_rank "$current")
        (( current_rank <= target_rank )) || return 0
        (( current_rank < target_rank )) || return 0
        (( target_rank == current_rank + 1 )) \
            || die 'exceptional install phase advance is non-sequential'
    else
        [[ $phase == prepared ]] || die 'exceptional install must begin at prepared'
    fi
    discard_safe_root_temporary "$INSTALL_JOURNAL_TEMP" 8192 \
        'exceptional install journal temporary'
    install_record_json syntaur.authority-replacement-install.v1 \
        "$phase" "$product_digest" >"$INSTALL_JOURNAL_TEMP"
    /usr/bin/chown 0:0 "$INSTALL_JOURNAL_TEMP"
    /usr/bin/chmod 0600 "$INSTALL_JOURNAL_TEMP"
    sync_path "$INSTALL_JOURNAL_TEMP"
    /usr/bin/mv -fT "$INSTALL_JOURNAL_TEMP" "$INSTALL_JOURNAL"
    sync_path "$AUTHORITY_ROOT"
    validate_install_journal "$product_digest"
}

fence_json() {
    local product_digest=$1
    install_record_json syntaur.authority-replacement-mutation-fence.v1 \
        blocked "$product_digest"
}

validate_mutation_fence() {
    local product_digest=$1 expected
    require_root_file "$NORMAL_PROMOTION_JOURNAL" 600 \
        'exceptional authority mutation fence'
    expected=$(fence_json "$product_digest")
    [[ $(<"$NORMAL_PROMOTION_JOURNAL") == "$expected" \
        && $(/usr/bin/wc -l <"$NORMAL_PROMOTION_JOURNAL") -eq 0 ]] \
        || die 'exceptional authority mutation fence differs'
}

publish_mutation_fence() {
    local product_digest=$1 temporary
    temporary=$AUTHORITY_ROOT/.authority-replacement-v1.fence.tmp
    discard_safe_root_temporary "$temporary" 8192 \
        'exceptional authority mutation fence temporary'
    if [[ -e $NORMAL_PROMOTION_JOURNAL || -L $NORMAL_PROMOTION_JOURNAL ]]; then
        validate_mutation_fence "$product_digest"
        return
    fi
    fence_json "$product_digest" >"$temporary"
    /usr/bin/chown 0:0 "$temporary"
    /usr/bin/chmod 0600 "$temporary"
    sync_path "$temporary"
    /usr/bin/mv -T "$temporary" "$NORMAL_PROMOTION_JOURNAL"
    sync_path "$AUTHORITY_ROOT"
    validate_mutation_fence "$product_digest"
}

install_receipt_json() {
    local product_digest=$1 record=$resolution_dir/$RESOLUTION base
    if [[ $(resolution_revision "$record") != 3 ]]; then
        install_record_json syntaur.authority-replacement-receipt.v1 \
            complete "$product_digest"
        return
    fi
    base=$(install_record_json syntaur.authority-replacement-receipt.v2 \
        complete "$product_digest")
    /usr/bin/jq -c \
        --arg origin_resolution_sha256 \
            "$(sha256_file "$(journal_resolution_record)")" \
        --arg recovery_resolution_sha256 "$expected_resolution_sha256" \
        --argjson recovery_resolution_revision 3 \
        --arg recovery_tool_sha256 "$expected_recovery_tool_sha256" \
        --arg correction_review_sha256 \
            "$(sha256_file "$resolution_dir/$CORRECTION_REVIEW")" \
        --arg proof_helper_source_commit \
            "$(resolution_value "$record" proof_helper_source_commit)" \
        --arg proof_helper_sha256 \
            "$(resolution_value "$record" proof_helper_sha256)" \
        --arg proof_helper_protocol_sha256 \
            "$(resolution_value "$record" proof_helper_protocol_sha256)" \
        '. + {
          origin_resolution_sha256:$origin_resolution_sha256,
          recovery_resolution_sha256:$recovery_resolution_sha256,
          recovery_resolution_revision:$recovery_resolution_revision,
          recovery_tool_sha256:$recovery_tool_sha256,
          correction_review_sha256:$correction_review_sha256,
          proof_helper_source_commit:$proof_helper_source_commit,
          proof_helper_sha256:$proof_helper_sha256,
          proof_helper_protocol_sha256:$proof_helper_protocol_sha256
        }' <<<"$base"
}

validate_install_receipt() {
    local product_digest=$1 expected
    require_root_file "$INSTALL_RECEIPT" 444 'exceptional authority install receipt'
    expected=$(install_receipt_json "$product_digest")
    [[ $(<"$INSTALL_RECEIPT") == "$expected" \
        && $(/usr/bin/wc -l <"$INSTALL_RECEIPT") -eq 0 ]] \
        || die 'exceptional authority install receipt differs'
}

publish_install_receipt() {
    local product_digest=$1 temporary
    temporary=$INSTALL_RECEIPT.tmp
    discard_safe_root_temporary "$temporary" 8192 \
        'exceptional authority install receipt temporary'
    if [[ -e $INSTALL_RECEIPT || -L $INSTALL_RECEIPT ]]; then
        validate_install_receipt "$product_digest"
        return
    fi
    install_receipt_json "$product_digest" >"$temporary"
    /usr/bin/chown 0:0 "$temporary"
    /usr/bin/chmod 0444 "$temporary"
    sync_path "$temporary"
    /usr/bin/mv -T "$temporary" "$INSTALL_RECEIPT"
    sync_path /etc/syntaur
    validate_install_receipt "$product_digest"
}

finalize_completed_install() {
    local product_digest=$1 phase
    validate_selected_active
    validate_install_receipt "$product_digest"
    [[ ! -e $ROLLBACK_JOURNAL && ! -L $ROLLBACK_JOURNAL \
        && ! -e $ROLLBACK_RECEIPT && ! -L $ROLLBACK_RECEIPT ]] \
        || die 'completed exceptional install conflicts with rollback state'
    if [[ -e $INSTALL_JOURNAL || -L $INSTALL_JOURNAL ]]; then
        validate_current_install_state "$product_digest"
        phase=$(/usr/bin/jq -er '.phase' "$INSTALL_JOURNAL")
        [[ $phase == manifest_published ]] \
            || die 'exceptional install receipt precedes its terminal journal phase'
        /usr/bin/rm -f -- "$INSTALL_JOURNAL"
        sync_path "$AUTHORITY_ROOT"
    fi
    if [[ -e $NORMAL_PROMOTION_JOURNAL || -L $NORMAL_PROMOTION_JOURNAL ]]; then
        validate_mutation_fence "$product_digest"
        /usr/bin/rm -f -- "$NORMAL_PROMOTION_JOURNAL"
        sync_path "$AUTHORITY_ROOT"
    fi
    [[ ! -e $INSTALL_JOURNAL && ! -L $INSTALL_JOURNAL \
        && ! -e $NORMAL_PROMOTION_JOURNAL \
        && ! -L $NORMAL_PROMOTION_JOURNAL ]] \
        || die 'completed exceptional install retains a mutation journal'
    assert_host_locks
}

component_generation() {
    local path=$1 mode=$2 predecessor_sha=$3 selected_sha=$4 label=$5 digest
    require_root_file "$path" "$mode" "$label"
    digest=$(sha256_file "$path")
    if [[ $predecessor_sha == "$selected_sha" && $digest == "$selected_sha" ]]; then
        /usr/bin/printf 'shared\n'
    elif [[ $digest == "$predecessor_sha" ]]; then
        /usr/bin/printf 'predecessor\n'
    elif [[ $digest == "$selected_sha" ]]; then
        /usr/bin/printf 'selected\n'
    else
        die "$label has an unknown digest"
    fi
}

validate_install_phase_state() {
    local phase=$1 selected_generation selected_workflow actual vector generation_state
    local shipper_state provisioner_state trust_state bundle_state manifest_state
    local predecessor_workflow predecessor_trust_sha selected_trust_sha
    selected_generation=$(manifest_value "$selected_dir/$MANIFEST" generation)
    selected_workflow=$(manifest_value "$selected_dir/$MANIFEST" workflow_commit)
    if [[ -e $ARTIFACT_ROOT/generation-$selected_generation \
        || -L $ARTIFACT_ROOT/generation-$selected_generation ]]; then
        validate_installed_generation "$ARTIFACT_ROOT/generation-$selected_generation" \
            "$selected_dir" "$selected_workflow" 'selected retained generation'
        generation_state=selected
    else
        generation_state=absent
    fi
    shipper_state=$(component_generation "$INSTALLED_SHIPPER" 1755 \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" \
        'installed shipper')
    provisioner_state=$(component_generation "$INSTALLED_PROVISIONER" 755 \
        "$(manifest_value "$predecessor_dir/$MANIFEST" provisioner_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" \
        'installed provisioner')
    if [[ $shipper_state == shared ]]; then
        if (( $(install_phase_rank "$phase") >= 2 )); then
            shipper_state=selected
        else
            shipper_state=predecessor
        fi
    fi
    if [[ $provisioner_state == shared ]]; then
        if (( $(install_phase_rank "$phase") >= 3 )); then
            provisioner_state=selected
        else
            provisioner_state=predecessor
        fi
    fi
    predecessor_workflow=$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)
    predecessor_trust_sha=$(workflow_trust_sha256 "$predecessor_workflow")
    selected_trust_sha=$(workflow_trust_sha256 "$selected_workflow")
    trust_state=$(component_generation "$AUTHORITY_ROOT/trusted-workflow-commit" 444 \
        "$predecessor_trust_sha" "$selected_trust_sha" 'active workflow trust')
    bundle_state=$(component_generation "$AUTHORITY_ROOT/$BUNDLE" 444 \
        "$(sha256_file "$predecessor_dir/$BUNDLE")" \
        "$(sha256_file "$selected_dir/$BUNDLE")" 'active authority bundle')
    manifest_state=$(component_generation "$AUTHORITY_ROOT/$MANIFEST" 444 \
        "$expected_predecessor_sha256" "$expected_selected_sha256" \
        'active authority manifest')
    vector=$generation_state:$shipper_state:$provisioner_state:$trust_state:$bundle_state:$manifest_state
    case $phase:$vector in
        prepared:absent:predecessor:predecessor:predecessor:predecessor:predecessor|\
        prepared:selected:predecessor:predecessor:predecessor:predecessor:predecessor|\
        generation_published:selected:predecessor:predecessor:predecessor:predecessor:predecessor|\
        generation_published:selected:selected:predecessor:predecessor:predecessor:predecessor|\
        shipper_published:selected:selected:predecessor:predecessor:predecessor:predecessor|\
        shipper_published:selected:selected:selected:predecessor:predecessor:predecessor|\
        provisioner_published:selected:selected:selected:predecessor:predecessor:predecessor|\
        provisioner_published:selected:selected:selected:selected:predecessor:predecessor|\
        trust_published:selected:selected:selected:selected:predecessor:predecessor|\
        trust_published:selected:selected:selected:selected:selected:predecessor|\
        bundle_published:selected:selected:selected:selected:selected:predecessor|\
        bundle_published:selected:selected:selected:selected:selected:selected|\
        manifest_published:selected:selected:selected:selected:selected:selected) ;;
        *) die "exceptional install journal and authority state disagree: $phase $vector" ;;
    esac
}

validate_current_install_state() {
    local product_digest=$1 phase
    validate_install_journal "$product_digest"
    phase=$(/usr/bin/jq -er '.phase' "$INSTALL_JOURNAL")
    validate_install_phase_state "$phase"
}

validate_selected_active() {
    local generation workflow
    generation=$(manifest_value "$selected_dir/$MANIFEST" generation)
    workflow=$(manifest_value "$selected_dir/$MANIFEST" workflow_commit)
    validate_installed_generation "$ARTIFACT_ROOT/generation-$generation" \
        "$selected_dir" "$workflow" 'selected retained generation'
    [[ $(sha256_file "$AUTHORITY_ROOT/$MANIFEST") == "$expected_selected_sha256" ]] \
        || die 'active selected manifest differs'
    [[ $(sha256_file "$AUTHORITY_ROOT/$BUNDLE") == \
        "$(sha256_file "$selected_dir/$BUNDLE")" ]] \
        || die 'active selected bundle differs'
    [[ $(sha256_file "$INSTALLED_SHIPPER") == \
        "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" ]] \
        || die 'installed selected shipper differs'
    [[ $(sha256_file "$INSTALLED_PROVISIONER") == \
        "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" ]] \
        || die 'installed selected provisioner differs'
    [[ $(<"$AUTHORITY_ROOT/trusted-workflow-commit") == "$workflow" ]] \
        || die 'active selected workflow trust differs'
}

install_selected_authority_exceptionally() {
    local record product_digest expected_product_digest previous_generation selected_generation
    local previous_workflow selected_workflow
    record=$resolution_dir/$RESOLUTION
    expected_product_digest=$(resolution_value "$record" settled_product_state_sha256)
    product_digest=$(product_state_digest)
    [[ $product_digest == "$expected_product_digest" ]] \
        || die 'settled product/deployment state differs from the signed resolution'
    require_no_product_mutation_journals
    [[ ! -e $ROLLBACK_JOURNAL && ! -L $ROLLBACK_JOURNAL \
        && ! -e $ROLLBACK_RECEIPT && ! -L $ROLLBACK_RECEIPT ]] \
        || die 'signed exceptional rollback makes the authority replacement terminal'
    if [[ -e $INSTALL_RECEIPT || -L $INSTALL_RECEIPT ]]; then
        die 'existing install receipt is inconsistent with an incomplete authority replacement'
    fi
    assert_host_locks
    previous_generation=$(manifest_value "$predecessor_dir/$MANIFEST" generation)
    selected_generation=$(manifest_value "$selected_dir/$MANIFEST" generation)
    previous_workflow=$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)
    selected_workflow=$(manifest_value "$selected_dir/$MANIFEST" workflow_commit)
    stage_generation "$predecessor_dir" "$previous_workflow" "$previous_generation"
    publish_mutation_fence "$product_digest"
    if [[ -e $INSTALL_JOURNAL || -L $INSTALL_JOURNAL ]]; then
        validate_current_install_state "$product_digest"
    else
        [[ $(sha256_file "$AUTHORITY_ROOT/$MANIFEST") == \
            "$expected_predecessor_sha256" ]] \
            || die 'fresh exceptional install does not start at the signed predecessor'
        write_install_journal prepared "$product_digest"
        validate_current_install_state "$product_digest"
    fi

    stage_generation "$selected_dir" "$selected_workflow" "$selected_generation"
    write_install_journal generation_published "$product_digest"
    validate_current_install_state "$product_digest"
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$selected_generation/syntaur-ship-linux-x86_64" \
        "$INSTALLED_SHIPPER" \
        "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" \
        1755 'installed shipper'
    write_install_journal shipper_published "$product_digest"
    validate_current_install_state "$product_digest"
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$selected_generation/syntaur-build-authority-provision" \
        "$INSTALLED_PROVISIONER" \
        "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" \
        "$(manifest_value "$predecessor_dir/$MANIFEST" provisioner_sha256)" \
        755 'installed provisioner'
    write_install_journal provisioner_published "$product_digest"
    validate_current_install_state "$product_digest"
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$selected_generation/trusted-workflow-commit" \
        "$AUTHORITY_ROOT/trusted-workflow-commit" \
        "$(workflow_trust_sha256 "$selected_workflow")" \
        "$(workflow_trust_sha256 "$previous_workflow")" 444 \
        'active workflow trust'
    write_install_journal trust_published "$product_digest"
    validate_current_install_state "$product_digest"
    publish_active_file "$ARTIFACT_ROOT/generation-$selected_generation/$BUNDLE" \
        "$AUTHORITY_ROOT/$BUNDLE" "$(sha256_file "$selected_dir/$BUNDLE")" \
        "$(sha256_file "$predecessor_dir/$BUNDLE")" 444 \
        'active authority bundle'
    write_install_journal bundle_published "$product_digest"
    validate_current_install_state "$product_digest"
    publish_active_file "$ARTIFACT_ROOT/generation-$selected_generation/$MANIFEST" \
        "$AUTHORITY_ROOT/$MANIFEST" "$expected_selected_sha256" \
        "$expected_predecessor_sha256" 444 'active authority manifest'
    write_install_journal manifest_published "$product_digest"
    validate_current_install_state "$product_digest"
    validate_selected_active
    [[ $(product_state_digest) == "$product_digest" ]] \
        || die 'product/deployment state changed during exceptional authority install'
    run_operator_product_state_proof "$product_digest"
    publish_install_receipt "$product_digest"
    finalize_completed_install "$product_digest"
}

rollback_phase_rank() {
    case $1 in
        prepared) /usr/bin/printf '0\n' ;;
        shipper_published) /usr/bin/printf '1\n' ;;
        provisioner_published) /usr/bin/printf '2\n' ;;
        trust_published) /usr/bin/printf '3\n' ;;
        bundle_published) /usr/bin/printf '4\n' ;;
        manifest_published) /usr/bin/printf '5\n' ;;
        *) die 'unknown exceptional rollback journal phase' ;;
    esac
}

rollback_record_json() {
    local phase=$1 product_digest=$2
    install_record_json syntaur.authority-replacement-rollback.v1 \
        "$phase" "$product_digest"
}

validate_rollback_journal() {
    local product_digest=$1 phase expected
    require_root_file "$ROLLBACK_JOURNAL" 600 'exceptional rollback journal'
    phase=$(/usr/bin/jq -er '.phase' "$ROLLBACK_JOURNAL")
    rollback_phase_rank "$phase" >/dev/null
    expected=$(rollback_record_json "$phase" "$product_digest")
    [[ $(<"$ROLLBACK_JOURNAL") == "$expected" \
        && $(/usr/bin/wc -l <"$ROLLBACK_JOURNAL") -eq 0 ]] \
        || die 'exceptional rollback journal differs from the signed transaction'
}

write_rollback_journal() {
    local phase=$1 product_digest=$2 current current_rank target_rank
    target_rank=$(rollback_phase_rank "$phase")
    if [[ -e $ROLLBACK_JOURNAL || -L $ROLLBACK_JOURNAL ]]; then
        validate_rollback_journal "$product_digest"
        current=$(/usr/bin/jq -er '.phase' "$ROLLBACK_JOURNAL")
        current_rank=$(rollback_phase_rank "$current")
        (( current_rank <= target_rank )) || return 0
        (( current_rank < target_rank )) || return 0
        (( target_rank == current_rank + 1 )) \
            || die 'exceptional rollback phase advance is non-sequential'
    else
        [[ $phase == prepared ]] || die 'exceptional rollback must begin at prepared'
    fi
    discard_safe_root_temporary "$ROLLBACK_JOURNAL_TEMP" 8192 \
        'exceptional rollback journal temporary'
    rollback_record_json "$phase" "$product_digest" >"$ROLLBACK_JOURNAL_TEMP"
    /usr/bin/chown 0:0 "$ROLLBACK_JOURNAL_TEMP"
    /usr/bin/chmod 0600 "$ROLLBACK_JOURNAL_TEMP"
    sync_path "$ROLLBACK_JOURNAL_TEMP"
    /usr/bin/mv -fT "$ROLLBACK_JOURNAL_TEMP" "$ROLLBACK_JOURNAL"
    sync_path "$AUTHORITY_ROOT"
    validate_rollback_journal "$product_digest"
}

validate_rollback_phase_state() {
    local phase=$1 shipper_state provisioner_state trust_state bundle_state manifest_state vector
    local predecessor_workflow selected_workflow predecessor_trust_sha selected_trust_sha
    shipper_state=$(component_generation "$INSTALLED_SHIPPER" 1755 \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" \
        'installed shipper')
    provisioner_state=$(component_generation "$INSTALLED_PROVISIONER" 755 \
        "$(manifest_value "$predecessor_dir/$MANIFEST" provisioner_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" \
        'installed provisioner')
    if [[ $shipper_state == shared ]]; then
        if (( $(rollback_phase_rank "$phase") >= 1 )); then
            shipper_state=predecessor
        else
            shipper_state=selected
        fi
    fi
    if [[ $provisioner_state == shared ]]; then
        if (( $(rollback_phase_rank "$phase") >= 2 )); then
            provisioner_state=predecessor
        else
            provisioner_state=selected
        fi
    fi
    predecessor_workflow=$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)
    selected_workflow=$(manifest_value "$selected_dir/$MANIFEST" workflow_commit)
    predecessor_trust_sha=$(workflow_trust_sha256 "$predecessor_workflow")
    selected_trust_sha=$(workflow_trust_sha256 "$selected_workflow")
    trust_state=$(component_generation "$AUTHORITY_ROOT/trusted-workflow-commit" 444 \
        "$predecessor_trust_sha" "$selected_trust_sha" 'active workflow trust')
    bundle_state=$(component_generation "$AUTHORITY_ROOT/$BUNDLE" 444 \
        "$(sha256_file "$predecessor_dir/$BUNDLE")" \
        "$(sha256_file "$selected_dir/$BUNDLE")" 'active authority bundle')
    manifest_state=$(component_generation "$AUTHORITY_ROOT/$MANIFEST" 444 \
        "$expected_predecessor_sha256" "$expected_selected_sha256" \
        'active authority manifest')
    vector=$shipper_state:$provisioner_state:$trust_state:$bundle_state:$manifest_state
    case $phase:$vector in
        prepared:selected:selected:selected:selected:selected|\
        prepared:predecessor:selected:selected:selected:selected|\
        shipper_published:predecessor:selected:selected:selected:selected|\
        shipper_published:predecessor:predecessor:selected:selected:selected|\
        provisioner_published:predecessor:predecessor:selected:selected:selected|\
        provisioner_published:predecessor:predecessor:predecessor:selected:selected|\
        trust_published:predecessor:predecessor:predecessor:selected:selected|\
        trust_published:predecessor:predecessor:predecessor:predecessor:selected|\
        bundle_published:predecessor:predecessor:predecessor:predecessor:selected|\
        bundle_published:predecessor:predecessor:predecessor:predecessor:predecessor|\
        manifest_published:predecessor:predecessor:predecessor:predecessor:predecessor) ;;
        *) die "exceptional rollback journal and authority state disagree: $phase $vector" ;;
    esac
}

validate_current_rollback_state() {
    local product_digest=$1 phase
    validate_rollback_journal "$product_digest"
    phase=$(/usr/bin/jq -er '.phase' "$ROLLBACK_JOURNAL")
    validate_rollback_phase_state "$phase"
}

validate_predecessor_active() {
    local generation workflow
    generation=$(manifest_value "$predecessor_dir/$MANIFEST" generation)
    workflow=$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)
    validate_installed_generation "$ARTIFACT_ROOT/generation-$generation" \
        "$predecessor_dir" "$workflow" 'predecessor retained generation'
    [[ $(sha256_file "$AUTHORITY_ROOT/$MANIFEST") == "$expected_predecessor_sha256" ]] \
        || die 'active predecessor manifest differs'
    [[ $(sha256_file "$AUTHORITY_ROOT/$BUNDLE") == \
        "$(sha256_file "$predecessor_dir/$BUNDLE")" ]] \
        || die 'active predecessor bundle differs'
    [[ $(sha256_file "$INSTALLED_SHIPPER") == \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" ]] \
        || die 'installed predecessor shipper differs'
    [[ $(sha256_file "$INSTALLED_PROVISIONER") == \
        "$(manifest_value "$predecessor_dir/$MANIFEST" provisioner_sha256)" ]] \
        || die 'installed predecessor provisioner differs'
    [[ $(<"$AUTHORITY_ROOT/trusted-workflow-commit") == "$workflow" ]] \
        || die 'active predecessor workflow trust differs'
}

rollback_receipt_json() {
    local product_digest=$1
    rollback_record_json complete "$product_digest"
}

validate_rollback_receipt() {
    local product_digest=$1 expected
    require_root_file "$ROLLBACK_RECEIPT" 444 'exceptional authority rollback receipt'
    expected=$(rollback_receipt_json "$product_digest")
    [[ $(<"$ROLLBACK_RECEIPT") == "$expected" \
        && $(/usr/bin/wc -l <"$ROLLBACK_RECEIPT") -eq 0 ]] \
        || die 'exceptional authority rollback receipt differs'
}

publish_rollback_receipt() {
    local product_digest=$1 temporary
    temporary=$ROLLBACK_RECEIPT.tmp
    discard_safe_root_temporary "$temporary" 8192 \
        'exceptional authority rollback receipt temporary'
    if [[ -e $ROLLBACK_RECEIPT || -L $ROLLBACK_RECEIPT ]]; then
        validate_rollback_receipt "$product_digest"
        return
    fi
    rollback_receipt_json "$product_digest" >"$temporary"
    /usr/bin/chown 0:0 "$temporary"
    /usr/bin/chmod 0444 "$temporary"
    sync_path "$temporary"
    /usr/bin/mv -T "$temporary" "$ROLLBACK_RECEIPT"
    sync_path /etc/syntaur
    validate_rollback_receipt "$product_digest"
}

finalize_completed_rollback() {
    local product_digest=$1 phase
    validate_predecessor_active
    validate_install_receipt "$product_digest"
    validate_rollback_receipt "$product_digest"
    [[ ! -e $INSTALL_JOURNAL && ! -L $INSTALL_JOURNAL ]] \
        || die 'completed exceptional rollback conflicts with an install journal'
    if [[ -e $ROLLBACK_JOURNAL || -L $ROLLBACK_JOURNAL ]]; then
        validate_current_rollback_state "$product_digest"
        phase=$(/usr/bin/jq -er '.phase' "$ROLLBACK_JOURNAL")
        [[ $phase == manifest_published ]] \
            || die 'exceptional rollback receipt precedes its terminal journal phase'
        /usr/bin/rm -f -- "$ROLLBACK_JOURNAL"
        sync_path "$AUTHORITY_ROOT"
    fi
    if [[ -e $NORMAL_PROMOTION_JOURNAL || -L $NORMAL_PROMOTION_JOURNAL ]]; then
        validate_mutation_fence "$product_digest"
        /usr/bin/rm -f -- "$NORMAL_PROMOTION_JOURNAL"
        sync_path "$AUTHORITY_ROOT"
    fi
    [[ ! -e $ROLLBACK_JOURNAL && ! -L $ROLLBACK_JOURNAL \
        && ! -e $NORMAL_PROMOTION_JOURNAL \
        && ! -L $NORMAL_PROMOTION_JOURNAL ]] \
        || die 'completed exceptional rollback retains a mutation journal'
    assert_host_locks
}

rollback_selected_authority_exceptionally() {
    local product_digest expected_product_digest previous_generation previous_workflow
    local selected_generation selected_workflow
    expected_product_digest=$(resolution_value \
        "$resolution_dir/$RESOLUTION" settled_product_state_sha256)
    product_digest=$(product_state_digest)
    [[ $product_digest == "$expected_product_digest" ]] \
        || die 'rollback is forbidden after product/deployment state moved from the signed start state'
    require_no_product_mutation_journals
    [[ ! -e $INSTALL_JOURNAL && ! -L $INSTALL_JOURNAL ]] \
        || die 'exceptional install must finish forward before rollback'
    validate_install_receipt "$product_digest"
    previous_generation=$(manifest_value "$predecessor_dir/$MANIFEST" generation)
    selected_generation=$(manifest_value "$selected_dir/$MANIFEST" generation)
    previous_workflow=$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)
    selected_workflow=$(manifest_value "$selected_dir/$MANIFEST" workflow_commit)
    validate_installed_generation "$ARTIFACT_ROOT/generation-$previous_generation" \
        "$predecessor_dir" "$previous_workflow" 'predecessor retained generation'
    validate_installed_generation "$ARTIFACT_ROOT/generation-$selected_generation" \
        "$selected_dir" "$selected_workflow" 'selected retained generation'
    publish_mutation_fence "$product_digest"
    if [[ -e $ROLLBACK_JOURNAL || -L $ROLLBACK_JOURNAL ]]; then
        validate_current_rollback_state "$product_digest"
    else
        validate_selected_active
        run_operator_product_state_proof "$product_digest"
        write_rollback_journal prepared "$product_digest"
        validate_current_rollback_state "$product_digest"
    fi
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$previous_generation/syntaur-ship-linux-x86_64" \
        "$INSTALLED_SHIPPER" \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" shipper_sha256)" \
        1755 'installed shipper'
    write_rollback_journal shipper_published "$product_digest"
    validate_current_rollback_state "$product_digest"
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$previous_generation/syntaur-build-authority-provision" \
        "$INSTALLED_PROVISIONER" \
        "$(manifest_value "$predecessor_dir/$MANIFEST" provisioner_sha256)" \
        "$(manifest_value "$selected_dir/$MANIFEST" provisioner_sha256)" \
        755 'installed provisioner'
    write_rollback_journal provisioner_published "$product_digest"
    validate_current_rollback_state "$product_digest"
    publish_active_file \
        "$ARTIFACT_ROOT/generation-$previous_generation/trusted-workflow-commit" \
        "$AUTHORITY_ROOT/trusted-workflow-commit" \
        "$(workflow_trust_sha256 "$previous_workflow")" \
        "$(workflow_trust_sha256 "$selected_workflow")" 444 \
        'active workflow trust'
    write_rollback_journal trust_published "$product_digest"
    validate_current_rollback_state "$product_digest"
    publish_active_file "$ARTIFACT_ROOT/generation-$previous_generation/$BUNDLE" \
        "$AUTHORITY_ROOT/$BUNDLE" "$(sha256_file "$predecessor_dir/$BUNDLE")" \
        "$(sha256_file "$selected_dir/$BUNDLE")" 444 \
        'active authority bundle'
    write_rollback_journal bundle_published "$product_digest"
    validate_current_rollback_state "$product_digest"
    publish_active_file "$ARTIFACT_ROOT/generation-$previous_generation/$MANIFEST" \
        "$AUTHORITY_ROOT/$MANIFEST" "$expected_predecessor_sha256" \
        "$expected_selected_sha256" 444 'active authority manifest'
    write_rollback_journal manifest_published "$product_digest"
    validate_current_rollback_state "$product_digest"
    validate_predecessor_active
    [[ $(product_state_digest) == "$product_digest" ]] \
        || die 'product/deployment state changed during exceptional authority rollback'
    publish_rollback_receipt "$product_digest"
    finalize_completed_rollback "$product_digest"
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

[[ $# -ge 1 ]] || usage
operation=$1
shift
[[ $operation == verify || $operation == install || $operation == rollback ]] || usage

predecessor_dir=
rejected_dir=
selected_dir=
resolution_dir=
expected_resolution_sha256=
expected_recovery_tool_sha256=
expected_predecessor_sha256=
expected_rejected_sha256=
expected_selected_sha256=
correction_authorization=
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
        --expected-recovery-tool-sha256)
            [[ -z $expected_recovery_tool_sha256 ]] || usage
            expected_recovery_tool_sha256=$2
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
        --correction-authorization)
            [[ -z $correction_authorization ]] || usage
            correction_authorization=$2
            ;;
        --authorize-reason) [[ -z $authorize_reason ]] || usage; authorize_reason=$2 ;;
        *) usage ;;
    esac
    shift 2
done
for value in "$predecessor_dir" "$rejected_dir" "$selected_dir" "$resolution_dir"; do
    [[ -n $value ]] || usage
done
for digest in "$expected_resolution_sha256" "$expected_recovery_tool_sha256" \
    "$expected_predecessor_sha256" \
    "$expected_rejected_sha256" "$expected_selected_sha256"; do
    valid_sha256 "$digest" || usage
done
[[ $authorize_reason == authority_target_mismatch ]] || usage
if /usr/bin/env | /usr/bin/cut -d= -f1 | /usr/bin/grep -Eq '^SYNTAUR_'; then
    die 'ambient SYNTAUR_* overrides are forbidden'
fi

if [[ $operation == install || $operation == rollback ]]; then
    [[ $(/usr/bin/id -u) == 0 ]] || die 'install requires sudo and an all-root identity'
    [[ $(/usr/bin/hostname) == claudevm ]] || die 'install may run only on claudevm'
    [[ ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && ${SUDO_GID:-} =~ ^[0-9]+$ \
        && ${SUDO_USER:-} =~ ^[A-Za-z0-9_-]+$ ]] \
        || die 'install requires an exact non-root sudo operator identity'
    /usr/bin/grep -Eq '^Uid:[[:space:]]+0[[:space:]]+0[[:space:]]+0[[:space:]]+0$' \
        /proc/self/status || die 'install requires all-root real/effective/saved/filesystem UIDs'
    /usr/bin/grep -Eq '^Gid:[[:space:]]+0[[:space:]]+0[[:space:]]+0[[:space:]]+0$' \
        /proc/self/status || die 'install requires all-root real/effective/saved/filesystem GIDs'
    require_sealed_runtime
else
    [[ $(sha256_file "${BASH_SOURCE[0]}") == "$expected_recovery_tool_sha256" ]] \
        || die 'verification recovery tool differs from the operator-authorized hash'
    verify_inputs "$operation"
    printf 'release authority replacement evidence verified: predecessor=%s rejected=%s selected=%s resolution=%s\n' \
        "$expected_predecessor_sha256" "$expected_rejected_sha256" \
        "$expected_selected_sha256" "$expected_resolution_sha256"
    exit 0
fi

require_safe_file "$INSTALLED_SHIPPER" 268435456 true 'installed predecessor shipper'
require_safe_file "$AUTHORITY_ROOT/$MANIFEST" 32768 false 'installed predecessor manifest'
require_root_directory "$AUTHORITY_ROOT" 'authority root'
require_root_directory "$ARTIFACT_ROOT" 'retained authority generation store'
[[ $(/usr/bin/stat -c '%a' "$ARTIFACT_ROOT") == 755 ]] \
    || die 'retained authority generation store mode differs'
if [[ -e $REPLACEMENT_LOCK || -L $REPLACEMENT_LOCK ]]; then
    require_root_file "$REPLACEMENT_LOCK" 600 'authority replacement lock'
fi
exec 7<>"$REPLACEMENT_LOCK"
/usr/bin/chown 0:0 "$REPLACEMENT_LOCK"
/usr/bin/chmod 0600 "$REPLACEMENT_LOCK"
require_root_file "$REPLACEMENT_LOCK" 600 'authority replacement lock'
/usr/bin/flock -n 7 || die 'another authority replacement recovery holds the lock'
resolve_operator_home
seal_install_inputs "$operation"
active_manifest_sha256=$(sha256_file "$AUTHORITY_ROOT/$MANIFEST")
verify_resolution_correction_state "$operation" "$active_manifest_sha256"
install_resolution_receipt
if [[ $operation == rollback ]]; then
    transaction_product_digest=$(resolution_value \
        "$resolution_dir/$RESOLUTION" settled_product_state_sha256)
    if [[ $active_manifest_sha256 == "$expected_predecessor_sha256" \
        && ( -e $ROLLBACK_RECEIPT || -L $ROLLBACK_RECEIPT ) ]]; then
        [[ $(product_state_digest) == "$transaction_product_digest" ]] \
            || die 'completed rollback product/deployment state differs from its signed start state'
        finalize_completed_rollback "$transaction_product_digest"
    else
        [[ $active_manifest_sha256 == "$expected_selected_sha256" \
            || ( $active_manifest_sha256 == "$expected_predecessor_sha256" \
                && ( -e $ROLLBACK_JOURNAL || -L $ROLLBACK_JOURNAL ) ) ]] \
            || die 'authority state is outside the signed rollback transaction'
        rollback_selected_authority_exceptionally
    fi
    run_operator_authority_status
    [[ $(product_state_digest) == "$transaction_product_digest" ]] \
        || die 'authority rollback status changed the settled product/deployment state'
    printf 'release authority replacement rolled back: generation=%s manifest_sha256=%s\n' \
        "$(resolution_value "$resolution_dir/$RESOLUTION" predecessor_generation)" \
        "$expected_predecessor_sha256"
    exit 0
fi

if [[ $active_manifest_sha256 == "$expected_selected_sha256" \
    && ( -e $INSTALL_RECEIPT || -L $INSTALL_RECEIPT ) ]]; then
    transaction_product_digest=$(resolution_value \
        "$resolution_dir/$RESOLUTION" settled_product_state_sha256)
    [[ $(product_state_digest) == "$transaction_product_digest" ]] \
        || die 'product/deployment state moved after exceptional install; continue forward under selected authority'
    run_operator_product_state_proof "$transaction_product_digest"
    finalize_completed_install "$transaction_product_digest"
    run_operator_authority_status
    [[ $(product_state_digest) == "$transaction_product_digest" ]] \
        || die 'authority status changed the settled product/deployment state'
    printf 'release authority replacement already complete: generation=%s manifest_sha256=%s\n' \
        "$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)" \
        "$expected_selected_sha256"
    exit 0
fi
[[ $active_manifest_sha256 == "$expected_predecessor_sha256" \
    || ( $active_manifest_sha256 == "$expected_selected_sha256" \
        && ( -e $INSTALL_JOURNAL || -L $INSTALL_JOURNAL ) ) ]] \
    || die 'installed authority is neither the exact predecessor nor selected replacement'
if [[ $active_manifest_sha256 == "$expected_predecessor_sha256" ]]; then
    [[ $(sha256_file "$INSTALLED_SHIPPER") == \
        "$(manifest_value "$predecessor_dir/$MANIFEST" shipper_sha256)" ]] \
        || die 'installed predecessor shipper differs from the signed predecessor manifest'
fi
install_selected_authority_exceptionally
run_operator_authority_status
printf 'release authority replacement complete: generation=%s manifest_sha256=%s\n' \
    "$(resolution_value "$resolution_dir/$RESOLUTION" selected_generation)" \
    "$expected_selected_sha256"
