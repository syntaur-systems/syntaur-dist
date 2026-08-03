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

process_inspector_harness=scripts/test-process-inspector-install-container.sh
expected_process_inspector_image='image=ubuntu@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54'
expected_process_inspector_cap_add="  --cap-add=SYS_PTRACE \\"
expected_process_inspector_mount="  --mount \"type=bind,src=\$repository,dst=/repo,readonly\" \\"
image_count=$(grep -Fxc -- \
  "$expected_process_inspector_image" "$process_inspector_harness" || true)
[ "$image_count" -eq 1 ] || {
  echo "process inspector test image is not pinned to the reviewed digest" >&2
  exit 1
}
cap_add_count=$(grep -Ec -- \
  '^[[:space:]]*--cap-add=' "$process_inspector_harness" || true)
exact_cap_count=$(grep -Fxc -- \
  "$expected_process_inspector_cap_add" "$process_inspector_harness" || true)
if [ "$cap_add_count" -ne 1 ] || [ "$exact_cap_count" -ne 1 ]; then
  echo "process inspector harness must add only SYS_PTRACE" >&2
  exit 1
fi
mount_count=$(grep -Ec -- \
  '^[[:space:]]*--mount ' "$process_inspector_harness" || true)
readonly_mount_count=$(grep -Fxc -- \
  "$expected_process_inspector_mount" \
  "$process_inspector_harness" || true)
if [ "$mount_count" -ne 1 ] || [ "$readonly_mount_count" -ne 1 ]; then
  echo "process inspector harness must use only the reviewed read-only repository mount" >&2
  exit 1
fi
if grep -Eq -- \
    '^[[:space:]]*--(device|ipc|network|pid|privileged|uts)([=[:space:]\\]|$)|docker\.sock' \
    "$process_inspector_harness"; then
  echo "process inspector harness contains a forbidden host-escape option" >&2
  exit 1
fi

direct_process_inspector_calls=0
harness_process_inspector_calls=0
for workflow_file in "${workflow_files[@]}"; do
  direct_count=$(yq -r '
    [.jobs[].steps[]? |
      select(has("run")) |
      .run |
      select(contains("scripts/test-process-inspector-install.sh"))] |
    length
  ' "$workflow_file")
  harness_count=$(yq -r '
    [.jobs[].steps[]? |
      select(has("run")) |
      .run |
      select(contains("scripts/test-process-inspector-install-container.sh"))] |
    length
  ' "$workflow_file")
  direct_process_inspector_calls=$((direct_process_inspector_calls + direct_count))
  harness_process_inspector_calls=$((harness_process_inspector_calls + harness_count))
done
[ "$direct_process_inspector_calls" -eq 0 ] || {
  echo "a workflow bypasses the bounded process inspector harness" >&2
  exit 1
}
[ "$harness_process_inspector_calls" -eq 2 ] || {
  echo "expected exactly two workflow process inspector harness calls" >&2
  exit 1
}

lint_process_step_count=$(yq -r '
  [.jobs."release-workflow".steps[]? |
    select(.name == "Verify privileged process inspector installation")] |
  length
' .github/workflows/workflow-lint.yml)
lint_process_run=$(yq -r '
  .jobs."release-workflow".steps[]? |
  select(.name == "Verify privileged process inspector installation") |
  .run
' .github/workflows/workflow-lint.yml)
if [ "$lint_process_step_count" -ne 1 ] \
    || [ "$lint_process_run" != \
      'bash scripts/test-process-inspector-install-container.sh' ]; then
  echo "workflow lint must run the bounded process inspector fixture exactly once" >&2
  exit 1
fi

release_process_step_count=$(yq -r '
  [.jobs."sign-and-release".steps[]? |
    select(.name == "Verify shipped Rust process inspector installation")] |
  length
' "$workflow")
release_process_run=$(yq -r '
  .jobs."sign-and-release".steps[]? |
  select(.name == "Verify shipped Rust process inspector installation") |
  .run
' "$workflow")
expected_release_inspector="SYNTAUR_TEST_PROCESS_INSPECTOR=\"\$PWD/dist/syntaur-process-inspector-linux-x86_64\""
if [ "$release_process_step_count" -ne 1 ] \
    || [[ "$release_process_run" != *"$expected_release_inspector"* ]] \
    || [[ "$release_process_run" != \
      *'bash scripts/test-process-inspector-install-container.sh'* ]]; then
  echo "release signing must validate the downloaded process inspector through the bounded harness" >&2
  exit 1
fi

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

product_environment_jobs=$(yq -r '
  .jobs | to_entries[] |
  select(.value.environment == "product-release-source") |
  .key
' "$workflow" | sort)
[ "$product_environment_jobs" = $'build\nbuild-engine' ] || {
  echo "private product builds must use only the protected product-release-source environment" >&2
  exit 1
}
product_source_key_jobs=$(yq -r '
  .jobs | to_entries[] |
  select(.value | tostring |
    contains("secrets.SYNTAUR_PRODUCT_SOURCE_DEPLOY_KEY")) |
  .key
' "$workflow" | sort)
product_engine_key_jobs=$(yq -r '
  .jobs | to_entries[] |
  select(.value | tostring |
    contains("secrets.SYNTAUR_PRODUCT_ENGINE_DEPLOY_KEY")) |
  .key
' "$workflow" | sort)
if [ "$product_source_key_jobs" != $'build\nbuild-engine' ] \
    || [ "$product_engine_key_jobs" != build-engine ]; then
  echo "product deploy keys escaped their protected build jobs" >&2
  exit 1
fi
if grep -Eq 'secrets\.SYNTAUR_(SOURCE|ENGINE)_DEPLOY_KEY' "$workflow"; then
  echo "legacy repository-wide product deploy key names are forbidden" >&2
  exit 1
fi

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
  [ "$(grep -Fc 'sudo chown -R 65534:65534 source' \
    "$authority_workflow")" -eq 1 ] || {
    echo "authority source ownership is not normalized for the unprivileged builder" >&2
    exit 1
  }
  if grep -q 'SYNTAUR_RELEASE_AUTHORITY_PUBLISHER_' "$authority_workflow"; then
    echo "publisher App credentials are forbidden" >&2
    exit 1
  fi
  publish_token_jobs=$(jq -r '
    to_entries[] |
    select(
      .value |
      tostring |
      contains("secrets.SYNTAUR_RELEASE_AUTHORITY_PUBLISH_TOKEN")
    ) |
    .key
  ' <<<"$jobs_json")
  [ "$publish_token_jobs" = publish ] || {
    echo "publication token escaped its isolated job: $publish_token_jobs" >&2
    exit 1
  }
  [ "$(grep -o 'secrets.SYNTAUR_RELEASE_AUTHORITY_PUBLISH_TOKEN' \
    "$authority_workflow" | wc -l)" -eq 1 ]
  [ "$(yq -r '.jobs.predecessor.permissions.attestations' \
    "$authority_workflow")" = read ] || {
    echo "predecessor lacks read access to release attestations" >&2
    exit 1
  }
  [ "$(yq -r '.jobs.publish.permissions.attestations' \
    "$authority_workflow")" = read ] || {
    echo "publisher lacks read access to release attestations" >&2
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
  scripts/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh
  scripts/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh
  scripts/bootstrap-release-authority-genesis-v2.sh
  scripts/recover-release-authority-g10-g11-canary-root-v1.sh
  scripts/recover-release-authority-g11-g12-canary-root-v1.sh
  scripts/recover-release-authority-g12-g13-canary-root-v1.sh
  scripts/fixtures/release_authority_bootstrap_driver.sh
  scripts/fixtures/release_authority_fake_cosign.sh
  scripts/fixtures/release_authority_g10_g11_driver.sh
  scripts/fixtures/release_authority_g11_g12_driver.sh
  scripts/fixtures/release_authority_g12_g13_driver.sh
  scripts/release-authority-manifest.sh
  scripts/test-release-authority-bootstrap.sh
  scripts/test-release-authority-workflow.sh
  scripts/test-process-inspector-install.sh
  scripts/test-process-inspector-install-container.sh
  scripts/validate-release-workflow.sh
  scripts/verify-g1-authority-source.sh
  scripts/verify-release-authority-policy.sh
)
for authority_script in "${authority_scripts[@]}"; do
  bash -n "$authority_script"
  shellcheck "$authority_script"
done
