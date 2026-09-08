#!/usr/bin/env bash
set -euo pipefail

# Exercise the actual workflow step in real Git histories, including a push to
# main where origin/main already names HEAD. All writes stay in this fixture.
repository=$(pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
yq -r '.jobs."release-workflow".steps[] | select(.id == "scope") | .run' \
  .github/workflows/workflow-lint.yml >"$temporary/scope.sh"
test -s "$temporary/scope.sh"
bash -n "$temporary/scope.sh"
git init -q --initial-branch=main "$temporary/repo"
cd "$temporary/repo"
git config user.name 'Scope fixture'
git config user.email 'scope@example.invalid'
mkdir scripts
cp "$repository/scripts/classify-workflow-change.sh" scripts/
printf 'old installer\n' >install.sh
printf 'old policy\n' >policy.txt
git add .
tree=$(git write-tree)
export GIT_AUTHOR_DATE='2000-01-01T00:00:00Z'
export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
zero_base=
ordinary_base=
for ((nonce = 0; nonce < 4096; nonce++)); do
  commit=$(printf 'fixture %s\n' "$nonce" | git commit-tree "$tree")
  if [[ $commit == 0* ]]; then
    zero_base=$commit
  else
    ordinary_base=$commit
  fi
  if [[ -n $zero_base && -n $ordinary_base ]]; then
    break
  fi
done
test -n "$zero_base"
test -n "$ordinary_base"
git update-ref refs/heads/main "$zero_base"
git reset -q --hard "$zero_base"
printf 'new installer\n' >install.sh
git add install.sh
git commit -qm 'installer only'
installer_head=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$installer_head"

cases=0
check_scope() {
  local label=$1 event=$2 before=$3 pr_base=$4 head=$5 expected=$6
  : >"$temporary/output"
  EVENT_NAME=$event PUSH_BEFORE_SHA=$before PR_BASE_SHA=$pr_base \
    GITHUB_SHA=$head GITHUB_OUTPUT="$temporary/output" \
    bash "$temporary/scope.sh"
  local actual
  actual=$(cat "$temporary/output")
  if [[ $actual != "scope=$expected" ]]; then
    printf '%s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  cases=$((cases + 1))
  printf 'PASS %s\n' "$label"
}

check_scope leading-zero-main-push push "$zero_base" '' "$installer_head" installer-only
check_scope ordinary-base-push push "$ordinary_base" '' "$installer_head" installer-only
check_scope pull-request-base pull_request '' "$zero_base" "$installer_head" installer-only
check_scope no-changes push "$installer_head" '' "$installer_head" full
check_scope unsupported-event workflow_dispatch "$zero_base" '' "$installer_head" full
check_scope zero-sentinel-main push 0000000000000000000000000000000000000000 '' "$installer_head" full
check_scope malformed-before-main push 'not-a-sha' '' "$installer_head" full
check_scope missing-pr-base pull_request '' '' "$installer_head" full
git update-ref refs/remotes/origin/main "$zero_base"
check_scope new-branch-merge-base push 0000000000000000000000000000000000000000 '' "$installer_head" installer-only
git update-ref -d refs/remotes/origin/main
check_scope missing-origin-main push 0000000000000000000000000000000000000000 '' "$installer_head" full

: >"$temporary/output"
if EVENT_NAME=push PUSH_BEFORE_SHA=0000000000000000000000000000000000000001 \
  PR_BASE_SHA='' GITHUB_SHA=$installer_head GITHUB_OUTPUT="$temporary/output" \
  bash "$temporary/scope.sh" >"$temporary/unknown.log" 2>&1; then
  echo 'unknown commit must fail closed' >&2
  exit 1
fi
test ! -s "$temporary/output"
cases=$((cases + 1))
printf 'PASS unknown-commit-fails-closed\n'

printf 'new policy\n' >policy.txt
git add policy.txt
git commit -qm 'policy and installer change'
check_scope mixed-change push "$zero_base" '' "$(git rev-parse HEAD)" full
git reset -q --hard "$zero_base"
git rm -q install.sh
git commit -qm 'remove installer'
check_scope installer-deletion push "$zero_base" '' "$(git rev-parse HEAD)" installer-only
# Product release workflows are not inputs to the isolated legacy bootstrap
# fixture. Any mixed change must retain full coverage.
git reset -q --hard "$zero_base"
mkdir -p .github/workflows
printf 'release fixture\n' >.github/workflows/release-sign.yml
git add .github/workflows/release-sign.yml
git commit -qm 'product release workflow'
product_base=$(git rev-parse HEAD)
check_scope product-release-workflow push "$zero_base" '' "$product_base" product-workflows-only
printf 'pretag fixture\n' >.github/workflows/source-pretag.yml
git add .github/workflows/source-pretag.yml
git commit -qm 'source pretag workflow'
product_head=$(git rev-parse HEAD)
check_scope source-pretag-workflow push "$product_base" '' "$product_head" product-workflows-only
check_scope both-product-workflows push "$zero_base" '' "$product_head" product-workflows-only
check_scope product-workflow-pr pull_request '' "$zero_base" "$product_head" product-workflows-only
for mixed_path in \
    install.sh \
    policy.txt \
    .github/workflows/workflow-lint.yml \
    .github/workflows/release-authority.yml \
    scripts/classify-workflow-change.sh \
    scripts/test-release-authority-bootstrap.sh \
    scripts/bootstrap-release-authority-genesis-v2.sh \
    scripts/fixtures/release_authority_bootstrap.Dockerfile; do
  git reset -q --hard "$product_head"
  mkdir -p "$(dirname "$mixed_path")"
  printf '# mixed change\n' >>"$mixed_path"
  git add "$mixed_path"
  git commit -qm 'mixed product and bootstrap dependency'
  check_scope "product-mixed-$mixed_path" push "$zero_base" '' "$(git rev-parse HEAD)" full
done
git reset -q --hard "$product_head"
git rm -q .github/workflows/source-pretag.yml
git commit -qm 'remove pretag workflow'
check_scope product-deletion push "$product_head" '' "$(git rev-parse HEAD)" product-workflows-only
# Classifying a deletion does not admit a missing required workflow; the
# mandatory validator rejects it before any scope-dependent fixture step.
printf 'workflow change-scope cases passed: %s\n' "$cases"
