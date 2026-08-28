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
    local schema
    schema=$(manifest_value "$record" schema)
    if [[ $schema == 2 ]]; then
        jq -cjn \
            --argjson schema "$schema" \
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
            --argjson rejected_generation "$(manifest_value "$record" rejected_generation)" \
            --arg rejected_manifest_sha256 "$(manifest_value "$record" rejected_manifest_sha256)" \
            --arg rejected_workflow_commit "$(manifest_value "$record" rejected_workflow_commit)" \
            --arg rejected_authority_version "$(manifest_value "$record" rejected_authority_version)" \
            --arg rejected_authority_commit "$(manifest_value "$record" rejected_authority_commit)" \
            --arg rejected_product_release_commit "$(manifest_value "$record" rejected_product_release_commit)" \
            --arg settled_product_version "$(manifest_value "$record" settled_product_version)" \
            --arg settled_product_gateway_commit "$(manifest_value "$record" settled_product_gateway_commit)" \
            --arg settled_product_engine_commit "$(manifest_value "$record" settled_product_engine_commit)" \
            --arg settled_product_state_sha256 "$(manifest_value "$record" settled_product_state_sha256)" \
            --arg settled_promotion_policy_sha256 "$(manifest_value "$record" settled_promotion_policy_sha256)" \
            --arg selected_engine_commit "$(manifest_value "$record" selected_engine_commit)" \
            --arg planned_product_version "$(manifest_value "$record" planned_product_version)" \
            --arg planned_product_base_commit "$(manifest_value "$record" planned_product_base_commit)" \
            --arg replacement_reason "$(manifest_value "$record" replacement_reason)" \
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
              promotion_recovery_sha256:$promotion_recovery_sha256,
              rejected_generation:$rejected_generation,
              rejected_manifest_sha256:$rejected_manifest_sha256,
              rejected_workflow_commit:$rejected_workflow_commit,
              rejected_authority_version:$rejected_authority_version,
              rejected_authority_commit:$rejected_authority_commit,
              rejected_product_release_commit:$rejected_product_release_commit,
              settled_product_version:$settled_product_version,
              settled_product_gateway_commit:$settled_product_gateway_commit,
              settled_product_engine_commit:$settled_product_engine_commit,
              settled_product_state_sha256:$settled_product_state_sha256,
              settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
              selected_engine_commit:$selected_engine_commit,
              planned_product_version:$planned_product_version,
              planned_product_base_commit:$planned_product_base_commit,
              replacement_reason:$replacement_reason
            }'
        return
    fi
    jq -cjn \
        --argjson schema "$schema" \
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
        ((.schema == 1) or (.schema == 2)) and
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
        (.promotion_recovery_sha256 | digest) and
        (if .schema == 1 then
           (keys | sort) == ([
             "authority_commit", "authority_tree_sha256", "authority_version",
             "baseline_generation", "baseline_profile", "baseline_tree_sha256",
             "browser_bundle_sha256", "browser_launch_profile_sha256", "browser_version",
             "build_authority_schema", "previous_generation",
             "previous_manifest_sha256", "production_contract_sha256",
             "production_member_count", "promotion_recovery_schema",
             "promotion_recovery_sha256", "provisioner_sha256", "receipt_schema",
             "schema", "shipper_sha256", "verification_policy_revision",
             "verifier_schema", "verifier_sha256"
           ] | sort)
         else
           (.rejected_generation | uint and . > 0) and
           (.rejected_generation == (.previous_generation + 1)) and
           (.rejected_manifest_sha256 | digest) and
           (.rejected_manifest_sha256 != .previous_manifest_sha256) and
           (.rejected_workflow_commit | commit) and
           (.rejected_authority_version | type == "string" and
             test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$")) and
           (.rejected_authority_commit | commit) and
           (.rejected_product_release_commit | commit) and
           (.rejected_authority_commit != .rejected_product_release_commit) and
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
           (.settled_product_version == .authority_version) and
           (.settled_product_gateway_commit != .authority_commit) and
           (.planned_product_base_commit == .authority_commit) and
           ((.authority_version | split(".") | map(tonumber)) as $selected |
            (.planned_product_version | split(".") | map(tonumber)) as $planned |
            ($planned[0] == $selected[0]) and
            ($planned[1] == $selected[1]) and
            ($planned[2] == ($selected[2] + 1))) and
           (.replacement_reason == "authority_target_mismatch") and
           (keys | sort) == ([
             "authority_commit", "authority_tree_sha256", "authority_version",
             "baseline_generation", "baseline_profile", "baseline_tree_sha256",
             "browser_bundle_sha256", "browser_launch_profile_sha256", "browser_version",
             "build_authority_schema", "previous_generation",
             "previous_manifest_sha256", "production_contract_sha256",
             "production_member_count", "promotion_recovery_schema",
             "promotion_recovery_sha256", "provisioner_sha256", "receipt_schema",
             "rejected_authority_commit", "rejected_authority_version",
             "rejected_generation", "rejected_manifest_sha256",
             "rejected_product_release_commit", "rejected_workflow_commit",
             "planned_product_base_commit", "planned_product_version",
             "replacement_reason", "schema", "selected_engine_commit",
             "settled_product_engine_commit", "settled_product_gateway_commit",
             "settled_product_state_sha256", "settled_product_version",
             "settled_promotion_policy_sha256", "shipper_sha256",
             "verification_policy_revision", "verifier_schema", "verifier_sha256"
           ] | sort)
         end)
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
    local approval_schema=${AUTHORITY_APPROVAL_SCHEMA:-1}
    [[ $approval_schema == 1 || $approval_schema == 2 ]] \
        || die 'authority approval schema must be 1 or 2'
    if [[ $approval_schema == 2 ]]; then
        : "${REJECTED_AUTHORITY_GENERATION:?}"
        : "${REJECTED_AUTHORITY_MANIFEST_SHA256:?}"
        : "${REJECTED_AUTHORITY_WORKFLOW_COMMIT:?}"
        : "${REJECTED_AUTHORITY_VERSION:?}"
        : "${REJECTED_AUTHORITY_COMMIT:?}"
        : "${REJECTED_PRODUCT_RELEASE_COMMIT:?}"
        : "${SETTLED_PRODUCT_VERSION:?}"
        : "${SETTLED_PRODUCT_GATEWAY_COMMIT:?}"
        : "${SETTLED_PRODUCT_ENGINE_COMMIT:?}"
        : "${SETTLED_PRODUCT_STATE_SHA256:?}"
        : "${SETTLED_PROMOTION_POLICY_SHA256:?}"
        : "${SELECTED_ENGINE_COMMIT:?}"
        : "${PLANNED_PRODUCT_VERSION:?}"
        : "${PLANNED_PRODUCT_BASE_COMMIT:?}"
        : "${AUTHORITY_REPLACEMENT_REASON:?}"
    fi
    jq -cjn \
        --argjson schema "$approval_schema" \
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
        --argjson rejected_generation "${REJECTED_AUTHORITY_GENERATION:-0}" \
        --arg rejected_manifest_sha256 "${REJECTED_AUTHORITY_MANIFEST_SHA256:-}" \
        --arg rejected_workflow_commit "${REJECTED_AUTHORITY_WORKFLOW_COMMIT:-}" \
        --arg rejected_authority_version "${REJECTED_AUTHORITY_VERSION:-}" \
        --arg rejected_authority_commit "${REJECTED_AUTHORITY_COMMIT:-}" \
        --arg rejected_product_release_commit "${REJECTED_PRODUCT_RELEASE_COMMIT:-}" \
        --arg settled_product_version "${SETTLED_PRODUCT_VERSION:-}" \
        --arg settled_product_gateway_commit "${SETTLED_PRODUCT_GATEWAY_COMMIT:-}" \
        --arg settled_product_engine_commit "${SETTLED_PRODUCT_ENGINE_COMMIT:-}" \
        --arg settled_product_state_sha256 "${SETTLED_PRODUCT_STATE_SHA256:-}" \
        --arg settled_promotion_policy_sha256 "${SETTLED_PROMOTION_POLICY_SHA256:-}" \
        --arg selected_engine_commit "${SELECTED_ENGINE_COMMIT:-}" \
        --arg planned_product_version "${PLANNED_PRODUCT_VERSION:-}" \
        --arg planned_product_base_commit "${PLANNED_PRODUCT_BASE_COMMIT:-}" \
        --arg replacement_reason "${AUTHORITY_REPLACEMENT_REASON:-}" \
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
        } + (if $schema == 2 then {
          rejected_generation:$rejected_generation,
          rejected_manifest_sha256:$rejected_manifest_sha256,
          rejected_workflow_commit:$rejected_workflow_commit,
          rejected_authority_version:$rejected_authority_version,
          rejected_authority_commit:$rejected_authority_commit,
          rejected_product_release_commit:$rejected_product_release_commit,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_product_state_sha256:$settled_product_state_sha256,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_engine_commit:$selected_engine_commit,
          planned_product_version:$planned_product_version,
          planned_product_base_commit:$planned_product_base_commit,
          replacement_reason:$replacement_reason
        } else {} end)' >"$output"
    validate_approval_record "$output"
}

selection_review_from_file() {
    local record=$1
    jq -cjn \
        --argjson schema "$(manifest_value "$record" schema)" \
        --arg reason "$(manifest_value "$record" reason)" \
        --argjson predecessor_generation "$(manifest_value "$record" predecessor_generation)" \
        --arg predecessor_manifest_sha256 "$(manifest_value "$record" predecessor_manifest_sha256)" \
        --argjson rejected_generation "$(manifest_value "$record" rejected_generation)" \
        --arg rejected_tag "$(manifest_value "$record" rejected_tag)" \
        --arg rejected_manifest_sha256 "$(manifest_value "$record" rejected_manifest_sha256)" \
        --arg rejected_workflow_commit "$(manifest_value "$record" rejected_workflow_commit)" \
        --arg rejected_authority_version "$(manifest_value "$record" rejected_authority_version)" \
        --arg rejected_authority_commit "$(manifest_value "$record" rejected_authority_commit)" \
        --arg rejected_product_release_commit "$(manifest_value "$record" rejected_product_release_commit)" \
        --argjson selected_generation "$(manifest_value "$record" selected_generation)" \
        --arg selected_tag "$(manifest_value "$record" selected_tag)" \
        --arg selected_manifest_sha256 "$(manifest_value "$record" selected_manifest_sha256)" \
        --arg selected_workflow_commit "$(manifest_value "$record" selected_workflow_commit)" \
        --arg selected_authority_version "$(manifest_value "$record" selected_authority_version)" \
        --arg selected_authority_commit "$(manifest_value "$record" selected_authority_commit)" \
        --arg settled_product_version "$(manifest_value "$record" settled_product_version)" \
        --arg settled_product_gateway_commit "$(manifest_value "$record" settled_product_gateway_commit)" \
        --arg settled_product_engine_commit "$(manifest_value "$record" settled_product_engine_commit)" \
        --arg settled_product_state_sha256 "$(manifest_value "$record" settled_product_state_sha256)" \
        --arg settled_promotion_policy_sha256 "$(manifest_value "$record" settled_promotion_policy_sha256)" \
        --arg selected_engine_commit "$(manifest_value "$record" selected_engine_commit)" \
        --arg planned_product_version "$(manifest_value "$record" planned_product_version)" \
        --arg planned_product_base_commit "$(manifest_value "$record" planned_product_base_commit)" \
        '{
          schema:$schema,
          reason:$reason,
          predecessor_generation:$predecessor_generation,
          predecessor_manifest_sha256:$predecessor_manifest_sha256,
          rejected_generation:$rejected_generation,
          rejected_tag:$rejected_tag,
          rejected_manifest_sha256:$rejected_manifest_sha256,
          rejected_workflow_commit:$rejected_workflow_commit,
          rejected_authority_version:$rejected_authority_version,
          rejected_authority_commit:$rejected_authority_commit,
          rejected_product_release_commit:$rejected_product_release_commit,
          selected_generation:$selected_generation,
          selected_tag:$selected_tag,
          selected_manifest_sha256:$selected_manifest_sha256,
          selected_workflow_commit:$selected_workflow_commit,
          selected_authority_version:$selected_authority_version,
          selected_authority_commit:$selected_authority_commit,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_product_state_sha256:$settled_product_state_sha256,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_engine_commit:$selected_engine_commit,
          planned_product_version:$planned_product_version,
          planned_product_base_commit:$planned_product_base_commit
        }'
}

validate_selection_review() {
    local record=$1
    [[ -s $record && -f $record && ! -L $record ]] \
        || die 'authority replacement selection review is unsafe'
    jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        def version: type == "string" and
          test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$");
        def uint: type == "number" and . >= 0 and . <= 9007199254740991 and floor == .;
        (.schema == 1) and
        (.reason == "authority_target_mismatch") and
        (.predecessor_generation | uint and . > 0 and . < 9007199254740991) and
        (.predecessor_manifest_sha256 | digest) and
        (.rejected_generation == (.predecessor_generation + 1)) and
        (.selected_generation == .rejected_generation) and
        (.rejected_tag == ("authority-v1-g" + (.rejected_generation | tostring))) and
        (.selected_tag == ("authority-replacement-v1-g" + (.selected_generation | tostring))) and
        (.rejected_manifest_sha256 | digest) and
        (.selected_manifest_sha256 | digest) and
        (.rejected_manifest_sha256 != .selected_manifest_sha256) and
        (.rejected_workflow_commit | commit) and
        (.selected_workflow_commit | commit) and
        (.rejected_workflow_commit != .selected_workflow_commit) and
        (.rejected_authority_version | version) and
        (.selected_authority_version | version) and
        (.rejected_authority_commit | commit) and
        (.selected_authority_commit | commit) and
        (.settled_product_version | version) and
        (.settled_product_gateway_commit | commit) and
        (.settled_product_engine_commit | commit) and
        (.settled_product_state_sha256 | digest) and
        (.settled_promotion_policy_sha256 | digest) and
        (.selected_engine_commit | commit) and
        (.planned_product_version | version) and
        (.planned_product_base_commit | commit) and
        (.settled_product_version == .selected_authority_version) and
        (.settled_product_gateway_commit != .selected_authority_commit) and
        (.planned_product_base_commit == .selected_authority_commit) and
        ((.selected_authority_version | split(".") | map(tonumber)) as $selected |
         (.planned_product_version | split(".") | map(tonumber)) as $planned |
         ($planned[0] == $selected[0]) and
         ($planned[1] == $selected[1]) and
         ($planned[2] == ($selected[2] + 1))) and
        (.rejected_product_release_commit | commit) and
        (.rejected_authority_commit != .rejected_product_release_commit) and
        (keys | sort) == ([
          "planned_product_base_commit", "planned_product_version",
          "predecessor_generation", "predecessor_manifest_sha256", "reason",
          "rejected_authority_commit", "rejected_authority_version",
          "rejected_generation", "rejected_manifest_sha256",
          "rejected_product_release_commit", "rejected_tag",
          "rejected_workflow_commit", "schema", "selected_authority_commit",
          "selected_engine_commit",
          "selected_authority_version", "selected_generation",
          "selected_manifest_sha256", "selected_tag", "selected_workflow_commit",
          "settled_product_engine_commit", "settled_product_gateway_commit",
          "settled_product_state_sha256", "settled_product_version",
          "settled_promotion_policy_sha256"
        ] | sort)
    ' "$record" >/dev/null \
        || die 'authority replacement selection review shape or values are invalid'
    local canonical
    canonical=$(selection_review_from_file "$record")
    [[ $(wc -c <"$record") -eq ${#canonical} && $(<"$record") == "$canonical" ]] \
        || die 'authority replacement selection review is not exact canonical JSON'
}

render_selection_review() {
    local output=$1
    : "${REPLACEMENT_PREDECESSOR_GENERATION:?}"
    : "${REPLACEMENT_PREDECESSOR_MANIFEST_SHA256:?}"
    : "${REJECTED_AUTHORITY_GENERATION:?}"
    : "${REJECTED_AUTHORITY_MANIFEST_SHA256:?}"
    : "${REJECTED_AUTHORITY_WORKFLOW_COMMIT:?}"
    : "${REJECTED_AUTHORITY_VERSION:?}"
    : "${REJECTED_AUTHORITY_COMMIT:?}"
    : "${REJECTED_PRODUCT_RELEASE_COMMIT:?}"
    : "${SELECTED_AUTHORITY_GENERATION:?}"
    : "${SELECTED_AUTHORITY_MANIFEST_SHA256:?}"
    : "${SELECTED_AUTHORITY_WORKFLOW_COMMIT:?}"
    : "${SELECTED_AUTHORITY_VERSION:?}"
    : "${SELECTED_AUTHORITY_COMMIT:?}"
    : "${SETTLED_PRODUCT_VERSION:?}"
    : "${SETTLED_PRODUCT_GATEWAY_COMMIT:?}"
    : "${SETTLED_PRODUCT_ENGINE_COMMIT:?}"
    : "${SETTLED_PRODUCT_STATE_SHA256:?}"
    : "${SETTLED_PROMOTION_POLICY_SHA256:?}"
    : "${SELECTED_ENGINE_COMMIT:?}"
    : "${PLANNED_PRODUCT_VERSION:?}"
    : "${PLANNED_PRODUCT_BASE_COMMIT:?}"
    jq -cjn \
        --argjson schema 1 \
        --arg reason authority_target_mismatch \
        --argjson predecessor_generation "$REPLACEMENT_PREDECESSOR_GENERATION" \
        --arg predecessor_manifest_sha256 "$REPLACEMENT_PREDECESSOR_MANIFEST_SHA256" \
        --argjson rejected_generation "$REJECTED_AUTHORITY_GENERATION" \
        --arg rejected_tag "authority-v1-g${REJECTED_AUTHORITY_GENERATION}" \
        --arg rejected_manifest_sha256 "$REJECTED_AUTHORITY_MANIFEST_SHA256" \
        --arg rejected_workflow_commit "$REJECTED_AUTHORITY_WORKFLOW_COMMIT" \
        --arg rejected_authority_version "$REJECTED_AUTHORITY_VERSION" \
        --arg rejected_authority_commit "$REJECTED_AUTHORITY_COMMIT" \
        --arg rejected_product_release_commit "$REJECTED_PRODUCT_RELEASE_COMMIT" \
        --argjson selected_generation "$SELECTED_AUTHORITY_GENERATION" \
        --arg selected_tag "authority-replacement-v1-g${SELECTED_AUTHORITY_GENERATION}" \
        --arg selected_manifest_sha256 "$SELECTED_AUTHORITY_MANIFEST_SHA256" \
        --arg selected_workflow_commit "$SELECTED_AUTHORITY_WORKFLOW_COMMIT" \
        --arg selected_authority_version "$SELECTED_AUTHORITY_VERSION" \
        --arg selected_authority_commit "$SELECTED_AUTHORITY_COMMIT" \
        --arg settled_product_version "$SETTLED_PRODUCT_VERSION" \
        --arg settled_product_gateway_commit "$SETTLED_PRODUCT_GATEWAY_COMMIT" \
        --arg settled_product_engine_commit "$SETTLED_PRODUCT_ENGINE_COMMIT" \
        --arg settled_product_state_sha256 "$SETTLED_PRODUCT_STATE_SHA256" \
        --arg settled_promotion_policy_sha256 "$SETTLED_PROMOTION_POLICY_SHA256" \
        --arg selected_engine_commit "$SELECTED_ENGINE_COMMIT" \
        --arg planned_product_version "$PLANNED_PRODUCT_VERSION" \
        --arg planned_product_base_commit "$PLANNED_PRODUCT_BASE_COMMIT" \
        '{
          schema:$schema,
          reason:$reason,
          predecessor_generation:$predecessor_generation,
          predecessor_manifest_sha256:$predecessor_manifest_sha256,
          rejected_generation:$rejected_generation,
          rejected_tag:$rejected_tag,
          rejected_manifest_sha256:$rejected_manifest_sha256,
          rejected_workflow_commit:$rejected_workflow_commit,
          rejected_authority_version:$rejected_authority_version,
          rejected_authority_commit:$rejected_authority_commit,
          rejected_product_release_commit:$rejected_product_release_commit,
          selected_generation:$selected_generation,
          selected_tag:$selected_tag,
          selected_manifest_sha256:$selected_manifest_sha256,
          selected_workflow_commit:$selected_workflow_commit,
          selected_authority_version:$selected_authority_version,
          selected_authority_commit:$selected_authority_commit,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_product_state_sha256:$settled_product_state_sha256,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_engine_commit:$selected_engine_commit,
          planned_product_version:$planned_product_version,
          planned_product_base_commit:$planned_product_base_commit
        }' >"$output"
    validate_selection_review "$output"
}

replacement_resolution_from_file() {
    local record=$1
    jq -cjn \
        --argjson schema "$(manifest_value "$record" schema)" \
        --arg reason "$(manifest_value "$record" reason)" \
        --argjson predecessor_generation "$(manifest_value "$record" predecessor_generation)" \
        --arg predecessor_manifest_sha256 "$(manifest_value "$record" predecessor_manifest_sha256)" \
        --argjson rejected_generation "$(manifest_value "$record" rejected_generation)" \
        --arg rejected_tag "$(manifest_value "$record" rejected_tag)" \
        --arg rejected_manifest_sha256 "$(manifest_value "$record" rejected_manifest_sha256)" \
        --arg rejected_workflow_commit "$(manifest_value "$record" rejected_workflow_commit)" \
        --arg rejected_authority_version "$(manifest_value "$record" rejected_authority_version)" \
        --arg rejected_authority_commit "$(manifest_value "$record" rejected_authority_commit)" \
        --arg rejected_product_release_commit "$(manifest_value "$record" rejected_product_release_commit)" \
        --argjson selected_generation "$(manifest_value "$record" selected_generation)" \
        --arg selected_tag "$(manifest_value "$record" selected_tag)" \
        --arg selected_manifest_sha256 "$(manifest_value "$record" selected_manifest_sha256)" \
        --arg selected_workflow_commit "$(manifest_value "$record" selected_workflow_commit)" \
        --arg selected_authority_version "$(manifest_value "$record" selected_authority_version)" \
        --arg selected_authority_commit "$(manifest_value "$record" selected_authority_commit)" \
        --arg settled_product_version "$(manifest_value "$record" settled_product_version)" \
        --arg settled_product_gateway_commit "$(manifest_value "$record" settled_product_gateway_commit)" \
        --arg settled_product_engine_commit "$(manifest_value "$record" settled_product_engine_commit)" \
        --arg settled_product_state_sha256 "$(manifest_value "$record" settled_product_state_sha256)" \
        --arg settled_promotion_policy_sha256 "$(manifest_value "$record" settled_promotion_policy_sha256)" \
        --arg selected_engine_commit "$(manifest_value "$record" selected_engine_commit)" \
        --arg planned_product_version "$(manifest_value "$record" planned_product_version)" \
        --arg planned_product_base_commit "$(manifest_value "$record" planned_product_base_commit)" \
        --arg selection_review_sha256 "$(manifest_value "$record" selection_review_sha256)" \
        --arg recovery_tool_sha256 "$(manifest_value "$record" recovery_tool_sha256)" \
        --arg manifest_helper_sha256 "$(manifest_value "$record" manifest_helper_sha256)" \
        --arg resolution_workflow_commit "$(manifest_value "$record" resolution_workflow_commit)" \
        '{
          schema:$schema,
          reason:$reason,
          predecessor_generation:$predecessor_generation,
          predecessor_manifest_sha256:$predecessor_manifest_sha256,
          rejected_generation:$rejected_generation,
          rejected_tag:$rejected_tag,
          rejected_manifest_sha256:$rejected_manifest_sha256,
          rejected_workflow_commit:$rejected_workflow_commit,
          rejected_authority_version:$rejected_authority_version,
          rejected_authority_commit:$rejected_authority_commit,
          rejected_product_release_commit:$rejected_product_release_commit,
          selected_generation:$selected_generation,
          selected_tag:$selected_tag,
          selected_manifest_sha256:$selected_manifest_sha256,
          selected_workflow_commit:$selected_workflow_commit,
          selected_authority_version:$selected_authority_version,
          selected_authority_commit:$selected_authority_commit,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_product_state_sha256:$settled_product_state_sha256,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_engine_commit:$selected_engine_commit,
          planned_product_version:$planned_product_version,
          planned_product_base_commit:$planned_product_base_commit,
          selection_review_sha256:$selection_review_sha256,
          recovery_tool_sha256:$recovery_tool_sha256,
          manifest_helper_sha256:$manifest_helper_sha256,
          resolution_workflow_commit:$resolution_workflow_commit
        }'
}

validate_replacement_resolution() {
    local record=$1
    [[ -s $record && -f $record && ! -L $record ]] \
        || die 'authority replacement resolution is unsafe'
    jq -e '
        def digest: type == "string" and test("^[0-9a-f]{64}$");
        def commit: type == "string" and test("^[0-9a-f]{40}$");
        def version: type == "string" and
          test("^(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})\\.(0|[1-9][0-9]{0,9})$");
        def uint: type == "number" and . >= 0 and . <= 9007199254740991 and floor == .;
        (.schema == 1) and
        (.reason == "authority_target_mismatch") and
        (.predecessor_generation | uint and . > 0 and . < 9007199254740991) and
        (.predecessor_manifest_sha256 | digest) and
        (.rejected_generation == (.predecessor_generation + 1)) and
        (.selected_generation == .rejected_generation) and
        (.rejected_tag == ("authority-v1-g" + (.rejected_generation | tostring))) and
        (.selected_tag == ("authority-replacement-v1-g" + (.selected_generation | tostring))) and
        (.rejected_manifest_sha256 | digest) and
        (.selected_manifest_sha256 | digest) and
        (.rejected_manifest_sha256 != .selected_manifest_sha256) and
        (.rejected_workflow_commit | commit) and
        (.selected_workflow_commit | commit) and
        (.resolution_workflow_commit | commit) and
        (.rejected_workflow_commit != .selected_workflow_commit) and
        (.rejected_workflow_commit != .resolution_workflow_commit) and
        (.selected_workflow_commit != .resolution_workflow_commit) and
        (.rejected_authority_version | version) and
        (.selected_authority_version | version) and
        (.rejected_authority_commit | commit) and
        (.selected_authority_commit | commit) and
        (.settled_product_version | version) and
        (.settled_product_gateway_commit | commit) and
        (.settled_product_engine_commit | commit) and
        (.settled_product_state_sha256 | digest) and
        (.settled_promotion_policy_sha256 | digest) and
        (.selected_engine_commit | commit) and
        (.planned_product_version | version) and
        (.planned_product_base_commit | commit) and
        (.settled_product_version == .selected_authority_version) and
        (.settled_product_gateway_commit != .selected_authority_commit) and
        (.planned_product_base_commit == .selected_authority_commit) and
        ((.selected_authority_version | split(".") | map(tonumber)) as $selected |
         (.planned_product_version | split(".") | map(tonumber)) as $planned |
         ($planned[0] == $selected[0]) and
         ($planned[1] == $selected[1]) and
         ($planned[2] == ($selected[2] + 1))) and
        (.rejected_product_release_commit | commit) and
        (.rejected_authority_commit != .rejected_product_release_commit) and
        (.selection_review_sha256 | digest) and
        (.recovery_tool_sha256 | digest) and
        (.manifest_helper_sha256 | digest) and
        (keys | sort) == ([
          "manifest_helper_sha256", "planned_product_base_commit",
          "planned_product_version", "predecessor_generation",
          "predecessor_manifest_sha256", "reason", "recovery_tool_sha256",
          "resolution_workflow_commit",
          "rejected_authority_commit", "rejected_authority_version",
          "rejected_generation", "rejected_manifest_sha256",
          "rejected_product_release_commit", "rejected_tag",
          "rejected_workflow_commit", "schema", "selected_authority_commit",
          "selected_authority_version", "selected_engine_commit", "selected_generation",
          "selected_manifest_sha256", "selected_tag", "selected_workflow_commit",
          "selection_review_sha256", "settled_product_engine_commit",
          "settled_product_gateway_commit", "settled_product_state_sha256",
          "settled_product_version", "settled_promotion_policy_sha256"
        ] | sort)
    ' "$record" >/dev/null || die 'authority replacement resolution shape or values are invalid'
    local canonical
    canonical=$(replacement_resolution_from_file "$record")
    [[ $(wc -c <"$record") -eq ${#canonical} && $(<"$record") == "$canonical" ]] \
        || die 'authority replacement resolution is not exact canonical JSON'
}

render_replacement_resolution() {
    local output=$1
    : "${REPLACEMENT_PREDECESSOR_GENERATION:?}"
    : "${REPLACEMENT_PREDECESSOR_MANIFEST_SHA256:?}"
    : "${REJECTED_AUTHORITY_GENERATION:?}"
    : "${REJECTED_AUTHORITY_MANIFEST_SHA256:?}"
    : "${REJECTED_AUTHORITY_WORKFLOW_COMMIT:?}"
    : "${REJECTED_AUTHORITY_VERSION:?}"
    : "${REJECTED_AUTHORITY_COMMIT:?}"
    : "${REJECTED_PRODUCT_RELEASE_COMMIT:?}"
    : "${SELECTED_AUTHORITY_GENERATION:?}"
    : "${SELECTED_AUTHORITY_MANIFEST_SHA256:?}"
    : "${SELECTED_AUTHORITY_WORKFLOW_COMMIT:?}"
    : "${SELECTED_AUTHORITY_VERSION:?}"
    : "${SELECTED_AUTHORITY_COMMIT:?}"
    : "${SETTLED_PRODUCT_VERSION:?}"
    : "${SETTLED_PRODUCT_GATEWAY_COMMIT:?}"
    : "${SETTLED_PRODUCT_ENGINE_COMMIT:?}"
    : "${SETTLED_PRODUCT_STATE_SHA256:?}"
    : "${SETTLED_PROMOTION_POLICY_SHA256:?}"
    : "${SELECTED_ENGINE_COMMIT:?}"
    : "${PLANNED_PRODUCT_VERSION:?}"
    : "${PLANNED_PRODUCT_BASE_COMMIT:?}"
    : "${SELECTION_REVIEW_SHA256:?}"
    : "${RECOVERY_TOOL_SHA256:?}"
    : "${MANIFEST_HELPER_SHA256:?}"
    : "${RESOLUTION_WORKFLOW_COMMIT:?}"
    jq -cjn \
        --argjson schema 1 \
        --arg reason authority_target_mismatch \
        --argjson predecessor_generation "$REPLACEMENT_PREDECESSOR_GENERATION" \
        --arg predecessor_manifest_sha256 "$REPLACEMENT_PREDECESSOR_MANIFEST_SHA256" \
        --argjson rejected_generation "$REJECTED_AUTHORITY_GENERATION" \
        --arg rejected_tag "authority-v1-g${REJECTED_AUTHORITY_GENERATION}" \
        --arg rejected_manifest_sha256 "$REJECTED_AUTHORITY_MANIFEST_SHA256" \
        --arg rejected_workflow_commit "$REJECTED_AUTHORITY_WORKFLOW_COMMIT" \
        --arg rejected_authority_version "$REJECTED_AUTHORITY_VERSION" \
        --arg rejected_authority_commit "$REJECTED_AUTHORITY_COMMIT" \
        --arg rejected_product_release_commit "$REJECTED_PRODUCT_RELEASE_COMMIT" \
        --argjson selected_generation "$SELECTED_AUTHORITY_GENERATION" \
        --arg selected_tag "authority-replacement-v1-g${SELECTED_AUTHORITY_GENERATION}" \
        --arg selected_manifest_sha256 "$SELECTED_AUTHORITY_MANIFEST_SHA256" \
        --arg selected_workflow_commit "$SELECTED_AUTHORITY_WORKFLOW_COMMIT" \
        --arg selected_authority_version "$SELECTED_AUTHORITY_VERSION" \
        --arg selected_authority_commit "$SELECTED_AUTHORITY_COMMIT" \
        --arg settled_product_version "$SETTLED_PRODUCT_VERSION" \
        --arg settled_product_gateway_commit "$SETTLED_PRODUCT_GATEWAY_COMMIT" \
        --arg settled_product_engine_commit "$SETTLED_PRODUCT_ENGINE_COMMIT" \
        --arg settled_product_state_sha256 "$SETTLED_PRODUCT_STATE_SHA256" \
        --arg settled_promotion_policy_sha256 "$SETTLED_PROMOTION_POLICY_SHA256" \
        --arg selected_engine_commit "$SELECTED_ENGINE_COMMIT" \
        --arg planned_product_version "$PLANNED_PRODUCT_VERSION" \
        --arg planned_product_base_commit "$PLANNED_PRODUCT_BASE_COMMIT" \
        --arg selection_review_sha256 "$SELECTION_REVIEW_SHA256" \
        --arg recovery_tool_sha256 "$RECOVERY_TOOL_SHA256" \
        --arg manifest_helper_sha256 "$MANIFEST_HELPER_SHA256" \
        --arg resolution_workflow_commit "$RESOLUTION_WORKFLOW_COMMIT" \
        '{
          schema:$schema,
          reason:$reason,
          predecessor_generation:$predecessor_generation,
          predecessor_manifest_sha256:$predecessor_manifest_sha256,
          rejected_generation:$rejected_generation,
          rejected_tag:$rejected_tag,
          rejected_manifest_sha256:$rejected_manifest_sha256,
          rejected_workflow_commit:$rejected_workflow_commit,
          rejected_authority_version:$rejected_authority_version,
          rejected_authority_commit:$rejected_authority_commit,
          rejected_product_release_commit:$rejected_product_release_commit,
          selected_generation:$selected_generation,
          selected_tag:$selected_tag,
          selected_manifest_sha256:$selected_manifest_sha256,
          selected_workflow_commit:$selected_workflow_commit,
          selected_authority_version:$selected_authority_version,
          selected_authority_commit:$selected_authority_commit,
          settled_product_version:$settled_product_version,
          settled_product_gateway_commit:$settled_product_gateway_commit,
          settled_product_engine_commit:$settled_product_engine_commit,
          settled_product_state_sha256:$settled_product_state_sha256,
          settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
          selected_engine_commit:$selected_engine_commit,
          planned_product_version:$planned_product_version,
          planned_product_base_commit:$planned_product_base_commit,
          selection_review_sha256:$selection_review_sha256,
          recovery_tool_sha256:$recovery_tool_sha256,
          manifest_helper_sha256:$manifest_helper_sha256,
          resolution_workflow_commit:$resolution_workflow_commit
        }' >"$output"
    validate_replacement_resolution "$output"
}

validate_replacement_resolution_assets() {
    local directory=$1
    [[ -d $directory && ! -L $directory ]] \
        || die 'authority replacement resolution directory is unsafe'
    local actual expected
    actual=$(find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    expected=$(printf '%s\n' \
        recover-release-authority-replacement-v1.sh \
        release-authority-manifest.sh \
        release-authority-selection-review-v1.json \
        release-authority-replacement-v1.json \
        release-authority-replacement-v1.json.cosign.bundle \
        | LC_ALL=C sort)
    [[ $actual == "$expected" ]] \
        || die 'authority replacement resolution asset set is inexact'
    local resolution review
    resolution=$directory/release-authority-replacement-v1.json
    review=$directory/release-authority-selection-review-v1.json
    for name in \
        recover-release-authority-replacement-v1.sh \
        release-authority-manifest.sh \
        release-authority-selection-review-v1.json \
        release-authority-replacement-v1.json \
        release-authority-replacement-v1.json.cosign.bundle; do
        [[ -f $directory/$name && ! -L $directory/$name ]] \
            || die 'authority replacement resolution contains a non-regular entry'
    done
    validate_replacement_resolution "$resolution"
    validate_selection_review "$review"
    local tool_sha helper_sha review_sha
    tool_sha=$(sha256_file "$directory/recover-release-authority-replacement-v1.sh")
    helper_sha=$(sha256_file "$directory/release-authority-manifest.sh")
    review_sha=$(sha256_file "$review")
    [[ $tool_sha == "$(manifest_value \
        "$resolution" recovery_tool_sha256)" ]] \
        || die 'authority replacement recovery tool differs from the signed resolution'
    [[ $helper_sha == "$(manifest_value \
        "$resolution" manifest_helper_sha256)" ]] \
        || die 'authority replacement manifest helper differs from the signed resolution'
    [[ $review_sha == "$(manifest_value "$resolution" selection_review_sha256)" ]] \
        || die 'authority replacement selection review differs from the signed resolution'
    [[ $(selection_review_from_file "$resolution") == "$(<"$review")" ]] \
        || die 'authority replacement resolution does not bind the exact selection review'
}

assert_replacement() {
    local predecessor=$1
    local rejected=$2
    local selected=$3
    local resolution=$4
    [[ -s $predecessor && -f $predecessor && ! -L $predecessor ]] \
        || die 'replacement predecessor manifest is unsafe'
    [[ -s $rejected && -f $rejected && ! -L $rejected ]] \
        || die 'replacement rejected manifest is unsafe'
    [[ -s $selected && -f $selected && ! -L $selected ]] \
        || die 'replacement selected manifest is unsafe'
    validate_replacement_resolution "$resolution"
    assert_successor "$predecessor" "$rejected"
    assert_successor "$predecessor" "$selected"

    local predecessor_sha rejected_sha selected_sha
    predecessor_sha=$(sha256_file "$predecessor")
    rejected_sha=$(sha256_file "$rejected")
    selected_sha=$(sha256_file "$selected")
    jq -e \
        --arg predecessor_sha "$predecessor_sha" \
        --arg rejected_sha "$rejected_sha" \
        --arg selected_sha "$selected_sha" \
        --argjson predecessor_generation "$(manifest_value "$predecessor" generation)" \
        --argjson rejected_generation "$(manifest_value "$rejected" generation)" \
        --arg rejected_workflow_commit "$(manifest_value "$rejected" workflow_commit)" \
        --arg rejected_authority_version "$(manifest_value "$rejected" authority_version)" \
        --arg rejected_authority_commit "$(manifest_value "$rejected" authority_commit)" \
        --argjson selected_generation "$(manifest_value "$selected" generation)" \
        --arg selected_workflow_commit "$(manifest_value "$selected" workflow_commit)" \
        --arg selected_authority_version "$(manifest_value "$selected" authority_version)" \
        --arg selected_authority_commit "$(manifest_value "$selected" authority_commit)" \
        '
          .predecessor_generation == $predecessor_generation and
          .predecessor_manifest_sha256 == $predecessor_sha and
          .rejected_generation == $rejected_generation and
          .rejected_manifest_sha256 == $rejected_sha and
          .rejected_workflow_commit == $rejected_workflow_commit and
          .rejected_authority_version == $rejected_authority_version and
          .rejected_authority_commit == $rejected_authority_commit and
          .selected_generation == $selected_generation and
          .selected_manifest_sha256 == $selected_sha and
          .selected_workflow_commit == $selected_workflow_commit and
          .selected_authority_version == $selected_authority_version and
          .selected_authority_commit == $selected_authority_commit
        ' "$resolution" >/dev/null \
        || die 'replacement resolution does not bind the exact authority manifests'
}

validate_special_tag_namespace() {
    local prefix=$1
    local maximum_generation=$2
    local names_file=$3
    case $prefix in
        authority-replacement-v1-g|authority-resolution-v1-g) ;;
        *) die 'special authority tag namespace is unsupported' ;;
    esac
    [[ $maximum_generation =~ ^(0|[1-9][0-9]{0,15})$ \
        && $maximum_generation -le 9007199254740991 ]] \
        || die 'special authority tag generation bound is invalid'
    [[ -f $names_file && ! -L $names_file ]] \
        || die 'special authority tag inventory is unsafe'

    local -a names=()
    local name generation
    mapfile -t names <"$names_file"
    for name in "${names[@]}"; do
        [[ $name =~ ^${prefix}([1-9][0-9]{0,15})$ ]] \
            || die 'special authority tag is malformed'
        generation=${BASH_REMATCH[1]}
        [[ $generation -le $maximum_generation ]] \
            || die 'special authority tag is ahead of the approved operation'
    done
    [[ $(printf '%s\n' "${names[@]}" | sed '/^$/d' | LC_ALL=C sort -u | wc -l) \
        -eq ${#names[@]} ]] \
        || die 'special authority tag inventory contains duplicates'
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
    render-selection-review)
        [[ $# -eq 2 ]] || die 'usage: render-selection-review OUTPUT'
        render_selection_review "$2"
        ;;
    validate-selection-review)
        [[ $# -eq 2 ]] || die 'usage: validate-selection-review RECORD'
        validate_selection_review "$2"
        ;;
    render-replacement-resolution)
        [[ $# -eq 2 ]] || die 'usage: render-replacement-resolution OUTPUT'
        render_replacement_resolution "$2"
        ;;
    validate-replacement-resolution)
        [[ $# -eq 2 ]] || die 'usage: validate-replacement-resolution RECORD'
        validate_replacement_resolution "$2"
        ;;
    validate-replacement-resolution-assets)
        [[ $# -eq 2 ]] || die 'usage: validate-replacement-resolution-assets DIRECTORY'
        validate_replacement_resolution_assets "$2"
        ;;
    assert-replacement)
        [[ $# -eq 5 ]] \
            || die 'usage: assert-replacement PREDECESSOR REJECTED SELECTED RESOLUTION'
        assert_replacement "$2" "$3" "$4" "$5"
        ;;
    validate-special-tag-namespace)
        [[ $# -eq 4 ]] \
            || die 'usage: validate-special-tag-namespace PREFIX MAXIMUM_GENERATION NAMES_FILE'
        validate_special_tag_namespace "$2" "$3" "$4"
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
        die 'usage: release-authority-manifest.sh render-approval-record|validate-approval-record|render-selection-review|validate-selection-review|render-replacement-resolution|validate-replacement-resolution|validate-replacement-resolution-assets|assert-replacement|validate-special-tag-namespace|asset-schema|validate|render-v2|assert-genesis|assert-successor|protocol-from-manifest|validate-protocol|shipper-self-test-from-manifest|validate-shipper-self-test|verifier-self-test-from-manifest|validate-verifier-self-test|source-tree-sha256|stage-v2|validate-stage-v2 ...'
        ;;
esac
