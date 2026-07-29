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
if [ "${#cosign_releases[@]}" -ne 1 ] \
  || [ "${cosign_releases[0]:-}" != v2.5.2 ]; then
  echo "release workflow must pin exactly one Cosign v2.5.2 installer" >&2
  exit 1
fi

# Authority candidates build inside one architecture-specific Rust image pinned
# by digest. Generic checks below reject future jobs that recombine authority.
authority_workflow=.github/workflows/release-authority.yml
if [ -f "$authority_workflow" ]; then
  mapfile -t authority_toolchains < <(
    yq -r '.jobs[].steps[]? | select(.uses == "dtolnay/rust-toolchain@fa04a1451ff1842e2626ccb99004d0195b455a88") | .with.toolchain' \
      "$authority_workflow"
  )
  [ "${#authority_toolchains[@]}" -eq 0 ] || {
    echo "authority workflow must use only its digest-pinned container toolchain" >&2
    exit 1
  }

  mapfile -t authority_cosign_releases < <(
    yq -r '.jobs[].steps[]? | select(.uses == "sigstore/cosign-installer@398d4b0eeef1380460a10c8013a76f728fb906ac") | .with["cosign-release"]' \
      "$authority_workflow"
  )
  [ "${#authority_cosign_releases[@]}" -eq 3 ] || {
    echo "authority workflow must pin Cosign in predecessor, signer, and publisher jobs" >&2
    exit 1
  }
  for cosign_release in "${authority_cosign_releases[@]}"; do
    [ "$cosign_release" = v2.5.2 ] || {
      echo "authority Cosign release is not v2.5.2: $cosign_release" >&2
      exit 1
    }
  done

  authority_builder=$(yq -r '.env.AUTHORITY_BUILDER_IMAGE' "$authority_workflow")
  [[ "$authority_builder" =~ ^rust@sha256:[0-9a-f]{64}$ ]] || {
    echo "authority builder is not pinned to an exact Rust image digest" >&2
    exit 1
  }

  [ "$(yq -r '.permissions | length' "$authority_workflow")" = 0 ]
  [ "$(yq -r '.on | has("push")' .github/workflows/workflow-lint.yml)" = true ]
  [ "$(yq -r '.on | has("pull_request")' .github/workflows/workflow-lint.yml)" = true ]

  oidc_writers=$(yq -r '
    .jobs | to_entries[] |
    select(.value.permissions."id-token" == "write") |
    .key
  ' "$authority_workflow")
  [ "$oidc_writers" = sign ] || {
    echo "only sign may hold OIDC write authority: $oidc_writers" >&2
    exit 1
  }
  contents_writers=$(yq -r '
    .jobs | to_entries[] |
    select(.value.permissions.contents == "write") |
    .key
  ' "$authority_workflow")
  [ -z "$contents_writers" ] || {
    echo "GITHUB_TOKEN contents-write authority is forbidden: $contents_writers" >&2
    exit 1
  }
  yq -e '
    [.jobs | to_entries[] |
      select(
        .value.permissions."id-token" == "write" and
        .value.permissions.contents == "write"
      )] | length == 0
  ' "$authority_workflow" >/dev/null

  jobs_json=$(yq -o=json '.jobs' "$authority_workflow")
  jq -e '
    all(.[]; (.permissions | type) == "object") and
    ([
      to_entries[] as $job |
      $job.value.permissions | to_entries[] |
      select(.value == "write") |
      {job:$job.key, permission:.key}
    ] == [{job:"sign", permission:"id-token"}])
  ' <<<"$jobs_json" >/dev/null || {
    echo "job permissions contain unrecognized or recombined write authority" >&2
    exit 1
  }
  deploy_key_jobs=$(jq -r '
    to_entries[] |
    select(.value | tostring | contains("secrets.SYNTAUR_SOURCE_DEPLOY_KEY")) |
    .key
  ' <<<"$jobs_json")
  [ "$deploy_key_jobs" = source_metadata ] || {
    echo "private-source deploy key escaped its credential-only job: $deploy_key_jobs" >&2
    exit 1
  }
  candidate_and_deploy_key_jobs=$(jq -r '
    to_entries[] |
    select(
      (.value | tostring | contains("secrets.SYNTAUR_SOURCE_DEPLOY_KEY")) and
      (
        (.value | tostring | contains("cargo build")) or
        (.value | tostring | contains("cargo test")) or
        (.value | tostring | contains("syntaur-ship authority-protocol-inputs")) or
        (.value | tostring | contains("syntaur-verify --authority-protocol-self-test"))
      )
    ) |
    .key
  ' <<<"$jobs_json")
  [ -z "$candidate_and_deploy_key_jobs" ] || {
    echo "a deploy-key job executes candidate code: $candidate_and_deploy_key_jobs" >&2
    exit 1
  }
  age_secret_jobs=$(jq -r '
    to_entries[] |
    select(.value | tostring | contains("SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY")) |
    .key
  ' <<<"$jobs_json")
  [ "$age_secret_jobs" = isolated_build ] || {
    echo "source decryption identity escaped isolated_build: $age_secret_jobs" >&2
    exit 1
  }
  [ "$(grep -o 'secrets.SYNTAUR_SOURCE_ARCHIVE_AGE_IDENTITY' \
    "$authority_workflow" | wc -l)" -eq 1 ]
  publisher_secret_jobs=$(jq -r '
    to_entries[] |
    select(
      .value |
      tostring |
      contains("SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_")
    ) |
    .key
  ' <<<"$jobs_json")
  [ "$publisher_secret_jobs" = publish ] || {
    echo "publisher credential escaped its protected job: $publisher_secret_jobs" >&2
    exit 1
  }
  [ "$(grep -o 'secrets.SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_CLIENT_ID' \
    "$authority_workflow" | wc -l)" -eq 1 ]
  [ "$(grep -o 'secrets.SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_PRIVATE_KEY' \
    "$authority_workflow" | wc -l)" -eq 1 ]
  [ "$(yq -r '.jobs.predecessor.permissions.attestations' \
    "$authority_workflow")" = read ] || {
    echo "predecessor lacks read access to release attestations" >&2
    exit 1
  }
  publisher_attestations=$(yq -r '
    .jobs.publish.steps[]? |
    select(.uses == "actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1") |
    .with."permission-attestations"
  ' "$authority_workflow")
  [ "$publisher_attestations" = read ] || {
    echo "publisher App token lacks read access to release attestations" >&2
    exit 1
  }
  [ "$(yq -r '.jobs.repository_policy.environment' "$authority_workflow")" \
    = release-authority-source ]
  [ "$(yq -r '.jobs.source_metadata.environment' "$authority_workflow")" \
    = release-authority-source ]
  [ "$(yq -r '.jobs.isolated_build.environment' "$authority_workflow")" \
    = release-authority-source ]
  [ "$(yq -r '.jobs.approval_policy.environment' "$authority_workflow")" \
    = release-authority ]
  [ "$(yq -r '.jobs.publish.environment' "$authority_workflow")" \
    = release-authority ]

  signer=$(yq -r '.jobs.sign.steps[]? | select(has("run")) | .run' "$authority_workflow")
  publisher=$(yq -r '.jobs.publish.steps[]? | select(has("run")) | .run' "$authority_workflow")
  [[ "$signer" != *'syntaur-ship authority-protocol-inputs'* ]]
  [[ "$signer" != *'--authority-protocol-self-test'* ]]
  [[ "$publisher" != *'syntaur-ship authority-protocol-inputs'* ]]
  [[ "$publisher" != *'--authority-protocol-self-test'* ]]
fi

temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
for syntax_workflow in "$workflow" "$authority_workflow"; do
  count=$(yq -r \
    '[.jobs[].steps[]? | select(has("run")) |
      select(.shell != "pwsh" and .shell != "powershell")] | length' \
    "$syntax_workflow")
  for ((index = 0; index < count; index++)); do
    yq -r \
      "[.jobs[].steps[]? | select(has(\"run\")) |
        select(.shell != \"pwsh\" and .shell != \"powershell\")][$index].run" \
      "$syntax_workflow" >"$temporary"
    bash -n "$temporary"
  done
  printf 'validated %s Bash run blocks in %s\n' "$count" "$syntax_workflow"
done

bash scripts/test-release-workflow-recovery.sh "$workflow"
authority_scripts=(
  scripts/bootstrap-release-authority-genesis-v2.sh
  scripts/fixtures/release_authority_bootstrap_driver.sh
  scripts/fixtures/release_authority_fake_cosign.sh
  scripts/release-authority-manifest.sh
  scripts/test-release-authority-bootstrap.sh
  scripts/test-release-authority-workflow.sh
  scripts/validate-release-workflow.sh
  scripts/verify-release-authority-policy.sh
)
for authority_script in "${authority_scripts[@]}"; do
  bash -n "$authority_script"
  shellcheck "$authority_script"
done
