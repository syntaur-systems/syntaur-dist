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
for action in "${actions[@]}"; do
  [[ "$action" =~ ^[^[:space:]@]+/[^@]+@[0-9a-f]{40}$ ]] || {
    echo "workflow action is not pinned to a full commit: $action" >&2
    exit 1
  }
done

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
  yq -r '.jobs[].steps[]? | select(.uses == "sigstore/cosign-installer@398d4b0eeef1380460a10c8013a76f728fb906ac") | .with["cosign-release"]' "$workflow"
)
[ "${#cosign_releases[@]}" -eq 1 ] && [ "${cosign_releases[0]}" = v2.5.2 ] || {
  echo "release workflow must pin exactly one Cosign v2.5.2 installer" >&2
  exit 1
}

# The authority promotion is a separate, manually approved workflow. Validate
# its toolchain independently so adding the frozen-authority build cannot
# silently weaken the product-release pins or trip a repository-wide count.
authority_workflow=.github/workflows/release-authority.yml
if [ -f "$authority_workflow" ]; then
  mapfile -t authority_toolchains < <(
    yq -r '.jobs[].steps[]? | select(.uses == "dtolnay/rust-toolchain@fa04a1451ff1842e2626ccb99004d0195b455a88") | .with.toolchain' \
      "$authority_workflow"
  )
  [ "${#authority_toolchains[@]}" -eq 1 ] && [ "${authority_toolchains[0]}" = 1.94.1 ] || {
    echo "authority workflow must pin exactly one Rust 1.94.1 toolchain step" >&2
    exit 1
  }

  mapfile -t authority_cosign_releases < <(
    yq -r '.jobs[].steps[]? | select(.uses == "sigstore/cosign-installer@398d4b0eeef1380460a10c8013a76f728fb906ac") | .with["cosign-release"]' \
      "$authority_workflow"
  )
  [ "${#authority_cosign_releases[@]}" -eq 1 ] && [ "${authority_cosign_releases[0]}" = v2.5.2 ] || {
    echo "authority workflow must pin exactly one Cosign v2.5.2 installer" >&2
    exit 1
  }
fi

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
