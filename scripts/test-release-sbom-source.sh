#!/usr/bin/env bash
set -euo pipefail
workflow=${1:-.github/workflows/release-sign.yml}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
yq -o=json '.jobs.build' "$workflow" >"$temporary/job.json"
jq -e '
  .steps as $s |
  [$s[] | select(.name == "Prepare exact dependency SBOM source (Linux gateway only)")] as $p |
  [$s[] | select(.name == "Generate dependency SBOM (Linux gateway only)")] as $g |
  [$s[] | select(.name == "Validate dependency SBOM artifact (Linux gateway only)")] as $v |
  ($p | length == 1) and ($g | length == 1) and ($v | length == 1) and
  $p[0].id == "sbom_source" and
  (($p[0]["continue-on-error"] // false) == false) and
  (($v[0]["continue-on-error"] // false) == false) and
  $g[0].with.path == "${{ steps.sbom_source.outputs.path }}" and
  $g[0].with["upload-release-assets"] == false and
  ($p[0].if == $g[0].if and $v[0].if == $g[0].if) and
  ($s | map(.name) | index($p[0].name) < index($g[0].name)) and
  ($s | map(.name) | index($g[0].name) < index($v[0].name)) and
  ($s | map(.name) | index($v[0].name) < index("Upload optional SBOM artifact (Linux gateway only)"))
' "$temporary/job.json" >/dev/null
jq -r '.steps[] | select(.id == "sbom_source") | .run' "$temporary/job.json" >"$temporary/prepare.sh"
jq -r '.steps[] | select(.name == "Validate dependency SBOM artifact (Linux gateway only)") | .run' "$temporary/job.json" >"$temporary/validate.sh"
bash -n "$temporary/prepare.sh" "$temporary/validate.sh"
mkdir "$temporary/source" "$temporary/runner" "$temporary/artifact"
cd "$temporary/source"
git init -q
git config user.name Test
git config user.email test@example.invalid
mkdir -p nested
printf 'root lock\n' >Cargo.lock
printf 'nested lock\n' >nested/Cargo.lock
printf 'manifest\n' >nested/Cargo.toml
git add .
git commit -qm fixture
mkdir -p target/debug dist
printf 'polluted build metadata\n' >target/debug/Cargo.lock
printf 'binary\n' >dist/syntaur
printf 'untracked\n' >extra.lock
printf 'mutated after build\n' >Cargo.lock
export RUNNER_TEMP="$temporary/runner" GITHUB_OUTPUT="$temporary/output"
bash "$temporary/prepare.sh"
snapshot=$(sed -n 's/^path=//p' "$GITHUB_OUTPUT")
test "$(cat "$snapshot/Cargo.lock")" = 'root lock'
test "$(cat "$snapshot/nested/Cargo.lock")" = 'nested lock'
test -f "$snapshot/nested/Cargo.toml"
test ! -e "$snapshot/target"
test ! -e "$snapshot/dist"
test ! -e "$snapshot/extra.lock"
# An unhandled submodule must not silently omit dependencies.
git update-index --add --cacheinfo 160000,"$(git rev-parse HEAD)",aaa-submodule
# Large trailing tree catches an early grep -q/SIGPIPE false-negative.
mkdir many
for n in {1..3000}; do printf 'fixture\n' >"many/$n"; done
git add many
git commit -qm submodule
if bash "$temporary/prepare.sh" >/dev/null 2>&1; then
  echo 'SBOM preparation accepted a submodule' >&2; exit 1
fi
git rm --cached aaa-submodule >/dev/null
if bash "$temporary/prepare.sh" >/dev/null 2>&1; then
  echo 'SBOM preparation accepted a committed submodule hidden by index changes' >&2; exit 1
fi
printf 'nested/Cargo.lock export-ignore\n' >.gitattributes
git add .gitattributes
git commit -qm archive-omission
if bash "$temporary/prepare.sh" >/dev/null 2>&1; then
  echo 'SBOM preparation accepted archive-omitted source' >&2; exit 1
fi
git rm .gitattributes >/dev/null
ln -s /tmp outside-source
git add outside-source
git commit -qm source-symlink
if bash "$temporary/prepare.sh" >/dev/null 2>&1; then
  echo 'SBOM preparation accepted a source symlink' >&2; exit 1
fi
cd "$temporary/artifact"
bash "$temporary/validate.sh" # absent supplementary artifact
printf '{"spdxVersion":"SPDX-2.3","packages":[]}\n' >syntaur-sbom.spdx.json
bash "$temporary/validate.sh"
for kind in empty oversized malformed wrong-schema json-stream symlink dangling; do
  rm -f syntaur-sbom.spdx.json
  case "$kind" in
    empty) touch syntaur-sbom.spdx.json ;;
    oversized) truncate -s 16777217 syntaur-sbom.spdx.json ;;
    malformed) printf 'invalid' >syntaur-sbom.spdx.json ;;
    wrong-schema) printf '{}' >syntaur-sbom.spdx.json ;;
    json-stream) printf '{} {"spdxVersion":"SPDX-2.3","packages":[]}\n' >syntaur-sbom.spdx.json ;;
    symlink) printf '{}' >target; ln -s target syntaur-sbom.spdx.json ;;
    dangling) ln -s absent syntaur-sbom.spdx.json ;;
  esac
  if bash "$temporary/validate.sh" >/dev/null 2>&1; then
    echo "SBOM validation accepted $kind" >&2; exit 1
  fi
done
echo 'Dependency SBOM source snapshot, workflow wiring, and artifact bounds passed.'
