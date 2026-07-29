#!/usr/bin/env bash
# shellcheck disable=SC2016 # Static workflow probes intentionally match literal expressions.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/release-authority-manifest.sh"
tmp_root=$(mktemp -d)
cleanup() {
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
export AUTHORITY_VERSION AUTHORITY_COMMIT AUTHORITY_TREE_SHA256
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
jq -c 'del(.promotion_recovery_sha256)' "$tmp_root/approval-record.json" \
    >"$tmp_root/approval-record-missing.json"
expect_failure "$helper" validate-approval-record "$tmp_root/approval-record-missing.json"
printf '%s\n' "$(<"$tmp_root/approval-record.json")" \
    >"$tmp_root/approval-record-newline.json"
expect_failure "$helper" validate-approval-record "$tmp_root/approval-record-newline.json"

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

workflow="$repo_root/.github/workflows/release-authority.yml"
[[ $(yq -r '.on.workflow_dispatch.inputs | length' "$workflow") == 1 ]]
grep -Fq 'approval_record:' "$workflow"
for required in \
    provisioner_sha256 \
    production_contract_sha256 \
    production_member_count \
    receipt_schema \
    build_authority_schema \
    promotion_recovery_schema \
    promotion_recovery_sha256; do
    grep -Fq "$required" "$workflow"
done
grep -Fq 'authority-protocol-inputs' "$workflow"
grep -Fq -- '--authority-protocol-self-test' "$workflow"
grep -Fq -- '--network none' "$workflow"
grep -Fq 'release-authority-source' "$workflow"
grep -Fq 'SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY' "$workflow"
grep -Fq 'encrypted-authority-source-run-' "$workflow"
grep -Fq 'assert-genesis' "$workflow"
grep -Fq 'draft' "$workflow"
grep -Fq 'snapshot_authority_namespace' "$workflow"
grep -Fq 'permission-attestations: read' "$workflow"
grep -Fq '"/repos/${GITHUB_REPOSITORY}/releases?per_page=100"' "$workflow"
grep -Fq 'release=$(gh api --method POST' "$workflow"
grep -Fq 'generation=$((EXPECTED_PREVIOUS_GENERATION + 1))' "$workflow"
if grep -Eq 'generation=.*(github\\.run_id|GITHUB_RUN_ID)' "$workflow"; then
    fail 'authority generation derives from a workflow run ID'
fi
if grep -Fq 'python' "$workflow"; then
    fail 'authority workflow must not depend on Python'
fi

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

printf 'release authority workflow fixture tests passed\n'
