#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are intentionally single-quoted.
set -euo pipefail

die() {
    printf 'release authority manifest error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

manifest_value() {
    local manifest=$1
    local field=$2
    jq -er --arg field "$field" '.[$field]' "$manifest"
}

approval_record_from_file() {
    local record=$1
    jq -cjn \
        --argjson schema "$(manifest_value "$record" schema)" \
        --argjson previous_generation "$(manifest_value "$record" previous_generation)" \
        --arg previous_manifest_sha256 "$(manifest_value "$record" previous_manifest_sha256)" \
        --arg authority_version "$(manifest_value "$record" authority_version)" \
        --arg authority_commit "$(manifest_value "$record" authority_commit)" \
        --arg verification_policy_revision "$(manifest_value "$record" verification_policy_revision)" \
        --arg authority_tree_sha256 "$(manifest_value "$record" authority_tree_sha256)" \
        --arg shipper_sha256 "$(manifest_value "$record" shipper_sha256)" \
        --arg verifier_sha256 "$(manifest_value "$record" verifier_sha256)" \
        --arg baseline_profile "$(manifest_value "$record" baseline_profile)" \
        --arg baseline_generation "$(manifest_value "$record" baseline_generation)" \
        --arg baseline_tree_sha256 "$(manifest_value "$record" baseline_tree_sha256)" \
        --arg browser_bundle_sha256 "$(manifest_value "$record" browser_bundle_sha256)" \
        --arg browser_version "$(manifest_value "$record" browser_version)" \
        --arg browser_launch_profile_sha256 "$(manifest_value "$record" browser_launch_profile_sha256)" \
        --argjson verifier_schema "$(manifest_value "$record" verifier_schema)" \
        --arg provisioner_sha256 "$(manifest_value "$record" provisioner_sha256)" \
        --arg production_contract_sha256 "$(manifest_value "$record" production_contract_sha256)" \
        --argjson production_member_count "$(manifest_value "$record" production_member_count)" \
        --argjson receipt_schema "$(manifest_value "$record" receipt_schema)" \
        --argjson build_authority_schema "$(manifest_value "$record" build_authority_schema)" \
        --argjson promotion_recovery_schema "$(manifest_value "$record" promotion_recovery_schema)" \
        --arg promotion_recovery_sha256 "$(manifest_value "$record" promotion_recovery_sha256)" \
        '{
          schema:$schema,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          verification_policy_revision:$verification_policy_revision,
          authority_tree_sha256:$authority_tree_sha256,
          shipper_sha256:$shipper_sha256,
          verifier_sha256:$verifier_sha256,
          baseline_profile:$baseline_profile,
          baseline_generation:$baseline_generation,
          baseline_tree_sha256:$baseline_tree_sha256,
          browser_bundle_sha256:$browser_bundle_sha256,
          browser_version:$browser_version,
          browser_launch_profile_sha256:$browser_launch_profile_sha256,
          verifier_schema:$verifier_schema,
          provisioner_sha256:$provisioner_sha256,
          production_contract_sha256:$production_contract_sha256,
          production_member_count:$production_member_count,
          receipt_schema:$receipt_schema,
          build_authority_schema:$build_authority_schema,
          promotion_recovery_schema:$promotion_recovery_schema,
          promotion_recovery_sha256:$promotion_recovery_sha256
        }'
}

validate_approval_record() {
    local record=$1
    [[ -s $record && -f $record && ! -L $record ]] || die 'approval record is unsafe'
    jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        def text: type == "string" and length > 0 and length <= 256
                  and (test("[\u0000-\u001f\u007f]") | not);
        def uint: type == "number" and . >= 0 and . <= 9007199254740991 and floor == .;
        (.schema == 1) and
        (.previous_generation | uint and . < 9007199254740991) and
        (.previous_manifest_sha256 | digest) and
        (((.previous_generation == 0) and
          (.previous_manifest_sha256 == ("0" * 64))) or
         ((.previous_generation > 0) and
          (.previous_manifest_sha256 != ("0" * 64)))) and
        (.authority_version | type == "string"
          and test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
        (.authority_commit | commit) and
        (.verification_policy_revision | commit) and
        (.authority_tree_sha256 | digest) and
        (.shipper_sha256 | digest) and
        (.verifier_sha256 | digest) and
        (.baseline_profile | text and test("^[A-Za-z0-9._-]+$")) and
        (.baseline_generation | text and test("^[A-Za-z0-9._-]+$")) and
        (.baseline_tree_sha256 | digest) and
        (.browser_bundle_sha256 | digest) and
        (.browser_version | type == "string"
          and test("^Google Chrome for Testing [0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")) and
        (.browser_launch_profile_sha256 | digest) and
        (.verifier_schema | uint and . > 0) and
        (.provisioner_sha256 | digest) and
        (.production_contract_sha256 | digest) and
        (.production_member_count == 12) and
        (.receipt_schema == 6) and
        (.build_authority_schema == 4) and
        (.promotion_recovery_schema == 1) and
        (.promotion_recovery_sha256 | digest)
    ' "$record" >/dev/null || die 'approval record shape or values are invalid'
    local canonical
    canonical=$(approval_record_from_file "$record")
    [[ $(wc -c <"$record") -eq ${#canonical} && $(<"$record") == "$canonical" ]] \
        || die 'approval record is not exact canonical JSON'
}

render_approval_record() {
    local output=$1
    : "${PREVIOUS_AUTHORITY_GENERATION:?}"
    : "${PREVIOUS_AUTHORITY_MANIFEST_SHA256:?}"
    : "${AUTHORITY_VERSION:?}"
    : "${AUTHORITY_COMMIT:?}"
    : "${VERIFICATION_POLICY_REVISION:?}"
    : "${AUTHORITY_TREE_SHA256:?}"
    : "${SHIPPER_SHA256:?}"
    : "${VERIFIER_SHA256:?}"
    : "${BASELINE_PROFILE:?}"
    : "${BASELINE_GENERATION:?}"
    : "${BASELINE_TREE_SHA256:?}"
    : "${BROWSER_BUNDLE_SHA256:?}"
    : "${BROWSER_VERSION:?}"
    : "${BROWSER_LAUNCH_PROFILE_SHA256:?}"
    : "${VERIFIER_SCHEMA:?}"
    : "${PROVISIONER_SHA256:?}"
    : "${PRODUCTION_CONTRACT_SHA256:?}"
    : "${PRODUCTION_MEMBER_COUNT:?}"
    : "${RECEIPT_SCHEMA:?}"
    : "${BUILD_AUTHORITY_SCHEMA:?}"
    : "${PROMOTION_RECOVERY_SCHEMA:?}"
    : "${PROMOTION_RECOVERY_SHA256:?}"
    jq -cjn \
        --argjson schema 1 \
        --argjson previous_generation "$PREVIOUS_AUTHORITY_GENERATION" \
        --arg previous_manifest_sha256 "$PREVIOUS_AUTHORITY_MANIFEST_SHA256" \
        --arg authority_version "$AUTHORITY_VERSION" \
        --arg authority_commit "$AUTHORITY_COMMIT" \
        --arg verification_policy_revision "$VERIFICATION_POLICY_REVISION" \
        --arg authority_tree_sha256 "$AUTHORITY_TREE_SHA256" \
        --arg shipper_sha256 "$SHIPPER_SHA256" \
        --arg verifier_sha256 "$VERIFIER_SHA256" \
        --arg baseline_profile "$BASELINE_PROFILE" \
        --arg baseline_generation "$BASELINE_GENERATION" \
        --arg baseline_tree_sha256 "$BASELINE_TREE_SHA256" \
        --arg browser_bundle_sha256 "$BROWSER_BUNDLE_SHA256" \
        --arg browser_version "$BROWSER_VERSION" \
        --arg browser_launch_profile_sha256 "$BROWSER_LAUNCH_PROFILE_SHA256" \
        --argjson verifier_schema "$VERIFIER_SCHEMA" \
        --arg provisioner_sha256 "$PROVISIONER_SHA256" \
        --arg production_contract_sha256 "$PRODUCTION_CONTRACT_SHA256" \
        --argjson production_member_count "$PRODUCTION_MEMBER_COUNT" \
        --argjson receipt_schema "$RECEIPT_SCHEMA" \
        --argjson build_authority_schema "$BUILD_AUTHORITY_SCHEMA" \
        --argjson promotion_recovery_schema "$PROMOTION_RECOVERY_SCHEMA" \
        --arg promotion_recovery_sha256 "$PROMOTION_RECOVERY_SHA256" \
        '{
          schema:$schema,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          verification_policy_revision:$verification_policy_revision,
          authority_tree_sha256:$authority_tree_sha256,
          shipper_sha256:$shipper_sha256,
          verifier_sha256:$verifier_sha256,
          baseline_profile:$baseline_profile,
          baseline_generation:$baseline_generation,
          baseline_tree_sha256:$baseline_tree_sha256,
          browser_bundle_sha256:$browser_bundle_sha256,
          browser_version:$browser_version,
          browser_launch_profile_sha256:$browser_launch_profile_sha256,
          verifier_schema:$verifier_schema,
          provisioner_sha256:$provisioner_sha256,
          production_contract_sha256:$production_contract_sha256,
          production_member_count:$production_member_count,
          receipt_schema:$receipt_schema,
          build_authority_schema:$build_authority_schema,
          promotion_recovery_schema:$promotion_recovery_schema,
          promotion_recovery_sha256:$promotion_recovery_sha256
        }' >"$output"
    validate_approval_record "$output"
}

asset_schema() {
    local names_file=$1
    [[ -f $names_file && ! -L $names_file ]] || die 'asset-name input is unsafe'
    mapfile -t names <"$names_file"
    ((${#names[@]} > 0)) || die 'authority release has no assets'

    local name
    for name in "${names[@]}"; do
        [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid authority asset name: $name"
    done
    [[ $(printf '%s\n' "${names[@]}" | LC_ALL=C sort -u | wc -l) -eq ${#names[@]} ]] \
        || die 'authority release has duplicate asset names'

    local actual expected_v1 expected_v2
    actual=$(printf '%s\n' "${names[@]}" | LC_ALL=C sort)
    expected_v1=$(printf '%s\n' \
        release-authority-v1.json \
        release-authority-v1.json.cosign.bundle \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 | LC_ALL=C sort)
    expected_v2=$(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 | LC_ALL=C sort)
    if [[ $actual == "$expected_v1" ]]; then
        printf '1\n'
    elif [[ $actual == "$expected_v2" ]]; then
        printf '2\n'
    else
        die 'authority release asset set is mixed, missing, or unknown'
    fi
}

common_manifest_shape='
def digest: type == "string" and test("^[0-9a-f]{64}$");
def commit: type == "string" and test("^[0-9a-f]{40}$");
def text: type == "string" and length > 0 and length <= 256
          and (test("[\u0000-\u001f\u007f]") | not);
def uint: type == "number" and . >= 0 and . <= 9007199254740991 and floor == .;
(.schema | uint) and
(.generation | uint and . > 0) and
(.previous_generation | uint and . < $generation) and
(.previous_manifest_sha256 | digest) and
(.authority_version | type == "string"
  and test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
(.authority_commit | commit) and
(.authority_tree_sha256 | digest) and
(.verification_policy_revision | commit) and
(.shipper_sha256 | digest) and
(.verifier_sha256 | digest) and
(.verifier_toolchain_id | text) and
(.verifier_cargo_sha256 | digest) and
(.verifier_rustc_sha256 | digest) and
(.verifier_rustdoc_sha256 | digest) and
(.approved_baseline_profile | text) and
(.approved_baseline_generation | text) and
(.approved_baseline_tree_sha256 | digest) and
(.approved_browser_bundle_sha256 | digest) and
(.approved_browser_version | text) and
(.approved_browser_launch_profile_sha256 | digest) and
(.verifier_schema | uint and . > 0) and
(.workflow_commit | commit) and
(.generation == $generation) and
(.workflow_commit == $workflow_commit) and
((.previous_generation == 0) ==
 (.previous_manifest_sha256 == ("0" * 64)))
'

render_v1_from_manifest() {
    local manifest=$1
    jq -cjn \
        --argjson schema "$(manifest_value "$manifest" schema)" \
        --argjson generation "$(manifest_value "$manifest" generation)" \
        --argjson previous_generation "$(manifest_value "$manifest" previous_generation)" \
        --arg previous_manifest_sha256 "$(manifest_value "$manifest" previous_manifest_sha256)" \
        --arg authority_version "$(manifest_value "$manifest" authority_version)" \
        --arg authority_commit "$(manifest_value "$manifest" authority_commit)" \
        --arg authority_tree_sha256 "$(manifest_value "$manifest" authority_tree_sha256)" \
        --arg verification_policy_revision "$(manifest_value "$manifest" verification_policy_revision)" \
        --arg shipper_sha256 "$(manifest_value "$manifest" shipper_sha256)" \
        --arg verifier_sha256 "$(manifest_value "$manifest" verifier_sha256)" \
        --arg verifier_toolchain_id "$(manifest_value "$manifest" verifier_toolchain_id)" \
        --arg verifier_cargo_sha256 "$(manifest_value "$manifest" verifier_cargo_sha256)" \
        --arg verifier_rustc_sha256 "$(manifest_value "$manifest" verifier_rustc_sha256)" \
        --arg verifier_rustdoc_sha256 "$(manifest_value "$manifest" verifier_rustdoc_sha256)" \
        --arg approved_baseline_profile "$(manifest_value "$manifest" approved_baseline_profile)" \
        --arg approved_baseline_generation "$(manifest_value "$manifest" approved_baseline_generation)" \
        --arg approved_baseline_tree_sha256 "$(manifest_value "$manifest" approved_baseline_tree_sha256)" \
        --arg approved_browser_bundle_sha256 "$(manifest_value "$manifest" approved_browser_bundle_sha256)" \
        --arg approved_browser_version "$(manifest_value "$manifest" approved_browser_version)" \
        --arg approved_browser_launch_profile_sha256 "$(manifest_value "$manifest" approved_browser_launch_profile_sha256)" \
        --argjson verifier_schema "$(manifest_value "$manifest" verifier_schema)" \
        --arg workflow_commit "$(manifest_value "$manifest" workflow_commit)" \
        '{
          schema:$schema,
          generation:$generation,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          authority_tree_sha256:$authority_tree_sha256,
          verification_policy_revision:$verification_policy_revision,
          shipper_sha256:$shipper_sha256,
          verifier_sha256:$verifier_sha256,
          verifier_toolchain_id:$verifier_toolchain_id,
          verifier_cargo_sha256:$verifier_cargo_sha256,
          verifier_rustc_sha256:$verifier_rustc_sha256,
          verifier_rustdoc_sha256:$verifier_rustdoc_sha256,
          approved_baseline_profile:$approved_baseline_profile,
          approved_baseline_generation:$approved_baseline_generation,
          approved_baseline_tree_sha256:$approved_baseline_tree_sha256,
          approved_browser_bundle_sha256:$approved_browser_bundle_sha256,
          approved_browser_version:$approved_browser_version,
          approved_browser_launch_profile_sha256:$approved_browser_launch_profile_sha256,
          verifier_schema:$verifier_schema,
          workflow_commit:$workflow_commit
        }'
}

render_v2_from_manifest() {
    local manifest=$1
    jq -cjn \
        --argjson schema "$(manifest_value "$manifest" schema)" \
        --argjson generation "$(manifest_value "$manifest" generation)" \
        --argjson previous_generation "$(manifest_value "$manifest" previous_generation)" \
        --arg previous_manifest_sha256 "$(manifest_value "$manifest" previous_manifest_sha256)" \
        --arg authority_version "$(manifest_value "$manifest" authority_version)" \
        --arg authority_commit "$(manifest_value "$manifest" authority_commit)" \
        --arg authority_tree_sha256 "$(manifest_value "$manifest" authority_tree_sha256)" \
        --arg verification_policy_revision "$(manifest_value "$manifest" verification_policy_revision)" \
        --arg shipper_sha256 "$(manifest_value "$manifest" shipper_sha256)" \
        --arg verifier_sha256 "$(manifest_value "$manifest" verifier_sha256)" \
        --arg provisioner_sha256 "$(manifest_value "$manifest" provisioner_sha256)" \
        --arg production_contract_sha256 "$(manifest_value "$manifest" production_contract_sha256)" \
        --argjson production_member_count "$(manifest_value "$manifest" production_member_count)" \
        --argjson receipt_schema "$(manifest_value "$manifest" receipt_schema)" \
        --argjson build_authority_schema "$(manifest_value "$manifest" build_authority_schema)" \
        --argjson promotion_recovery_schema "$(manifest_value "$manifest" promotion_recovery_schema)" \
        --arg promotion_recovery_sha256 "$(manifest_value "$manifest" promotion_recovery_sha256)" \
        --arg verifier_toolchain_id "$(manifest_value "$manifest" verifier_toolchain_id)" \
        --arg verifier_cargo_sha256 "$(manifest_value "$manifest" verifier_cargo_sha256)" \
        --arg verifier_rustc_sha256 "$(manifest_value "$manifest" verifier_rustc_sha256)" \
        --arg verifier_rustdoc_sha256 "$(manifest_value "$manifest" verifier_rustdoc_sha256)" \
        --arg approved_baseline_profile "$(manifest_value "$manifest" approved_baseline_profile)" \
        --arg approved_baseline_generation "$(manifest_value "$manifest" approved_baseline_generation)" \
        --arg approved_baseline_tree_sha256 "$(manifest_value "$manifest" approved_baseline_tree_sha256)" \
        --arg approved_browser_bundle_sha256 "$(manifest_value "$manifest" approved_browser_bundle_sha256)" \
        --arg approved_browser_version "$(manifest_value "$manifest" approved_browser_version)" \
        --arg approved_browser_launch_profile_sha256 "$(manifest_value "$manifest" approved_browser_launch_profile_sha256)" \
        --argjson verifier_schema "$(manifest_value "$manifest" verifier_schema)" \
        --arg workflow_commit "$(manifest_value "$manifest" workflow_commit)" \
        '{
          schema:$schema,
          generation:$generation,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          authority_tree_sha256:$authority_tree_sha256,
          verification_policy_revision:$verification_policy_revision,
          shipper_sha256:$shipper_sha256,
          verifier_sha256:$verifier_sha256,
          provisioner_sha256:$provisioner_sha256,
          production_contract_sha256:$production_contract_sha256,
          production_member_count:$production_member_count,
          receipt_schema:$receipt_schema,
          build_authority_schema:$build_authority_schema,
          promotion_recovery_schema:$promotion_recovery_schema,
          promotion_recovery_sha256:$promotion_recovery_sha256,
          verifier_toolchain_id:$verifier_toolchain_id,
          verifier_cargo_sha256:$verifier_cargo_sha256,
          verifier_rustc_sha256:$verifier_rustc_sha256,
          verifier_rustdoc_sha256:$verifier_rustdoc_sha256,
          approved_baseline_profile:$approved_baseline_profile,
          approved_baseline_generation:$approved_baseline_generation,
          approved_baseline_tree_sha256:$approved_baseline_tree_sha256,
          approved_browser_bundle_sha256:$approved_browser_bundle_sha256,
          approved_browser_version:$approved_browser_version,
          approved_browser_launch_profile_sha256:$approved_browser_launch_profile_sha256,
          verifier_schema:$verifier_schema,
          workflow_commit:$workflow_commit
        }'
}

assert_elf_x86_64() {
    local path=$1
    [[ -s $path && -f $path && ! -L $path ]] || die "unsafe ELF payload: $path"
    [[ $(od -An -tx1 -N6 "$path" | tr -d ' \n') == 7f454c460201 ]] \
        || die "payload is not little-endian ELF64: $path"
    [[ $(od -An -tx1 -j18 -N2 "$path" | tr -d ' \n') == 3e00 ]] \
        || die "payload is not x86_64 ELF: $path"
}

validate_manifest() {
    local manifest=$1
    local schema=$2
    local expected_generation=$3
    local expected_workflow_commit=$4
    local payload_dir=$5
    [[ $schema == 1 || $schema == 2 ]] || die 'unsupported manifest schema'
    [[ -s $manifest && -f $manifest && ! -L $manifest ]] || die 'manifest is unsafe'
    [[ $expected_generation =~ ^[1-9][0-9]{0,15}$ ]] \
        || die 'expected generation is invalid'
    ((expected_generation <= 9007199254740991)) || die 'expected generation is not exact in JSON'
    [[ $expected_workflow_commit =~ ^[0-9a-f]{40}$ ]] || die 'workflow commit is invalid'

    jq -e \
        --argjson schema "$schema" \
        --argjson generation "$expected_generation" \
        --arg workflow_commit "$expected_workflow_commit" \
        "$common_manifest_shape and (.schema == \$schema)" \
        "$manifest" >/dev/null || die 'manifest shape or semantic authority is invalid'
    if [[ $schema == 2 ]]; then
        jq -e \
            '(((.previous_generation == 0) and (.generation == 1)) or
              ((.previous_generation > 0) and
               (.generation == (.previous_generation + 1)))) and
             (.provisioner_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
             (.production_contract_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
             (.production_member_count == 12) and
             (.receipt_schema == 6) and
             (.build_authority_schema == 4) and
             (.promotion_recovery_schema == 1) and
             (.promotion_recovery_sha256 | type == "string" and test("^[0-9a-f]{64}$"))' \
            "$manifest" >/dev/null || die 'V2 protocol tuple or successor relation is invalid'
    fi

    local canonical
    if [[ $schema == 1 ]]; then
        canonical=$(render_v1_from_manifest "$manifest")
    else
        canonical=$(render_v2_from_manifest "$manifest")
    fi
    [[ $(wc -c <"$manifest") -eq ${#canonical} ]] \
        || die 'manifest is not exact canonical JSON'
    [[ $(<"$manifest") == "$canonical" ]] || die 'manifest is not exact canonical JSON'

    local shipper="$payload_dir/syntaur-ship-linux-x86_64"
    local verifier="$payload_dir/syntaur-verify-linux-x86_64"
    assert_elf_x86_64 "$shipper"
    assert_elf_x86_64 "$verifier"
    [[ $(sha256_file "$shipper") == "$(manifest_value "$manifest" shipper_sha256)" ]] \
        || die 'shipper digest differs from manifest'
    [[ $(sha256_file "$verifier") == "$(manifest_value "$manifest" verifier_sha256)" ]] \
        || die 'verifier digest differs from manifest'
    if [[ $schema == 2 ]]; then
        local provisioner="$payload_dir/syntaur-build-authority-provision"
        [[ -s $provisioner && -f $provisioner && ! -L $provisioner ]] \
            || die 'V2 provisioner payload is unsafe'
        [[ $(head -n 1 "$provisioner") == '#!/usr/bin/bash' ]] \
            || die 'V2 provisioner interpreter is invalid'
        [[ $(sha256_file "$provisioner") == "$(manifest_value "$manifest" provisioner_sha256)" ]] \
            || die 'provisioner digest differs from manifest'
    fi
}

assert_genesis() {
    local manifest=$1
    [[ -s $manifest && -f $manifest && ! -L $manifest ]] \
        || die 'genesis manifest is unsafe'
    jq -e \
        '(.schema == 2) and
         (.generation == 1) and
         (.previous_generation == 0) and
         (.previous_manifest_sha256 == ("0" * 64))' \
        "$manifest" >/dev/null || die 'initial authority is not the sole V2 genesis'
}

protocol_from_manifest() {
    local manifest=$1
    jq -cjn \
        --argjson schema 1 \
        --arg provisioner_sha256 "$(manifest_value "$manifest" provisioner_sha256)" \
        --arg production_contract_sha256 "$(manifest_value "$manifest" production_contract_sha256)" \
        --argjson production_member_count "$(manifest_value "$manifest" production_member_count)" \
        --argjson receipt_schema "$(manifest_value "$manifest" receipt_schema)" \
        --argjson build_authority_schema "$(manifest_value "$manifest" build_authority_schema)" \
        --argjson promotion_recovery_schema "$(manifest_value "$manifest" promotion_recovery_schema)" \
        --arg promotion_recovery_sha256 "$(manifest_value "$manifest" promotion_recovery_sha256)" \
        '{
          schema:$schema,
          provisioner_sha256:$provisioner_sha256,
          production_contract_sha256:$production_contract_sha256,
          production_member_count:$production_member_count,
          receipt_schema:$receipt_schema,
          build_authority_schema:$build_authority_schema,
          promotion_recovery_schema:$promotion_recovery_schema,
          promotion_recovery_sha256:$promotion_recovery_sha256
        }'
}

shipper_self_test_from_manifest() {
    local manifest=$1
    jq -cjn \
        --argjson schema 1 \
        --arg authority_version "$(manifest_value "$manifest" authority_version)" \
        --arg authority_commit "$(manifest_value "$manifest" authority_commit)" \
        --argjson protocol "$(protocol_from_manifest "$manifest")" \
        '{
          schema:$schema,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          protocol:$protocol
        }'
}

verifier_self_test_from_manifest() {
    local manifest=$1
    jq -cjn \
        --argjson schema 1 \
        --arg authority_version "$(manifest_value "$manifest" authority_version)" \
        --argjson verifier_schema "$(manifest_value "$manifest" verifier_schema)" \
        --argjson required_gate_count 18 \
        --argjson required_viewport_gate_count 4 \
        --arg protocol syntaur-verify-attestation-v5 \
        '{
          schema:$schema,
          authority_version:$authority_version,
          verifier_schema:$verifier_schema,
          required_gate_count:$required_gate_count,
          required_viewport_gate_count:$required_viewport_gate_count,
          protocol:$protocol
        }'
}

validate_exact_json_line() {
    local actual=$1
    local expected=$2
    [[ -s $actual && -f $actual && ! -L $actual ]] || die 'protocol output is unsafe'
    cmp -s "$actual" <(printf '%s\n' "$expected") \
        || die 'candidate protocol output is not the exact canonical line'
}

render_v2() {
    local output=$1
    : "${AUTHORITY_GENERATION:?}"
    : "${PREVIOUS_AUTHORITY_GENERATION:?}"
    : "${PREVIOUS_AUTHORITY_MANIFEST_SHA256:?}"
    : "${AUTHORITY_VERSION:?}"
    : "${AUTHORITY_COMMIT:?}"
    : "${VERIFICATION_POLICY_REVISION:?}"
    : "${AUTHORITY_TREE_SHA256:?}"
    : "${SHIPPER_SHA256:?}"
    : "${VERIFIER_SHA256:?}"
    : "${PROVISIONER_SHA256:?}"
    : "${PRODUCTION_CONTRACT_SHA256:?}"
    : "${PRODUCTION_MEMBER_COUNT:?}"
    : "${RECEIPT_SCHEMA:?}"
    : "${BUILD_AUTHORITY_SCHEMA:?}"
    : "${PROMOTION_RECOVERY_SCHEMA:?}"
    : "${PROMOTION_RECOVERY_SHA256:?}"
    : "${VERIFIER_TOOLCHAIN_ID:?}"
    : "${VERIFIER_CARGO_SHA256:?}"
    : "${VERIFIER_RUSTC_SHA256:?}"
    : "${VERIFIER_RUSTDOC_SHA256:?}"
    : "${BASELINE_PROFILE:?}"
    : "${BASELINE_GENERATION:?}"
    : "${BASELINE_TREE_SHA256:?}"
    : "${BROWSER_BUNDLE_SHA256:?}"
    : "${BROWSER_VERSION:?}"
    : "${BROWSER_LAUNCH_PROFILE_SHA256:?}"
    : "${VERIFIER_SCHEMA:?}"
    : "${GITHUB_SHA:?}"

    local json
    json=$(jq -cjn \
        --argjson schema 2 \
        --argjson generation "$AUTHORITY_GENERATION" \
        --argjson previous_generation "$PREVIOUS_AUTHORITY_GENERATION" \
        --arg previous_manifest_sha256 "$PREVIOUS_AUTHORITY_MANIFEST_SHA256" \
        --arg authority_version "$AUTHORITY_VERSION" \
        --arg authority_commit "$AUTHORITY_COMMIT" \
        --arg authority_tree_sha256 "$AUTHORITY_TREE_SHA256" \
        --arg verification_policy_revision "$VERIFICATION_POLICY_REVISION" \
        --arg shipper_sha256 "$SHIPPER_SHA256" \
        --arg verifier_sha256 "$VERIFIER_SHA256" \
        --arg provisioner_sha256 "$PROVISIONER_SHA256" \
        --arg production_contract_sha256 "$PRODUCTION_CONTRACT_SHA256" \
        --argjson production_member_count "$PRODUCTION_MEMBER_COUNT" \
        --argjson receipt_schema "$RECEIPT_SCHEMA" \
        --argjson build_authority_schema "$BUILD_AUTHORITY_SCHEMA" \
        --argjson promotion_recovery_schema "$PROMOTION_RECOVERY_SCHEMA" \
        --arg promotion_recovery_sha256 "$PROMOTION_RECOVERY_SHA256" \
        --arg verifier_toolchain_id "$VERIFIER_TOOLCHAIN_ID" \
        --arg verifier_cargo_sha256 "$VERIFIER_CARGO_SHA256" \
        --arg verifier_rustc_sha256 "$VERIFIER_RUSTC_SHA256" \
        --arg verifier_rustdoc_sha256 "$VERIFIER_RUSTDOC_SHA256" \
        --arg approved_baseline_profile "$BASELINE_PROFILE" \
        --arg approved_baseline_generation "$BASELINE_GENERATION" \
        --arg approved_baseline_tree_sha256 "$BASELINE_TREE_SHA256" \
        --arg approved_browser_bundle_sha256 "$BROWSER_BUNDLE_SHA256" \
        --arg approved_browser_version "$BROWSER_VERSION" \
        --arg approved_browser_launch_profile_sha256 "$BROWSER_LAUNCH_PROFILE_SHA256" \
        --argjson verifier_schema "$VERIFIER_SCHEMA" \
        --arg workflow_commit "$GITHUB_SHA" \
        '{
          schema:$schema,
          generation:$generation,
          previous_generation:$previous_generation,
          previous_manifest_sha256:$previous_manifest_sha256,
          authority_version:$authority_version,
          authority_commit:$authority_commit,
          authority_tree_sha256:$authority_tree_sha256,
          verification_policy_revision:$verification_policy_revision,
          shipper_sha256:$shipper_sha256,
          verifier_sha256:$verifier_sha256,
          provisioner_sha256:$provisioner_sha256,
          production_contract_sha256:$production_contract_sha256,
          production_member_count:$production_member_count,
          receipt_schema:$receipt_schema,
          build_authority_schema:$build_authority_schema,
          promotion_recovery_schema:$promotion_recovery_schema,
          promotion_recovery_sha256:$promotion_recovery_sha256,
          verifier_toolchain_id:$verifier_toolchain_id,
          verifier_cargo_sha256:$verifier_cargo_sha256,
          verifier_rustc_sha256:$verifier_rustc_sha256,
          verifier_rustdoc_sha256:$verifier_rustdoc_sha256,
          approved_baseline_profile:$approved_baseline_profile,
          approved_baseline_generation:$approved_baseline_generation,
          approved_baseline_tree_sha256:$approved_baseline_tree_sha256,
          approved_browser_bundle_sha256:$approved_browser_bundle_sha256,
          approved_browser_version:$approved_browser_version,
          approved_browser_launch_profile_sha256:$approved_browser_launch_profile_sha256,
          verifier_schema:$verifier_schema,
          workflow_commit:$workflow_commit
        }')
    printf '%s' "$json" >"$output"
}

assert_successor() {
    local previous=$1
    local successor=$2
    [[ -s $previous && -f $previous && ! -L $previous ]] \
        || die 'predecessor manifest is unsafe'
    [[ -s $successor && -f $successor && ! -L $successor ]] \
        || die 'successor manifest is unsafe'
    [[ $(manifest_value "$successor" schema) == 2 ]] \
        || die 'successor must use manifest schema V2'

    local previous_generation successor_generation successor_previous successor_previous_sha
    previous_generation=$(manifest_value "$previous" generation)
    successor_generation=$(manifest_value "$successor" generation)
    successor_previous=$(manifest_value "$successor" previous_generation)
    successor_previous_sha=$(manifest_value "$successor" previous_manifest_sha256)
    [[ $successor_previous == "$previous_generation" ]] \
        || die 'successor previous generation differs'
    [[ $successor_generation -eq $((previous_generation + 1)) ]] \
        || die 'successor generation is not predecessor plus one'
    [[ $successor_previous_sha == "$(sha256_file "$previous")" ]] \
        || die 'successor predecessor-manifest digest differs'
}

source_tree_sha256() {
    local repository=$1
    local commit=$2
    [[ -d $repository/.git || -f $repository/.git ]] || die 'source repository is not a Git checkout'
    [[ $commit =~ ^[0-9a-f]{40}$ ]] || die 'source commit is invalid'
    git -C "$repository" cat-file -e "${commit}^{commit}"

    local listing
    listing=$(mktemp)
    trap 'rm -f "$listing"' RETURN
    git -C "$repository" ls-tree -r -z --full-tree "$commit" -- >"$listing"
    local size
    size=$(stat -c '%s' "$listing")
    {
        printf 'syntaur-source-tree-v1\0'
        local shift byte escaped
        for shift in 56 48 40 32 24 16 8 0; do
            byte=$(((size >> shift) & 255))
            printf -v escaped '\\%03o' "$byte"
            printf '%b' "$escaped"
        done
        cat "$listing"
    } | sha256sum | awk '{print $1}'
}

validate_stage_v2() {
    local stage=$1
    [[ -d $stage && ! -L $stage ]] || die 'V2 handoff stage is unsafe'
    [[ $(stat -c '%a' "$stage") == 500 ]] || die 'V2 handoff directory mode must be 0500'

    local actual expected
    actual=$(find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
    expected=$(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 | LC_ALL=C sort)
    [[ $actual == "$expected" ]] || die 'V2 handoff stage has an inexact file set'

    local file
    for file in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        [[ -f $stage/$file && ! -L $stage/$file ]] || die "unsafe V2 handoff file: $file"
        [[ $(stat -c '%a' "$stage/$file") == 400 ]] \
            || die "V2 handoff data mode must be 0400: $file"
    done
    for file in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        [[ -f $stage/$file && ! -L $stage/$file ]] || die "unsafe V2 handoff file: $file"
        [[ $(stat -c '%a' "$stage/$file") == 500 ]] \
            || die "V2 handoff executable mode must be 0500: $file"
    done

    validate_manifest \
        "$stage/release-authority-v2.json" \
        2 \
        "$(manifest_value "$stage/release-authority-v2.json" generation)" \
        "$(manifest_value "$stage/release-authority-v2.json" workflow_commit)" \
        "$stage"
}

stage_v2() {
    local manifest=$1
    local bundle=$2
    local payload_dir=$3
    local target=$4
    [[ -f $bundle && ! -L $bundle && -s $bundle ]] || die 'Cosign bundle is unsafe'
    [[ ! -e $target && ! -L $target ]] || die 'V2 handoff target already exists'
    local parent base temporary
    parent=$(dirname "$target")
    base=$(basename "$target")
    [[ -d $parent && ! -L $parent ]] || die 'V2 handoff parent is unsafe'
    [[ $base =~ ^[A-Za-z0-9._-]+$ ]] || die 'V2 handoff target name is unsafe'
    temporary="$parent/.${base}.stage.$$"
    [[ ! -e $temporary && ! -L $temporary ]] || die 'V2 handoff temporary path exists'

    umask 077
    mkdir -m 0700 "$temporary"
    trap 'chmod 0700 "$temporary" 2>/dev/null || true; rm -rf -- "$temporary"' RETURN
    install -m 0400 "$manifest" "$temporary/release-authority-v2.json"
    install -m 0400 "$bundle" "$temporary/release-authority-v2.json.cosign.bundle"
    install -m 0500 \
        "$payload_dir/syntaur-build-authority-provision" \
        "$payload_dir/syntaur-ship-linux-x86_64" \
        "$payload_dir/syntaur-verify-linux-x86_64" \
        "$temporary/"
    chmod 0500 "$temporary"
    mv -T "$temporary" "$target"
    trap - RETURN
    validate_stage_v2 "$target"
}

case ${1:-} in
    render-approval-record)
        [[ $# -eq 2 ]] || die 'usage: render-approval-record OUTPUT'
        render_approval_record "$2"
        ;;
    validate-approval-record)
        [[ $# -eq 2 ]] || die 'usage: validate-approval-record RECORD'
        validate_approval_record "$2"
        ;;
    asset-schema)
        [[ $# -eq 2 ]] || die 'usage: asset-schema NAMES_FILE'
        asset_schema "$2"
        ;;
    validate)
        [[ $# -eq 6 ]] || die 'usage: validate MANIFEST SCHEMA GENERATION WORKFLOW_COMMIT PAYLOAD_DIR'
        validate_manifest "$2" "$3" "$4" "$5" "$6"
        ;;
    render-v2)
        [[ $# -eq 2 ]] || die 'usage: render-v2 OUTPUT'
        render_v2 "$2"
        ;;
    assert-successor)
        [[ $# -eq 3 ]] || die 'usage: assert-successor PREVIOUS SUCCESSOR'
        assert_successor "$2" "$3"
        ;;
    assert-genesis)
        [[ $# -eq 2 ]] || die 'usage: assert-genesis MANIFEST'
        assert_genesis "$2"
        ;;
    protocol-from-manifest)
        [[ $# -eq 2 ]] || die 'usage: protocol-from-manifest MANIFEST'
        printf '%s\n' "$(protocol_from_manifest "$2")"
        ;;
    validate-protocol)
        [[ $# -eq 3 ]] || die 'usage: validate-protocol OUTPUT MANIFEST'
        validate_exact_json_line "$2" "$(protocol_from_manifest "$3")"
        ;;
    shipper-self-test-from-manifest)
        [[ $# -eq 2 ]] || die 'usage: shipper-self-test-from-manifest MANIFEST'
        printf '%s\n' "$(shipper_self_test_from_manifest "$2")"
        ;;
    validate-shipper-self-test)
        [[ $# -eq 3 ]] || die 'usage: validate-shipper-self-test OUTPUT MANIFEST'
        validate_exact_json_line "$2" "$(shipper_self_test_from_manifest "$3")"
        ;;
    verifier-self-test-from-manifest)
        [[ $# -eq 2 ]] || die 'usage: verifier-self-test-from-manifest MANIFEST'
        printf '%s\n' "$(verifier_self_test_from_manifest "$2")"
        ;;
    validate-verifier-self-test)
        [[ $# -eq 3 ]] || die 'usage: validate-verifier-self-test OUTPUT MANIFEST'
        validate_exact_json_line "$2" "$(verifier_self_test_from_manifest "$3")"
        ;;
    source-tree-sha256)
        [[ $# -eq 3 ]] || die 'usage: source-tree-sha256 REPOSITORY COMMIT'
        source_tree_sha256 "$2" "$3"
        ;;
    stage-v2)
        [[ $# -eq 5 ]] || die 'usage: stage-v2 MANIFEST BUNDLE PAYLOAD_DIR TARGET'
        stage_v2 "$2" "$3" "$4" "$5"
        ;;
    validate-stage-v2)
        [[ $# -eq 2 ]] || die 'usage: validate-stage-v2 STAGE'
        validate_stage_v2 "$2"
        ;;
    *)
        die 'usage: release-authority-manifest.sh render-approval-record|validate-approval-record|asset-schema|validate|render-v2|assert-genesis|assert-successor|protocol-from-manifest|validate-protocol|shipper-self-test-from-manifest|validate-shipper-self-test|verifier-self-test-from-manifest|validate-verifier-self-test|source-tree-sha256|stage-v2|validate-stage-v2 ...'
        ;;
esac
