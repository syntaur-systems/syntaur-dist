#!/usr/bin/env bash
set -euo pipefail

workflow=${1:-.github/workflows/release-sign.yml}
repository=$(pwd -P)
system_path=$PATH
command -v jq >/dev/null
command -v yq >/dev/null

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

extract_step() {
  local name=$1
  local destination=$2
  yq -r ".jobs[].steps[]? | select(.name == \"$name\") | .run" "$workflow" >"$destination"
  test -s "$destination"
}

validate_step="$temporary/validate-inputs.sh"
prepare_step="$temporary/prepare-operation.sh"
publish_step="$temporary/publish-draft.sh"
stage_installers_step="$temporary/stage-installers.sh"
extract_step 'Validate inputs' "$validate_step"
extract_step 'Prepare canonical release operation metadata' "$prepare_step"
extract_step 'Create draft release + upload assets (with retry + verification)' "$publish_step"
extract_step 'Stage install scripts into dist' "$stage_installers_step"

version=0.7.112
tag=v${version}
source_commit=$(printf 'a%.0s' {1..40})
engine_commit=$(printf 'b%.0s' {1..40})
dist_commit=$(printf 'c%.0s' {1..40})
correlation=$(
  printf 'syntaur-release-operation-v2\0%s\0%s\0%s\0%s\0%s\0' \
    "$version" "$tag" "$source_commit" "$engine_commit" "$dist_commit" \
    | sha256sum | awk '{print $1}'
)

run_validate() {
  env \
    REL_VERSION_IN="$version" \
    SRC_REF_IN="$tag" \
    SRC_COMMIT_IN="$source_commit" \
    ENGINE_COMMIT_IN="$engine_commit" \
    DIST_COMMIT_IN="$dist_commit" \
    RELEASE_CORRELATION_IN="${1:-$correlation}" \
    GITHUB_SHA="$dist_commit" \
    bash "$validate_step"
}

run_validate >/dev/null
if run_validate "$(printf 'd%.0s' {1..64})" >/dev/null 2>&1; then
  echo 'invalid release correlation passed validation' >&2
  exit 1
fi
if env \
  REL_VERSION_IN="$version" \
  SRC_REF_IN=v0.7.999 \
  SRC_COMMIT_IN="$source_commit" \
  ENGINE_COMMIT_IN="$engine_commit" \
  DIST_COMMIT_IN="$dist_commit" \
  RELEASE_CORRELATION_IN="$correlation" \
  GITHUB_SHA="$dist_commit" \
  bash "$validate_step" >/dev/null 2>&1; then
  echo 'mismatched release tag passed validation' >&2
  exit 1
fi

stage_case="$temporary/stage-installers"
mkdir -p "$stage_case/dist" "$stage_case/assets"
cp "$repository/install.sh" "$repository/install.ps1" "$stage_case/"
cp "$repository/assets/syntaur-icon.png" \
  "$repository/assets/syntaur-icon.icns" \
  "$repository/assets/syntaur-icon.ico" \
  "$stage_case/assets/"
printf 'runtime payload\n' >"$stage_case/dist/syntaur-runtime-linux-x86_64"
(
  cd "$stage_case"
  env REL_VERSION="$version" DIST_COMMIT="$dist_commit" bash "$stage_installers_step" >/dev/null
)
grep -Fxq "DIST_WORKFLOW_COMMIT=\"$dist_commit\"" "$stage_case/dist/install.sh"
grep -Eq '^RUNTIME_BOOTSTRAP_SHA256="[0-9a-f]{64}"$' "$stage_case/dist/install.sh"
sh -n "$stage_case/dist/install.sh"

installer_case="$temporary/installer-verification"
mkdir -p "$installer_case/release" "$installer_case/out"
printf 'installer payload\n' >"$installer_case/release/syntaur-gateway-linux-x86_64"
(
  cd "$installer_case/release"
  sha256sum syntaur-gateway-linux-x86_64 >checksums.txt
)
printf 'manifest bundle\n' >"$installer_case/release/checksums.txt.cosign.bundle"
(
  SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  . "$repository/install.sh"
  unset SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
  VERIFY=1
  DIST_WORKFLOW_COMMIT="$dist_commit"
  _fetch() {
    cp "${1#file://}" "$2"
  }
  release_url="file://$installer_case/release/syntaur-gateway-linux-x86_64"
  output="$installer_case/out/syntaur-gateway"

  rm "$installer_case/release/checksums.txt.cosign.bundle"
  if download_verified "$release_url" "$output" >/dev/null 2>&1; then
    echo 'installer accepted a missing manifest signature bundle' >&2
    exit 1
  fi
  printf 'manifest bundle\n' >"$installer_case/release/checksums.txt.cosign.bundle"

  # shellcheck disable=SC2329 # download_verified resolves this command wrapper dynamically.
  command() {
    if [ "$1" = -v ] && [ "${2:-}" = cosign ]; then
      return 1
    fi
    builtin command "$@"
  }
  if download_verified "$release_url" "$output" >/dev/null 2>&1; then
    echo 'installer accepted verification without cosign' >&2
    exit 1
  fi
  unset -f command

  cosign() { return 0; }
  download_verified "$release_url" "$output" >/dev/null
  cmp --silent "$installer_case/release/syntaur-gateway-linux-x86_64" "$output"
)

prepare_case="$temporary/prepare"
mkdir -p "$prepare_case/dist" "$prepare_case/bin"
operation_fixture="$prepare_case/operation.json"
jq -S -n \
  --argjson schema 1 \
  --arg version "$version" \
  --arg tag "$tag" \
  --arg source_commit "$source_commit" \
  --arg engine_commit "$engine_commit" \
  --arg dist_commit "$dist_commit" \
  --arg correlation "$correlation" \
  --argjson run_id 41 \
  --argjson run_attempt 2 \
  '{schema:$schema,version:$version,tag:$tag,source_commit:$source_commit,engine_commit:$engine_commit,dist_commit:$dist_commit,correlation:$correlation,run_id:$run_id,run_attempt:$run_attempt}' \
  >"$operation_fixture"
operation_size=$(stat -c '%s' "$operation_fixture")
release_fixture="$prepare_case/release.json"
jq -n \
  --arg tag "$tag" \
  --arg target "$dist_commit" \
  --arg body "<!-- syntaur-release-correlation:${correlation} -->" \
  --argjson size "$operation_size" \
  '{tag_name:$tag,target_commitish:$target,body:$body,draft:true,prerelease:false,assets:[{id:101,name:"syntaur-release-operation.json",size:$size,state:"uploaded"}]}' \
  >"$release_fixture"

cat >"$prepare_case/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
endpoint=${!#}
case "$endpoint" in
  repos/*/releases/tags/*) cat "$MOCK_RELEASE_JSON" ;;
  repos/*/git/ref/tags/*)
    jq -n --arg sha "$MOCK_TAG_COMMIT" '{object:{type:"commit",sha:$sha}}'
    ;;
  repos/*/releases/assets/101) cat "$MOCK_OPERATION" ;;
  *) echo "unexpected gh API endpoint: $endpoint" >&2; exit 1 ;;
esac
STUB
chmod +x "$prepare_case/bin/gh"

run_prepare() {
  (
    cd "$prepare_case"
    env \
      PATH="$prepare_case/bin:$system_path" \
      MOCK_RELEASE_JSON="$release_fixture" \
      MOCK_OPERATION="$operation_fixture" \
      MOCK_TAG_COMMIT="${1:-$dist_commit}" \
      GH_TOKEN=stub \
      GH_REPO=syntaur-systems/syntaur-dist \
      TAG="$tag" \
      REL_VERSION="$version" \
      SRC_COMMIT="$source_commit" \
      ENGINE_COMMIT="$engine_commit" \
      DIST_COMMIT="$dist_commit" \
      RELEASE_CORRELATION="$correlation" \
      GITHUB_RUN_ID=41 \
      GITHUB_RUN_ATTEMPT="${2:-2}" \
      bash "$prepare_step"
  )
}

run_prepare >/dev/null
cmp --silent "$operation_fixture" "$prepare_case/dist/syntaur-release-operation.json"
if run_prepare "$(printf 'd%.0s' {1..40})" >/dev/null 2>&1; then
  echo 'release recovery accepted a tag resolving to the wrong commit' >&2
  exit 1
fi
attempt_error="$temporary/attempt-mismatch.error"
if run_prepare "$dist_commit" 3 >/dev/null 2>"$attempt_error"; then
  echo 'release recovery replaced a signed operation from an earlier attempt' >&2
  exit 1
fi
grep -Fq 'successor version' "$attempt_error"

jq '.assets += [{id:102,name:"unexpected",size:1,state:"uploaded"}]' \
  "$release_fixture" >"$prepare_case/release-invalid.json"
release_fixture="$prepare_case/release-invalid.json"
if run_prepare >/dev/null 2>&1; then
  echo 'release recovery accepted an unexpected remote asset' >&2
  exit 1
fi
release_fixture="$prepare_case/release.json"

publish_case="$temporary/publish"
publish_dist="$publish_case/dist"
publish_state="$publish_case/state"
mkdir -p "$publish_dist" "$publish_state/assets" "$publish_case/bin"
cp "$operation_fixture" "$publish_dist/syntaur-release-operation.json"
printf 'signed payload\n' >"$publish_dist/syntaur-source-commit.txt"
printf 'operation bundle\n' >"$publish_dist/syntaur-release-operation.json.cosign.bundle"
printf 'payload bundle\n' >"$publish_dist/syntaur-source-commit.txt.cosign.bundle"
cp "$repository/assets/syntaur-icon.icns" "$publish_dist/syntaur-icon.icns"
printf 'icon bundle\n' >"$publish_dist/syntaur-icon.icns.cosign.bundle"
truncate -s 3145728 "$publish_dist/syntaur-sbom.spdx.json"
printf 'SBOM bundle\n' >"$publish_dist/syntaur-sbom.spdx.json.cosign.bundle"
(
  cd "$publish_dist"
  sha256sum \
    syntaur-icon.icns \
    syntaur-release-operation.json \
    syntaur-sbom.spdx.json \
    syntaur-source-commit.txt \
    >checksums.txt
)
printf 'manifest bundle\n' >"$publish_dist/checksums.txt.cosign.bundle"

cat >"$publish_case/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

release_json() {
  local assets='[]' id=100 path name size
  shopt -s nullglob
  for path in "$MOCK_STATE"/assets/*; do
    name=$(basename "$path")
    size=$(stat -c '%s' "$path")
    assets=$(jq -c \
      --arg name "$name" \
      --argjson id "$id" \
      --argjson size "$size" \
      '. + [{id:$id,name:$name,size:$size,state:"uploaded"}]' \
      <<<"$assets")
    ((id += 1))
  done
  jq -n \
    --arg tag "$TAG" \
    --arg target "$DIST_COMMIT" \
    --arg body "<!-- syntaur-release-correlation:${RELEASE_CORRELATION} -->" \
    --argjson assets "$assets" \
    '{id:17,tag_name:$tag,target_commitish:$target,body:$body,draft:true,prerelease:false,assets:$assets}'
}

if [ "$1" = api ]; then
  endpoint=${!#}
  case "$endpoint" in
    repos/*/releases/tags/*)
      if [ ! -f "$MOCK_STATE/created" ]; then
        echo 'gh: Not Found (HTTP 404)' >&2
        exit 1
      fi
      release_json
      if [ "${MOCK_OVERSIZED_RELEASE_JSON:-0}" = 1 ]; then
        dd if=/dev/zero bs=1048576 count=3 status=none
        touch "$MOCK_STATE/oversized-release-write-completed"
      fi
      ;;
    repos/*/git/ref/tags/*)
      if [ -n "${MOCK_PREEXISTING_TAG_COMMIT:-}" ]; then
        jq -n --arg sha "$MOCK_PREEXISTING_TAG_COMMIT" '{object:{type:"commit",sha:$sha}}'
      elif [ -f "$MOCK_STATE/created" ]; then
        jq -n --arg sha "$DIST_COMMIT" '{object:{type:"commit",sha:$sha}}'
      else
        echo 'gh: Not Found (HTTP 404)' >&2
        exit 1
      fi
      ;;
    repos/*/releases/assets/*)
      wanted=${endpoint##*/}
      id=100
      shopt -s nullglob
      for path in "$MOCK_STATE"/assets/*; do
        if [ "$id" = "$wanted" ]; then
          cat "$path"
          if [ "${MOCK_OVERSIZED_ASSET_NAME:-}" = "$(basename "$path")" ]; then
            dd if=/dev/zero bs=1048576 count=2 status=none
            touch "$MOCK_STATE/oversized-asset-write-completed"
          fi
          exit 0
        fi
        ((id += 1))
      done
      echo "unknown asset ID $wanted" >&2
      exit 1
      ;;
    *) echo "unexpected gh API endpoint: $endpoint" >&2; exit 1 ;;
  esac
elif [ "$1" = release ] && [ "$2" = create ]; then
  touch "$MOCK_STATE/created"
  exit 1
elif [ "$1" = release ] && [ "$2" = upload ]; then
  asset=${!#}
  cp "$asset" "$MOCK_STATE/assets/$(basename "$asset")"
  exit 1
else
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi
STUB
chmod +x "$publish_case/bin/gh"

run_publish() {
  local state=${1:-$publish_state}
  local preexisting_tag=${2:-}
  local oversized_release=${3:-0}
  local oversized_asset=${4:-}
  (
    cd "$publish_dist"
    env \
      PATH="$publish_case/bin:$system_path" \
      MOCK_STATE="$state" \
      MOCK_PREEXISTING_TAG_COMMIT="$preexisting_tag" \
      MOCK_OVERSIZED_RELEASE_JSON="$oversized_release" \
      MOCK_OVERSIZED_ASSET_NAME="$oversized_asset" \
      GH_TOKEN=stub \
      GH_REPO=syntaur-systems/syntaur-dist \
      TAG="$tag" \
      REL_VERSION="$version" \
      SRC_REF="$tag" \
      SRC_COMMIT="$source_commit" \
      ENGINE_COMMIT="$engine_commit" \
      DIST_COMMIT="$dist_commit" \
      RELEASE_CORRELATION="$correlation" \
      bash "$publish_step"
  )
}

wrong_tag_state="$publish_case/wrong-tag-state"
mkdir -p "$wrong_tag_state/assets"
if run_publish "$wrong_tag_state" "$(printf 'd%.0s' {1..40})" >/dev/null 2>&1; then
  echo 'release creation accepted a pre-existing tag at the wrong commit' >&2
  exit 1
fi
test ! -e "$wrong_tag_state/created"

run_publish >/dev/null
for asset in "$publish_dist"/*; do
  cmp --silent "$asset" "$publish_state/assets/$(basename "$asset")"
done

if run_publish "$publish_state" '' 1 >/dev/null 2>&1; then
  echo 'release reconciliation accepted oversized GitHub metadata' >&2
  exit 1
fi
test ! -e "$publish_state/oversized-release-write-completed"

if run_publish "$publish_state" '' 0 syntaur-source-commit.txt >/dev/null 2>&1; then
  echo 'release reconciliation accepted an asset response past its transfer bound' >&2
  exit 1
fi
test ! -e "$publish_state/oversized-asset-write-completed"

truncate -s 4194305 "$publish_state/assets/syntaur-icon.icns"
if run_publish >/dev/null 2>&1; then
  echo 'release reconciliation accepted an icon over 4 MiB' >&2
  exit 1
fi
cp "$publish_dist/syntaur-icon.icns" "$publish_state/assets/syntaur-icon.icns"

printf 'signed payloae\n' >"$publish_state/assets/syntaur-source-commit.txt"
if run_publish >/dev/null 2>&1; then
  echo 'release reconciliation accepted changed remote bytes' >&2
  exit 1
fi

printf 'release workflow recovery tests passed\n'
