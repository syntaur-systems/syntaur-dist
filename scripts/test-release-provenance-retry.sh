#!/usr/bin/env bash
set -euo pipefail

workflow=${1:-.github/workflows/release-sign.yml}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
yq -o=json '.jobs."sign-and-release"' "$workflow" >"$temporary/job.json"

# Check the actual workflow wiring as well as executing its mandatory gate.
# No credentials, GitHub requests, signing, or attestation uploads are used.
jq -e '
  .steps as $steps |
  [$steps[] | select((.id // "") | startswith("provenance_"))] as $attempts |
  ($attempts | length == 3) and
  ($attempts | map(.id) == ["provenance_1", "provenance_2", "provenance_3"]) and
  (all($attempts[];
    .uses == "actions/attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a" and
    .["timeout-minutes"] == 5 and
    .with == {"subject-path":"dist/syntaur-*\ndist/install.sh\ndist/install.ps1\n"} and
    (has("env") | not))) and
  ($attempts[0].if == null) and
  ($attempts[0]["continue-on-error"] == true) and
  ($attempts[1]["continue-on-error"] == true) and
  (($attempts[2]["continue-on-error"] // false) == false) and
  ($attempts[1].if == "steps.provenance_1.outcome == '\''failure'\''") and
  ($attempts[2].if == "steps.provenance_1.outcome == '\''failure'\'' && steps.provenance_2.outcome == '\''failure'\''") and
  ([$steps[] | select(.name == "Back off before second provenance attempt")] ==
    [{"name":"Back off before second provenance attempt", "if":$attempts[1].if, "run":"sleep 20"}]) and
  ([$steps[] | select(.name == "Back off before final provenance attempt")] ==
    [{"name":"Back off before final provenance attempt", "if":$attempts[2].if, "run":"sleep 40"}]) and
  ([$steps[] | select(.name == "Require successful SLSA provenance")] | length == 1) and
  ([$steps[] | select(.name == "Create draft release + upload assets (with retry + verification)")] | length == 1) and
  ([$steps | to_entries[] | select(.value.name == "Require successful SLSA provenance")][0] as $gate |
    ($gate.value.if == null) and
    (($gate.value["continue-on-error"] // false) == false) and
    ($gate.value.env == {
      "PROVENANCE_1":"${{ steps.provenance_1.outcome }}",
      "PROVENANCE_2":"${{ steps.provenance_2.outcome }}",
      "PROVENANCE_3":"${{ steps.provenance_3.outcome }}"
    }) and
    ($steps[$gate.key - 1] == $attempts[2]) and
    ($steps[$gate.key + 1].name == "Create draft release + upload assets (with retry + verification)") and
    ($steps[$gate.key + 1].if == null) and
    (($steps[$gate.key + 1]["continue-on-error"] // false) == false)) and
  ((.["continue-on-error"] // false) == false)
' "$temporary/job.json" >/dev/null

jq -r '.steps[] | select(.name == "Require successful SLSA provenance") | .run' \
  "$temporary/job.json" >"$temporary/require-provenance.sh"
bash -n "$temporary/require-provenance.sh"
passed=0
for first in success failure skipped cancelled unknown ''; do
  for second in success failure skipped cancelled unknown ''; do
    for third in success failure skipped cancelled unknown ''; do
      expected=1
      case "$first/$second/$third" in
        success/skipped/skipped|failure/success/skipped|failure/failure/success) expected=0 ;;
      esac
      actual=0
      PROVENANCE_1=$first PROVENANCE_2=$second PROVENANCE_3=$third \
        bash "$temporary/require-provenance.sh" >"$temporary/result" 2>&1 || actual=$?
      if [ "$actual" -ne "$expected" ]; then
        printf 'Unexpected provenance admission for %s/%s/%s: %s\n' \
          "$first" "$second" "$third" "$actual" >&2
        exit 1
      fi
      passed=$((passed + 1))
    done
  done
done
printf 'Provenance retry workflow wiring and %s admission cases passed.\n' "$passed"
