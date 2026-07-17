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
    GITHUB_RUN_ATTEMPT_IN="${2:-1}" \
    bash "$validate_step"
}

run_validate >/dev/null
if run_validate "$(printf 'd%.0s' {1..64})" >/dev/null 2>&1; then
  echo 'invalid release correlation passed validation' >&2
  exit 1
fi
if run_validate "$correlation" 2 >/dev/null 2>&1; then
  echo 'release workflow rerun passed first-attempt validation' >&2
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
  GITHUB_RUN_ATTEMPT_IN=1 \
  bash "$validate_step" >/dev/null 2>&1; then
  echo 'mismatched release tag passed validation' >&2
  exit 1
fi

stage_case="$temporary/stage-installers"
git clone --quiet --no-hardlinks "$repository" "$stage_case"
mkdir -p "$stage_case/dist"
cp "$repository/install.sh" "$repository/install.ps1" "$stage_case/"
cp "$repository/EULA.md" "$stage_case/EULA.md"
printf 'runtime payload\n' >"$stage_case/dist/syntaur-runtime-linux-x86_64"
printf 'process inspector payload\n' >"$stage_case/dist/syntaur-process-inspector-linux-x86_64"
(
  cd "$stage_case"
  env REL_VERSION="$version" DIST_COMMIT="$dist_commit" bash "$stage_installers_step" >/dev/null
)
grep -Fxq "DIST_WORKFLOW_COMMIT=\"$dist_commit\"" "$stage_case/dist/install.sh"
grep -Eq '^RUNTIME_BOOTSTRAP_SHA256="[0-9a-f]{64}"$' "$stage_case/dist/install.sh"
grep -Fxq \
  "PROCESS_INSPECTOR_SHA256=\"$(sha256sum "$stage_case/dist/syntaur-process-inspector-linux-x86_64" | awk '{print $1}')\"" \
  "$stage_case/dist/install.sh"
sh -n "$stage_case/dist/install.sh"

installer_case="$temporary/installer-verification"
mkdir -p "$installer_case/release" "$installer_case/out"
printf 'installer payload\n' >"$installer_case/release/syntaur-gateway-linux-x86_64"
printf 'process inspector payload\n' >"$installer_case/release/syntaur-process-inspector-linux-x86_64"
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

  inspector_asset=syntaur-process-inspector-linux-x86_64
  inspector_sha256=$(sha256sum "$installer_case/release/$inspector_asset" | awk '{print $1}')
  inspector_output="$installer_case/out/$inspector_asset"
  VERIFY=0
  download_pinned_release_asset \
    "file://$installer_case/release" \
    "$inspector_asset" \
    "$inspector_output" \
    "$inspector_sha256" \
    "process inspector" >/dev/null
  cmp --silent "$installer_case/release/$inspector_asset" "$inspector_output"
  printf 'wrong process inspector payload\n' >"$installer_case/release/$inspector_asset"
  if download_pinned_release_asset \
      "file://$installer_case/release" \
      "$inspector_asset" \
      "$inspector_output" \
      "$inspector_sha256" \
      "process inspector" >/dev/null 2>&1; then
    echo 'pinned process inspector accepted wrong bytes under VERIFY=0' >&2
    exit 1
  fi
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
  '{id:17,tag_name:$tag,target_commitish:$target,body:$body,draft:true,prerelease:false,assets:[{id:101,name:"syntaur-release-operation.json",size:$size,state:"uploaded"}]}' \
  >"$release_fixture"

cat >"$prepare_case/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
endpoint=${!#}
case "$endpoint" in
  repos/*/releases/tags/*)
    if [ "${MOCK_RELEASE_PUBLIC:-0}" = 1 ]; then
      cat "$MOCK_RELEASE_JSON"
    else
      echo 'gh: Not Found (HTTP 404)' >&2
      exit 1
    fi
    ;;
  repos/*/releases)
    if [ "${MOCK_DUPLICATE_RELEASE:-0}" = 1 ]; then
      jq -s '.[0] as $release | [$release, ($release + {id:102})]' "$MOCK_RELEASE_JSON"
    else
      jq -s '.' "$MOCK_RELEASE_JSON"
    fi
    ;;
  repos/*/releases/17) cat "$MOCK_RELEASE_JSON" ;;
  repos/*/git/ref/tags/*)
    if [ -n "${MOCK_TAG_COMMIT:-}" ]; then
      jq -n --arg sha "$MOCK_TAG_COMMIT" '{object:{type:"commit",sha:$sha}}'
    else
      echo 'gh: Not Found (HTTP 404)' >&2
      exit 1
    fi
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
      MOCK_TAG_COMMIT="${1:-}" \
      MOCK_DUPLICATE_RELEASE="${3:-0}" \
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
if run_prepare "" 3 >/dev/null 2>"$attempt_error"; then
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

jq '.assets = []' "$release_fixture" >"$prepare_case/release-empty.json"
release_fixture="$prepare_case/release-empty.json"
if run_prepare >/dev/null 2>&1; then
  echo 'release recovery accepted an existing empty draft without operation authority' >&2
  exit 1
fi
release_fixture="$prepare_case/release.json"

if run_prepare "" 2 1 >/dev/null 2>&1; then
  echo 'release recovery accepted duplicate exact release candidates' >&2
  exit 1
fi

publish_case="$temporary/publish"
publish_dist="$publish_case/dist"
publish_state="$publish_case/state"
mkdir -p "$publish_dist" "$publish_state/assets" "$publish_case/bin"
cp "$operation_fixture" "$publish_dist/syntaur-release-operation.json"
printf 'signed payload\n' >"$publish_dist/syntaur-source-commit.txt"
printf 'process inspector payload\n' >"$publish_dist/syntaur-process-inspector-linux-x86_64"
printf 'operation bundle\n' >"$publish_dist/syntaur-release-operation.json.cosign.bundle"
printf 'payload bundle\n' >"$publish_dist/syntaur-source-commit.txt.cosign.bundle"
printf 'process inspector bundle\n' >"$publish_dist/syntaur-process-inspector-linux-x86_64.cosign.bundle"
cp "$repository/assets/syntaur-icon.icns" "$publish_dist/syntaur-icon.icns"
printf 'icon bundle\n' >"$publish_dist/syntaur-icon.icns.cosign.bundle"
truncate -s 3145728 "$publish_dist/syntaur-sbom.spdx.json"
printf 'SBOM bundle\n' >"$publish_dist/syntaur-sbom.spdx.json.cosign.bundle"
(
  cd "$publish_dist"
  sha256sum \
    syntaur-icon.icns \
    syntaur-release-operation.json \
    syntaur-process-inspector-linux-x86_64 \
    syntaur-sbom.spdx.json \
    syntaur-source-commit.txt \
    >checksums.txt
)
printf 'manifest bundle\n' >"$publish_dist/checksums.txt.cosign.bundle"

cat >"$publish_case/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

is_public() {
  local count=0
  if [ "${MOCK_PUBLIC:-0}" = 1 ]; then
    return 0
  fi
  if [ -f "$MOCK_STATE/upload-count" ]; then
    read -r count <"$MOCK_STATE/upload-count"
  fi
  [ "${MOCK_PUBLISH_AFTER_UPLOADS:-0}" -gt 0 ] \
    && [ "$count" -ge "${MOCK_PUBLISH_AFTER_UPLOADS}" ]
}

release_json() {
  local assets='[]' id=100 path name size draft=true release_id=17
  if is_public; then
    draft=false
  fi
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
    --arg upload_url "https://uploads.github.com/repos/${GH_REPO}/releases/${release_id}/assets{?name,label}" \
    --argjson assets "$assets" \
    --argjson draft "$draft" \
    --argjson id "$release_id" \
    '{id:$id,tag_name:$tag,target_commitish:$target,body:$body,upload_url:$upload_url,draft:$draft,prerelease:false,assets:$assets}'
}

increment() {
  local path=$1 value=0
  if [ -f "$path" ]; then
    read -r value <"$path"
  fi
  printf '%s\n' "$((value + 1))" >"$path"
}

argument_after() {
  local wanted=$1 previous= argument
  shift
  for argument in "$@"; do
    if [ "$previous" = "$wanted" ]; then
      printf '%s\n' "$argument"
      return 0
    fi
    previous=$argument
  done
  return 1
}

if [ "$1" = api ]; then
  endpoint=${!#}
  method=$(argument_after --method "$@" 2>/dev/null || printf 'GET\n')
  case "$endpoint" in
    repos/*/releases/tags/*)
      if [ ! -f "$MOCK_STATE/created" ] || ! is_public; then
        echo 'gh: Not Found (HTTP 404)' >&2
        exit 1
      fi
      release_json
      ;;
    repos/*/git/ref/tags/*)
      if [ -n "${MOCK_PREEXISTING_TAG_COMMIT:-}" ]; then
        jq -n --arg sha "$MOCK_PREEXISTING_TAG_COMMIT" '{object:{type:"commit",sha:$sha}}'
      elif [ -f "$MOCK_STATE/created" ] && is_public; then
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
    repos/*/releases)
      if [ "$method" = POST ]; then
        increment "$MOCK_STATE/create-count"
        touch "$MOCK_STATE/created"
        release_json
        exit "${MOCK_CREATE_STATUS:-1}"
      fi
      page=1
      for argument in "$@"; do
        case "$argument" in
          page=*) page=${argument#page=} ;;
        esac
      done
      if [ "${MOCK_INVENTORY_API_FAILURE:-0}" = 1 ]; then
        increment "$MOCK_STATE/inventory-api-failure-count"
        echo 'gh: simulated inventory API failure' >&2
        exit 1
      elif [ "${MOCK_FULL_INVENTORY:-0}" = 1 ]; then
        jq -n --arg page "$page" \
          '[range(0;10) as $index | {id:((($page | tonumber) * 1000) + $index),tag_name:("v0.6." + $page + "." + ($index | tostring)),body:"unrelated"}]'
      elif [ ! -f "$MOCK_STATE/created" ] || [ "${MOCK_NEVER_VISIBLE:-0}" = 1 ]; then
        printf '[]\n'
      elif [ "${MOCK_TRANSIENT_VISIBILITY:-0}" = 1 ]; then
        increment "$MOCK_STATE/transient-visibility-count"
        read -r transient_visibility_count <"$MOCK_STATE/transient-visibility-count"
        if [ "$transient_visibility_count" = 1 ]; then
          printf '[]\n'
        else
          release=$(release_json)
          jq -n --argjson release "$release" '[$release]'
        fi
      elif [ "${MOCK_MUTATE_BETWEEN_SCANS:-0}" = 1 ]; then
        increment "$MOCK_STATE/mutation-scan-count"
        read -r mutation_scan_count <"$MOCK_STATE/mutation-scan-count"
        if (( mutation_scan_count % 2 == 1 )); then
          release=$(release_json)
          jq -n --argjson release "$release" '[$release]'
        else
          printf '[]\n'
        fi
      elif [ "${MOCK_SPLIT_DUPLICATE:-0}" = 1 ]; then
        release=$(release_json)
        if [ "$page" = 1 ]; then
          jq -n --argjson release "$release" \
            '[$release] + [range(0;9) as $index | {id:(2000 + $index),tag_name:("v0.6." + ($index | tostring)),body:"unrelated"}]'
        else
          jq -n --argjson release "$release" '[$release]'
        fi
      elif [ "${MOCK_CROSS_PAGE:-0}" = 1 ] && [ "$page" = 1 ]; then
        jq -n '[range(0;10) as $index | {id:(3000 + $index),tag_name:("v0.6." + ($index | tostring)),body:"unrelated"}]'
      else
        increment "$MOCK_STATE/inventory-count"
        read -r inventory_count <"$MOCK_STATE/inventory-count"
        if (( inventory_count <= ${MOCK_INVENTORY_DELAY:-0} )); then
          printf '[]\n'
        elif [ "${MOCK_DUPLICATE_RELEASE:-0}" = 1 ]; then
          release=$(release_json)
          jq -n --argjson release "$release" '[$release, ($release + {id:18})]'
        else
          release=$(release_json)
          if [ "${MOCK_VOLATILE_METADATA:-0}" = 1 ]; then
            increment "$MOCK_STATE/volatile-metadata-count"
            read -r volatile_metadata_count <"$MOCK_STATE/volatile-metadata-count"
            release=$(jq -c --argjson count "$volatile_metadata_count" \
              '.assets |= map(. + {download_count:$count})' <<<"$release")
          fi
          jq -n --argjson release "$release" '[$release]'
        fi
      fi
      if [ "${MOCK_OVERSIZED_RELEASE_JSON:-0}" = 1 ]; then
        dd if=/dev/zero bs=1048576 count=3 status=none
        touch "$MOCK_STATE/oversized-release-write-completed"
      fi
      ;;
    repos/*/releases/[0-9]*)
      if [ -f "$MOCK_STATE/created" ] && [ "${endpoint##*/}" = 17 ]; then
        release_json
      else
        echo 'gh: Not Found (HTTP 404)' >&2
        exit 1
      fi
      ;;
    https://uploads.github.com/*)
      asset=$(argument_after --input "$@")
      test "$(argument_after -f "$@")" = "name=$(basename "$asset")"
      increment "$MOCK_STATE/upload-count"
      increment "$MOCK_STATE/upload-$(basename "$asset")-count"
      ln "$asset" "$MOCK_STATE/assets/$(basename "$asset")"
      jq -n --arg name "$(basename "$asset")" --argjson size "$(stat -c '%s' "$asset")" \
        '{id:999,name:$name,size:$size,state:"uploaded"}'
      exit "${MOCK_UPLOAD_STATUS:-1}"
      ;;
    *) echo "unexpected gh API endpoint: $endpoint" >&2; exit 1 ;;
  esac
else
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi
STUB
chmod +x "$publish_case/bin/gh"
cat >"$publish_case/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$publish_case/bin/sleep"

detach_state_assets() {
  local state=$1 path detached
  for path in "$state"/assets/*; do
    detached="${path}.detached"
    cp "$path" "$detached"
    mv "$detached" "$path"
  done
}

run_publish() {
  local state=${1:-$publish_state}
  local preexisting_tag=${2:-}
  local oversized_release=${3:-0}
  local oversized_asset=${4:-}
  local duplicate_release=${5:-0}
  local never_visible=${6:-0}
  local public_release=${7:-0}
  local cross_page=${8:-0}
  local split_duplicate=${9:-0}
  local full_inventory=${10:-0}
  local publish_after_uploads=${11:-0}
  local mutate_between_scans=${12:-0}
  local inventory_api_failure=${13:-0}
  local transient_visibility=${14:-0}
  local volatile_metadata=${15:-0}
  (
    cd "$publish_dist"
    env \
      PATH="$publish_case/bin:$system_path" \
      MOCK_STATE="$state" \
      MOCK_PREEXISTING_TAG_COMMIT="$preexisting_tag" \
      MOCK_OVERSIZED_RELEASE_JSON="$oversized_release" \
      MOCK_OVERSIZED_ASSET_NAME="$oversized_asset" \
      MOCK_DUPLICATE_RELEASE="$duplicate_release" \
      MOCK_NEVER_VISIBLE="$never_visible" \
      MOCK_PUBLIC="$public_release" \
      MOCK_CROSS_PAGE="$cross_page" \
      MOCK_SPLIT_DUPLICATE="$split_duplicate" \
      MOCK_FULL_INVENTORY="$full_inventory" \
      MOCK_PUBLISH_AFTER_UPLOADS="$publish_after_uploads" \
      MOCK_MUTATE_BETWEEN_SCANS="$mutate_between_scans" \
      MOCK_INVENTORY_API_FAILURE="$inventory_api_failure" \
      MOCK_TRANSIENT_VISIBILITY="$transient_visibility" \
      MOCK_VOLATILE_METADATA="$volatile_metadata" \
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
detach_state_assets "$publish_state"
test "$(cat "$publish_state/create-count")" = 1
for asset in "$publish_dist"/*; do
  cmp --silent "$asset" "$publish_state/assets/$(basename "$asset")"
  test "$(cat "$publish_state/upload-$(basename "$asset")-count")" = 1
done

existing_draft_state="$publish_case/existing-draft-state"
mkdir -p "$existing_draft_state/assets"
touch "$existing_draft_state/created"
run_publish "$existing_draft_state" >/dev/null
detach_state_assets "$existing_draft_state"
test ! -e "$existing_draft_state/create-count"
for asset in "$publish_dist"/*; do
  cmp --silent "$asset" "$existing_draft_state/assets/$(basename "$asset")"
  test "$(cat "$existing_draft_state/upload-$(basename "$asset")-count")" = 1
done

published_during_upload_state="$publish_case/published-during-upload-state"
mkdir -p "$published_during_upload_state/assets"
touch "$published_during_upload_state/created"
if run_publish "$published_during_upload_state" '' 0 '' 0 0 0 0 0 0 1 >/dev/null 2>&1; then
  echo 'release staging continued uploading after the draft became public' >&2
  exit 1
fi
test "$(cat "$published_during_upload_state/upload-count")" = 1

duplicate_state="$publish_case/duplicate-state"
mkdir -p "$duplicate_state/assets"
touch "$duplicate_state/created"
if run_publish "$duplicate_state" '' 0 '' 1 >/dev/null 2>&1; then
  echo 'release staging accepted duplicate exact release candidates' >&2
  exit 1
fi
test ! -e "$duplicate_state/create-count"
test ! -e "$duplicate_state/upload-count"

cross_page_state="$publish_case/cross-page-state"
mkdir -p "$cross_page_state/assets"
touch "$cross_page_state/created"
for asset in "$publish_dist"/*; do
  cp "$asset" "$cross_page_state/assets/$(basename "$asset")"
done
run_publish "$cross_page_state" '' 0 '' 0 0 0 1 >/dev/null
test ! -e "$cross_page_state/create-count"
test ! -e "$cross_page_state/upload-count"

split_duplicate_state="$publish_case/split-duplicate-state"
mkdir -p "$split_duplicate_state/assets"
touch "$split_duplicate_state/created"
if run_publish "$split_duplicate_state" '' 0 '' 0 0 0 0 1 >/dev/null 2>&1; then
  echo 'release staging accepted duplicate candidates split across inventory pages' >&2
  exit 1
fi
test ! -e "$split_duplicate_state/create-count"
test ! -e "$split_duplicate_state/upload-count"

mutating_inventory_state="$publish_case/mutating-inventory-state"
mkdir -p "$mutating_inventory_state/assets"
touch "$mutating_inventory_state/created"
if run_publish "$mutating_inventory_state" '' 0 '' 0 0 0 0 0 0 0 1 >/dev/null 2>&1; then
  echo 'release staging accepted inventory mutation between complete scans' >&2
  exit 1
fi
test ! -e "$mutating_inventory_state/create-count"
test ! -e "$mutating_inventory_state/upload-count"

inventory_failure_state="$publish_case/inventory-failure-state"
mkdir -p "$inventory_failure_state/assets"
if run_publish "$inventory_failure_state" '' 0 '' 0 0 0 0 0 0 0 0 1 >/dev/null 2>&1; then
  echo 'release staging inferred absence from inventory API failures' >&2
  exit 1
fi
test "$(cat "$inventory_failure_state/inventory-api-failure-count")" = 2
test ! -e "$inventory_failure_state/create-count"
test ! -e "$inventory_failure_state/upload-count"

transient_visibility_state="$publish_case/transient-visibility-state"
mkdir -p "$transient_visibility_state/assets"
run_publish "$transient_visibility_state" '' 0 '' 0 0 0 0 0 0 0 0 0 1 >/dev/null
detach_state_assets "$transient_visibility_state"
test "$(cat "$transient_visibility_state/create-count")" = 1
for asset in "$publish_dist"/*; do
  cmp --silent "$asset" "$transient_visibility_state/assets/$(basename "$asset")"
  test "$(cat "$transient_visibility_state/upload-$(basename "$asset")-count")" = 1
done

volatile_metadata_state="$publish_case/volatile-metadata-state"
mkdir -p "$volatile_metadata_state/assets"
touch "$volatile_metadata_state/created"
for asset in "$publish_dist"/*; do
  cp "$asset" "$volatile_metadata_state/assets/$(basename "$asset")"
done
run_publish "$volatile_metadata_state" '' 0 '' 0 0 0 0 0 0 0 0 0 0 1 >/dev/null
test ! -e "$volatile_metadata_state/create-count"
test ! -e "$volatile_metadata_state/upload-count"

full_inventory_state="$publish_case/full-inventory-state"
mkdir -p "$full_inventory_state/assets"
if run_publish "$full_inventory_state" '' 0 '' 0 0 0 0 0 1 >/dev/null 2>&1; then
  echo 'release staging inferred absence from a full bounded inventory' >&2
  exit 1
fi
test ! -e "$full_inventory_state/create-count"
test ! -e "$full_inventory_state/upload-count"

invisible_state="$publish_case/invisible-state"
mkdir -p "$invisible_state/assets"
if run_publish "$invisible_state" '' 0 '' 0 1 >/dev/null 2>&1; then
  echo 'release staging accepted an unreconciled ambiguous create' >&2
  exit 1
fi
test "$(cat "$invisible_state/create-count")" = 1
test ! -e "$invisible_state/upload-count"

public_wrong_tag_state="$publish_case/public-wrong-tag-state"
mkdir -p "$public_wrong_tag_state/assets"
touch "$public_wrong_tag_state/created"
if run_publish "$public_wrong_tag_state" "$(printf 'd%.0s' {1..40})" 0 '' 0 0 1 >/dev/null 2>&1; then
  echo 'release staging accepted a public release whose tag resolved incorrectly' >&2
  exit 1
fi
test ! -e "$public_wrong_tag_state/upload-count"

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
