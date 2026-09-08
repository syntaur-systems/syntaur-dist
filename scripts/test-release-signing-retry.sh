#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/release-sign.yml
[ "$#" -eq 0 ] || workflow=$1
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
yq -o=json '.jobs."sign-and-release"' "$workflow" >"$temporary/job.json"
jq -e '
  [.steps[] | select(.name == "Sign each artifact")] as $steps |
  ($steps | length == 1) and
  ($steps[0]["timeout-minutes"] == 15) and
  ($steps[0]["working-directory"] == "dist") and
  ($steps[0].if == null) and
  (($steps[0]["continue-on-error"] // false) == false) and
  ((.["continue-on-error"] // false) == false)
' "$temporary/job.json" >/dev/null
jq -r '.steps[] | select(.name == "Sign each artifact") | .run' \
  "$temporary/job.json" >"$temporary/sign.sh"
bash -n "$temporary/sign.sh"
mkdir "$temporary/bin"

# Execute the actual workflow block with only the external signing, deadline,
# and delay commands replaced. No OIDC credentials or network calls are used.
cat >"$temporary/bin/timeout" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = --kill-after=10s ] && [ "$2" = 120s ]
shift 2
[ "$1" = cosign ] && [ "$2" = sign-blob ]
printf 'bounded-sign\n' >>"$CASE_ROOT/timeouts"
exec "$@"
STUB
cat >"$temporary/bin/sleep" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in 20|40) ;; *) exit 99 ;; esac
printf '%s\n' "$1" >>"$CASE_ROOT/delays"
STUB
cat >"$temporary/bin/cosign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
operation=$1
shift
bundle= provider= flow= identity= issuer= workflow_sha= blob= yes=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) yes=true; shift ;;
    --bundle) bundle=$2; shift 2 ;;
    --oidc-provider) provider=$2; shift 2 ;;
    --fulcio-auth-flow) flow=$2; shift 2 ;;
    --certificate-identity) identity=$2; shift 2 ;;
    --certificate-oidc-issuer) issuer=$2; shift 2 ;;
    --certificate-github-workflow-sha) workflow_sha=$2; shift 2 ;;
    --*) exit 98 ;;
    *) [ -z "$blob" ]; blob=$1; shift ;;
  esac
done
[ -f "$blob" ] && [ -n "$bundle" ]
case "$operation" in
  sign-blob)
    [ "$yes" = true ] && [ "$provider" = github-actions ] && [ "$flow" = token ]
    [[ "$bundle" == "$RUNNER_TEMP"/syntaur-sign.*/[123].cosign.bundle ]]
    # A previous failed request must never leave its partial bundle to reuse.
    [ ! -e "$bundle" ]
    count_file="$CASE_ROOT/count-$blob"
    count=0
    [ ! -f "$count_file" ] || read -r count <"$count_file"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    printf '%s %s\n' "$blob" "$count" >>"$CASE_ROOT/signs"
    if [ "$blob" = "$TARGET_BLOB" ]; then
      case "$SCENARIO" in
        mutate-failure)
          printf 'changed\n' >>"$blob"
          printf 'partial\n' >"$bundle"
          exit 1 ;;
        mutate-success) printf 'changed\n' >>"$blob" ;;
        missing-bundle) exit 0 ;;
        always-fail|timeout)
          printf 'partial\n' >"$bundle"
          [ "$SCENARIO" != timeout ] || exit 124
          exit 1 ;;
        retry-two|retry-three)
          limit=2
          [ "$SCENARIO" != retry-three ] || limit=3
          if [ "$count" -lt "$limit" ]; then
            printf 'partial\n' >"$bundle"
            exit 1
          fi ;;
      esac
    fi
    sha256sum -- "$blob" >"$bundle"
    ;;
  verify-blob)
    [ "$identity" = 'https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main' ]
    [ "$issuer" = 'https://token.actions.githubusercontent.com' ]
    [ "$workflow_sha" = "$DIST_COMMIT" ]
    printf '%s\n' "$blob" >>"$CASE_ROOT/verifies"
    if [ "$SCENARIO" = bad-certificate ] && [ "$blob" = "$TARGET_BLOB" ]; then
      exit 1
    fi
    [ -s "$bundle" ]
    sha256sum -- "$blob" | cmp - "$bundle"
    ;;
  *) exit 97 ;;
esac
STUB
chmod +x "$temporary/bin/"*
passed=0
run_case() {
  local scenario=$1 target=$2 expected_status=$3 expected_signs=$4 expected_delays=$5
  local case_root="$temporary/case-$passed" actual_status=0 signs=0 delays=0
  mkdir -p "$case_root/dist/.resume-assets" "$case_root/runner"
  for blob in syntaur-engine-test install.sh install.ps1; do
    printf 'fixture %s\n' "$blob" >"$case_root/dist/$blob"
  done
  (
    cd "$case_root/dist"
    sha256sum syntaur-engine-test install.sh install.ps1 >checksums.txt
  )
  if [ "$scenario" = recovered ] || [ "$scenario" = bad-recovered ]; then
    (
      cd "$case_root/dist"
      sha256sum syntaur-engine-test >.resume-assets/syntaur-engine-test.cosign.bundle
    )
    if [ "$scenario" = bad-recovered ]; then
      printf 'invalid bundle\n' >"$case_root/dist/.resume-assets/syntaur-engine-test.cosign.bundle"
    fi
  fi
  (
    cd "$case_root/dist"
    PATH="$temporary/bin:$PATH" CASE_ROOT="$case_root" \
      RUNNER_TEMP="$case_root/runner" DIST_COMMIT=0123456789abcdef0123456789abcdef01234567 \
      TARGET_BLOB="$target" SCENARIO="$scenario" \
      bash "$temporary/sign.sh"
  ) >"$case_root/output" 2>&1 || actual_status=$?
  if [ "$expected_status" = 0 ]; then
    [ "$actual_status" = 0 ]
    for blob in syntaur-engine-test install.sh install.ps1 checksums.txt; do
      [ -s "$case_root/dist/$blob.cosign.bundle" ]
    done
    (cd "$case_root/dist"; sha256sum --strict -c checksums.txt) >/dev/null
  else
    [ "$actual_status" != 0 ]
    [ ! -e "$case_root/dist/$target.cosign.bundle" ]
    [ ! -e "$case_root/dist/checksums.txt.cosign.bundle" ]
  fi
  [ ! -e "$case_root/signs" ] || signs=$(wc -l <"$case_root/signs")
  [ ! -e "$case_root/delays" ] || delays=$(wc -l <"$case_root/delays")
  [ "$signs" -eq "$expected_signs" ]
  [ "$delays" -eq "$expected_delays" ]
  # Retries must all use the outer deadline, and partial temporary outputs must
  # never escape the signing step or survive its cleanup.
  if [ "$signs" -gt 0 ]; then
    [ "$(wc -l <"$case_root/timeouts")" -eq "$signs" ]
  fi
  [ -z "$(find "$case_root/runner" -mindepth 1 -print -quit)" ]
  passed=$((passed + 1))
  printf 'PASS signing case %s target %s\n' "$scenario" "$target"
}
run_case success syntaur-engine-test 0 4 0
run_case retry-two syntaur-engine-test 0 5 1
run_case retry-three syntaur-engine-test 0 6 2
run_case always-fail syntaur-engine-test 1 3 2
run_case always-fail checksums.txt 1 6 2
run_case timeout syntaur-engine-test 1 3 2
run_case missing-bundle syntaur-engine-test 1 1 0
run_case bad-certificate syntaur-engine-test 1 1 0
run_case bad-certificate checksums.txt 1 4 0
run_case recovered syntaur-engine-test 0 3 0
run_case bad-recovered syntaur-engine-test 1 0 0
run_case mutate-failure syntaur-engine-test 1 1 1
run_case mutate-success syntaur-engine-test 1 1 0
printf 'Signing retry workflow wiring and %s execution cases passed.\n' "$passed"
