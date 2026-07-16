#!/usr/bin/env bash
set -euo pipefail

workflow=${1:-.github/workflows/release-sign.yml}
command -v actionlint >/dev/null
command -v yq >/dev/null

shopt -s nullglob
workflow_files=(.github/workflows/*.yml .github/workflows/*.yaml)
(( ${#workflow_files[@]} > 0 ))
actionlint "${workflow_files[@]}"

mapfile -t actions < <(
  for workflow_file in "${workflow_files[@]}"; do
    yq -r '.jobs[].steps[]? | select(has("uses")) | .uses' "$workflow_file"
  done
)
rust_action_count=0
cosign_action_count=0
for action in "${actions[@]}"; do
  [[ "$action" =~ ^[^[:space:]@]+/[^@]+@[0-9a-f]{40}$ ]] || {
    echo "workflow action is not pinned to a full commit: $action" >&2
    exit 1
  }
  case "$action" in
    dtolnay/rust-toolchain@*) rust_action_count=$(( rust_action_count + 1 )) ;;
    sigstore/cosign-installer@*) cosign_action_count=$(( cosign_action_count + 1 )) ;;
  esac
done
[ "$rust_action_count" -eq 2 ] || {
  echo "release workflow must contain exactly two Rust toolchain actions" >&2
  exit 1
}
[ "$cosign_action_count" -eq 1 ] || {
  echo "release workflow must contain exactly one Cosign installer action" >&2
  exit 1
}

mapfile -t toolchains < <(
  yq -r '.jobs[].steps[]? | select(.uses == "dtolnay/rust-toolchain@fa04a1451ff1842e2626ccb99004d0195b455a88") | .with.toolchain' "$workflow"
)
(( ${#toolchains[@]} == 2 )) || {
  echo "release workflow must contain exactly two pinned Rust toolchain steps" >&2
  exit 1
}
for toolchain in "${toolchains[@]}"; do
  [ "$toolchain" = 1.94.1 ] || {
    echo "release Rust toolchain is not pinned to 1.94.1: $toolchain" >&2
    exit 1
  }
done

mapfile -t cosign_releases < <(
  yq -r '.jobs[].steps[]? | select(.uses == "sigstore/cosign-installer@f713795cb21599bc4e5c4b58cbad1da852d7eeb9") | .with["cosign-release"]' "$workflow"
)
[ "${#cosign_releases[@]}" -eq 1 ] && [ "${cosign_releases[0]}" = v2.5.2 ] || {
  echo "release workflow must pin exactly one Cosign v2.5.2 installer" >&2
  exit 1
}

count=$(yq -r '[.jobs[].steps[]? | select(has("run")) | select(.shell != "pwsh")] | length' "$workflow")
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
for ((index = 0; index < count; index++)); do
  yq -r "[.jobs[].steps[]? | select(has(\"run\")) | select(.shell != \"pwsh\")][$index].run" \
    "$workflow" >"$temporary"
  bash -n "$temporary"
done

printf 'validated %s Bash run blocks in %s\n' "$count" "$workflow"
bash scripts/test-release-workflow-recovery.sh "$workflow"
