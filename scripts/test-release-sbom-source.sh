#!/usr/bin/env bash
set -euo pipefail
workflow=${1:-.github/workflows/release-sign.yml}
real_sbom=${2:-}
if [ -n "$real_sbom" ]; then real_sbom=$(realpath "$real_sbom"); fi
repository=$(cd "$(dirname "$workflow")/../.." && pwd)
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
  $g[0].with["syft-version"] == "v1.42.3" and
  ([$s[] | select(.name == "Checkout exact SBOM release helper")][0] |
    .with.repository == "syntaur-systems/syntaur-dist" and
    .with.ref == "${{ github.workflow_sha }}" and
    .with.path == ".release-sbom-tools" and
    .with["persist-credentials"] == false) and
  ([$s[] | select(.name == "Build exact Rust SBOM release helper")][0] |
    .env.WORKFLOW_COMMIT == "${{ github.workflow_sha }}" and
    (.run | contains("cargo test --locked")) and
    (.run | contains("cargo build --locked"))) and
  ($p[0].if == $g[0].if and $v[0].if == $g[0].if) and
  ($s | map(.name) | index($p[0].name) < index($g[0].name)) and
  ($s | map(.name) | index($g[0].name) < index($v[0].name)) and
  ($s | map(.name) | index($v[0].name) < index("Upload optional SBOM artifact (Linux gateway only)"))
' "$temporary/job.json" >/dev/null
jq -r '.steps[] | select(.id == "sbom_source") | .run' "$temporary/job.json" >"$temporary/prepare.sh"
jq -r '.steps[] | select(.name == "Validate dependency SBOM artifact (Linux gateway only)") | .run' "$temporary/job.json" >"$temporary/validate.sh"
bash -n "$temporary/prepare.sh" "$temporary/validate.sh"
cargo test --locked --manifest-path "$repository/tools/sbom-normalize/Cargo.toml" --target-dir "$temporary/rust-target"
cargo build --locked --manifest-path "$repository/tools/sbom-normalize/Cargo.toml" --target-dir "$temporary/rust-target"
export SYNTAUR_SBOM_NORMALIZER="$temporary/rust-target/debug/syntaur-sbom-normalize"

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
printf '{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[]}\n' >syntaur-sbom.spdx.json
bash "$temporary/validate.sh"
for kind in empty oversized malformed wrong-schema json-stream symlink dangling; do
  rm -f syntaur-sbom.spdx.json
  case "$kind" in
    empty) touch syntaur-sbom.spdx.json ;;
    oversized) truncate -s 33554433 syntaur-sbom.spdx.json ;;
    malformed) printf 'invalid' >syntaur-sbom.spdx.json ;;
    wrong-schema) printf '{}' >syntaur-sbom.spdx.json ;;
    json-stream) printf '{} {"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[]}\n' >syntaur-sbom.spdx.json ;;
    symlink) printf '{}' >target; ln -s target syntaur-sbom.spdx.json ;;
    dangling) ln -s absent syntaur-sbom.spdx.json ;;
  esac
  if bash "$temporary/validate.sh" >/dev/null 2>&1; then
    echo "SBOM validation accepted $kind" >&2; exit 1
  fi
done
# Exercise every SPDX 2.3 local-reference field, plus metadata that must
# remain unchanged even when its text happens to equal an old node ID.
rm -f syntaur-sbom.spdx.json
cat > original.json <<'JSON'
{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT",
 "documentDescribes":["SPDXRef-Package-long"],
 "packages":[{"SPDXID":"SPDXRef-Package-long","name":"fixture","hasFiles":["SPDXRef-File-long"],"comment":"SPDXRef-File-long","externalRefs":[{"referenceLocator":"pkg:cargo/example@1","referenceType":"purl","referenceCategory":"PACKAGE-MANAGER"}]}],
 "files":[{"SPDXID":"SPDXRef-File-long","fileName":"Cargo.lock","fileDependencies":["SPDXRef-File-long"]}],
 "snippets":[{"SPDXID":"SPDXRef-Snippet-long","snippetFromFile":"SPDXRef-File-long","ranges":[{"startPointer":{"reference":"SPDXRef-File-long","offset":0},"endPointer":{"reference":"SPDXRef-File-long","offset":5}}]}],
 "relationships":[{"spdxElementId":"SPDXRef-Package-long","relatedSpdxElement":"SPDXRef-File-long","relationshipType":"CONTAINS"},{"spdxElementId":"SPDXRef-Package-long","relatedSpdxElement":"NOASSERTION","relationshipType":"OTHER"}]}
JSON
cp original.json syntaur-sbom.spdx.json
bash "$temporary/validate.sh"
# Assert independent expected relabeling, including untouched metadata.
jq -e '
 .documentDescribes == ["SPDXRef-1"] and
 .packages[0].SPDXID == "SPDXRef-1" and .packages[0].hasFiles == ["SPDXRef-0"] and
 .packages[0].comment == "SPDXRef-File-long" and
 .packages[0].externalRefs[0].referenceLocator == "pkg:cargo/example@1" and
 .files[0].SPDXID == "SPDXRef-0" and .files[0].fileDependencies == ["SPDXRef-0"] and
 .snippets[0].SPDXID == "SPDXRef-2" and .snippets[0].snippetFromFile == "SPDXRef-0" and
 .snippets[0].ranges[0].startPointer.reference == "SPDXRef-0" and
 .snippets[0].ranges[0].endPointer.reference == "SPDXRef-0" and
 .relationships[0].spdxElementId == "SPDXRef-1" and
 .relationships[0].relatedSpdxElement == "SPDXRef-0" and
 .relationships[1].relatedSpdxElement == "NOASSERTION"
' syntaur-sbom.spdx.json >/dev/null
for mutation in   '.packages[0].SPDXID = "SPDXRef-DOCUMENT"'   '.packages[0].SPDXID = "bad identifier"'   'del(.files[0].SPDXID)'   '.relationships[0].relatedSpdxElement = "SPDXRef-missing"'   '.files[0].fileDependencies = ["SPDXRef-missing"]' '.packages[0].hasFiles = ["NONE"]'   '.snippets[0].ranges[0].startPointer.reference = "SPDXRef-missing"'   '.externalDocumentRefs = [{"externalDocumentId":"DocumentRef-external"}]'   '.spdxVersion = "SPDX-3.0"'   '.packages[0].comment = ("x" * 16777216)'; do
  jq -c "$mutation" original.json >syntaur-sbom.spdx.json
  before=$(sha256sum syntaur-sbom.spdx.json)
  if bash "$temporary/validate.sh" >/dev/null 2>&1; then
    echo "SBOM normalization accepted invalid or over-limit input: $mutation" >&2; exit 1
  fi
  test "$before" = "$(sha256sum syntaur-sbom.spdx.json)"
done
if [ -n "$real_sbom" ]; then
  cp "$real_sbom" syntaur-sbom.spdx.json
  bash "$temporary/validate.sh"
  jq -e --slurpfile original "$real_sbom" '
    . as $output |
    all(["packages","files","relationships"][];
      . as $field | ($output[$field] | length) == ($original[0][$field] | length))
  ' syntaur-sbom.spdx.json >/dev/null
  printf 'Real scanner fixture normalized to %s bytes with unchanged graph counts.\n'     "$(wc -c <syntaur-sbom.spdx.json)"
fi
echo 'Dependency SBOM source snapshot, all local-reference fields, graph checks, and artifact bounds passed.'
