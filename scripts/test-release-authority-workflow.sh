#!/usr/bin/env bash
# shellcheck disable=SC2016 # Static workflow probes intentionally match literal expressions.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/release-authority-manifest.sh"
tmp_root=$(mktemp -d "$repo_root/.test-release-authority-workflow.XXXXXX")
cleanup() {
    local root_owned_fixture
    for root_owned_fixture in "${root_fixture:-}" "${entry_fixture:-}" \
        "${state_fixture:-}"; do
        if [[ -n $root_owned_fixture \
            && ( $root_owned_fixture == "$tmp_root/root-fixture" \
                || $root_owned_fixture == "$tmp_root/replacement-entry-fixture" \
                || $root_owned_fixture == "$tmp_root/replacement-state-machine-fixture" ) \
            && ( -e $root_owned_fixture || -L $root_owned_fixture ) ]]; then
            sudo -n rm -rf -- "$root_owned_fixture" 2>/dev/null || true
        fi
    done
    chmod -R u+rwX "$tmp_root" 2>/dev/null || true
    rm -rf "$tmp_root"
}
trap cleanup EXIT

fail() {
    printf 'release authority workflow fixture failed: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    if "$@" >"$tmp_root/rejected.stdout" 2>"$tmp_root/rejected.stderr"; then
        fail "command unexpectedly succeeded: $*"
    fi
}

make_elf() {
    local path=$1
    local marker=$2
    dd if=/dev/zero of="$path" bs=64 count=1 status=none
    printf '\177ELF\002\001' | dd of="$path" conv=notrunc status=none
    printf '\076\000' | dd of="$path" bs=1 seek=18 conv=notrunc status=none
    printf '%s' "$marker" | dd of="$path" bs=1 seek=24 conv=notrunc status=none
}

digest_text() {
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}

payload="$tmp_root/payload"
mkdir -p "$payload"
make_elf "$payload/syntaur-ship-linux-x86_64" shipper
make_elf "$payload/syntaur-verify-linux-x86_64" verifier
printf '#!/usr/bin/bash\nset -euo pipefail\n' \
    >"$payload/syntaur-build-authority-provision"

SHIPPER_SHA256=$(sha256sum "$payload/syntaur-ship-linux-x86_64" | awk '{print $1}')
VERIFIER_SHA256=$(sha256sum "$payload/syntaur-verify-linux-x86_64" | awk '{print $1}')
PROVISIONER_SHA256=$(sha256sum "$payload/syntaur-build-authority-provision" | awk '{print $1}')
PRODUCTION_CONTRACT_SHA256=$(digest_text production-contract)
PROMOTION_RECOVERY_SHA256=$(digest_text promotion-recovery)
AUTHORITY_VERSION=0.7.116
AUTHORITY_COMMIT=$(printf 'a%.0s' {1..40})
VERIFICATION_POLICY_REVISION=$(printf 'c%.0s' {1..40})
AUTHORITY_TREE_SHA256=$(digest_text authority-tree)
VERIFIER_TOOLCHAIN_ID=rust-1.94.1-x86_64-unknown-linux-gnu
VERIFIER_CARGO_SHA256=$(digest_text cargo)
VERIFIER_RUSTC_SHA256=$(digest_text rustc)
VERIFIER_RUSTDOC_SHA256=$(digest_text rustdoc)
BASELINE_PROFILE=mac-isolated-v1
BASELINE_GENERATION='generation-1'
BASELINE_TREE_SHA256=$(digest_text baseline)
BROWSER_BUNDLE_SHA256=$(digest_text browser)
BROWSER_VERSION='Google Chrome for Testing 131.0.6778.264'
BROWSER_LAUNCH_PROFILE_SHA256=$(digest_text launch)
VERIFIER_SCHEMA=5
PRODUCTION_MEMBER_COUNT=12
RECEIPT_SCHEMA=6
BUILD_AUTHORITY_SCHEMA=4
PROMOTION_RECOVERY_SCHEMA=1
GITHUB_SHA=$(printf 'b%.0s' {1..40})
export SHIPPER_SHA256 VERIFIER_SHA256 PROVISIONER_SHA256
export PRODUCTION_CONTRACT_SHA256 PROMOTION_RECOVERY_SHA256
export AUTHORITY_VERSION AUTHORITY_COMMIT VERIFICATION_POLICY_REVISION
export AUTHORITY_TREE_SHA256
export VERIFIER_TOOLCHAIN_ID VERIFIER_CARGO_SHA256 VERIFIER_RUSTC_SHA256
export VERIFIER_RUSTDOC_SHA256 BASELINE_PROFILE BASELINE_GENERATION
export BASELINE_TREE_SHA256 BROWSER_BUNDLE_SHA256 BROWSER_VERSION
export BROWSER_LAUNCH_PROFILE_SHA256 VERIFIER_SCHEMA PRODUCTION_MEMBER_COUNT
export RECEIPT_SCHEMA BUILD_AUTHORITY_SCHEMA PROMOTION_RECOVERY_SCHEMA GITHUB_SHA

zero_digest=$(printf '0%.0s' {1..64})
AUTHORITY_GENERATION=700
PREVIOUS_AUTHORITY_GENERATION=0
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$zero_digest
export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
"$helper" render-v2 "$tmp_root/v2-seed.json"
v1=$(jq -c \
    'del(.provisioner_sha256,
         .production_contract_sha256,
         .production_member_count,
         .receipt_schema,
         .build_authority_schema,
         .promotion_recovery_schema,
         .promotion_recovery_sha256) | .schema = 1' \
    "$tmp_root/v2-seed.json")
printf '%s' "$v1" >"$tmp_root/release-authority-v1.json"
"$helper" validate \
    "$tmp_root/release-authority-v1.json" 1 700 "$GITHUB_SHA" "$payload"

AUTHORITY_GENERATION=701
PREVIOUS_AUTHORITY_GENERATION=700
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$(sha256sum \
    "$tmp_root/release-authority-v1.json" | awk '{print $1}')
export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
"$helper" render-v2 "$tmp_root/release-authority-v2.json"
"$helper" validate \
    "$tmp_root/release-authority-v2.json" 2 701 "$GITHUB_SHA" "$payload"
"$helper" assert-successor \
    "$tmp_root/release-authority-v1.json" "$tmp_root/release-authority-v2.json"
"$helper" render-approval-record "$tmp_root/approval-record.json"
"$helper" validate-approval-record "$tmp_root/approval-record.json"
jq -e --arg revision "$VERIFICATION_POLICY_REVISION" \
    '.verification_policy_revision == $revision' \
    "$tmp_root/approval-record.json" >/dev/null
jq -c 'del(.verification_policy_revision)' "$tmp_root/approval-record.json" \
    >"$tmp_root/approval-record-policy-missing.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/approval-record-policy-missing.json"
jq -c 'del(.promotion_recovery_sha256)' "$tmp_root/approval-record.json" \
    >"$tmp_root/approval-record-missing.json"
expect_failure "$helper" validate-approval-record "$tmp_root/approval-record-missing.json"
printf '%s\n' "$(<"$tmp_root/approval-record.json")" \
    >"$tmp_root/approval-record-newline.json"
expect_failure "$helper" validate-approval-record "$tmp_root/approval-record-newline.json"

AUTHORITY_APPROVAL_SCHEMA=2
REJECTED_AUTHORITY_GENERATION=701
REJECTED_AUTHORITY_MANIFEST_SHA256=$(digest_text rejected-authority-manifest)
REJECTED_AUTHORITY_WORKFLOW_COMMIT=$(printf 'd%.0s' {1..40})
REJECTED_AUTHORITY_VERSION=0.7.115
REJECTED_AUTHORITY_COMMIT=$(printf 'e%.0s' {1..40})
REJECTED_PRODUCT_RELEASE_COMMIT=$(printf 'f%.0s' {1..40})
SETTLED_PRODUCT_VERSION=$AUTHORITY_VERSION
SETTLED_PRODUCT_GATEWAY_COMMIT=$(printf '7%.0s' {1..40})
SETTLED_PRODUCT_ENGINE_COMMIT=$(printf '8%.0s' {1..40})
SETTLED_PRODUCT_STATE_SHA256=$(digest_text settled-product-state)
SETTLED_PROMOTION_POLICY_SHA256=$(digest_text settled-promotion-policy)
SELECTED_ENGINE_COMMIT=$(printf '9%.0s' {1..40})
PLANNED_PRODUCT_VERSION=0.7.117
PLANNED_PRODUCT_BASE_COMMIT=$AUTHORITY_COMMIT
AUTHORITY_REPLACEMENT_REASON=authority_target_mismatch
export AUTHORITY_APPROVAL_SCHEMA REJECTED_AUTHORITY_GENERATION
export REJECTED_AUTHORITY_MANIFEST_SHA256 REJECTED_AUTHORITY_WORKFLOW_COMMIT
export REJECTED_AUTHORITY_VERSION REJECTED_AUTHORITY_COMMIT
export REJECTED_PRODUCT_RELEASE_COMMIT AUTHORITY_REPLACEMENT_REASON
export SETTLED_PRODUCT_VERSION SETTLED_PRODUCT_GATEWAY_COMMIT
export SETTLED_PRODUCT_ENGINE_COMMIT SELECTED_ENGINE_COMMIT
export SETTLED_PRODUCT_STATE_SHA256
export SETTLED_PROMOTION_POLICY_SHA256
export PLANNED_PRODUCT_VERSION PLANNED_PRODUCT_BASE_COMMIT
"$helper" render-approval-record "$tmp_root/replacement-approval-record.json"
"$helper" validate-approval-record "$tmp_root/replacement-approval-record.json"
jq -e '
    .schema == 2 and
    .rejected_generation == 701 and
    .replacement_reason == "authority_target_mismatch"
' "$tmp_root/replacement-approval-record.json" >/dev/null
source_proof=$tmp_root/syntaur-source-commit.txt
engine_proof=$tmp_root/syntaur-engine-source-commit.txt
public_dist_commit=$(printf '6%.0s' {1..40})
printf 'source_ref: v%s\nresolved_commit: %s\n' \
    "$SETTLED_PRODUCT_VERSION" "$SETTLED_PRODUCT_GATEWAY_COMMIT" >"$source_proof"
printf 'engine_ref: %s\nresolved_commit: %s\n' \
    "$SETTLED_PRODUCT_ENGINE_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT" \
    >"$engine_proof"
"$helper" validate-product-source-proofs \
    "$source_proof" "$engine_proof" "$SETTLED_PRODUCT_VERSION" \
    "$SETTLED_PRODUCT_GATEWAY_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT"
printf 'source_ref: v%s\nresolved_commit: %s\n' \
    "$SETTLED_PRODUCT_VERSION" "$public_dist_commit" >"$source_proof"
expect_failure "$helper" validate-product-source-proofs \
    "$source_proof" "$engine_proof" "$SETTLED_PRODUCT_VERSION" \
    "$SETTLED_PRODUCT_GATEWAY_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT"
printf 'source_ref: v%s\nresolved_commit: %s\n' \
    "$SETTLED_PRODUCT_VERSION" "$SETTLED_PRODUCT_GATEWAY_COMMIT" >"$source_proof"
printf 'engine_ref: %s\nresolved_commit: %s\nextra: rejected\n' \
    "$SETTLED_PRODUCT_ENGINE_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT" \
    >"$engine_proof"
expect_failure "$helper" validate-product-source-proofs \
    "$source_proof" "$engine_proof" "$SETTLED_PRODUCT_VERSION" \
    "$SETTLED_PRODUCT_GATEWAY_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT"
printf 'engine_ref: %s\nresolved_commit: %s\n' \
    "$SETTLED_PRODUCT_ENGINE_COMMIT" "$SETTLED_PRODUCT_ENGINE_COMMIT" \
    >"$engine_proof"
ln -s "$source_proof" "$tmp_root/syntaur-source-commit-symlink.txt"
expect_failure "$helper" validate-product-source-proofs \
    "$tmp_root/syntaur-source-commit-symlink.txt" "$engine_proof" \
    "$SETTLED_PRODUCT_VERSION" "$SETTLED_PRODUCT_GATEWAY_COMMIT" \
    "$SETTLED_PRODUCT_ENGINE_COMMIT"
jq -c '.settled_product_version = "0.7.117"' \
    "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-wrong-settled-version.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-wrong-settled-version.json"
jq -c '.planned_product_version = .authority_version' \
    "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-non-successor-version.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-non-successor-version.json"
jq -c '.planned_product_base_commit = .settled_product_gateway_commit' \
    "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-wrong-planned-base.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-wrong-planned-base.json"
jq -c '.rejected_product_release_commit = .rejected_authority_commit' \
    "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-same-target.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-same-target.json"
jq -c '.replacement_reason = "operator_override"' \
    "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-wrong-reason.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-wrong-reason.json"
jq -c '. + {unexpected:true}' "$tmp_root/replacement-approval-record.json" \
    >"$tmp_root/replacement-approval-extra.json"
expect_failure "$helper" validate-approval-record \
    "$tmp_root/replacement-approval-extra.json"
unset AUTHORITY_APPROVAL_SCHEMA REJECTED_AUTHORITY_GENERATION
unset REJECTED_AUTHORITY_MANIFEST_SHA256 REJECTED_AUTHORITY_WORKFLOW_COMMIT
unset REJECTED_AUTHORITY_VERSION REJECTED_AUTHORITY_COMMIT
unset REJECTED_PRODUCT_RELEASE_COMMIT AUTHORITY_REPLACEMENT_REASON
unset SETTLED_PRODUCT_VERSION SETTLED_PRODUCT_GATEWAY_COMMIT
unset SETTLED_PRODUCT_ENGINE_COMMIT SELECTED_ENGINE_COMMIT
unset SETTLED_PRODUCT_STATE_SHA256
unset SETTLED_PROMOTION_POLICY_SHA256
unset PLANNED_PRODUCT_VERSION PLANNED_PRODUCT_BASE_COMMIT

resolution_dir="$tmp_root/replacement-resolution"
mkdir -m 0700 "$resolution_dir"
printf '#!/usr/bin/bash\nset -euo pipefail\n' \
    >"$resolution_dir/recover-release-authority-replacement-v1.sh"
chmod 0500 "$resolution_dir/recover-release-authority-replacement-v1.sh"
cp "$helper" "$resolution_dir/release-authority-manifest.sh"
chmod 0500 "$resolution_dir/release-authority-manifest.sh"
selected_authority_version=$AUTHORITY_VERSION
selected_authority_commit=$AUTHORITY_COMMIT
selected_workflow_commit=$GITHUB_SHA
AUTHORITY_VERSION=0.7.115
AUTHORITY_COMMIT=$(printf 'e%.0s' {1..40})
GITHUB_SHA=$(printf 'd%.0s' {1..40})
"$helper" render-v2 "$tmp_root/rejected-release-authority-v2.json"
"$helper" validate \
    "$tmp_root/rejected-release-authority-v2.json" 2 701 "$GITHUB_SHA" "$payload"
AUTHORITY_VERSION=$selected_authority_version
AUTHORITY_COMMIT=$selected_authority_commit
GITHUB_SHA=$selected_workflow_commit
REPLACEMENT_PREDECESSOR_GENERATION=700
REPLACEMENT_PREDECESSOR_MANIFEST_SHA256=$PREVIOUS_AUTHORITY_MANIFEST_SHA256
REJECTED_AUTHORITY_GENERATION=701
REJECTED_AUTHORITY_MANIFEST_SHA256=$(sha256sum \
    "$tmp_root/rejected-release-authority-v2.json" | awk '{print $1}')
REJECTED_AUTHORITY_WORKFLOW_COMMIT=$(printf 'd%.0s' {1..40})
REJECTED_AUTHORITY_VERSION=0.7.115
REJECTED_AUTHORITY_COMMIT=$(printf 'e%.0s' {1..40})
REJECTED_PRODUCT_RELEASE_COMMIT=$(printf 'f%.0s' {1..40})
SELECTED_AUTHORITY_GENERATION=701
SELECTED_AUTHORITY_MANIFEST_SHA256=$(sha256sum \
    "$tmp_root/release-authority-v2.json" | awk '{print $1}')
SELECTED_AUTHORITY_WORKFLOW_COMMIT=$GITHUB_SHA
SELECTED_AUTHORITY_VERSION=$AUTHORITY_VERSION
SELECTED_AUTHORITY_COMMIT=$AUTHORITY_COMMIT
SETTLED_PRODUCT_VERSION=$AUTHORITY_VERSION
SETTLED_PRODUCT_GATEWAY_COMMIT=$(printf '7%.0s' {1..40})
SETTLED_PRODUCT_ENGINE_COMMIT=$(printf '8%.0s' {1..40})
SETTLED_PRODUCT_STATE_SHA256=$(digest_text settled-product-state)
SETTLED_PROMOTION_POLICY_SHA256=$(digest_text settled-promotion-policy)
SELECTED_ENGINE_COMMIT=$(printf '9%.0s' {1..40})
PLANNED_PRODUCT_VERSION=0.7.117
PLANNED_PRODUCT_BASE_COMMIT=$SELECTED_AUTHORITY_COMMIT
RECOVERY_TOOL_SHA256=$(sha256sum \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" | awk '{print $1}')
MANIFEST_HELPER_SHA256=$(sha256sum \
    "$resolution_dir/release-authority-manifest.sh" | awk '{print $1}')
RESOLUTION_WORKFLOW_COMMIT=$(printf '1%.0s' {1..40})
export REPLACEMENT_PREDECESSOR_GENERATION
export REPLACEMENT_PREDECESSOR_MANIFEST_SHA256
export REJECTED_AUTHORITY_GENERATION REJECTED_AUTHORITY_MANIFEST_SHA256
export REJECTED_AUTHORITY_WORKFLOW_COMMIT REJECTED_AUTHORITY_VERSION
export REJECTED_AUTHORITY_COMMIT REJECTED_PRODUCT_RELEASE_COMMIT
export SELECTED_AUTHORITY_GENERATION SELECTED_AUTHORITY_MANIFEST_SHA256
export SELECTED_AUTHORITY_WORKFLOW_COMMIT SELECTED_AUTHORITY_VERSION
export SELECTED_AUTHORITY_COMMIT RECOVERY_TOOL_SHA256 MANIFEST_HELPER_SHA256
export SETTLED_PRODUCT_VERSION SETTLED_PRODUCT_GATEWAY_COMMIT
export SETTLED_PRODUCT_ENGINE_COMMIT SELECTED_ENGINE_COMMIT
export SETTLED_PRODUCT_STATE_SHA256
export SETTLED_PROMOTION_POLICY_SHA256
export PLANNED_PRODUCT_VERSION PLANNED_PRODUCT_BASE_COMMIT
"$helper" render-selection-review \
    "$resolution_dir/release-authority-selection-review-v1.json"
SELECTION_REVIEW_SHA256=$(sha256sum \
    "$resolution_dir/release-authority-selection-review-v1.json" | awk '{print $1}')
export SELECTION_REVIEW_SHA256 RESOLUTION_WORKFLOW_COMMIT
"$helper" render-replacement-resolution \
    "$resolution_dir/release-authority-replacement-v1.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$resolution_dir/release-authority-replacement-v1.json.cosign.bundle"
"$helper" validate-replacement-resolution \
    "$resolution_dir/release-authority-replacement-v1.json"
"$helper" validate-replacement-resolution-tag \
    authority-resolution-v1-g701 \
    "$resolution_dir/release-authority-replacement-v1.json"
expect_failure "$helper" validate-replacement-resolution-tag \
    authority-resolution-v1-g701-r2 \
    "$resolution_dir/release-authority-replacement-v1.json"
"$helper" validate-replacement-resolution-assets "$resolution_dir"
"$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/release-authority-v2.json" \
    "$resolution_dir/release-authority-replacement-v1.json"
jq -c '.selected_tag = "authority-v1-g701"' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-tag.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-wrong-tag.json"
jq -c '.selected_manifest_sha256 = .rejected_manifest_sha256' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-same-manifest.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-same-manifest.json"
jq -c '.resolution_workflow_commit = .selected_workflow_commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-selected-resolution-same-commit.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-selected-resolution-same-commit.json"
jq -c '.resolution_workflow_commit = .rejected_workflow_commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-rejected-resolution-same-commit.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-rejected-resolution-same-commit.json"
jq -c '.planned_product_base_commit = .settled_product_gateway_commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-planned-base.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-wrong-planned-base.json"
jq -c '.selected_workflow_commit = .rejected_workflow_commit' \
    "$resolution_dir/release-authority-selection-review-v1.json" \
    >"$tmp_root/replacement-selection-review-same-commit.json"
expect_failure "$helper" validate-selection-review \
    "$tmp_root/replacement-selection-review-same-commit.json"
jq -c --arg digest "$(digest_text wrong-predecessor)" \
    '.predecessor_manifest_sha256 = $digest' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-predecessor.json"
expect_failure "$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/release-authority-v2.json" \
    "$tmp_root/replacement-resolution-wrong-predecessor.json"
jq -c --arg commit "$(printf '2%.0s' {1..40})" \
    '.rejected_workflow_commit = $commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-rejected-workflow.json"
expect_failure "$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/release-authority-v2.json" \
    "$tmp_root/replacement-resolution-wrong-rejected-workflow.json"
jq -c --arg commit "$(printf '3%.0s' {1..40})" \
    '.selected_workflow_commit = $commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-selected-workflow.json"
expect_failure "$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/release-authority-v2.json" \
    "$tmp_root/replacement-resolution-wrong-selected-workflow.json"
jq -c --arg commit "$(printf '4%.0s' {1..40})" \
    '.authority_commit = $commit' "$tmp_root/release-authority-v2.json" \
    >"$tmp_root/competing-release-authority-v2.json"
expect_failure "$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/competing-release-authority-v2.json" \
    "$resolution_dir/release-authority-replacement-v1.json"
printf unexpected >"$resolution_dir/unexpected"
expect_failure "$helper" validate-replacement-resolution-assets "$resolution_dir"
rm "$resolution_dir/unexpected"
mkdir "$resolution_dir/unexpected-directory"
expect_failure "$helper" validate-replacement-resolution-assets "$resolution_dir"
rmdir "$resolution_dir/unexpected-directory"
ln -s release-authority-replacement-v1.json "$resolution_dir/unexpected-link"
expect_failure "$helper" validate-replacement-resolution-assets "$resolution_dir"
rm "$resolution_dir/unexpected-link"
mv "$resolution_dir/release-authority-selection-review-v1.json" \
    "$resolution_dir/release-authority-selection-review-v1.json.saved"
ln -s release-authority-selection-review-v1.json.saved \
    "$resolution_dir/release-authority-selection-review-v1.json"
expect_failure "$helper" validate-replacement-resolution-assets "$resolution_dir"
rm "$resolution_dir/release-authority-selection-review-v1.json"
mv "$resolution_dir/release-authority-selection-review-v1.json.saved" \
    "$resolution_dir/release-authority-selection-review-v1.json"

superseded_resolution_sha256=$(sha256sum \
    "$resolution_dir/release-authority-replacement-v1.json" | awk '{print $1}')
superseded_recovery_tool_sha256=$(sha256sum \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" | awk '{print $1}')
superseded_manifest_helper_sha256=$(sha256sum \
    "$resolution_dir/release-authority-manifest.sh" | awk '{print $1}')
superseded_resolution_workflow_commit=$RESOLUTION_WORKFLOW_COMMIT
install -m 0500 "$resolution_dir/recover-release-authority-replacement-v1.sh" \
    "$tmp_root/superseded-recovery-tool"
install -m 0500 "$resolution_dir/release-authority-manifest.sh" \
    "$tmp_root/superseded-manifest-helper"
chmod 0700 \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" \
    "$resolution_dir/release-authority-manifest.sh"
printf '\n# corrected recovery fixture\n' \
    >>"$resolution_dir/recover-release-authority-replacement-v1.sh"
printf '\n# corrected manifest-helper fixture\n' \
    >>"$resolution_dir/release-authority-manifest.sh"
chmod 0500 \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" \
    "$resolution_dir/release-authority-manifest.sh"
RECOVERY_TOOL_SHA256=$(sha256sum \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" | awk '{print $1}')
MANIFEST_HELPER_SHA256=$(sha256sum \
    "$resolution_dir/release-authority-manifest.sh" | awk '{print $1}')
RESOLUTION_WORKFLOW_COMMIT=$(printf '2%.0s' {1..40})
export RECOVERY_TOOL_SHA256 MANIFEST_HELPER_SHA256 RESOLUTION_WORKFLOW_COMMIT
correction_review=$resolution_dir/release-authority-resolution-correction-v1.json
jq -cjn \
    --argjson generation "$SELECTED_AUTHORITY_GENERATION" \
    --arg supersedes_resolution_sha256 "$superseded_resolution_sha256" \
    --arg superseded_resolution_workflow_commit \
        "$superseded_resolution_workflow_commit" \
    --arg superseded_recovery_tool_sha256 "$superseded_recovery_tool_sha256" \
    --arg superseded_manifest_helper_sha256 "$superseded_manifest_helper_sha256" \
    --arg corrected_recovery_tool_sha256 "$RECOVERY_TOOL_SHA256" \
    --arg corrected_manifest_helper_sha256 "$MANIFEST_HELPER_SHA256" \
    --argjson active_generation "$REPLACEMENT_PREDECESSOR_GENERATION" \
    --arg active_manifest_sha256 "$REPLACEMENT_PREDECESSOR_MANIFEST_SHA256" \
    --arg active_product_state_sha256 "$SETTLED_PRODUCT_STATE_SHA256" \
    --arg selected_manifest_sha256 "$SELECTED_AUTHORITY_MANIFEST_SHA256" \
    '{schema:1,generation:$generation,resolution_revision:2,
      resolution_tag:("authority-resolution-v1-g" + ($generation | tostring) + "-r2"),
      supersedes_resolution_tag:("authority-resolution-v1-g" + ($generation | tostring)),
      supersedes_resolution_sha256:$supersedes_resolution_sha256,
      superseded_resolution_workflow_commit:$superseded_resolution_workflow_commit,
      superseded_recovery_tool_sha256:$superseded_recovery_tool_sha256,
      superseded_manifest_helper_sha256:$superseded_manifest_helper_sha256,
      corrected_recovery_tool_sha256:$corrected_recovery_tool_sha256,
      corrected_manifest_helper_sha256:$corrected_manifest_helper_sha256,
      active_generation:$active_generation,
      active_manifest_sha256:$active_manifest_sha256,
      active_product_state_sha256:$active_product_state_sha256,
      selected_manifest_sha256:$selected_manifest_sha256,
      correction_reason:"recovery_tool_execution_failure",
      failure_class:"bash_dynamic_scope_unbound_operation",
      failure_stage:"sealed_input_revalidation",
      authority_mutated:false,product_state_mutated:false,
      normal_promotion_journal_present:false,
      normal_promotion_journal_temp_present:false,
      install_journal_present:false,install_journal_temp_present:false,
      rollback_journal_present:false,rollback_journal_temp_present:false,
      install_receipt_present:false,rollback_receipt_present:false,
      resolution_receipt_present:false}' >"$correction_review"
"$helper" validate-resolution-correction-review "$correction_review"
RESOLUTION_REVISION=2
SUPERSEDES_RESOLUTION_TAG=authority-resolution-v1-g701
SUPERSEDES_RESOLUTION_SHA256=$superseded_resolution_sha256
SUPERSEDED_RECOVERY_TOOL_SHA256=$superseded_recovery_tool_sha256
CORRECTION_REVIEW_SHA256=$(sha256sum "$correction_review" | awk '{print $1}')
export RESOLUTION_REVISION SUPERSEDES_RESOLUTION_TAG SUPERSEDES_RESOLUTION_SHA256
export SUPERSEDED_RECOVERY_TOOL_SHA256 CORRECTION_REVIEW_SHA256
"$helper" render-replacement-resolution \
    "$resolution_dir/release-authority-replacement-v1.json"
"$helper" validate-replacement-resolution-assets "$resolution_dir"
"$helper" validate-replacement-resolution-tag \
    authority-resolution-v1-g701-r2 \
    "$resolution_dir/release-authority-replacement-v1.json"
expect_failure "$helper" validate-replacement-resolution-tag \
    authority-resolution-v1-g701-r3 \
    "$resolution_dir/release-authority-replacement-v1.json"
jq -c --arg commit "$(printf '6%.0s' {1..40})" \
    '.planned_product_base_commit = $commit' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-r2-wrong-planned-base.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-r2-wrong-planned-base.json"
RESOLUTION_SHA256=$(sha256sum \
    "$resolution_dir/release-authority-replacement-v1.json" | awk '{print $1}')
export RESOLUTION_SHA256
correction_authorization=$tmp_root/release-authority-resolution-authorization-v1.json
"$helper" render-resolution-correction-authorization "$correction_authorization"
"$helper" validate-resolution-correction-authorization "$correction_authorization"
jq -cj '.resolution_tag += "-r2"' "$correction_authorization" \
    >"$tmp_root/replacement-resolution-wrong-authorization.json"
expect_failure "$helper" validate-resolution-correction-authorization \
    "$tmp_root/replacement-resolution-wrong-authorization.json"
jq -cj '.supersedes_resolution_tag =
    ("authority-resolution-v1-g" + (.selected_generation | tostring) + "-r2")' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$tmp_root/replacement-resolution-wrong-supersession.json"
expect_failure "$helper" validate-replacement-resolution \
    "$tmp_root/replacement-resolution-wrong-supersession.json"
jq -cj '.authority_mutated = true' "$correction_review" \
    >"$tmp_root/replacement-resolution-mutated-correction.json"
expect_failure "$helper" validate-resolution-correction-review \
    "$tmp_root/replacement-resolution-mutated-correction.json"
rm "$correction_review"
unset RESOLUTION_REVISION SUPERSEDES_RESOLUTION_TAG SUPERSEDES_RESOLUTION_SHA256
unset SUPERSEDED_RECOVERY_TOOL_SHA256 CORRECTION_REVIEW_SHA256 RESOLUTION_SHA256
install -m 0500 "$tmp_root/superseded-recovery-tool" \
    "$resolution_dir/recover-release-authority-replacement-v1.sh"
install -m 0500 "$tmp_root/superseded-manifest-helper" \
    "$resolution_dir/release-authority-manifest.sh"
RECOVERY_TOOL_SHA256=$(sha256sum \
    "$resolution_dir/recover-release-authority-replacement-v1.sh" | awk '{print $1}')
MANIFEST_HELPER_SHA256=$(sha256sum \
    "$resolution_dir/release-authority-manifest.sh" | awk '{print $1}')
RESOLUTION_WORKFLOW_COMMIT=$superseded_resolution_workflow_commit
export RECOVERY_TOOL_SHA256 MANIFEST_HELPER_SHA256 RESOLUTION_WORKFLOW_COMMIT
"$helper" render-replacement-resolution \
    "$resolution_dir/release-authority-replacement-v1.json"
"$helper" validate-replacement-resolution-assets "$resolution_dir"

: >"$tmp_root/empty-special-tags"
"$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 0 "$tmp_root/empty-special-tags"
printf '%s\n' authority-replacement-v1-g1 authority-replacement-v1-g60 \
    >"$tmp_root/bounded-replacement-tags"
"$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 60 "$tmp_root/bounded-replacement-tags"
printf '%s\n' authority-resolution-v1-g60 authority-resolution-v1-g60-r2 \
    authority-resolution-v1-g60-r3 \
    >"$tmp_root/bounded-resolution-tags"
"$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/bounded-resolution-tags"
{
    printf '%s\n' authority-resolution-v1-g59
    for revision in {2..10}; do
        printf 'authority-resolution-v1-g59-r%s\n' "$revision"
    done
} >"$tmp_root/two-digit-contiguous-resolution-tags"
"$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 \
    "$tmp_root/two-digit-contiguous-resolution-tags"
printf '%s\n' authority-replacement-v1-g61 >"$tmp_root/one-ahead-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 60 "$tmp_root/one-ahead-tags"
printf '%s\n' authority-resolution-v1-g62 >"$tmp_root/two-ahead-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/two-ahead-tags"
printf '%s\n' authority-replacement-v1-g060 >"$tmp_root/malformed-special-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 60 "$tmp_root/malformed-special-tags"
printf '%s\n' authority-resolution-v1-g99999999999999999 \
    >"$tmp_root/oversized-special-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/oversized-special-tags"
printf '%s\n' authority-resolution-v1-g60-r1 >"$tmp_root/malformed-resolution-revision"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/malformed-resolution-revision"
printf '%s\n' authority-resolution-v1-g60-r02 >"$tmp_root/leading-zero-resolution-revision"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/leading-zero-resolution-revision"
printf '%s\n' authority-resolution-v1-g60 authority-resolution-v1-g60-r3 \
    >"$tmp_root/gapped-resolution-revisions"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/gapped-resolution-revisions"
printf '%s\n' authority-resolution-v1-g60-r2 \
    >"$tmp_root/missing-base-resolution-revision"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/missing-base-resolution-revision"
printf '%s\n' authority-resolution-v1-g60 authority-resolution-v1-g60 \
    >"$tmp_root/duplicate-special-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/duplicate-special-tags"
expect_failure "$helper" validate-special-tag-namespace \
    authority-v1-g 60 "$tmp_root/empty-special-tags"

AUTHORITY_GENERATION=702
PREVIOUS_AUTHORITY_GENERATION=701
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$(sha256sum \
    "$tmp_root/release-authority-v2.json" | awk '{print $1}')
export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
"$helper" render-v2 "$tmp_root/release-authority-v2-next.json"
"$helper" validate \
    "$tmp_root/release-authority-v2-next.json" 2 702 "$GITHUB_SHA" "$payload"
"$helper" assert-successor \
    "$tmp_root/release-authority-v2.json" "$tmp_root/release-authority-v2-next.json"
expect_failure "$helper" assert-replacement \
    "$tmp_root/release-authority-v1.json" \
    "$tmp_root/rejected-release-authority-v2.json" \
    "$tmp_root/release-authority-v2-next.json" \
    "$resolution_dir/release-authority-replacement-v1.json"

AUTHORITY_GENERATION=1
PREVIOUS_AUTHORITY_GENERATION=0
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$zero_digest
export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
"$helper" render-v2 "$tmp_root/v2-genesis.json"
"$helper" validate \
    "$tmp_root/v2-genesis.json" 2 1 "$GITHUB_SHA" "$payload"
"$helper" assert-genesis "$tmp_root/v2-genesis.json"
"$helper" render-approval-record "$tmp_root/genesis-approval-record.json"
"$helper" validate-approval-record "$tmp_root/genesis-approval-record.json"

AUTHORITY_GENERATION=2
export AUTHORITY_GENERATION
"$helper" render-v2 "$tmp_root/v2-false-genesis.json"
expect_failure "$helper" validate \
    "$tmp_root/v2-false-genesis.json" 2 2 "$GITHUB_SHA" "$payload"
expect_failure "$helper" assert-genesis "$tmp_root/v2-false-genesis.json"

AUTHORITY_GENERATION=704
PREVIOUS_AUTHORITY_GENERATION=702
PREVIOUS_AUTHORITY_MANIFEST_SHA256=$(sha256sum \
    "$tmp_root/release-authority-v2-next.json" | awk '{print $1}')
export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
export PREVIOUS_AUTHORITY_MANIFEST_SHA256
"$helper" render-v2 "$tmp_root/v2-gap.json"
expect_failure "$helper" validate \
    "$tmp_root/v2-gap.json" 2 704 "$GITHUB_SHA" "$payload"
expect_failure "$helper" assert-successor \
    "$tmp_root/release-authority-v2-next.json" "$tmp_root/v2-gap.json"

printf '%s\n' \
    release-authority-v1.json \
    release-authority-v1.json.cosign.bundle \
    syntaur-ship-linux-x86_64 \
    syntaur-verify-linux-x86_64 >"$tmp_root/v1-assets"
[[ $("$helper" asset-schema "$tmp_root/v1-assets") == 1 ]]
printf '%s\n' \
    release-authority-v2.json \
    release-authority-v2.json.cosign.bundle \
    syntaur-build-authority-provision \
    syntaur-ship-linux-x86_64 \
    syntaur-verify-linux-x86_64 >"$tmp_root/v2-assets"
[[ $("$helper" asset-schema "$tmp_root/v2-assets") == 2 ]]

cp "$tmp_root/v1-assets" "$tmp_root/v1-plus-provisioner"
printf '%s\n' syntaur-build-authority-provision >>"$tmp_root/v1-plus-provisioner"
expect_failure "$helper" asset-schema "$tmp_root/v1-plus-provisioner"
grep -v syntaur-build-authority-provision "$tmp_root/v2-assets" \
    >"$tmp_root/v2-missing-provisioner"
expect_failure "$helper" asset-schema "$tmp_root/v2-missing-provisioner"
sed 's/release-authority-v2.json/release-authority-v1.json/' \
    "$tmp_root/v2-assets" >"$tmp_root/mixed-assets"
expect_failure "$helper" asset-schema "$tmp_root/mixed-assets"

printf '%s\n' "$(cat "$tmp_root/release-authority-v2.json")" \
    >"$tmp_root/noncanonical.json"
expect_failure "$helper" validate \
    "$tmp_root/noncanonical.json" 2 701 "$GITHUB_SHA" "$payload"
duplicate=$(<"$tmp_root/release-authority-v2.json")
printf '%s' "${duplicate%\}},\"schema\":2}" >"$tmp_root/duplicate.json"
expect_failure "$helper" validate \
    "$tmp_root/duplicate.json" 2 701 "$GITHUB_SHA" "$payload"
jq -c 'del(.promotion_recovery_sha256)' "$tmp_root/release-authority-v2.json" \
    | tr -d '\n' >"$tmp_root/v2-missing-field.json"
expect_failure "$helper" validate \
    "$tmp_root/v2-missing-field.json" 2 701 "$GITHUB_SHA" "$payload"
jq -c '.schema = 9' "$tmp_root/release-authority-v2.json" \
    | tr -d '\n' >"$tmp_root/unknown-schema.json"
expect_failure "$helper" validate \
    "$tmp_root/unknown-schema.json" 9 701 "$GITHUB_SHA" "$payload"
jq -c --arg digest "$PROVISIONER_SHA256" \
    '. + {provisioner_sha256:$digest}' "$tmp_root/release-authority-v1.json" \
    | tr -d '\n' >"$tmp_root/v1-with-v2-field.json"
expect_failure "$helper" validate \
    "$tmp_root/v1-with-v2-field.json" 1 700 "$GITHUB_SHA" "$payload"

cp -a "$payload" "$tmp_root/mismatched-payload"
printf x >>"$tmp_root/mismatched-payload/syntaur-ship-linux-x86_64"
expect_failure "$helper" validate \
    "$tmp_root/release-authority-v2.json" 2 701 "$GITHUB_SHA" \
    "$tmp_root/mismatched-payload"
printf '#!/usr/bin/env bash\n' >"$tmp_root/mismatched-payload/syntaur-build-authority-provision"
expect_failure "$helper" validate \
    "$tmp_root/release-authority-v2.json" 2 701 "$GITHUB_SHA" \
    "$tmp_root/mismatched-payload"

"$helper" protocol-from-manifest "$tmp_root/release-authority-v2.json" \
    >"$tmp_root/protocol.json"
"$helper" validate-protocol \
    "$tmp_root/protocol.json" "$tmp_root/release-authority-v2.json"
jq -c '. + {unexpected:true}' "$tmp_root/protocol.json" \
    >"$tmp_root/protocol-extra.json"
expect_failure "$helper" validate-protocol \
    "$tmp_root/protocol-extra.json" "$tmp_root/release-authority-v2.json"

"$helper" shipper-self-test-from-manifest "$tmp_root/release-authority-v2.json" \
    >"$tmp_root/shipper-self-test.json"
"$helper" validate-shipper-self-test \
    "$tmp_root/shipper-self-test.json" "$tmp_root/release-authority-v2.json"
jq -c '.authority_commit = ("f" * 40)' "$tmp_root/shipper-self-test.json" \
    >"$tmp_root/shipper-self-test-wrong.json"
expect_failure "$helper" validate-shipper-self-test \
    "$tmp_root/shipper-self-test-wrong.json" "$tmp_root/release-authority-v2.json"

"$helper" verifier-self-test-from-manifest "$tmp_root/release-authority-v2.json" \
    >"$tmp_root/verifier-self-test.json"
"$helper" validate-verifier-self-test \
    "$tmp_root/verifier-self-test.json" "$tmp_root/release-authority-v2.json"
jq -c '.required_gate_count = 17' "$tmp_root/verifier-self-test.json" \
    >"$tmp_root/verifier-self-test-wrong.json"
expect_failure "$helper" validate-verifier-self-test \
    "$tmp_root/verifier-self-test-wrong.json" "$tmp_root/release-authority-v2.json"

printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$tmp_root/release-authority-v2.json.cosign.bundle"
"$helper" stage-v2 \
    "$tmp_root/release-authority-v2.json" \
    "$tmp_root/release-authority-v2.json.cosign.bundle" \
    "$payload" \
    "$tmp_root/handoff"
"$helper" validate-stage-v2 "$tmp_root/handoff"
[[ $(stat -c '%a' "$tmp_root/handoff") == 500 ]]
[[ $(stat -c '%a' "$tmp_root/handoff/release-authority-v2.json") == 400 ]]
[[ $(stat -c '%a' "$tmp_root/handoff/release-authority-v2.json.cosign.bundle") == 400 ]]
[[ $(stat -c '%a' "$tmp_root/handoff/syntaur-ship-linux-x86_64") == 500 ]]
chmod 0600 "$tmp_root/handoff/release-authority-v2.json"
expect_failure "$helper" validate-stage-v2 "$tmp_root/handoff"

source_repo="$tmp_root/source-repo"
mkdir "$source_repo"
git -C "$source_repo" init -q
git -C "$source_repo" config user.name fixture
git -C "$source_repo" config user.email fixture@example.invalid
printf 'one\n' >"$source_repo/one"
git -C "$source_repo" add one
git -C "$source_repo" commit -qm one
source_commit=$(git -C "$source_repo" rev-parse HEAD)
tree_one=$("$helper" source-tree-sha256 "$source_repo" "$source_commit")
[[ $tree_one =~ ^[0-9a-f]{64}$ ]]
printf 'uncommitted\n' >>"$source_repo/one"
[[ $("$helper" source-tree-sha256 "$source_repo" "$source_commit") == "$tree_one" ]]
git -C "$source_repo" add one
git -C "$source_repo" commit -qm two
source_commit_two=$(git -C "$source_repo" rev-parse HEAD)
[[ $("$helper" source-tree-sha256 "$source_repo" "$source_commit_two") != "$tree_one" ]]

g1_verifier="$repo_root/scripts/verify-g1-authority-source.sh"
g1_toml_parser="$tmp_root/yq-linux-amd64-v4.53.2"
/usr/bin/curl -fsSLo "$g1_toml_parser" \
    https://github.com/mikefarah/yq/releases/download/v4.53.2/yq_linux_amd64
printf '%s  %s\n' \
    d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b \
    "$g1_toml_parser" | sha256sum -c - >/dev/null
chmod 0500 "$g1_toml_parser"

verify_g1() {
    "$g1_verifier" "$@" "$g1_toml_parser"
}

g1_repo="$tmp_root/g1-source-repo"
mkdir -p \
    "$g1_repo/syntaur-ship/src" \
    "$g1_repo/syntaur-ship/build-tools" \
    "$g1_repo/scripts"
git -C "$g1_repo" init -q
git -C "$g1_repo" config user.name fixture
git -C "$g1_repo" config user.email fixture@example.invalid
printf '0.7.114\n' >"$g1_repo/VERSION"
printf 'baseline validator\n' >"$g1_repo/syntaur-ship/src/genesis_validation.rs"
printf 'baseline date\n' >"$g1_repo/syntaur-ship/build-tools/date"
printf 'baseline git\n' >"$g1_repo/syntaur-ship/build-tools/git"
printf 'baseline provisioner\n' >"$g1_repo/scripts/provision-syntaur-build-authority.sh"
printf '%s\n' \
    'version = 3' \
    '' \
    '[[package]]' \
    'name = "core-dependency"' \
    'version = "1.0.0"' \
    '' \
    '[[package]]' \
    'name = "syntaur-ship"' \
    'version = "0.7.114"' \
    '' \
    '[[package]]' \
    'name = "syntaur-verify"' \
    'version = "0.7.114"' \
    >"$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm baseline
g1_parent=$(git -C "$g1_repo" rev-parse HEAD)
g1_parent_tree=$(git -C "$g1_repo" rev-parse "$g1_parent^{tree}")

write_g1_delta() {
    printf 'G1 validator\n' >"$g1_repo/syntaur-ship/src/genesis_validation.rs"
    printf 'G1 date\n' >"$g1_repo/syntaur-ship/build-tools/date"
    printf 'G1 git\n' >"$g1_repo/syntaur-ship/build-tools/git"
    printf 'G1 provisioner\n' >"$g1_repo/scripts/provision-syntaur-build-authority.sh"
    chmod 0755 \
        "$g1_repo/syntaur-ship/build-tools/date" \
        "$g1_repo/syntaur-ship/build-tools/git" \
        "$g1_repo/scripts/provision-syntaur-build-authority.sh"
}

write_g1_delta
sed -i 's/version = "0.7.114"/version = "0.7.115"/g' "$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm exact-g1
g1_candidate=$(git -C "$g1_repo" rev-parse HEAD)
verify_g1 \
    "$g1_repo" "$g1_candidate" "$g1_parent" "$g1_parent_tree" 0.7.114

required_g1_paths=(
    syntaur-ship/src/genesis_validation.rs
    syntaur-ship/build-tools/date
    syntaur-ship/build-tools/git
    scripts/provision-syntaur-build-authority.sh
)
invalid_g1_modes=(0755 0644 0644 0644)
for index in "${!required_g1_paths[@]}"; do
    required_path=${required_g1_paths[$index]}

    git -C "$g1_repo" checkout -q \
        -b "bad-required-deletion-$index" "$g1_parent"
    write_g1_delta
    rm -- "$g1_repo/$required_path"
    git -C "$g1_repo" add -A
    git -C "$g1_repo" commit -qm "bad required deletion $index"
    expect_failure verify_g1 \
        "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
        "$g1_parent" "$g1_parent_tree" 0.7.114

    git -C "$g1_repo" checkout -q \
        -b "bad-required-mode-$index" "$g1_parent"
    write_g1_delta
    chmod "${invalid_g1_modes[$index]}" "$g1_repo/$required_path"
    git -C "$g1_repo" add .
    git -C "$g1_repo" commit -qm "bad required mode $index"
    expect_failure verify_g1 \
        "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
        "$g1_parent" "$g1_parent_tree" 0.7.114

    git -C "$g1_repo" checkout -q \
        -b "bad-required-gitlink-$index" "$g1_parent"
    write_g1_delta
    rm -- "$g1_repo/$required_path"
    git -C "$g1_repo" add .
    git -C "$g1_repo" update-index --add \
        --cacheinfo "160000,$g1_parent,$required_path"
    git -C "$g1_repo" commit -qm "bad required gitlink $index"
    expect_failure verify_g1 \
        "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
        "$g1_parent" "$g1_parent_tree" 0.7.114
done

git -C "$g1_repo" checkout -q -b bad-product "$g1_parent"
write_g1_delta
mkdir -p "$g1_repo/truenas-infra"
printf 'product mutation\n' >"$g1_repo/truenas-infra/docker-compose-prod.yml"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-product
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

git -C "$g1_repo" checkout -q -b bad-lock "$g1_parent"
write_g1_delta
sed -i '0,/version = "1.0.0"/s//version = "2.0.0"/' "$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-lock
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

git -C "$g1_repo" checkout -q -b bad-lock-scalar-type "$g1_parent"
write_g1_delta
sed -i '1s/version = 3/version = 3.0/' "$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-lock-scalar-type
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

git -C "$g1_repo" checkout -q -b bad-lock-table-syntax "$g1_parent"
write_g1_delta
printf '%s\n' \
    '' \
    '[[ package ]]' \
    'name = "hidden-non-authority-package"' \
    'version = "1.0.0"' \
    >>"$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-lock-table-syntax
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

git -C "$g1_repo" checkout -q -b bad-lock-multiline-string "$g1_parent"
write_g1_delta
printf '%s\n' \
    '' \
    '[[package]]' \
    'name = "hidden-non-authority-package"' \
    'version = "1.0.0"' \
    'description = """' \
    'name = "syntaur-ship"' \
    '"""' \
    >>"$g1_repo/Cargo.lock"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-lock-multiline-string
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

git -C "$g1_repo" checkout -q -b bad-path-utf8 "$g1_parent"
write_g1_delta
invalid_utf8_path=$'syntaur-ship/\xff'
printf 'invalid UTF-8 path\n' >"$g1_repo/$invalid_utf8_path"
git -C "$g1_repo" add .
git -C "$g1_repo" commit -qm bad-path-utf8
expect_failure verify_g1 \
    "$g1_repo" "$(git -C "$g1_repo" rev-parse HEAD)" \
    "$g1_parent" "$g1_parent_tree" 0.7.114

workflow="$repo_root/.github/workflows/release-authority.yml"
release_workflow="$repo_root/.github/workflows/release-sign.yml"
recovery_tool="$repo_root/scripts/recover-release-authority-replacement-v1.sh"
checked_in_selection_review="$repo_root/.github/authority-replacement-reviews/g60.json"
checked_in_r2_correction="$repo_root/.github/authority-resolution-corrections/g60-r2.json"
checked_in_r3_correction="$repo_root/.github/authority-resolution-corrections/g60-r3.json"
checked_in_r4_correction="$repo_root/.github/authority-resolution-corrections/g60-r4.json"
checked_in_r5_correction="$repo_root/.github/authority-resolution-corrections/g60-r5.json"
expected_authority_download_consumers=$(printf '%s\n' \
    $'compare_builds\tDownload both isolated builds' \
    $'isolated_build\tDownload encrypted source export' \
    $'publish\tDownload signed authority' \
    $'recover_publish_resolution\tDownload recovered replacement resolution' \
    $'recover_sign_resolution\tDownload exact replacement proof helper' \
    $'replacement_proof_helper\tDownload encrypted proof-helper source export' \
    $'sign\tDownload approved candidate')
authority_download_consumers=$(yq -r '
    .jobs | to_entries[] |
    .key as $job |
    .value.steps[] |
    [$job, .name, (.uses // "")] | @tsv
' "$workflow" |
    awk -F '\t' '$3 ~ /^actions\/download-artifact@/ {print $1 "\t" $2}' |
    LC_ALL=C sort)
[[ $authority_download_consumers == "$expected_authority_download_consumers" ]]
release_download_consumers=$(yq -r '
    .jobs | to_entries[] |
    .key as $job |
    .value.steps[] |
    [$job, .name, (.uses // ""),
      ((.with."merge-multiple" // false) | tostring)] | @tsv
' "$release_workflow" |
    awk -F '\t' '$3 ~ /^actions\/download-artifact@/ {print $1 "\t" $2 "\t" $4}' |
    LC_ALL=C sort)
[[ $release_download_consumers \
    == $'sign-and-release\tDownload all built binaries\ttrue' ]]
proof_helper_artifact_selector=$(yq -r '
    .jobs.replacement_proof_helper.steps[] |
    select(.name == "Select exact encrypted proof-helper source export") |
    .run
' "$workflow")
isolated_build_artifact_selector=$(yq -r '
    .jobs.isolated_build.steps[] |
    select(.name == "Select newest immutable source export from this run") |
    .run
' "$workflow")
reviewed_candidate_artifact_selector=$(yq -r '
    .jobs.sign.steps[] |
    select(.name == "Select newest immutable reviewed candidate from this run") |
    .run
' "$workflow")
replacement_helper_artifact_selector=$(yq -r '
    .jobs.recover_sign_resolution.steps[] |
    select(.name == "Select exact replacement proof helper") |
    .run
' "$workflow")
recovered_resolution_artifact_selector=$(yq -r '
    .jobs.recover_publish_resolution.steps[] |
    select(.name == "Select recovered replacement resolution") |
    .run
' "$workflow")
signed_authority_artifact_selector=$(yq -r '
    .jobs.publish.steps[] |
    select(.name == "Select newest immutable signed package from this run") |
    .run
' "$workflow")
source_tuple_guard=$(yq -r '
    .jobs.source_metadata.steps[] |
    select(.name == "Select exact private source tuple without executing it") |
    .run
' "$workflow")
proof_helper_parent_guard=$(yq -r '
    .jobs.replacement_proof_helper.steps[] |
    select(.name == "Prove plaintext proof-helper source has no credential authority") |
    .run
' "$workflow")
resolution_lineage_guard=$(yq -r '
    .jobs.recover_sign_resolution.steps[] |
    select(.name == "Recover or sign only the missing replacement resolution") |
    .run
' "$workflow")
for selector in \
    "$proof_helper_artifact_selector" \
    "$isolated_build_artifact_selector" \
    "$reviewed_candidate_artifact_selector" \
    "$replacement_helper_artifact_selector" \
    "$recovered_resolution_artifact_selector" \
    "$signed_authority_artifact_selector"; do
    [[ -n $selector && $selector != null ]]
done
[[ $proof_helper_artifact_selector == "$isolated_build_artifact_selector" ]]
grep -Fq 'proof_helper_source_parent_commit' <<<"$source_tuple_guard"
grep -Fq '.planned_product_base_commit' <<<"$source_tuple_guard"
grep -Fq 'proof_helper_source_parent_commit' <<<"$proof_helper_parent_guard"
grep -Fq '.corrected_planned_product_base_commit' <<<"$resolution_lineage_guard"

run_single_artifact_selector() {
    local selector=$1
    local fixture=$2
    (
        cd "$fixture"
        GITHUB_RUN_ID=424242 bash --noprofile --norc \
            -e -o pipefail -c "$selector"
    )
}

exercise_single_artifact_selector() {
    local label=$1
    local selector=$2
    local source_dir=$3
    local target_dir=$4
    local artifact_prefix=$5
    local fixture nested_name older_name newest_name

    fixture="$tmp_root/${label}-flat"
    mkdir -p "$fixture/$source_dir"
    printf '%s' flat >"$fixture/$source_dir/payload.bin"
    printf '%s' metadata >"$fixture/$source_dir/metadata.json"
    run_single_artifact_selector "$selector" "$fixture"
    [[ ! -e $fixture/$source_dir ]]
    [[ $(<"$fixture/$target_dir/payload.bin") == flat ]]
    [[ -f $fixture/$target_dir/metadata.json ]]

    fixture="$tmp_root/${label}-nested"
    nested_name="${artifact_prefix}-424242-attempt-1"
    mkdir -p "$fixture/$source_dir/$nested_name"
    printf '%s' nested >"$fixture/$source_dir/$nested_name/payload.bin"
    run_single_artifact_selector "$selector" "$fixture"
    [[ $(<"$fixture/$target_dir/payload.bin") == nested ]]

    fixture="$tmp_root/${label}-rerun"
    older_name="${artifact_prefix}-424242-attempt-1"
    newest_name="${artifact_prefix}-424242-attempt-2"
    mkdir -p \
        "$fixture/$source_dir/$older_name" \
        "$fixture/$source_dir/$newest_name"
    printf '%s' older >"$fixture/$source_dir/$older_name/payload.bin"
    printf '%s' newest >"$fixture/$source_dir/$newest_name/payload.bin"
    run_single_artifact_selector "$selector" "$fixture"
    [[ $(<"$fixture/$target_dir/payload.bin") == newest ]]
    [[ -d $fixture/$source_dir/$older_name ]]

    fixture="$tmp_root/${label}-nested-contamination"
    mkdir -p "$fixture/$source_dir/$nested_name"
    printf '%s' unexpected >"$fixture/$source_dir/unexpected-file"
    expect_failure run_single_artifact_selector "$selector" "$fixture"
    [[ ! -e $fixture/$target_dir ]]

    fixture="$tmp_root/${label}-direct-contamination"
    mkdir -p "$fixture/$source_dir/unexpected-directory"
    printf '%s' direct >"$fixture/$source_dir/payload.bin"
    expect_failure run_single_artifact_selector "$selector" "$fixture"
    [[ ! -e $fixture/$target_dir ]]
}

exercise_single_artifact_selector \
    isolated-source "$isolated_build_artifact_selector" \
    encrypted-source-artifacts encrypted-source encrypted-authority-source-run
exercise_single_artifact_selector \
    replacement-source "$proof_helper_artifact_selector" \
    encrypted-source-artifacts encrypted-source encrypted-authority-source-run
exercise_single_artifact_selector \
    reviewed-candidate "$reviewed_candidate_artifact_selector" \
    reviewed-candidate-artifacts candidate reviewed-authority-candidate-run
exercise_single_artifact_selector \
    replacement-helper "$replacement_helper_artifact_selector" \
    replacement-proof-helper-artifacts replacement-proof-helper \
    replacement-proof-helper-run
exercise_single_artifact_selector \
    recovered-resolution "$recovered_resolution_artifact_selector" \
    recovered-resolution-artifacts signed-resolution \
    recovered-release-authority-resolution-run
exercise_single_artifact_selector \
    signed-authority "$signed_authority_artifact_selector" \
    signed-authority-artifacts signed-authority signed-release-authority-run

[[ $(yq -r '.on.workflow_dispatch.inputs | length' "$workflow") == 2 ]]
"$helper" validate-resolution-correction-review "$checked_in_r2_correction"
"$helper" validate-resolution-correction-review "$checked_in_r3_correction"
"$helper" validate-resolution-correction-review "$checked_in_r4_correction"
"$helper" validate-resolution-correction-review "$checked_in_r5_correction"
[[ $(jq -er '.corrected_recovery_tool_sha256' "$checked_in_r2_correction") \
    == 2c08e0522c2589198142d1dbeeff59361b204a615ae7038e03dc39cd50de8708 ]]
[[ $(jq -er '.corrected_manifest_helper_sha256' "$checked_in_r2_correction") \
    == 985843d676767bb715c12fb45f8a0ae32cc2aa824efd7123818a12494d677b80 ]]
[[ $(jq -er '.supersedes_resolution_sha256' "$checked_in_r3_correction") \
    == 3f42c2844a4b72b9eef3f5f52f9db6cc7bbed3ba8a4cb7907f854d32d54f9293 ]]
[[ $(jq -er '.superseded_recovery_tool_sha256' "$checked_in_r3_correction") \
    == "$(jq -er '.corrected_recovery_tool_sha256' \
        "$checked_in_r2_correction")" ]]
[[ $(jq -er '.superseded_manifest_helper_sha256' "$checked_in_r3_correction") \
    == "$(jq -er '.corrected_manifest_helper_sha256' \
        "$checked_in_r2_correction")" ]]
[[ $(jq -er '.corrected_recovery_tool_sha256' "$checked_in_r3_correction") \
    == e690a545bc2640555ab96db4a321dd1b2d307e46f6f001e9b3f91cad9c8626d8 ]]
[[ $(jq -er '.corrected_manifest_helper_sha256' "$checked_in_r3_correction") \
    == e7c2fa4f03755f2dea9664b1ee801143010852d2fd33d86a3854af9adbcbca5f ]]
[[ $(jq -er '.proof_helper_source_commit' "$checked_in_r3_correction") \
    == 5ac27c9c1ad06b32b6e1ba5858b6964383c70da0 ]]
[[ $(jq -er '.proof_helper_sha256' "$checked_in_r3_correction") \
    == c4e3e85d35216a06173f5a68d6574db917d099f89458241d4ee969a4abac96de ]]
[[ $(jq -er '.supersedes_resolution_sha256' "$checked_in_r4_correction") \
    == 24d931ae179a1a9f7a477e91ef9681d6da41180b9cf802eb7bb16e3bb8ecb734 ]]
[[ $(jq -er '.superseded_recovery_tool_sha256' "$checked_in_r4_correction") \
    == "$(jq -er '.corrected_recovery_tool_sha256' \
        "$checked_in_r3_correction")" ]]
[[ $(jq -er '.superseded_manifest_helper_sha256' "$checked_in_r4_correction") \
    == "$(jq -er '.corrected_manifest_helper_sha256' \
        "$checked_in_r3_correction")" ]]
[[ $(jq -er '.corrected_recovery_tool_sha256' "$checked_in_r4_correction") \
    == 87ab613c1d3be9e434717ea2086b7efc01fe830334e0b32c0f4c27d323e47e86 ]]
[[ $(jq -er '.corrected_manifest_helper_sha256' "$checked_in_r4_correction") \
    == 625c20103eaa6c79adbba3443937a014e64154ef3c5e60396fa596cb68885733 ]]
[[ $(jq -er '.sealed_inputs_resolution_sha256' "$checked_in_r4_correction") \
    == 3f42c2844a4b72b9eef3f5f52f9db6cc7bbed3ba8a4cb7907f854d32d54f9293 ]]
[[ $(jq -er '.sealed_inputs_resolution_sha256' "$checked_in_r4_correction") \
    != "$(jq -er '.supersedes_resolution_sha256' \
        "$checked_in_r4_correction")" ]]
[[ $(jq -er '.supersedes_resolution_sha256' "$checked_in_r5_correction") \
    == 2fbd262d7068e477787244b4b9c0fe74abd198d875053f5bbbfe7c7a0d5194f5 ]]
[[ $(jq -er '.superseded_recovery_tool_sha256' "$checked_in_r5_correction") \
    == "$(jq -er '.corrected_recovery_tool_sha256' \
        "$checked_in_r4_correction")" ]]
[[ $(jq -er '.superseded_manifest_helper_sha256' "$checked_in_r5_correction") \
    == "$(jq -er '.corrected_manifest_helper_sha256' \
        "$checked_in_r4_correction")" ]]
[[ $(jq -er '.corrected_recovery_tool_sha256' "$checked_in_r5_correction") \
    == "$(sha256sum "$recovery_tool" | awk '{print $1}')" ]]
[[ $(jq -er '.corrected_manifest_helper_sha256' "$checked_in_r5_correction") \
    == "$(sha256sum "$helper" | awk '{print $1}')" ]]
[[ $(jq -er '.sealed_inputs_resolution_sha256' "$checked_in_r5_correction") \
    == 3f42c2844a4b72b9eef3f5f52f9db6cc7bbed3ba8a4cb7907f854d32d54f9293 ]]
[[ $(jq -er '.sealed_inputs_resolution_sha256' "$checked_in_r5_correction") \
    != "$(jq -er '.supersedes_resolution_sha256' \
        "$checked_in_r5_correction")" ]]
[[ $(jq -er '.superseded_planned_product_base_commit' \
        "$checked_in_r5_correction") \
    == "$(jq -er '.corrected_planned_product_base_commit' \
        "$checked_in_r4_correction")" ]]
[[ $(jq -er '.proof_helper_source_parent_commit' "$checked_in_r5_correction") \
    == "$(jq -er '.planned_product_base_commit' \
        "$checked_in_selection_review")" ]]
[[ $(jq -er '.proof_helper_source_parent_commit' "$checked_in_r5_correction") \
    != "$(jq -er '.proof_helper_source_commit' "$checked_in_r5_correction")" ]]
[[ $(jq -er '.superseded_runtime_inputs_present' "$checked_in_r5_correction") \
    == true ]]
[[ $(jq -er '.superseded_runtime_resolution_sha256' "$checked_in_r5_correction") \
    == "$(jq -er '.supersedes_resolution_sha256' \
        "$checked_in_r5_correction")" ]]
[[ $(jq -er '.superseded_resolution_receipt_present' "$checked_in_r5_correction") \
    == false ]]
jq -cj \
    '.superseded_runtime_resolution_sha256 = .sealed_inputs_resolution_sha256' \
    "$checked_in_r5_correction" >"$tmp_root/r5-wrong-superseded-runtime.json"
expect_failure "$helper" validate-resolution-correction-review \
    "$tmp_root/r5-wrong-superseded-runtime.json"
jq -cj '.superseded_resolution_receipt_present = true' \
    "$checked_in_r5_correction" >"$tmp_root/r5-false-receipt-claim.json"
expect_failure "$helper" validate-resolution-correction-review \
    "$tmp_root/r5-false-receipt-claim.json"
jq -cj 'del(.proof_helper_source_parent_commit)' \
    "$checked_in_r5_correction" >"$tmp_root/r5-missing-source-parent.json"
expect_failure "$helper" validate-resolution-correction-review \
    "$tmp_root/r5-missing-source-parent.json"
jq -cj '.proof_helper_source_parent_commit = .proof_helper_source_commit' \
    "$checked_in_r5_correction" >"$tmp_root/r5-self-parent.json"
expect_failure "$helper" validate-resolution-correction-review \
    "$tmp_root/r5-self-parent.json"
(
    REPLACEMENT_PREDECESSOR_GENERATION=$(jq -er \
        '.predecessor_generation' "$checked_in_selection_review")
    REPLACEMENT_PREDECESSOR_MANIFEST_SHA256=$(jq -er \
        '.predecessor_manifest_sha256' "$checked_in_selection_review")
    REJECTED_AUTHORITY_GENERATION=$(jq -er \
        '.rejected_generation' "$checked_in_selection_review")
    REJECTED_AUTHORITY_MANIFEST_SHA256=$(jq -er \
        '.rejected_manifest_sha256' "$checked_in_selection_review")
    REJECTED_AUTHORITY_WORKFLOW_COMMIT=$(jq -er \
        '.rejected_workflow_commit' "$checked_in_selection_review")
    REJECTED_AUTHORITY_VERSION=$(jq -er \
        '.rejected_authority_version' "$checked_in_selection_review")
    REJECTED_AUTHORITY_COMMIT=$(jq -er \
        '.rejected_authority_commit' "$checked_in_selection_review")
    REJECTED_PRODUCT_RELEASE_COMMIT=$(jq -er \
        '.rejected_product_release_commit' "$checked_in_selection_review")
    SELECTED_AUTHORITY_GENERATION=$(jq -er \
        '.selected_generation' "$checked_in_selection_review")
    SELECTED_AUTHORITY_MANIFEST_SHA256=$(jq -er \
        '.selected_manifest_sha256' "$checked_in_selection_review")
    SELECTED_AUTHORITY_WORKFLOW_COMMIT=$(jq -er \
        '.selected_workflow_commit' "$checked_in_selection_review")
    SELECTED_AUTHORITY_VERSION=$(jq -er \
        '.selected_authority_version' "$checked_in_selection_review")
    SELECTED_AUTHORITY_COMMIT=$(jq -er \
        '.selected_authority_commit' "$checked_in_selection_review")
    SETTLED_PRODUCT_VERSION=$(jq -er \
        '.settled_product_version' "$checked_in_selection_review")
    SETTLED_PRODUCT_GATEWAY_COMMIT=$(jq -er \
        '.settled_product_gateway_commit' "$checked_in_selection_review")
    SETTLED_PRODUCT_ENGINE_COMMIT=$(jq -er \
        '.settled_product_engine_commit' "$checked_in_selection_review")
    SETTLED_PRODUCT_STATE_SHA256=$(jq -er \
        '.settled_product_state_sha256' "$checked_in_selection_review")
    SETTLED_PROMOTION_POLICY_SHA256=$(jq -er \
        '.settled_promotion_policy_sha256' "$checked_in_selection_review")
    SELECTED_ENGINE_COMMIT=$(jq -er \
        '.selected_engine_commit' "$checked_in_selection_review")
    PLANNED_PRODUCT_VERSION=$(jq -er \
        '.planned_product_version' "$checked_in_selection_review")
    PLANNED_PRODUCT_BASE_COMMIT=$(jq -er \
        '.corrected_planned_product_base_commit' "$checked_in_r4_correction")
    RECOVERY_TOOL_SHA256=$(sha256sum "$recovery_tool" | awk '{print $1}')
    MANIFEST_HELPER_SHA256=$(sha256sum "$helper" | awk '{print $1}')
    SELECTION_REVIEW_SHA256=$(sha256sum \
        "$checked_in_selection_review" | awk '{print $1}')
    RESOLUTION_WORKFLOW_COMMIT=$(git -C "$repo_root" rev-parse HEAD)
    RESOLUTION_REVISION=4
    SUPERSEDES_RESOLUTION_TAG=$(jq -er \
        '.supersedes_resolution_tag' "$checked_in_r4_correction")
    SUPERSEDES_RESOLUTION_SHA256=$(jq -er \
        '.supersedes_resolution_sha256' "$checked_in_r4_correction")
    SUPERSEDED_RECOVERY_TOOL_SHA256=$(jq -er \
        '.superseded_recovery_tool_sha256' "$checked_in_r4_correction")
    CORRECTION_REVIEW_SHA256=$(sha256sum \
        "$checked_in_r4_correction" | awk '{print $1}')
    PROOF_HELPER_SOURCE_COMMIT=$(jq -er \
        '.proof_helper_source_commit' "$checked_in_r4_correction")
    PROOF_HELPER_SOURCE_TREE_SHA256=$(jq -er \
        '.proof_helper_source_tree_sha256' "$checked_in_r4_correction")
    PROOF_HELPER_SHA256=$(jq -er \
        '.proof_helper_sha256' "$checked_in_r4_correction")
    PROOF_HELPER_CONTROL_PLANE_SHA256=$(jq -er \
        '.proof_helper_control_plane_sha256' "$checked_in_r4_correction")
    PROOF_HELPER_TOOLCHAIN_SHA256=$(jq -er \
        '.proof_helper_toolchain_sha256' "$checked_in_r4_correction")
    PROOF_HELPER_RUSTFLAGS_SHA256=$(jq -er \
        '.proof_helper_rustflags_sha256' "$checked_in_r4_correction")
    PROOF_HELPER_BUILD_TARGET=$(jq -er \
        '.proof_helper_build_target' "$checked_in_r4_correction")
    PROOF_HELPER_BUILD_PROFILE=$(jq -er \
        '.proof_helper_build_profile' "$checked_in_r4_correction")
    PROOF_HELPER_BUILD_CLEAN=$(jq -er \
        '.proof_helper_build_clean' "$checked_in_r4_correction")
    PROOF_HELPER_EXECUTION_PATH=$(jq -er \
        '.proof_helper_execution_path' "$checked_in_r4_correction")
    PROOF_HELPER_PROTOCOL_SHA256=$(jq -er \
        '.proof_helper_protocol_sha256' "$checked_in_r4_correction")
    export REPLACEMENT_PREDECESSOR_GENERATION
    export REPLACEMENT_PREDECESSOR_MANIFEST_SHA256
    export REJECTED_AUTHORITY_GENERATION REJECTED_AUTHORITY_MANIFEST_SHA256
    export REJECTED_AUTHORITY_WORKFLOW_COMMIT REJECTED_AUTHORITY_VERSION
    export REJECTED_AUTHORITY_COMMIT REJECTED_PRODUCT_RELEASE_COMMIT
    export SELECTED_AUTHORITY_GENERATION SELECTED_AUTHORITY_MANIFEST_SHA256
    export SELECTED_AUTHORITY_WORKFLOW_COMMIT SELECTED_AUTHORITY_VERSION
    export SELECTED_AUTHORITY_COMMIT SETTLED_PRODUCT_VERSION
    export SETTLED_PRODUCT_GATEWAY_COMMIT SETTLED_PRODUCT_ENGINE_COMMIT
    export SETTLED_PRODUCT_STATE_SHA256 SETTLED_PROMOTION_POLICY_SHA256
    export SELECTED_ENGINE_COMMIT PLANNED_PRODUCT_VERSION
    export PLANNED_PRODUCT_BASE_COMMIT RECOVERY_TOOL_SHA256
    export MANIFEST_HELPER_SHA256 SELECTION_REVIEW_SHA256
    export RESOLUTION_WORKFLOW_COMMIT RESOLUTION_REVISION
    export SUPERSEDES_RESOLUTION_TAG SUPERSEDES_RESOLUTION_SHA256
    export SUPERSEDED_RECOVERY_TOOL_SHA256 CORRECTION_REVIEW_SHA256
    export PROOF_HELPER_SOURCE_COMMIT PROOF_HELPER_SOURCE_TREE_SHA256
    export PROOF_HELPER_SHA256 PROOF_HELPER_CONTROL_PLANE_SHA256
    export PROOF_HELPER_TOOLCHAIN_SHA256 PROOF_HELPER_RUSTFLAGS_SHA256
    export PROOF_HELPER_BUILD_TARGET PROOF_HELPER_BUILD_PROFILE
    export PROOF_HELPER_BUILD_CLEAN PROOF_HELPER_EXECUTION_PATH
    export PROOF_HELPER_PROTOCOL_SHA256

    checked_in_r4_resolution="$tmp_root/checked-in-r4-resolution.json"
    "$helper" render-replacement-resolution "$checked_in_r4_resolution"
    "$helper" validate-replacement-resolution "$checked_in_r4_resolution"
    "$helper" validate-replacement-resolution-tag \
        authority-resolution-v1-g60-r4 "$checked_in_r4_resolution"
    jq -c '
        .planned_product_base_commit = .selected_authority_commit |
        .proof_helper_source_commit = .selected_authority_commit
    ' \
        "$checked_in_r4_resolution" \
        >"$tmp_root/r4-resolution-selected-authority-base.json"
    expect_failure "$helper" validate-replacement-resolution \
        "$tmp_root/r4-resolution-selected-authority-base.json"
    jq -c --arg commit "$(printf '6%.0s' {1..40})" \
        '.planned_product_base_commit = $commit' \
        "$checked_in_r4_resolution" \
        >"$tmp_root/r4-resolution-non-proof-base.json"
    expect_failure "$helper" validate-replacement-resolution \
        "$tmp_root/r4-resolution-non-proof-base.json"

    RESOLUTION_REVISION=5
    SUPERSEDES_RESOLUTION_TAG=$(jq -er \
        '.supersedes_resolution_tag' "$checked_in_r5_correction")
    SUPERSEDES_RESOLUTION_SHA256=$(jq -er \
        '.supersedes_resolution_sha256' "$checked_in_r5_correction")
    SUPERSEDED_RECOVERY_TOOL_SHA256=$(jq -er \
        '.superseded_recovery_tool_sha256' "$checked_in_r5_correction")
    CORRECTION_REVIEW_SHA256=$(sha256sum \
        "$checked_in_r5_correction" | awk '{print $1}')
    PLANNED_PRODUCT_BASE_COMMIT=$(jq -er \
        '.corrected_planned_product_base_commit' "$checked_in_r5_correction")
    export RESOLUTION_REVISION SUPERSEDES_RESOLUTION_TAG
    export SUPERSEDES_RESOLUTION_SHA256 SUPERSEDED_RECOVERY_TOOL_SHA256
    export CORRECTION_REVIEW_SHA256 PLANNED_PRODUCT_BASE_COMMIT
    checked_in_r5_resolution="$tmp_root/checked-in-r5-resolution.json"
    "$helper" render-replacement-resolution "$checked_in_r5_resolution"
    "$helper" validate-replacement-resolution "$checked_in_r5_resolution"
    "$helper" validate-replacement-resolution-tag \
        authority-resolution-v1-g60-r5 "$checked_in_r5_resolution"
)
grep -Fq 'approval_record:' "$workflow"
for required in \
    verification_policy_revision \
    provisioner_sha256 \
    production_contract_sha256 \
    production_member_count \
    receipt_schema \
    build_authority_schema \
    promotion_recovery_schema \
    promotion_recovery_sha256; do
    grep -Fq "$required" "$workflow"
done
grep -Fq 'git -C source rev-parse "${SOURCE_COMMIT}^"' "$workflow"
grep -Fq 'authority-protocol-inputs' "$workflow"
grep -Fq -- '--authority-protocol-self-test' "$workflow"
grep -Fq 'shipper-self-test.json' "$workflow"
grep -Fq 'YQ_VERSION: v4.53.2' "$workflow"
grep -Fq \
    'YQ_LINUX_AMD64_SHA256: d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b' \
    "$workflow"
grep -Fq -- '--network none' "$workflow"
grep -Fq 'release-authority-source' "$workflow"
[[ $(grep -Fc 'secrets.SYNTAUR_SOURCE_DEPLOY_KEY' "$workflow") -eq 1 ]]
[[ $(grep -Fc 'secrets.SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY' "$workflow") -eq 2 ]]
[[ $(grep -Fc 'sudo chown -R 65534:65534 source' "$workflow") -eq 2 ]]
grep -Fq 'proof_helper_source_commit' "$workflow"
grep -Fq 'proof_helper_source_parent_commit' "$workflow"
grep -Fq 'unset SOURCE_ARCHIVE_AGE_IDENTITY' "$workflow"
grep -Fq 'encrypted-authority-source-run-' "$workflow"
[[ $(grep -Fc -- '--repo "$GITHUB_REPOSITORY"' "$workflow") -eq 27 ]]
grep -Fq 'mkdir -m 0700 "$age_root/bin"' "$workflow"
grep -Fq '"$age_root/bin/"' "$workflow"
grep -Fq '"$age_root/bin/age-keygen" -y -' "$workflow"
grep -Fq '"$age_root/bin/age"' "$workflow"
[[ $(grep -Fc 'mv encrypted-source-artifacts encrypted-source' "$workflow") -eq 2 ]]
grep -Fq 'mv reviewed-candidate-artifacts candidate' "$workflow"
grep -Fq 'mv signed-authority-artifacts signed-authority' "$workflow"
if grep -Fq 'Sign exact replacement resolution' "$workflow"; then
    fail 'initial authority signer still signs a replacement resolution'
fi
grep -Fq 'authority-replacement-v1-g${generation}' "$workflow"
grep -Fq 'authority-resolution-v1-g${GENERATION}' "$workflow"
grep -Fq 'resolution_revision' "$workflow"
grep -Fq 'validate-resolution-correction-review' "$workflow"
grep -Fq 'release-authority-resolution-correction-v1.json' "$workflow"
grep -Fq 'validate-replacement-resolution-assets' "$workflow"
grep -Fq 'validate-product-source-proofs' "$workflow"
grep -Fq 'settled_dist_commit=$(jq -er' "$workflow"
grep -Fq 'syntaur-source-commit.txt.cosign.bundle' "$workflow"
grep -Fq 'syntaur-engine-source-commit.txt.cosign.bundle' "$workflow"
if grep -Fq '= "$settled_gateway_commit"' "$workflow"; then
    fail 'public product tag commit is still equated with private Gateway source commit'
fi
grep -Fq 'rejected_product_release_commit' "$workflow"
grep -Fq 'resolution_policy:' "$workflow"
grep -Fq 'recover_sign_resolution:' "$workflow"
grep -Fq 'recover_publish_resolution:' "$workflow"
grep -Fq 'resolution_workflow_commit' "$workflow"
grep -Fq 'release-authority-selection-review-v1.json' "$workflow"
recovered_resolution_publisher=$(yq -r '
    .jobs.recover_publish_resolution.steps[] |
    select(.name == "Publish or finish exact recovered replacement resolution") |
    .run
' "$workflow")
grep -Fq 'mapfile -t upload_assets' <<<"$recovered_resolution_publisher"
grep -Fq -- '-mindepth 1 -maxdepth 1 -type f' \
    <<<"$recovered_resolution_publisher"
grep -Fq '"${upload_assets[@]}"' <<<"$recovered_resolution_publisher"
grep -Fq 'https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${release_id}/assets{?name,label}' \
    <<<"$recovered_resolution_publisher"
grep -Fq -- '--input "$asset_path"' <<<"$recovered_resolution_publisher"
grep -Fq -- '-f "name=${asset_name}"' <<<"$recovered_resolution_publisher"
if grep -Fq 'gh release upload "$resolution_tag"' \
    <<<"$recovered_resolution_publisher"; then
    fail 'replacement resolution publisher resolves a draft by tag for upload'
fi
if grep -Fq 'upload_assets=(' <<<"$recovered_resolution_publisher"; then
    fail 'replacement resolution publisher maintains a second static asset list'
fi
grep -Fq 'SELECTION_REVIEW_SHA256' "$workflow"
grep -Fq 'SETTLED_PROMOTION_POLICY_SHA256' "$workflow"
grep -Fq 'target_already_published' "$workflow"
grep -Fq 'special_namespace_max=$previous' "$workflow"
grep -Fq 'validate-special-tag-namespace' "$workflow"
grep -Fq 'assert-replacement' "$recovery_tool"
grep -Fq 'SEALED_RUNTIME_ROOT=/etc/syntaur/release-authority-replacement-v1.runtime' \
    "$recovery_tool"
grep -Fq 'seal_install_inputs' "$recovery_tool"
grep -Fq 'verify_inputs "$operation"' "$recovery_tool"
grep -Fq -- '--expected-recovery-tool-sha256' "$recovery_tool"
grep -Fq 'discard_incomplete_resolution_stage' "$recovery_tool"
if grep -Fq 'authority-promote' "$recovery_tool"; then
    fail 'exceptional recovery still invokes the ordinary promotion gate'
fi
grep -Fq 'install_selected_authority_exceptionally' "$recovery_tool"
grep -Fq 'rollback_selected_authority_exceptionally' "$recovery_tool"
grep -Fq 'settled_product_state_sha256' "$recovery_tool"
grep -Fq 'manifest_published' "$recovery_tool"
grep -Fq 'assert-genesis' "$workflow"
grep -Fq 'fetch-depth: 2' "$workflow"
grep -Fq 'verify-g1-authority-source.sh' "$workflow"
grep -Fq 'b003360f63707d92fd0df1fd12384282f1c3004f' "$workflow"
grep -Fq '1bf740acd5a7223e98370f668148f01ebfb6eff8' "$workflow"
grep -Fq 'draft' "$workflow"
grep -Fq 'snapshot_authority_namespace' "$workflow"
grep -Fq 'GH_TOKEN: ${{ secrets.SYNTAUR_RELEASE_AUTHORITY_PUBLISH_TOKEN }}' "$workflow"
if grep -Fq 'SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_' "$workflow"; then
    fail 'authority workflow contains a publisher App credential'
fi
grep -Fq '"/repos/${GITHUB_REPOSITORY}/releases?per_page=100"' "$workflow"
grep -Fq 'release=$(gh api --method POST' "$workflow"
grep -Fq 'generation=$((EXPECTED_PREVIOUS_GENERATION + 1))' "$workflow"
if grep -Eq 'generation=.*(github\\.run_id|GITHUB_RUN_ID)' "$workflow"; then
    fail 'authority generation derives from a workflow run ID'
fi
if grep -Fq 'python' "$workflow"; then
    fail 'authority workflow must not depend on Python'
fi

sudo -n true || fail 'root recovery fixture requires noninteractive sudo'
root_fixture=$tmp_root/root-fixture
root_helpers=$tmp_root/recovery-root-functions.sh
mkdir -p "$root_fixture/material"
awk '
    /^\[\[ \$# -ge 1 \]\] \|\| usage$/ { exit }
    { print }
' "$recovery_tool" \
    | sed \
        -e "s|^readonly AUTHORITY_ROOT=.*|readonly AUTHORITY_ROOT=$root_fixture/etc/syntaur/release-authority|" \
        -e "s|^readonly INSTALLED_SHIPPER=.*|readonly INSTALLED_SHIPPER=$root_fixture/usr/local/bin/syntaur-ship|" \
        -e "s|^readonly INSTALLED_PROVISIONER=.*|readonly INSTALLED_PROVISIONER=$root_fixture/opt/syntaur-build-authority-provision|" \
        -e "s|^readonly INSTALL_RECEIPT=.*|readonly INSTALL_RECEIPT=$root_fixture/etc/syntaur/release-authority-replacement-v1.receipt.json|" \
        -e "s|^readonly ROLLBACK_RECEIPT=.*|readonly ROLLBACK_RECEIPT=$root_fixture/etc/syntaur/release-authority-replacement-v1.rollback-receipt.json|" \
        -e "s|^readonly SUPERSEDED_SEALED_RUNTIME_ROOT=.*|readonly SUPERSEDED_SEALED_RUNTIME_ROOT=$root_fixture/etc/syntaur/release-authority-replacement-v1.runtime|" \
        -e "s|^readonly PROOF_HELPER_PARENT=.*|readonly PROOF_HELPER_PARENT=$root_fixture/usr/local/libexec|" \
    >"$root_helpers"
chmod 0500 "$root_helpers"

large_resolution_source=$tmp_root/r4-large-resolution-source
install -d -m 0700 "$large_resolution_source"
printf '{}\n' >"$large_resolution_source/release-authority-replacement-v1.json"
chmod 0400 "$large_resolution_source/release-authority-replacement-v1.json"
install -m 0500 "$recovery_tool" \
    "$large_resolution_source/recover-release-authority-replacement-v1.sh"
install -m 0500 "$helper" \
    "$large_resolution_source/release-authority-manifest.sh"
truncate -s 5242880 \
    "$large_resolution_source/syntaur-authority-replacement-proof-linux-x86_64"
chmod 0500 \
    "$large_resolution_source/syntaur-authority-replacement-proof-linux-x86_64"
[[ $(stat -c '%s' \
    "$large_resolution_source/syntaur-authority-replacement-proof-linux-x86_64") \
    -gt 4194304 ]] || fail 'large proof-helper fixture does not cross the document limit'
/usr/bin/env RECOVERY_HELPERS="$root_helpers" \
    RESOLUTION_SOURCE="$large_resolution_source" /usr/bin/bash -c '
        set -euo pipefail
        source "$RECOVERY_HELPERS"
        validate_resolution_inline() { :; }
        resolution_data_names() {
            /usr/bin/printf "%s\n" "$RESOLUTION" "$PROOF_HELPER_ASSET"
        }
        resolution_all_names() {
            resolution_data_names "$1"
            /usr/bin/printf "%s\n" "$RECOVERY_TOOL" "$MANIFEST_HELPER"
        }
        require_resolution_source "$RESOLUTION_SOURCE"
    '

lineage_fixture=$tmp_root/lineage-hash-domain-regression
lineage_authority_root=$lineage_fixture/etc/syntaur/release-authority
lineage_runtime=$lineage_fixture/etc/syntaur/release-authority-replacement-v1.runtime
lineage_origin=$lineage_runtime/inputs/resolution
lineage_resolution=$lineage_fixture/resolution
lineage_receipt=$lineage_authority_root/replacement-resolution-v1/generation-60-r2
lineage_helpers=$lineage_fixture/recovery-functions.sh
install -d -m 0700 "$lineage_origin" "$lineage_resolution" "$lineage_receipt" \
    "$lineage_authority_root"
chmod 0700 "$lineage_runtime" "$lineage_runtime/inputs" "$lineage_origin"
awk '
    /^\[\[ \$# -ge 1 \]\] \|\| usage$/ { exit }
    { print }
' "$recovery_tool" | sed \
    -e "s|^readonly AUTHORITY_ROOT=.*|readonly AUTHORITY_ROOT=$lineage_authority_root|" \
    -e "s|^readonly SUPERSEDED_SEALED_RUNTIME_ROOT=.*|readonly SUPERSEDED_SEALED_RUNTIME_ROOT=$lineage_runtime|" \
    -e "s|^readonly INSTALL_RECEIPT=.*|readonly INSTALL_RECEIPT=$lineage_fixture/install-receipt.json|" \
    -e "s|^readonly ROLLBACK_RECEIPT=.*|readonly ROLLBACK_RECEIPT=$lineage_fixture/rollback-receipt.json|" \
    >"$lineage_helpers"
chmod 0500 "$lineage_helpers"
printf 'r2-resolution' >"$lineage_origin/release-authority-replacement-v1.json"
printf 'r2-bundle' >"$lineage_origin/release-authority-replacement-v1.json.cosign.bundle"
install -m 0400 "$lineage_origin/release-authority-replacement-v1.json" \
    "$lineage_receipt/release-authority-replacement-v1.json"
printf 'r4-resolution' >"$lineage_resolution/release-authority-replacement-v1.json"
printf 'r4-correction' >"$lineage_resolution/release-authority-resolution-correction-v1.json"
printf '{"phase":"manifest_published"}' \
    >"$lineage_authority_root/authority-replacement-v1-install.json"
printf 'promotion-journal' \
    >"$lineage_authority_root/authority-promotion-v1.json"
printf 'selected-authority' >"$lineage_authority_root/release-authority-v2.json"
: >"$lineage_authority_root/.authority-replacement-product-state-v1.tmp"
LINEAGE_HELPERS=$lineage_helpers LINEAGE_FIXTURE=$lineage_fixture \
LINEAGE_SELECTED=$(digest_text lineage-selected) \
LINEAGE_PRODUCT=$(digest_text lineage-product) \
LINEAGE_JOURNAL=$(digest_text lineage-journal) \
LINEAGE_R2=$(digest_text lineage-r2) \
LINEAGE_R3=$(digest_text lineage-r3) \
/usr/bin/bash -c '
    set -euo pipefail
    source "$LINEAGE_HELPERS"
    resolution_dir=$LINEAGE_FIXTURE/resolution
    expected_selected_sha256=$LINEAGE_SELECTED
    expected_predecessor_sha256=$(printf "a%.0s" {1..64})
    resolution_value() {
        local file=$1 field=$2
        case $(basename "$file"):$field in
            release-authority-resolution-correction-v1.json:active_manifest_sha256)
                printf "%s\n" "$LINEAGE_SELECTED" ;;
            release-authority-resolution-correction-v1.json:active_generation)
                printf "60\n" ;;
            release-authority-resolution-correction-v1.json:active_product_state_sha256)
                printf "%s\n" "$LINEAGE_PRODUCT" ;;
            release-authority-resolution-correction-v1.json:active_install_journal_sha256)
                printf "%s\n" "$LINEAGE_JOURNAL" ;;
            release-authority-resolution-correction-v1.json:active_install_journal_phase)
                printf "manifest_published\n" ;;
            release-authority-resolution-correction-v1.json:sealed_inputs_resolution_sha256)
                printf "%s\n" "$LINEAGE_R2" ;;
            release-authority-resolution-correction-v1.json:active_product_proof_temp_sha256)
                printf "%s\n" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ;;
            release-authority-resolution-correction-v1.json:active_product_proof_temp_size)
                printf "0\n" ;;
            release-authority-replacement-v1.json:selected_generation)
                printf "60\n" ;;
            release-authority-replacement-v1.json:selected_manifest_sha256)
                printf "%s\n" "$LINEAGE_SELECTED" ;;
            release-authority-replacement-v1.json:supersedes_resolution_sha256)
                printf "%s\n" "$LINEAGE_R3" ;;
            release-authority-replacement-v1.json:resolution_workflow_commit)
                printf "1111111111111111111111111111111111111111\n" ;;
            *) printf "unexpected lineage field: %s %s\n" "$file" "$field" >&2; return 1 ;;
        esac
    }
    resolution_revision() {
        if [[ $1 == "$resolution_dir/$RESOLUTION" ]]; then printf "4\n"; else printf "2\n"; fi
    }
    manifest_value() {
        [[ $2 == generation ]] || return 1
        printf "60\n"
    }
    sha256_file() {
        case $1 in
            "$INSTALL_JOURNAL") printf "%s\n" "$LINEAGE_JOURNAL" ;;
            "$SUPERSEDED_SEALED_RUNTIME_ROOT/inputs/resolution/$RESOLUTION")
                printf "%s\n" "$LINEAGE_R2" ;;
            "$PRODUCT_STATE_PROOF_TEMP")
                printf "%s\n" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ;;
            *) /usr/bin/sha256sum "$1" | /usr/bin/cut -d" " -f1 ;;
        esac
    }
    product_state_digest() { printf "%s\n" "$LINEAGE_PRODUCT"; }
    require_root_directory() { :; }
    require_root_file() { :; }
    validate_resolution_inline() { :; }
    verify_cosign() { :; }
    validate_mutation_fence() { :; }
    validate_current_install_state() { :; }
    validate_selected_active() { :; }
    install_resolution_receipt() { :; }
    resolution_receipt_directory() { printf "%s/current-r4-receipt\n" "$LINEAGE_FIXTURE"; }
    resolution_data_names() { printf "%s\n" "$RESOLUTION"; }
    verify_resolution_correction_r3_state \
        install "$LINEAGE_SELECTED" "$LINEAGE_PRODUCT" \
        "$resolution_dir/$CORRECTION_REVIEW"
'

shadow_runtime=$tmp_root/dynamic-scope-runtime
shadow_stage=$shadow_runtime/inputs.staged
shadow_resolution=$shadow_stage/resolution
install -d -m 0700 "$shadow_stage/predecessor" "$shadow_stage/rejected" \
    "$shadow_stage/selected" "$shadow_resolution"
shadow_tool=$shadow_runtime/recover-release-authority-replacement-v1.sh
awk '
    /^\[\[ \$# -ge 1 \]\] \|\| usage$/ { exit }
    { print }
' "$recovery_tool" \
    | sed \
        -e "s|^readonly SEALED_RUNTIME_ROOT=.*|readonly SEALED_RUNTIME_ROOT=$shadow_runtime|" \
    >"$shadow_tool"
chmod 0500 "$shadow_tool"
install -m 0500 "$shadow_tool" \
    "$shadow_resolution/recover-release-authority-replacement-v1.sh"
install -m 0500 "$helper" "$shadow_resolution/release-authority-manifest.sh"
install -m 0400 \
    "$resolution_dir/release-authority-selection-review-v1.json" \
    "$resolution_dir/release-authority-replacement-v1.json" \
    "$resolution_dir/release-authority-replacement-v1.json.cosign.bundle" \
    "$shadow_resolution/"
shadow_error=$tmp_root/dynamic-scope-error
if /usr/bin/env SHADOW_TOOL="$shadow_tool" SHADOW_STAGE="$shadow_stage" \
    /usr/bin/bash -c '
        source "$SHADOW_TOOL"
        predecessor_dir=$SHADOW_STAGE/predecessor
        rejected_dir=$SHADOW_STAGE/rejected
        selected_dir=$SHADOW_STAGE/selected
        resolution_dir=$SHADOW_STAGE/resolution
        expected_resolution_sha256=$(printf "0%.0s" {1..64})
        expected_recovery_tool_sha256=$expected_resolution_sha256
        correction_authorization=
        dynamic_scope_shadow_probe() {
            local mode operation
            verify_inputs install
        }
        dynamic_scope_shadow_probe
    ' 2>"$shadow_error"; then
    fail 'dynamic-scope regression unexpectedly verified invalid sealed inputs'
fi
if ! grep -Fq 'replacement resolution differs from the operator-authorized hash' \
    "$shadow_error"; then
    sed 's/^/dynamic-scope regression: /' "$shadow_error" >&2
    fail 'sealed-input verification did not reach the explicit-operation path'
fi
if grep -Fq 'unbound variable' "$shadow_error"; then
    fail 'sealed-input verification still depends on a dynamically scoped mode variable'
fi

phase_root=$tmp_root/correction-phase-matrix
phase_helpers=$phase_root/recovery-phase-functions.sh
phase_authority_root=$phase_root/etc/syntaur/release-authority
mkdir -p "$phase_authority_root" "$phase_root/resolution"
awk '
    /^\[\[ \$# -ge 1 \]\] \|\| usage$/ { exit }
    { print }
' "$recovery_tool" \
    | sed \
        -e "s|^readonly AUTHORITY_ROOT=.*|readonly AUTHORITY_ROOT=$phase_authority_root|" \
        -e "s|^readonly INSTALL_RECEIPT=.*|readonly INSTALL_RECEIPT=$phase_root/etc/syntaur/install-receipt.json|" \
        -e "s|^readonly ROLLBACK_RECEIPT=.*|readonly ROLLBACK_RECEIPT=$phase_root/etc/syntaur/rollback-receipt.json|" \
    >"$phase_helpers"
PHASE_HELPERS=$phase_helpers PHASE_ROOT=$phase_root \
PHASE_PRODUCT=$(digest_text correction-phase-product) \
PHASE_PREDECESSOR=$(digest_text correction-phase-predecessor) \
PHASE_SELECTED=$(digest_text correction-phase-selected) \
/usr/bin/bash -c '
    set -euo pipefail
    source "$PHASE_HELPERS"
    resolution_dir=$PHASE_ROOT/resolution
    expected_predecessor_sha256=$PHASE_PREDECESSOR
    expected_selected_sha256=$PHASE_SELECTED
    : >"$resolution_dir/$RESOLUTION"
    : >"$resolution_dir/$CORRECTION_REVIEW"

    resolution_value() {
        case $2 in
            schema) printf "2\n" ;;
            selected_generation) printf "60\n" ;;
            active_manifest_sha256) printf "%s\n" "$PHASE_PREDECESSOR" ;;
            active_generation) printf "59\n" ;;
            active_product_state_sha256) printf "%s\n" "$PHASE_PRODUCT" ;;
            *) printf "phase matrix requested unexpected resolution field: %s\n" "$2" >&2; return 1 ;;
        esac
    }
    resolution_revision() { printf "2\n"; }
    resolution_receipt_directory() { printf "%s/resolution-receipt\n" "$PHASE_ROOT"; }
    manifest_value() {
        [[ $2 == generation ]] || return 1
        printf "59\n"
    }
    product_state_digest() { printf "%s\n" "$PHASE_PRODUCT"; }
    install_resolution_receipt() { resolution_receipt_validations=$((resolution_receipt_validations + 1)); }
    validate_mutation_fence() { fence_validations=$((fence_validations + 1)); }
    validate_current_install_state() { install_validations=$((install_validations + 1)); }
    validate_current_rollback_state() { rollback_validations=$((rollback_validations + 1)); }
    validate_predecessor_active() { predecessor_validations=$((predecessor_validations + 1)); }
    validate_selected_active() { selected_validations=$((selected_validations + 1)); }
    validate_install_receipt() { install_receipt_validations=$((install_receipt_validations + 1)); }
    validate_rollback_receipt() { rollback_receipt_validations=$((rollback_receipt_validations + 1)); }

    resolution_receipt_validations=0
    fence_validations=0
    install_validations=0
    rollback_validations=0
    predecessor_validations=0
    selected_validations=0
    install_receipt_validations=0
    rollback_receipt_validations=0

    verify_resolution_correction_state install "$PHASE_PREDECESSOR"
    mkdir "$PHASE_ROOT/resolution-receipt"
    verify_resolution_correction_state install "$PHASE_PREDECESSOR"
    : >"$NORMAL_PROMOTION_JOURNAL"
    verify_resolution_correction_state install "$PHASE_PREDECESSOR"
    : >"$INSTALL_JOURNAL"
    verify_resolution_correction_state install "$PHASE_PREDECESSOR"
    rm "$INSTALL_JOURNAL" "$NORMAL_PROMOTION_JOURNAL"
    : >"$INSTALL_RECEIPT"
    verify_resolution_correction_state install "$PHASE_SELECTED"
    verify_resolution_correction_state rollback "$PHASE_SELECTED"
    : >"$NORMAL_PROMOTION_JOURNAL"
    : >"$ROLLBACK_JOURNAL"
    verify_resolution_correction_state rollback "$PHASE_SELECTED"
    rm "$NORMAL_PROMOTION_JOURNAL" "$ROLLBACK_JOURNAL"
    : >"$ROLLBACK_RECEIPT"
    verify_resolution_correction_state rollback "$PHASE_PREDECESSOR"

    rm "$INSTALL_RECEIPT" "$ROLLBACK_RECEIPT"
    : >"$INSTALL_JOURNAL"
    if ( verify_resolution_correction_state install "$PHASE_PREDECESSOR" ) \
        2>"$PHASE_ROOT/install-without-fence.error"; then
        printf "phase gate accepted install journal without fence\n" >&2
        exit 1
    fi
    rm "$INSTALL_JOURNAL"
    : >"$INSTALL_RECEIPT"
    : >"$ROLLBACK_RECEIPT"
    if ( verify_resolution_correction_state rollback "$PHASE_SELECTED" ) \
        2>"$PHASE_ROOT/selected-with-rollback-receipt.error"; then
        printf "phase gate accepted rollback receipt with selected authority\n" >&2
        exit 1
    fi
    [[ $resolution_receipt_validations -eq 7 ]]
    [[ $fence_validations -eq 3 ]]
    [[ $install_validations -eq 1 ]]
    [[ $rollback_validations -eq 1 ]]
    [[ $predecessor_validations -eq 1 ]]
    [[ $selected_validations -eq 0 ]]
    [[ $install_receipt_validations -eq 4 ]]
    [[ $rollback_receipt_validations -eq 1 ]]
'

entry_fixture=$tmp_root/replacement-entry-fixture
entry_authority_root=$entry_fixture/etc/syntaur/release-authority
entry_artifact_root=$entry_authority_root/release-authority
entry_runtime=$entry_fixture/etc/syntaur/release-authority-replacement-v1.runtime
entry_stage=$entry_runtime/inputs.staged
entry_operator_home=$entry_fixture/home/operator
entry_operator_state=$entry_operator_home/.syntaur/ship
entry_global_lock=$entry_fixture/etc/syntaur/syntaur-ship-mutation.lock
entry_shipper=$entry_fixture/usr/local/bin/syntaur-ship
entry_provisioner=$entry_fixture/opt/syntaur-build-authority-provision
entry_sources=$entry_fixture/sources
install -d -m 0700 \
    "$entry_runtime" "$entry_stage" \
    "$entry_stage/predecessor" "$entry_stage/rejected" \
    "$entry_stage/selected" "$entry_stage/resolution" \
    "$entry_operator_home" "$entry_operator_home/.syntaur" \
    "$entry_operator_state" \
    "$entry_sources/predecessor" "$entry_sources/rejected" \
    "$entry_sources/selected" "$entry_sources/resolution"
install -d -m 0755 "$entry_artifact_root" \
    "$(dirname "$entry_global_lock")" "$(dirname "$entry_shipper")" \
    "$(dirname "$entry_provisioner")"
for authority_dir in predecessor rejected selected; do
    printf '%s manifest\n' "$authority_dir" \
        >"$entry_sources/$authority_dir/release-authority-v2.json"
    printf '%s bundle\n' "$authority_dir" \
        >"$entry_sources/$authority_dir/release-authority-v2.json.cosign.bundle"
    for executable in syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
        printf '#!/usr/bin/bash\nexit 0\n' \
            >"$entry_sources/$authority_dir/$executable"
    done
    chmod 0400 \
        "$entry_sources/$authority_dir/release-authority-v2.json" \
        "$entry_sources/$authority_dir/release-authority-v2.json.cosign.bundle"
    chmod 0500 \
        "$entry_sources/$authority_dir/syntaur-build-authority-provision" \
        "$entry_sources/$authority_dir/syntaur-ship-linux-x86_64" \
        "$entry_sources/$authority_dir/syntaur-verify-linux-x86_64"
done
entry_tool=$entry_runtime/recover-release-authority-replacement-v1.sh
sed \
    -e "s|^readonly AUTHORITY_ROOT=.*|readonly AUTHORITY_ROOT=$entry_authority_root|" \
    -e "s|^readonly INSTALLED_SHIPPER=.*|readonly INSTALLED_SHIPPER=$entry_shipper|" \
    -e "s|^readonly INSTALLED_PROVISIONER=.*|readonly INSTALLED_PROVISIONER=$entry_provisioner|" \
    -e "s|^readonly GLOBAL_MUTATION_LOCK=.*|readonly GLOBAL_MUTATION_LOCK=$entry_global_lock|" \
    -e "s|^readonly SEALED_RUNTIME_ROOT=.*|readonly SEALED_RUNTIME_ROOT=$entry_runtime|" \
    -e "s|^    operator_state=.*|    operator_state=$entry_operator_state|" \
    "$recovery_tool" \
    | awk -v operator_home="$entry_operator_home" '
        /^    operator_home=\$\(\/usr\/bin\/getent passwd/ {
            print "    operator_home=" operator_home
            replacing_lookup=1
            next
        }
        replacing_lookup {
            if (/sudo operator account lookup failed/) {
                replacing_lookup=0
            }
            next
        }
        { print }
    ' >"$entry_tool"
chmod 0500 "$entry_tool"
install -m 0500 "$entry_tool" \
    "$entry_sources/resolution/recover-release-authority-replacement-v1.sh"
install -m 0500 "$helper" "$entry_sources/resolution/release-authority-manifest.sh"
install -m 0400 \
    "$resolution_dir/release-authority-selection-review-v1.json" \
    "$resolution_dir/release-authority-replacement-v1.json.cosign.bundle" \
    "$entry_sources/resolution/"
jq -cj \
    --arg supersedes_resolution_sha256 "$(digest_text entry-superseded-resolution)" \
    --arg superseded_recovery_tool_sha256 "$(digest_text entry-superseded-tool)" \
    --arg correction_review_sha256 "$(digest_text entry-correction-review)" \
    '.schema = 2 |
     .resolution_revision = 2 |
     .supersedes_resolution_tag =
       ("authority-resolution-v1-g" + (.selected_generation | tostring)) |
     .supersedes_resolution_sha256 = $supersedes_resolution_sha256 |
     .superseded_recovery_tool_sha256 = $superseded_recovery_tool_sha256 |
     .correction_reason = "recovery_tool_execution_failure" |
     .correction_review_sha256 = $correction_review_sha256' \
    "$resolution_dir/release-authority-replacement-v1.json" \
    >"$entry_sources/resolution/release-authority-replacement-v1.json"
printf 'entry correction review\n' \
    >"$entry_sources/resolution/release-authority-resolution-correction-v1.json"
chmod 0400 \
    "$entry_sources/resolution/release-authority-selection-review-v1.json" \
    "$entry_sources/resolution/release-authority-replacement-v1.json" \
    "$entry_sources/resolution/release-authority-replacement-v1.json.cosign.bundle" \
    "$entry_sources/resolution/release-authority-resolution-correction-v1.json"

for authority_dir in predecessor rejected selected; do
    install -m 0400 \
        "$entry_sources/$authority_dir/release-authority-v2.json" \
        "$entry_sources/$authority_dir/release-authority-v2.json.cosign.bundle" \
        "$entry_stage/$authority_dir/"
    install -m 0500 \
        "$entry_sources/$authority_dir/syntaur-build-authority-provision" \
        "$entry_sources/$authority_dir/syntaur-ship-linux-x86_64" \
        "$entry_sources/$authority_dir/syntaur-verify-linux-x86_64" \
        "$entry_stage/$authority_dir/"
done
install -m 0500 "$entry_tool" \
    "$entry_stage/resolution/recover-release-authority-replacement-v1.sh"
install -m 0500 "$helper" "$entry_stage/resolution/release-authority-manifest.sh"
install -m 0400 \
    "$resolution_dir/release-authority-selection-review-v1.json" \
    "$resolution_dir/release-authority-replacement-v1.json" \
    "$resolution_dir/release-authority-replacement-v1.json.cosign.bundle" \
    "$entry_stage/resolution/"
printf '#!/usr/bin/bash\nexit 0\n' >"$entry_shipper"
printf '#!/usr/bin/bash\nexit 0\n' >"$entry_provisioner"
chmod 0555 "$entry_shipper" "$entry_provisioner"
printf 'active predecessor manifest\n' >"$entry_authority_root/release-authority-v2.json"
chmod 0444 "$entry_authority_root/release-authority-v2.json"
: >"$entry_global_lock"
printf '\n' >"$entry_operator_state/deploy.lock"
sudo -n chown -R 0:0 "$entry_fixture/etc" "$entry_fixture/usr" "$entry_fixture/opt"
sudo -n chown "$(id -u):$(id -g)" "$entry_operator_state" \
    "$entry_operator_state/deploy.lock"
sudo -n chown "0:$(id -g)" "$entry_global_lock"
sudo -n chmod 0440 "$entry_global_lock"
sudo -n chmod 0600 "$entry_operator_state/deploy.lock"
entry_active_before=$(sha256sum "$entry_authority_root/release-authority-v2.json" \
    | awk '{print $1}')
entry_tool_sha256=$(sudo -n sha256sum "$entry_tool" | awk '{print $1}')
entry_error=$tmp_root/replacement-entry-error
if sudo -n env \
    ENTRY_TOOL="$entry_tool" ENTRY_SOURCES="$entry_sources" \
    ENTRY_TOOL_SHA256="$entry_tool_sha256" \
    ENTRY_UID="$(id -u)" ENTRY_GID="$(id -g)" ENTRY_USER="$(id -un)" \
    ENTRY_ERROR="$entry_error" \
    /usr/bin/unshare --uts --fork /usr/bin/bash -c '
        /usr/bin/hostname claudevm
        /usr/bin/env -i \
          SUDO_UID="$ENTRY_UID" SUDO_GID="$ENTRY_GID" SUDO_USER="$ENTRY_USER" \
          PATH=/usr/sbin:/usr/bin:/sbin:/bin \
          "$ENTRY_TOOL" install \
            --predecessor-dir "$ENTRY_SOURCES/predecessor" \
            --rejected-dir "$ENTRY_SOURCES/rejected" \
            --selected-dir "$ENTRY_SOURCES/selected" \
            --resolution-dir "$ENTRY_SOURCES/resolution" \
            --expected-resolution-sha256 \
              0000000000000000000000000000000000000000000000000000000000000000 \
            --expected-recovery-tool-sha256 "$ENTRY_TOOL_SHA256" \
            --expected-predecessor-manifest-sha256 \
              1111111111111111111111111111111111111111111111111111111111111111 \
            --expected-rejected-manifest-sha256 \
              2222222222222222222222222222222222222222222222222222222222222222 \
            --expected-selected-manifest-sha256 \
              3333333333333333333333333333333333333333333333333333333333333333 \
            --authorize-reason authority_target_mismatch
    ' 2>"$entry_error"; then
    fail 'real replacement entry fixture unexpectedly accepted a wrong resolution hash'
fi
if ! grep -Fq 'replacement resolution differs from the operator-authorized hash' \
    "$entry_error"; then
    sed 's/^/real-entry regression: /' "$entry_error" >&2
    fail 'real replacement entry did not reach sealed-input revalidation'
fi
if grep -Fq 'unbound variable' "$entry_error"; then
    fail 'real replacement entry still has a dynamic-scope unbound variable'
fi
[[ $(sha256sum "$entry_authority_root/release-authority-v2.json" | awk '{print $1}') \
    == "$entry_active_before" ]] \
    || fail 'real replacement entry changed the active authority before validation'
sudo -n test -f \
    "$entry_stage/resolution/release-authority-resolution-correction-v1.json" \
    || fail 'real replacement entry did not reseal the corrected inventory over stale r1 inputs'
for path in \
    "$entry_authority_root/authority-replacement-v1-install.json" \
    "$entry_authority_root/authority-replacement-v1-rollback.json" \
    "$entry_fixture/etc/syntaur/release-authority-replacement-v1.receipt.json"; do
    [[ ! -e $path && ! -L $path ]] \
        || fail 'real replacement entry created transaction state before validation'
done

state_fixture=$tmp_root/replacement-state-machine-fixture
state_authority_root=$state_fixture/etc/syntaur/release-authority
state_artifact_root=$state_authority_root/release-authority
state_runtime=$state_fixture/etc/syntaur/release-authority-replacement-v1.runtime
state_sources=$state_fixture/sources
state_operator_home=$state_fixture/home/operator
state_operator_state=$state_operator_home/.syntaur/ship
state_global_lock=$state_fixture/etc/syntaur/syntaur-ship-mutation.lock
state_shipper=$state_fixture/usr/local/bin/syntaur-ship
state_provisioner=$state_fixture/opt/syntaur-build-authority-provision
state_install_receipt=$state_fixture/etc/syntaur/release-authority-replacement-v1.receipt.json
state_rollback_receipt=$state_fixture/etc/syntaur/release-authority-replacement-v1.rollback-receipt.json
state_cosign=$state_fixture/bin/cosign
state_payload=$state_fixture/payload
install -d -m 0700 \
    "$state_sources/predecessor" "$state_sources/rejected" \
    "$state_sources/selected" "$state_sources/resolution" \
    "$state_operator_home" "$state_operator_home/.syntaur" \
    "$state_operator_state" "$state_operator_state/deploy-stamp.generations" \
    "$state_payload" "$(dirname "$state_cosign")"
install -d -m 0755 "$state_artifact_root" \
    "$(dirname "$state_global_lock")" "$(dirname "$state_shipper")" \
    "$(dirname "$state_provisioner")"
install -m 0555 /usr/bin/true \
    "$state_payload/syntaur-ship-linux-x86_64"
install -m 0555 /usr/bin/true \
    "$state_payload/syntaur-verify-linux-x86_64"
printf '#!/usr/bin/bash\nexit 0\n' \
    >"$state_payload/syntaur-build-authority-provision"
chmod 0555 "$state_payload/syntaur-build-authority-provision"
printf '#!/usr/bin/bash\nexit 0\n' >"$state_cosign"
chmod 0555 "$state_cosign"

state_pred_workflow=$(printf '1%.0s' {1..40})
state_selected_workflow=$(printf '2%.0s' {1..40})
state_rejected_workflow=$(printf '3%.0s' {1..40})
state_resolution_workflow=$(printf '4%.0s' {1..40})
state_pred_commit=$(printf '5%.0s' {1..40})
state_selected_commit=$(printf '6%.0s' {1..40})
state_rejected_commit=$(printf '7%.0s' {1..40})
state_rejected_product_commit=$(printf '8%.0s' {1..40})
state_gateway_commit=$(printf '9%.0s' {1..40})
state_engine_commit=$(printf 'a%.0s' {1..40})
state_selected_engine_commit=$(printf 'b%.0s' {1..40})
state_gateway_sha=$(digest_text state-gateway)
state_browser_sha=$(digest_text state-browser)
state_production_id=$(digest_text state-production)
state_deploy_generation="g-b-$(digest_text state-source)-$(digest_text state-engine)"
state_product_digest=$({
    printf '%s\0' syntaur-exact-terminal-production-state-v1
    printf '%s\0' 0.7.116 "$state_gateway_commit" "$state_engine_commit" \
        "$state_deploy_generation" "$state_gateway_sha" \
        "$state_browser_sha" "$state_production_id"
} | sha256sum | awk '{print $1}')
state_policy_digest=$(digest_text state-promotion-policy)

SHIPPER_SHA256=$(sha256sum "$state_payload/syntaur-ship-linux-x86_64" \
    | awk '{print $1}')
VERIFIER_SHA256=$(sha256sum "$state_payload/syntaur-verify-linux-x86_64" \
    | awk '{print $1}')
PROVISIONER_SHA256=$(sha256sum \
    "$state_payload/syntaur-build-authority-provision" | awk '{print $1}')
VERIFICATION_POLICY_REVISION=$(printf 'c%.0s' {1..40})
AUTHORITY_TREE_SHA256=$(digest_text state-authority-tree)
VERIFIER_TOOLCHAIN_ID=rust-1.94.1-x86_64-unknown-linux-gnu
VERIFIER_CARGO_SHA256=$(digest_text state-cargo)
VERIFIER_RUSTC_SHA256=$(digest_text state-rustc)
VERIFIER_RUSTDOC_SHA256=$(digest_text state-rustdoc)
BASELINE_PROFILE=mac-isolated-v1
BASELINE_GENERATION='generation-state'
BASELINE_TREE_SHA256=$(digest_text state-baseline)
BROWSER_BUNDLE_SHA256=$(digest_text state-browser-bundle)
BROWSER_VERSION='Google Chrome for Testing 131.0.6778.264'
BROWSER_LAUNCH_PROFILE_SHA256=$(digest_text state-browser-launch)
VERIFIER_SCHEMA=5
PRODUCTION_CONTRACT_SHA256=$(digest_text state-production-contract)
PRODUCTION_MEMBER_COUNT=12
RECEIPT_SCHEMA=6
BUILD_AUTHORITY_SCHEMA=4
PROMOTION_RECOVERY_SCHEMA=1
PROMOTION_RECOVERY_SHA256=$(digest_text state-promotion-recovery)
export SHIPPER_SHA256 VERIFIER_SHA256 PROVISIONER_SHA256
export VERIFICATION_POLICY_REVISION AUTHORITY_TREE_SHA256
export VERIFIER_TOOLCHAIN_ID VERIFIER_CARGO_SHA256 VERIFIER_RUSTC_SHA256
export VERIFIER_RUSTDOC_SHA256 BASELINE_PROFILE BASELINE_GENERATION
export BASELINE_TREE_SHA256 BROWSER_BUNDLE_SHA256 BROWSER_VERSION
export BROWSER_LAUNCH_PROFILE_SHA256 VERIFIER_SCHEMA
export PRODUCTION_CONTRACT_SHA256 PRODUCTION_MEMBER_COUNT RECEIPT_SCHEMA
export BUILD_AUTHORITY_SCHEMA PROMOTION_RECOVERY_SCHEMA PROMOTION_RECOVERY_SHA256

render_state_authority() {
    local directory=$1 generation=$2 previous_generation=$3 previous_sha=$4
    local workflow=$5 version=$6 authority_commit=$7
    AUTHORITY_GENERATION=$generation
    PREVIOUS_AUTHORITY_GENERATION=$previous_generation
    PREVIOUS_AUTHORITY_MANIFEST_SHA256=$previous_sha
    GITHUB_SHA=$workflow
    AUTHORITY_VERSION=$version
    AUTHORITY_COMMIT=$authority_commit
    export AUTHORITY_GENERATION PREVIOUS_AUTHORITY_GENERATION
    export PREVIOUS_AUTHORITY_MANIFEST_SHA256 GITHUB_SHA
    export AUTHORITY_VERSION AUTHORITY_COMMIT
    "$helper" render-v2 "$directory/release-authority-v2.json"
    install -m 0555 \
        "$state_payload/syntaur-build-authority-provision" \
        "$state_payload/syntaur-ship-linux-x86_64" \
        "$state_payload/syntaur-verify-linux-x86_64" "$directory/"
    printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","workflow":"%s"}\n' \
        "$workflow" >"$directory/release-authority-v2.json.cosign.bundle"
    chmod 0444 "$directory/release-authority-v2.json" \
        "$directory/release-authority-v2.json.cosign.bundle"
    "$helper" validate "$directory/release-authority-v2.json" 2 \
        "$generation" "$workflow" "$directory"
}

state_previous_sha=$(digest_text state-generation-58)
render_state_authority "$state_sources/predecessor" 59 58 \
    "$state_previous_sha" "$state_pred_workflow" 0.7.116 "$state_pred_commit"
state_pred_sha=$(sha256sum "$state_sources/predecessor/release-authority-v2.json" \
    | awk '{print $1}')
render_state_authority "$state_sources/rejected" 60 59 \
    "$state_pred_sha" "$state_rejected_workflow" 0.7.115 "$state_rejected_commit"
render_state_authority "$state_sources/selected" 60 59 \
    "$state_pred_sha" "$state_selected_workflow" 0.7.116 "$state_selected_commit"
state_rejected_sha=$(sha256sum "$state_sources/rejected/release-authority-v2.json" \
    | awk '{print $1}')
state_selected_sha=$(sha256sum "$state_sources/selected/release-authority-v2.json" \
    | awk '{print $1}')

state_tool=$state_runtime/recover-release-authority-replacement-v1.sh
state_helper=$state_sources/resolution/release-authority-manifest.sh
install -d -m 0700 "$state_runtime"
sed \
    -e "s|^readonly COSIGN=.*|readonly COSIGN=$state_cosign|" \
    -e "s|^readonly COSIGN_SHA256=.*|readonly COSIGN_SHA256=$(sha256sum "$state_cosign" | awk '{print $1}')|" \
    -e "s|^readonly AUTHORITY_ROOT=.*|readonly AUTHORITY_ROOT=$state_authority_root|" \
    -e "s|^readonly INSTALLED_SHIPPER=.*|readonly INSTALLED_SHIPPER=$state_shipper|" \
    -e "s|^readonly INSTALLED_PROVISIONER=.*|readonly INSTALLED_PROVISIONER=$state_provisioner|" \
    -e "s|^readonly GLOBAL_MUTATION_LOCK=.*|readonly GLOBAL_MUTATION_LOCK=$state_global_lock|" \
    -e "s|^readonly INSTALL_RECEIPT=.*|readonly INSTALL_RECEIPT=$state_install_receipt|" \
    -e "s|^readonly ROLLBACK_RECEIPT=.*|readonly ROLLBACK_RECEIPT=$state_rollback_receipt|" \
    -e "s|^readonly SEALED_RUNTIME_ROOT=.*|readonly SEALED_RUNTIME_ROOT=$state_runtime|" \
    -e "s|^    sync_path /etc/syntaur$|    sync_path $state_fixture/etc/syntaur|" \
    -e "s|^    operator_state=.*|    operator_state=$state_operator_state|" \
    "$recovery_tool" \
    | awk -v operator_home="$state_operator_home" '
        /^    operator_home=\$\(\/usr\/bin\/getent passwd/ {
            print "    operator_home=" operator_home
            replacing_lookup=1
            next
        }
        replacing_lookup {
            if (/sudo operator account lookup failed/) replacing_lookup=0
            next
        }
        /^run_operator_product_state_proof\(\) \{/ {
            print
            print "    :"
            replacing_proof=1
            next
        }
        replacing_proof {
            if (/^}/) {
                print
                replacing_proof=0
            }
            next
        }
        { print }
    ' >"$state_tool"
chmod 0500 "$state_tool"
install -m 0500 "$state_tool" \
    "$state_sources/resolution/recover-release-authority-replacement-v1.sh"
install -m 0500 "$helper" "$state_helper"

REPLACEMENT_PREDECESSOR_GENERATION=59
REPLACEMENT_PREDECESSOR_MANIFEST_SHA256=$state_pred_sha
REJECTED_AUTHORITY_GENERATION=60
REJECTED_AUTHORITY_MANIFEST_SHA256=$state_rejected_sha
REJECTED_AUTHORITY_WORKFLOW_COMMIT=$state_rejected_workflow
REJECTED_AUTHORITY_VERSION=0.7.115
REJECTED_AUTHORITY_COMMIT=$state_rejected_commit
REJECTED_PRODUCT_RELEASE_COMMIT=$state_rejected_product_commit
SELECTED_AUTHORITY_GENERATION=60
SELECTED_AUTHORITY_MANIFEST_SHA256=$state_selected_sha
SELECTED_AUTHORITY_WORKFLOW_COMMIT=$state_selected_workflow
SELECTED_AUTHORITY_VERSION=0.7.116
SELECTED_AUTHORITY_COMMIT=$state_selected_commit
SETTLED_PRODUCT_VERSION=0.7.116
SETTLED_PRODUCT_GATEWAY_COMMIT=$state_gateway_commit
SETTLED_PRODUCT_ENGINE_COMMIT=$state_engine_commit
SETTLED_PRODUCT_STATE_SHA256=$state_product_digest
SETTLED_PROMOTION_POLICY_SHA256=$state_policy_digest
SELECTED_ENGINE_COMMIT=$state_selected_engine_commit
PLANNED_PRODUCT_VERSION=0.7.117
PLANNED_PRODUCT_BASE_COMMIT=$state_selected_commit
RECOVERY_TOOL_SHA256=$(sha256sum "$state_tool" | awk '{print $1}')
MANIFEST_HELPER_SHA256=$(sha256sum "$state_helper" | awk '{print $1}')
RESOLUTION_WORKFLOW_COMMIT=$state_resolution_workflow
export REPLACEMENT_PREDECESSOR_GENERATION
export REPLACEMENT_PREDECESSOR_MANIFEST_SHA256
export REJECTED_AUTHORITY_GENERATION REJECTED_AUTHORITY_MANIFEST_SHA256
export REJECTED_AUTHORITY_WORKFLOW_COMMIT REJECTED_AUTHORITY_VERSION
export REJECTED_AUTHORITY_COMMIT REJECTED_PRODUCT_RELEASE_COMMIT
export SELECTED_AUTHORITY_GENERATION SELECTED_AUTHORITY_MANIFEST_SHA256
export SELECTED_AUTHORITY_WORKFLOW_COMMIT SELECTED_AUTHORITY_VERSION
export SELECTED_AUTHORITY_COMMIT SETTLED_PRODUCT_VERSION
export SETTLED_PRODUCT_GATEWAY_COMMIT SETTLED_PRODUCT_ENGINE_COMMIT
export SETTLED_PRODUCT_STATE_SHA256 SETTLED_PROMOTION_POLICY_SHA256
export SELECTED_ENGINE_COMMIT PLANNED_PRODUCT_VERSION PLANNED_PRODUCT_BASE_COMMIT
export RECOVERY_TOOL_SHA256 MANIFEST_HELPER_SHA256 RESOLUTION_WORKFLOW_COMMIT
"$helper" render-selection-review \
    "$state_sources/resolution/release-authority-selection-review-v1.json"
SELECTION_REVIEW_SHA256=$(sha256sum \
    "$state_sources/resolution/release-authority-selection-review-v1.json" \
    | awk '{print $1}')
export SELECTION_REVIEW_SHA256
state_correction=$state_sources/resolution/release-authority-resolution-correction-v1.json
jq -cjn \
    --arg pred_sha "$state_pred_sha" \
    --arg selected_sha "$state_selected_sha" \
    --arg product_sha "$state_product_digest" \
    --arg tool_sha "$RECOVERY_TOOL_SHA256" \
    --arg helper_sha "$MANIFEST_HELPER_SHA256" \
    --arg superseded_resolution_sha "$(digest_text state-superseded-resolution)" \
    --arg superseded_tool_sha "$(digest_text state-superseded-tool)" \
    --arg superseded_helper_sha "$(digest_text state-superseded-helper)" \
    '{schema:1,generation:60,resolution_revision:2,
      resolution_tag:"authority-resolution-v1-g60-r2",
      supersedes_resolution_tag:"authority-resolution-v1-g60",
      supersedes_resolution_sha256:$superseded_resolution_sha,
      superseded_resolution_workflow_commit:"1111111111111111111111111111111111111111",
      superseded_recovery_tool_sha256:$superseded_tool_sha,
      superseded_manifest_helper_sha256:$superseded_helper_sha,
      corrected_recovery_tool_sha256:$tool_sha,
      corrected_manifest_helper_sha256:$helper_sha,
      active_generation:59,active_manifest_sha256:$pred_sha,
      active_product_state_sha256:$product_sha,
      selected_manifest_sha256:$selected_sha,
      correction_reason:"recovery_tool_execution_failure",
      failure_class:"bash_dynamic_scope_unbound_operation",
      failure_stage:"sealed_input_revalidation",
      authority_mutated:false,product_state_mutated:false,
      normal_promotion_journal_present:false,
      normal_promotion_journal_temp_present:false,
      install_journal_present:false,install_journal_temp_present:false,
      rollback_journal_present:false,rollback_journal_temp_present:false,
      install_receipt_present:false,rollback_receipt_present:false,
      resolution_receipt_present:false}' >"$state_correction"
"$helper" validate-resolution-correction-review "$state_correction"
RESOLUTION_REVISION=2
SUPERSEDES_RESOLUTION_TAG=authority-resolution-v1-g60
SUPERSEDES_RESOLUTION_SHA256=$(jq -er '.supersedes_resolution_sha256' \
    "$state_correction")
SUPERSEDED_RECOVERY_TOOL_SHA256=$(jq -er '.superseded_recovery_tool_sha256' \
    "$state_correction")
CORRECTION_REVIEW_SHA256=$(sha256sum "$state_correction" | awk '{print $1}')
export RESOLUTION_REVISION SUPERSEDES_RESOLUTION_TAG
export SUPERSEDES_RESOLUTION_SHA256 SUPERSEDED_RECOVERY_TOOL_SHA256
export CORRECTION_REVIEW_SHA256
"$helper" render-replacement-resolution \
    "$state_sources/resolution/release-authority-replacement-v1.json"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' \
    >"$state_sources/resolution/release-authority-replacement-v1.json.cosign.bundle"
chmod 0400 "$state_sources/resolution/"*.json \
    "$state_sources/resolution/"*.bundle
"$helper" validate-replacement-resolution-assets "$state_sources/resolution"
state_resolution_sha=$(sha256sum \
    "$state_sources/resolution/release-authority-replacement-v1.json" \
    | awk '{print $1}')
RESOLUTION_SHA256=$state_resolution_sha
export RESOLUTION_SHA256
state_authorization=$state_runtime/release-authority-resolution-authorization-v1.json
"$helper" render-resolution-correction-authorization "$state_authorization"
chmod 0400 "$state_authorization"

state_stamp_root=$state_operator_state/deploy-stamp.generations/$state_deploy_generation
install -d -m 0700 "$state_stamp_root"
printf 'authorized\n' >"$state_stamp_root/AUTHORIZED.json"
jq -cjn \
    --arg version 0.7.116 --arg git_head "$state_gateway_commit" \
    --arg browser_git_head "$state_engine_commit" \
    --arg gateway_sha256 "$state_gateway_sha" \
    --arg browser_sha256 "$state_browser_sha" \
    --arg production_generation_id "$state_production_id" \
    '{version:$version,git_head:$git_head,browser_git_head:$browser_git_head,
      gateway_sha256:$gateway_sha256,browser_sha256:$browser_sha256,
      production_generation:{production_generation_id:$production_generation_id}}' \
    >"$state_stamp_root/deploy-stamp.json"
printf 'bundle\n' >"$state_stamp_root/deploy-stamp.json.cosign.bundle"
chmod 0400 "$state_stamp_root/"*
ln -s "deploy-stamp.generations/$state_deploy_generation" \
    "$state_operator_state/deploy-stamp.current"
ln -s deploy-stamp.current/deploy-stamp.json \
    "$state_operator_state/deploy-stamp.json"
ln -s deploy-stamp.current/deploy-stamp.json.cosign.bundle \
    "$state_operator_state/deploy-stamp.json.cosign.bundle"
printf '\n' >"$state_operator_state/deploy.lock"
chmod 0600 "$state_operator_state/deploy.lock"

sudo -n install -o 0 -g 0 -m 0444 \
    "$state_sources/predecessor/release-authority-v2.json" \
    "$state_authority_root/release-authority-v2.json"
sudo -n install -o 0 -g 0 -m 0444 \
    "$state_sources/predecessor/release-authority-v2.json.cosign.bundle" \
    "$state_authority_root/release-authority-v2.json.cosign.bundle"
sudo -n install -o 0 -g 0 -m 1755 \
    "$state_sources/predecessor/syntaur-ship-linux-x86_64" "$state_shipper"
sudo -n install -o 0 -g 0 -m 0755 \
    "$state_sources/predecessor/syntaur-build-authority-provision" \
    "$state_provisioner"
printf '%s\n' "$state_pred_workflow" >"$state_fixture/trusted-workflow-commit"
sudo -n install -o 0 -g 0 -m 0444 "$state_fixture/trusted-workflow-commit" \
    "$state_authority_root/trusted-workflow-commit"
: >"$state_global_lock"
sudo -n chown -R 0:0 "$state_fixture/etc" "$state_fixture/usr" \
    "$state_fixture/opt"
sudo -n chown "0:$(id -g)" "$state_global_lock"
sudo -n chmod 0440 "$state_global_lock"
sudo -n chown -R "$(id -u):$(id -g)" "$state_operator_home"
sudo -n chmod 0700 "$state_operator_home" "$state_operator_home/.syntaur" \
    "$state_operator_state" "$state_operator_state/deploy-stamp.generations" \
    "$state_stamp_root"
sudo -n chmod 0400 "$state_stamp_root/"*
sudo -n chmod 0600 "$state_operator_state/deploy.lock"

state_helpers=$state_fixture/recovery-state-functions.sh
sudo -n awk '
    /^\[\[ \$# -ge 1 \]\] \|\| usage$/ { exit }
    { print }
' "$state_tool" | sudo -n tee "$state_helpers" >/dev/null
sudo -n chmod 0500 "$state_helpers"
sudo -n env \
    STATE_HELPERS="$state_helpers" STATE_SOURCES="$state_sources" \
    STATE_PRED_SHA="$state_pred_sha" STATE_REJECTED_SHA="$state_rejected_sha" \
    STATE_SELECTED_SHA="$state_selected_sha" \
    STATE_RESOLUTION_SHA="$state_resolution_sha" \
    STATE_TOOL_SHA="$(sudo -n sha256sum "$state_tool" | awk '{print $1}')" \
    STATE_PRODUCT_SHA="$state_product_digest" \
    STATE_OPERATOR_HOME="$state_operator_home" \
    STATE_OPERATOR_STATE="$state_operator_state" \
    STATE_UID="$(id -u)" STATE_GID="$(id -g)" STATE_USER="$(id -un)" \
    /usr/bin/bash -c '
        set -euo pipefail
        source "$STATE_HELPERS"
        predecessor_dir=$STATE_SOURCES/predecessor
        rejected_dir=$STATE_SOURCES/rejected
        selected_dir=$STATE_SOURCES/selected
        resolution_dir=$STATE_SOURCES/resolution
        expected_resolution_sha256=$STATE_RESOLUTION_SHA
        expected_recovery_tool_sha256=$STATE_TOOL_SHA
        expected_predecessor_sha256=$STATE_PRED_SHA
        expected_rejected_sha256=$STATE_REJECTED_SHA
        expected_selected_sha256=$STATE_SELECTED_SHA
        SUDO_UID=$STATE_UID
        SUDO_GID=$STATE_GID
        SUDO_USER=$STATE_USER
        operator_home=$STATE_OPERATOR_HOME
        operator_state=$STATE_OPERATOR_STATE
        verify_resolution_correction_state install "$STATE_PRED_SHA"
        install_resolution_receipt
        stage_generation "$predecessor_dir" \
            "$(manifest_value "$predecessor_dir/$MANIFEST" workflow_commit)" 59
        publish_mutation_fence "$STATE_PRODUCT_SHA"
        write_install_journal prepared "$STATE_PRODUCT_SHA"
    '

run_state_recovery() {
    local operation=$1
    sudo -n env \
        STATE_TOOL="$state_tool" STATE_SOURCES="$state_sources" \
        STATE_TOOL_SHA="$(sudo -n sha256sum "$state_tool" | awk '{print $1}')" \
        STATE_RESOLUTION_SHA="$state_resolution_sha" \
        STATE_PRED_SHA="$state_pred_sha" STATE_REJECTED_SHA="$state_rejected_sha" \
        STATE_SELECTED_SHA="$state_selected_sha" \
        STATE_AUTHORIZATION="$state_authorization" \
        STATE_OPERATION="$operation" \
        STATE_UID="$(id -u)" STATE_GID="$(id -g)" STATE_USER="$(id -un)" \
        /usr/bin/unshare --uts --fork /usr/bin/bash -c '
            /usr/bin/hostname claudevm
            /usr/bin/env -i \
              SUDO_UID="$STATE_UID" SUDO_GID="$STATE_GID" SUDO_USER="$STATE_USER" \
              PATH=/usr/sbin:/usr/bin:/sbin:/bin \
              "$STATE_TOOL" "$STATE_OPERATION" \
                --predecessor-dir "$STATE_SOURCES/predecessor" \
                --rejected-dir "$STATE_SOURCES/rejected" \
                --selected-dir "$STATE_SOURCES/selected" \
                --resolution-dir "$STATE_SOURCES/resolution" \
                --expected-resolution-sha256 "$STATE_RESOLUTION_SHA" \
                --expected-recovery-tool-sha256 "$STATE_TOOL_SHA" \
                --expected-predecessor-manifest-sha256 "$STATE_PRED_SHA" \
                --expected-rejected-manifest-sha256 "$STATE_REJECTED_SHA" \
                --expected-selected-manifest-sha256 "$STATE_SELECTED_SHA" \
                --correction-authorization "$STATE_AUTHORIZATION" \
                --authorize-reason authority_target_mismatch
        '
}

run_state_recovery install
[[ $(sudo -n sha256sum "$state_authority_root/release-authority-v2.json" \
    | awk '{print $1}') == "$state_selected_sha" ]] \
    || fail 'schema-2 resumed install did not activate the selected authority'
sudo -n test -f "$state_install_receipt" \
    || fail 'schema-2 resumed install did not publish its receipt'
sudo -n test ! -e "$state_authority_root/authority-replacement-v1-install.json" \
    || fail 'schema-2 resumed install retained its journal'
sudo -n env \
    STATE_HELPERS="$state_helpers" STATE_SOURCES="$state_sources" \
    STATE_PRED_SHA="$state_pred_sha" STATE_SELECTED_SHA="$state_selected_sha" \
    /usr/bin/bash -c '
        set -euo pipefail
        source "$STATE_HELPERS"
        predecessor_dir=$STATE_SOURCES/predecessor
        rejected_dir=$STATE_SOURCES/rejected
        selected_dir=$STATE_SOURCES/selected
        resolution_dir=$STATE_SOURCES/resolution
        expected_predecessor_sha256=$STATE_PRED_SHA
        expected_selected_sha256=$STATE_SELECTED_SHA
        phase_shadow_probe() {
            local phase
            validate_rollback_phase_state prepared
        }
        phase_shadow_probe
    '
run_state_recovery install
run_state_recovery rollback
[[ $(sudo -n sha256sum "$state_authority_root/release-authority-v2.json" \
    | awk '{print $1}') == "$state_pred_sha" ]] \
    || fail 'schema-2 rollback did not restore the predecessor authority'
sudo -n test -f "$state_rollback_receipt" \
    || fail 'schema-2 rollback did not publish its receipt'
run_state_recovery rollback

digest_vector=$(/usr/bin/env RECOVERY_HELPERS="$root_helpers" /usr/bin/bash -c '
    source "$RECOVERY_HELPERS"
    product_state_digest_values \
        0.7.163 \
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
        cccccccccccccccccccccccccccccccccccccccc \
        g-b-dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee \
        ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
        1111111111111111111111111111111111111111111111111111111111111111 \
        2222222222222222222222222222222222222222222222222222222222222222
')
[[ $digest_vector == \
    c0787475847440227a948f3bf7d305c830a8fef6471a1cf1d3b354f29fb09997 ]] \
    || fail 'root recovery product-state digest differs from the Rust vector'
current_product_digest=$(/usr/bin/env RECOVERY_HELPERS="$root_helpers" /usr/bin/bash -c '
    source "$RECOVERY_HELPERS"
    product_state_digest_values \
        0.7.163 \
        cd7a62f518eab678e1cf14a454a6ddc20fe2117d \
        e10a0b11534254e9e38420ae06e368a9a7000f2a \
        g-b-6d2d55b6abeaa79fd313ce6cc986848b0878e5b96cccce4fa81b4869c3066acf-27a86ccdcc82070b7defc2713bda3c6e17579f6067795c9a9e95548c497b1a10 \
        57c78a9011fbad1896bcb445f96b27726259e6c505f85da9aff7c171e21503ab \
        ff9cb7fbaf31fe9dfe91b1eb76803654f2041b01a3a5cbc2b05a0f0631e6cb51 \
        ba812d6de7e80f875fa7e5ee0032d35e2370ee9a2592d9d34307ef767ad6874a
')
[[ $current_product_digest == \
    83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17 ]] \
    || fail 'root recovery current product-state digest differs from the reviewed vector'
for name in \
    release-authority-v2.json \
    release-authority-v2.json.cosign.bundle \
    syntaur-build-authority-provision \
    syntaur-ship-linux-x86_64 \
    syntaur-verify-linux-x86_64; do
    printf 'selected-%s\n' "$name" >"$root_fixture/material/$name"
done
chmod 0444 \
    "$root_fixture/material/release-authority-v2.json" \
    "$root_fixture/material/release-authority-v2.json.cosign.bundle"
chmod 0555 \
    "$root_fixture/material/syntaur-build-authority-provision" \
    "$root_fixture/material/syntaur-ship-linux-x86_64" \
    "$root_fixture/material/syntaur-verify-linux-x86_64"
sudo -n install -d -o 0 -g 0 -m 0755 \
    "$root_fixture/etc/syntaur/release-authority/release-authority"
sudo -n chown -R 0:0 "$root_fixture/material"
partial_stage=$root_fixture/etc/syntaur/release-authority/release-authority/.generation-60-authority-replacement-v1.staged
sudo -n install -d -o 0 -g 0 -m 0700 "$partial_stage"
sudo -n install -o 0 -g 0 -m 0600 \
    "$root_fixture/material/release-authority-v2.json" \
    "$partial_stage/release-authority-v2.json"
sudo -n chmod 0555 "$partial_stage"
sudo -n env RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        stage_generation "$ROOT_FIXTURE/material" \
            1111111111111111111111111111111111111111 60
    '
[[ $(find "$root_fixture/etc/syntaur/release-authority/release-authority/generation-60" \
    -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) == \
    $(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C sort) ]] \
    || fail 'partial generation stage did not recover to the exact inventory'

unsafe_stage=$root_fixture/etc/syntaur/release-authority/release-authority/.generation-61-authority-replacement-v1.staged
sudo -n install -d -o 0 -g 0 -m 0700 "$unsafe_stage"
sudo -n ln -s release-authority-v2.json \
    "$unsafe_stage/release-authority-v2.json"
expect_failure sudo -n env \
    RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        stage_generation "$ROOT_FIXTURE/material" \
            2222222222222222222222222222222222222222 61
    '
sudo -n rm -f -- "$unsafe_stage/release-authority-v2.json"
sudo -n rmdir -- "$unsafe_stage"

active_target=$root_fixture/etc/syntaur/release-authority/active-manifest.json
active_temporary=$active_target.authority-replacement-v1.tmp
printf 'predecessor\n' >"$tmp_root/predecessor-active"
sudo -n install -o 0 -g 0 -m 0444 "$tmp_root/predecessor-active" "$active_target"
sudo -n install -o 0 -g 0 -m 0600 "$tmp_root/predecessor-active" "$active_temporary"
selected_sha=$(sha256sum "$root_fixture/material/release-authority-v2.json" | awk '{print $1}')
predecessor_sha=$(sha256sum "$tmp_root/predecessor-active" | awk '{print $1}')
sudo -n env \
    RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    SELECTED_SHA="$selected_sha" PREDECESSOR_SHA="$predecessor_sha" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        publish_active_file \
            "$ROOT_FIXTURE/material/release-authority-v2.json" \
            "$ROOT_FIXTURE/etc/syntaur/release-authority/active-manifest.json" \
            "$SELECTED_SHA" "$PREDECESSOR_SHA" 444 "active manifest fixture"
    '
cmp "$root_fixture/material/release-authority-v2.json" "$active_target"
sudo -n install -o 0 -g 0 -m 0444 "$tmp_root/predecessor-active" "$active_target"
sudo -n ln -s "$root_fixture/material/release-authority-v2.json" "$active_temporary"
expect_failure sudo -n env \
    RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    SELECTED_SHA="$selected_sha" PREDECESSOR_SHA="$predecessor_sha" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        publish_active_file \
            "$ROOT_FIXTURE/material/release-authority-v2.json" \
            "$ROOT_FIXTURE/etc/syntaur/release-authority/active-manifest.json" \
            "$SELECTED_SHA" "$PREDECESSOR_SHA" 444 "active manifest fixture"
    '
sudo -n rm -f -- "$active_temporary"

mock_proof=$tmp_root/mock-product-state-proof.json
mock_shipper_source=$tmp_root/mock-syntaur-ship
mock_resolution=$root_fixture/resolution/release-authority-replacement-v1.json
selected_manifest_fixture=$(printf 'a%.0s' {1..64})
selected_commit_fixture=$(printf 'b%.0s' {1..40})
policy_fixture=5ee3b70e5d71abcb5a2fba970b9a9eb46c607eb43ce2f26ff759fa5daaf8522c
jq -cn \
    --arg installed_authority_manifest_sha256 "$selected_manifest_fixture" \
    --arg installed_authority_commit "$selected_commit_fixture" \
    --arg promotion_policy_sha256 "$policy_fixture" \
    '{schema:1,state:"exact_terminal_production",
      installed_authority_generation:60,
      installed_authority_manifest_sha256:$installed_authority_manifest_sha256,
      installed_authority_commit:$installed_authority_commit,
      product_version:"0.7.163",
      product_source_commit:"cd7a62f518eab678e1cf14a454a6ddc20fe2117d",
      product_engine_commit:"e10a0b11534254e9e38420ae06e368a9a7000f2a",
      deploy_stamp_generation:"g-b-6d2d55b6abeaa79fd313ce6cc986848b0878e5b96cccce4fa81b4869c3066acf-27a86ccdcc82070b7defc2713bda3c6e17579f6067795c9a9e95548c497b1a10",
      gateway_sha256:"57c78a9011fbad1896bcb445f96b27726259e6c505f85da9aff7c171e21503ab",
      browser_sha256:"ff9cb7fbaf31fe9dfe91b1eb76803654f2041b01a3a5cbc2b05a0f0631e6cb51",
      production_generation_id:"ba812d6de7e80f875fa7e5ee0032d35e2370ee9a2592d9d34307ef767ad6874a",
      product_state_sha256:"83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17",
      promotion_policy_sha256:$promotion_policy_sha256}' >"$mock_proof"
{
    printf '%s\n' '#!/usr/bin/bash' 'set -euo pipefail'
    printf '%s\n' '[[ $# -eq 11 ]]'
    printf '%s\n' '[[ $1 == authority-replacement-product-state ]]'
    printf '%s\n' '[[ $2 == --expected-installed-generation && $3 == 60 ]]'
    printf '%s\n' \
        '[[ $4 == --expected-installed-manifest-sha256 && $5 == aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]]'
    printf '%s\n' '[[ $6 == --expected-product-version && $7 == 0.7.163 ]]'
    printf '%s\n' \
        '[[ $8 == --expected-product-source-commit && $9 == cd7a62f518eab678e1cf14a454a6ddc20fe2117d ]]'
    printf '%s\n' \
        '[[ ${10} == --expected-product-engine-commit && ${11} == e10a0b11534254e9e38420ae06e368a9a7000f2a ]]'
    printf '/usr/bin/cat %q\n' "$mock_proof"
} >"$mock_shipper_source"
chmod 0555 "$mock_shipper_source"
mkdir -p "$root_fixture/resolution"
jq -cjn \
    --arg selected_authority_commit "$selected_commit_fixture" \
    --arg settled_promotion_policy_sha256 "$policy_fixture" \
    '{schema:2,resolution_revision:2,selected_generation:60,
      selected_authority_commit:$selected_authority_commit,
      settled_product_version:"0.7.163",
      settled_product_gateway_commit:"cd7a62f518eab678e1cf14a454a6ddc20fe2117d",
      settled_product_engine_commit:"e10a0b11534254e9e38420ae06e368a9a7000f2a",
      settled_promotion_policy_sha256:$settled_promotion_policy_sha256}' \
    >"$mock_resolution"
sudo -n install -d -o 0 -g 0 -m 0755 "$root_fixture/usr/local/bin"
sudo -n install -o 0 -g 0 -m 1755 "$mock_shipper_source" \
    "$root_fixture/usr/local/bin/syntaur-ship"
fixture_operator_home=$(getent passwd "$(id -u)" | awk -F: '{print $6}')
sudo -n env \
    RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_SELECTED="$selected_manifest_fixture" \
    OPERATOR_HOME="$fixture_operator_home" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_selected_sha256=$EXPECTED_SELECTED
        operator_home=$OPERATOR_HOME
        run_operator_product_state_proof \
            83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17
    '
[[ ! -e $root_fixture/etc/syntaur/release-authority/.authority-replacement-product-state-v1.tmp ]] \
    || fail 'validated product-state proof temporary was not retired'
jq -c '.settled_promotion_policy_sha256 = ("0" * 64)' "$mock_resolution" \
    >"$tmp_root/wrong-policy-resolution.json"
cp "$tmp_root/wrong-policy-resolution.json" "$mock_resolution"
expect_failure sudo -n env \
    RECOVERY_HELPERS="$root_helpers" ROOT_FIXTURE="$root_fixture" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_SELECTED="$selected_manifest_fixture" \
    OPERATOR_HOME="$fixture_operator_home" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_selected_sha256=$EXPECTED_SELECTED
        operator_home=$OPERATOR_HOME
        run_operator_product_state_proof \
            83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17
    '

mock_helper_source=$tmp_root/mock-authority-replacement-proof-helper
mock_proof_valid=$tmp_root/mock-product-state-proof-valid.json
proof_helper_root=$root_fixture/usr/local/libexec/syntaur-authority-replacement-proof-v1
proof_helper_stage=$root_fixture/usr/local/libexec/.syntaur-authority-replacement-proof-v1.staged
cp "$mock_proof" "$mock_proof_valid"
{
    printf '%s\n' '#!/usr/bin/bash' 'set -euo pipefail'
    printf '%s\n' '[[ $# -eq 1 ]]'
    printf '%s\n' '[[ $1 == authority-replacement-product-state-helper ]]'
    printf '/usr/bin/cat %q\n' "$mock_proof"
} >"$mock_helper_source"
chmod 0555 "$mock_helper_source"
mock_helper_sha256=$(sha256sum "$mock_helper_source" | awk '{print $1}')
jq -cjn \
    --arg selected_authority_commit "$selected_commit_fixture" \
    --arg settled_promotion_policy_sha256 "$policy_fixture" \
    --arg proof_helper_sha256 "$mock_helper_sha256" \
    '{schema:2,resolution_revision:3,selected_generation:60,
      selected_authority_commit:$selected_authority_commit,
      settled_product_version:"0.7.163",
      settled_product_gateway_commit:"cd7a62f518eab678e1cf14a454a6ddc20fe2117d",
      settled_product_engine_commit:"e10a0b11534254e9e38420ae06e368a9a7000f2a",
      settled_promotion_policy_sha256:$settled_promotion_policy_sha256,
      proof_helper_sha256:$proof_helper_sha256}' >"$mock_resolution"
printf 'r3 mock resolution bundle\n' \
    >"$root_fixture/resolution/release-authority-replacement-v1.json.cosign.bundle"
install -m 0555 "$mock_helper_source" \
    "$root_fixture/resolution/syntaur-authority-replacement-proof-linux-x86_64"
chmod 0444 "$mock_resolution" \
    "$root_fixture/resolution/release-authority-replacement-v1.json.cosign.bundle"
mock_resolution_sha256=$(sha256sum "$mock_resolution" | awk '{print $1}')
sudo -n install -d -o 0 -g 0 -m 0755 "$root_fixture/usr/local/libexec"

jq -c '.settled_promotion_policy_sha256 = ("0" * 64)' "$mock_proof_valid" \
    >"$mock_proof"
expect_failure sudo -n env \
    RECOVERY_HELPERS="$root_helpers" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_RESOLUTION="$mock_resolution_sha256" \
    EXPECTED_SELECTED="$selected_manifest_fixture" \
    OPERATOR_HOME="$fixture_operator_home" \
    FIXTURE_UID="$(id -u)" FIXTURE_GID="$(id -g)" FIXTURE_USER="$(id -un)" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_resolution_sha256=$EXPECTED_RESOLUTION
        expected_selected_sha256=$EXPECTED_SELECTED
        operator_home=$OPERATOR_HOME
        SUDO_UID=$FIXTURE_UID
        SUDO_GID=$FIXTURE_GID
        SUDO_USER=$FIXTURE_USER
        run_operator_product_state_proof \
            83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17
    '
if ! sudo -n test -f "$proof_helper_root/syntaur-ship"; then
    sed 's/^/r3 proof-helper regression: /' "$tmp_root/rejected.stderr" >&2
    fail 'r3 proof-helper failure did not preserve the installed helper for retry'
fi
[[ $(sudo -n stat -c '%u:%g:%a:%h' "$proof_helper_root/syntaur-ship") == \
    0:0:555:1 ]] || fail 'r3 installed proof helper identity differs after failure'
sudo -n test -f \
    "$root_fixture/etc/syntaur/release-authority/.authority-replacement-product-state-v1.tmp" \
    || fail 'r3 failed product proof did not preserve bounded failure evidence'

sudo -n install -d -o 0 -g 0 -m 0700 "$proof_helper_stage"
expect_failure sudo -n env \
    RECOVERY_HELPERS="$root_helpers" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_RESOLUTION="$mock_resolution_sha256" \
    EXPECTED_SELECTED="$selected_manifest_fixture" \
    OPERATOR_HOME="$fixture_operator_home" \
    FIXTURE_UID="$(id -u)" FIXTURE_GID="$(id -g)" FIXTURE_USER="$(id -un)" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_resolution_sha256=$EXPECTED_RESOLUTION
        expected_selected_sha256=$EXPECTED_SELECTED
        operator_home=$OPERATOR_HOME
        SUDO_UID=$FIXTURE_UID
        SUDO_GID=$FIXTURE_GID
        SUDO_USER=$FIXTURE_USER
        run_operator_product_state_proof \
            83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17
    '
sudo -n rmdir -- "$proof_helper_stage"

cp "$mock_proof_valid" "$mock_proof"
sudo -n env \
    RECOVERY_HELPERS="$root_helpers" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_RESOLUTION="$mock_resolution_sha256" \
    EXPECTED_SELECTED="$selected_manifest_fixture" \
    OPERATOR_HOME="$fixture_operator_home" \
    FIXTURE_UID="$(id -u)" FIXTURE_GID="$(id -g)" FIXTURE_USER="$(id -un)" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_resolution_sha256=$EXPECTED_RESOLUTION
        expected_selected_sha256=$EXPECTED_SELECTED
        operator_home=$OPERATOR_HOME
        SUDO_UID=$FIXTURE_UID
        SUDO_GID=$FIXTURE_GID
        SUDO_USER=$FIXTURE_USER
        run_operator_product_state_proof \
            83e8b033104254fceb46a9c70c14d7cc258d9e035986eff99215d7259023df17
    '
[[ ! -e $proof_helper_root && ! -L $proof_helper_root \
    && ! -e $proof_helper_stage && ! -L $proof_helper_stage ]] \
    || fail 'r3 proof helper was not retired after a successful retry'
[[ ! -e $root_fixture/etc/syntaur/release-authority/.authority-replacement-product-state-v1.tmp ]] \
    || fail 'r3 successful product proof did not retire prior failure evidence'

sudo -n install -d -o 0 -g 0 -m 0700 "$proof_helper_stage"
sudo -n install -o 0 -g 0 -m 0555 "$mock_helper_source" \
    "$proof_helper_stage/syntaur-ship"
sudo -n env \
    RECOVERY_HELPERS="$root_helpers" \
    RESOLUTION_FIXTURE="$root_fixture/resolution" \
    EXPECTED_RESOLUTION="$mock_resolution_sha256" \
    /usr/bin/bash -c '
        source "$RECOVERY_HELPERS"
        resolution_dir=$RESOLUTION_FIXTURE
        expected_resolution_sha256=$EXPECTED_RESOLUTION
        install_proof_helper
        retire_proof_helper
    '
[[ ! -e $proof_helper_root && ! -L $proof_helper_root \
    && ! -e $proof_helper_stage && ! -L $proof_helper_stage ]] \
    || fail 'r3 proof-helper retirement did not recover its partial quarantine'

r3_gate_resolution=$root_fixture/r3-gate-resolution
r3_gate_superseded=$root_fixture/etc/syntaur/release-authority-replacement-v1.runtime
r3_gate_origin=$r3_gate_superseded/inputs/resolution
r3_gate_receipt=$root_fixture/etc/syntaur/release-authority/replacement-resolution-v1/generation-60-r2
r3_gate_selected=$(digest_text r3-gate-selected)
r3_gate_product=$(digest_text r3-gate-product)
r3_gate_source=$tmp_root/r3-gate-source
install -d -m 0700 "$r3_gate_resolution" "$r3_gate_source"
printf '{"generation":60}\n' >"$r3_gate_source/release-authority-v2.json"
printf '{"phase":"manifest_published"}\n' \
    >"$r3_gate_source/authority-replacement-v1-install.json"
printf 'r3 gate promotion fence\n' \
    >"$r3_gate_source/authority-promotion-v1.json"
jq -cjn \
    --arg selected_manifest_sha256 "$r3_gate_selected" \
    '{schema:2,resolution_revision:2,selected_generation:60,
      selected_manifest_sha256:$selected_manifest_sha256,
      resolution_workflow_commit:"1111111111111111111111111111111111111111"}' \
    >"$r3_gate_source/release-authority-replacement-v1.json"
printf 'r3 gate origin bundle\n' \
    >"$r3_gate_source/release-authority-replacement-v1.json.cosign.bundle"
printf 'r3 gate selection\n' \
    >"$r3_gate_source/release-authority-selection-review-v1.json"
printf 'r3 gate r2 correction\n' \
    >"$r3_gate_source/release-authority-resolution-correction-v1.json"
r3_gate_origin_sha=$(sha256sum \
    "$r3_gate_source/release-authority-replacement-v1.json" | awk '{print $1}')
r3_gate_journal_sha=$(sha256sum \
    "$r3_gate_source/authority-replacement-v1-install.json" | awk '{print $1}')
jq -cjn \
    --arg supersedes_resolution_sha256 "$r3_gate_origin_sha" \
    '{schema:2,resolution_revision:3,selected_generation:60,
      supersedes_resolution_sha256:$supersedes_resolution_sha256}' \
    >"$r3_gate_resolution/release-authority-replacement-v1.json"
jq -cjn \
    --arg active_manifest_sha256 "$r3_gate_selected" \
    --arg active_product_state_sha256 "$r3_gate_product" \
    --arg active_install_journal_sha256 "$r3_gate_journal_sha" \
    --arg sealed_inputs_resolution_sha256 "$r3_gate_origin_sha" \
    '{active_generation:60,
      active_manifest_sha256:$active_manifest_sha256,
      active_product_state_sha256:$active_product_state_sha256,
      active_install_journal_sha256:$active_install_journal_sha256,
      active_install_journal_phase:"manifest_published",
      active_product_proof_temp_sha256:
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      active_product_proof_temp_size:0,
      sealed_inputs_resolution_sha256:$sealed_inputs_resolution_sha256}' \
    >"$r3_gate_resolution/release-authority-resolution-correction-v1.json"

sudo -n install -d -o 0 -g 0 -m 0700 \
    "$r3_gate_superseded" "$r3_gate_superseded/inputs" \
    "$r3_gate_origin" "$r3_gate_receipt"
for name in \
    release-authority-selection-review-v1.json \
    release-authority-resolution-correction-v1.json \
    release-authority-replacement-v1.json \
    release-authority-replacement-v1.json.cosign.bundle; do
    sudo -n install -o 0 -g 0 -m 0400 "$r3_gate_source/$name" \
        "$r3_gate_origin/$name"
    sudo -n install -o 0 -g 0 -m 0444 "$r3_gate_source/$name" \
        "$r3_gate_receipt/$name"
done
sudo -n install -o 0 -g 0 -m 0444 \
    "$r3_gate_source/release-authority-v2.json" \
    "$root_fixture/etc/syntaur/release-authority/release-authority-v2.json"
sudo -n install -o 0 -g 0 -m 0444 \
    "$r3_gate_source/authority-promotion-v1.json" \
    "$root_fixture/etc/syntaur/release-authority/authority-promotion-v1.json"
sudo -n install -o 0 -g 0 -m 0444 \
    "$r3_gate_source/authority-replacement-v1-install.json" \
    "$root_fixture/etc/syntaur/release-authority/authority-replacement-v1-install.json"
sudo -n install -o 0 -g 0 -m 0600 /dev/null \
    "$root_fixture/etc/syntaur/release-authority/.authority-replacement-product-state-v1.tmp"

sudo -n env \
    RECOVERY_HELPERS="$root_helpers" \
    R3_GATE_RESOLUTION="$r3_gate_resolution" \
    R3_GATE_SELECTED="$r3_gate_selected" R3_GATE_PRODUCT="$r3_gate_product" \
    /usr/bin/bash -c '
        set -euo pipefail
        source "$RECOVERY_HELPERS"
        resolution_dir=$R3_GATE_RESOLUTION
        expected_selected_sha256=$R3_GATE_SELECTED
        product_state_digest() { printf "%s\n" "$R3_GATE_PRODUCT"; }
        validate_resolution_inline() { :; }
        verify_cosign() { :; }
        validate_mutation_fence() { fence_validations=$((fence_validations + 1)); }
        validate_current_install_state() { install_validations=$((install_validations + 1)); }
        validate_selected_active() { selected_validations=$((selected_validations + 1)); }
        fence_validations=0
        install_validations=0
        selected_validations=0

        verify_resolution_correction_state install "$R3_GATE_SELECTED"
        [[ $fence_validations -eq 1 && $install_validations -eq 1 \
            && $selected_validations -eq 1 ]]

        rollback_error=$R3_GATE_RESOLUTION/rollback.error
        if ( verify_resolution_correction_state rollback "$R3_GATE_SELECTED" ) \
            2>"$rollback_error"; then
            printf "r3 state gate accepted rollback\n" >&2
            exit 1
        fi
        grep -Fq "forward completion only" "$rollback_error"

        printf "{\"phase\":\"prepared\"}\n" >"$INSTALL_JOURNAL"
        journal_error=$R3_GATE_RESOLUTION/journal.error
        if ( verify_resolution_correction_state install "$R3_GATE_SELECTED" ) \
            2>"$journal_error"; then
            printf "r3 state gate accepted a changed install journal\n" >&2
            exit 1
        fi
        grep -Fq "install journal differs from the reviewed failure" \
            "$journal_error"
    '
sudo -n rm -rf -- "$root_fixture"
root_fixture=

export RUNNER_TEMP=$tmp_root
for step_name in \
    'Verify immutable predecessor and choose exact successor' \
    'Recover draft and publish immutable exact successor'; do
    embedded_step="$tmp_root/embedded-$RANDOM.sh"
    embedded_lookup="$tmp_root/release-by-tag-$RANDOM.sh"
    yq -r \
        ".jobs[].steps[]? | select(.name == \"$step_name\") | .run" \
        "$workflow" >"$embedded_step"
    awk '
        /^release_by_tag\(\) \{$/ { copying=1 }
        copying { print }
        copying && /^}$/ { exit }
    ' "$embedded_step" >"$embedded_lookup"
    [[ -s $embedded_lookup ]] || fail "missing release_by_tag in $step_name"
    # shellcheck disable=SC1090 # The function is extracted from the workflow under test.
    source "$embedded_lookup"

    inventory="$tmp_root/inventory-$RANDOM.jsons"
    output="$tmp_root/release-$RANDOM.json"
    printf '%s\n' \
        '{"id":1,"tag_name":"authority-v1-g1"}' \
        '{"id":2,"tag_name":"authority-v1-g1"}' >"$inventory"
    if status=$(release_by_tag \
        "$inventory" authority-v1-g1 "$output" 2>"$tmp_root/duplicate.error"); then
        fail "$step_name accepted duplicate exact-tag releases as $status"
    fi
    grep -Fq 'duplicate release records' "$tmp_root/duplicate.error"
    printf '{malformed\n' >"$inventory"
    if status=$(release_by_tag \
        "$inventory" authority-v1-g1 "$output" 2>"$tmp_root/malformed.error"); then
        fail "$step_name inferred $status from a failed release inventory parse"
    fi
    unset -f release_by_tag
done

retry_step="$tmp_root/publish-consistency-step.sh"
retry_function="$tmp_root/publish-consistency-function.sh"
yq -r \
    '.jobs[].steps[]? |
     select(.name == "Recover draft and publish immutable exact successor") |
     .run' "$workflow" >"$retry_step"
awk '
    /^snapshot_authority_namespace_consistent\(\) \{$/ { copying=1 }
    copying { print }
    copying && /^}$/ { exit }
' "$retry_step" >"$retry_function"
[[ -s $retry_function ]] || fail 'missing namespace consistency retry'
# shellcheck disable=SC1090 # Function is extracted from the workflow under test.
source "$retry_function"
retry_calls=0
# shellcheck disable=SC2317,SC2329 # Called indirectly by the extracted retry function.
snapshot_authority_namespace() {
    retry_calls=$((retry_calls + 1))
    (( retry_calls >= 3 ))
}
# shellcheck disable=SC2317,SC2329 # Called indirectly by the extracted retry function.
sleep() { :; }
snapshot_authority_namespace_consistent "$tmp_root/retry-inventory"
[[ $retry_calls -eq 3 ]] \
    || fail 'namespace consistency retry did not recover after convergence'
unset -f snapshot_authority_namespace snapshot_authority_namespace_consistent sleep

printf 'release authority workflow fixture tests passed\n'
