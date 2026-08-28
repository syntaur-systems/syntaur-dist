#!/usr/bin/env bash
# shellcheck disable=SC2016 # Static workflow probes intentionally match literal expressions.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/release-authority-manifest.sh"
tmp_root=$(mktemp -d)
cleanup() {
    if [[ -n ${root_fixture:-} \
        && $root_fixture == "$tmp_root/root-fixture" \
        && ( -e $root_fixture || -L $root_fixture ) ]]; then
        sudo -n rm -rf -- "$root_fixture" 2>/dev/null || true
    fi
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
BASELINE_GENERATION=generation-1
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

: >"$tmp_root/empty-special-tags"
"$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 0 "$tmp_root/empty-special-tags"
printf '%s\n' authority-replacement-v1-g1 authority-replacement-v1-g60 \
    >"$tmp_root/bounded-replacement-tags"
"$helper" validate-special-tag-namespace \
    authority-replacement-v1-g 60 "$tmp_root/bounded-replacement-tags"
printf '%s\n' authority-resolution-v1-g60 \
    >"$tmp_root/bounded-resolution-tags"
"$helper" validate-special-tag-namespace \
    authority-resolution-v1-g 60 "$tmp_root/bounded-resolution-tags"
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
recovery_tool="$repo_root/scripts/recover-release-authority-replacement-v1.sh"
[[ $(yq -r '.on.workflow_dispatch.inputs | length' "$workflow") == 1 ]]
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
grep -Fq 'git -C source rev-parse "${AUTHORITY_COMMIT}^"' "$workflow"
grep -Fq 'authority-protocol-inputs' "$workflow"
grep -Fq -- '--authority-protocol-self-test' "$workflow"
grep -Fq 'shipper-self-test.json' "$workflow"
grep -Fq 'YQ_VERSION: v4.53.2' "$workflow"
grep -Fq \
    'YQ_LINUX_AMD64_SHA256: d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b' \
    "$workflow"
grep -Fq -- '--network none' "$workflow"
grep -Fq 'release-authority-source' "$workflow"
grep -Fq 'SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY' "$workflow"
grep -Fq 'sudo chown -R 65534:65534 source' "$workflow"
grep -Fq 'encrypted-authority-source-run-' "$workflow"
[[ $(grep -Fc -- '--repo "$GITHUB_REPOSITORY"' "$workflow") -eq 22 ]]
grep -Fq 'mkdir -m 0700 "$age_root/bin"' "$workflow"
grep -Fq '"$age_root/bin/"' "$workflow"
grep -Fq '"$age_root/bin/age-keygen" -y -' "$workflow"
grep -Fq '"$age_root/bin/age"' "$workflow"
grep -Fq 'mv encrypted-source-artifacts encrypted-source' "$workflow"
grep -Fq 'mv reviewed-candidate-artifacts candidate' "$workflow"
grep -Fq 'mv signed-authority-artifacts signed-authority' "$workflow"
if grep -Fq 'Sign exact replacement resolution' "$workflow"; then
    fail 'initial authority signer still signs a replacement resolution'
fi
grep -Fq 'authority-replacement-v1-g${generation}' "$workflow"
grep -Fq 'authority-resolution-v1-g${GENERATION}' "$workflow"
grep -Fq 'validate-replacement-resolution-assets' "$workflow"
grep -Fq 'rejected_product_release_commit' "$workflow"
grep -Fq 'resolution_policy:' "$workflow"
grep -Fq 'recover_sign_resolution:' "$workflow"
grep -Fq 'recover_publish_resolution:' "$workflow"
grep -Fq 'resolution_workflow_commit' "$workflow"
grep -Fq 'release-authority-selection-review-v1.json' "$workflow"
grep -Fq 'SELECTION_REVIEW_SHA256' "$workflow"
grep -Fq 'SETTLED_PROMOTION_POLICY_SHA256' "$workflow"
grep -Fq 'target_already_published' "$workflow"
grep -Fq 'special_namespace_max=$previous' "$workflow"
grep -Fq 'validate-special-tag-namespace' "$workflow"
grep -Fq 'assert-replacement' "$recovery_tool"
grep -Fq 'SEALED_RUNTIME_ROOT=/etc/syntaur/release-authority-replacement-v1.runtime' \
    "$recovery_tool"
grep -Fq 'seal_install_inputs' "$recovery_tool"
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
    >"$root_helpers"
chmod 0500 "$root_helpers"
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
    '{selected_generation:60,
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
