#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'release authority policy error: %s\n' "$*" >&2
    exit 1
}

: "${GH_TOKEN:?SYNTAUR_RELEASE_AUTHORITY_ADMIN_READ_TOKEN is required}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_REF:?}"
: "${GITHUB_ACTOR:?}"

[[ $GITHUB_REPOSITORY == syntaur-systems/syntaur-dist ]] \
    || die 'repository identity differs'
[[ $GITHUB_REF == refs/heads/main ]] || die 'authority must run from main'

repo_root=${GITHUB_WORKSPACE:-.}
if [[ -d $repo_root/public-workflow ]]; then
    repo_root=$repo_root/public-workflow
fi
codeowners="$repo_root/.github/CODEOWNERS"
[[ -f $codeowners && ! -L $codeowners ]] || die 'CODEOWNERS is absent or unsafe'
[[ $(wc -l <"$codeowners") -eq 1 ]] || die 'CODEOWNERS must have one exact rule'
[[ $(<"$codeowners") == '* @buddyholly007' ]] \
    || die 'CODEOWNERS does not bind the repository owner'

actions_app_id=$(gh api /apps/github-actions --jq '.id')
protection=$(gh api \
    "/repos/${GITHUB_REPOSITORY}/branches/main/protection")
jq -e --argjson actions_app_id "$actions_app_id" '
    .required_status_checks.strict == true and
    (.required_status_checks.checks | length) == 2 and
    ([.required_status_checks.checks[].context] | sort) == [
      "release-workflow",
      "windows-eula"
    ] and
    all(.required_status_checks.checks[]; .app_id == $actions_app_id)
' <<<"$protection" >/dev/null \
    || die 'main required checks are not exact GitHub Actions checks'
[[ $(jq -r '.enforce_admins.enabled' <<<"$protection") == true ]] \
    || die 'main protection does not include administrators'
jq -e '
    .required_pull_request_reviews == null and
    .required_conversation_resolution.enabled == true and
    .required_linear_history.enabled == false and
    .allow_force_pushes.enabled == false and
    .allow_deletions.enabled == false
' <<<"$protection" >/dev/null \
    || die 'main automated and history protection is incomplete'

validate_environment() {
    local name=$1
    local environment policies
    environment=$(gh api \
        "/repos/${GITHUB_REPOSITORY}/environments/${name}")
    jq -e '
        .can_admins_bypass == false and
        .deployment_branch_policy.protected_branches == false and
        .deployment_branch_policy.custom_branch_policies == true and
        (.protection_rules | length) == 1 and
        .protection_rules[0].type == "branch_policy"
    ' <<<"$environment" >/dev/null \
        || die "${name} automated environment policy differs"
    policies=$(gh api --paginate \
        "/repos/${GITHUB_REPOSITORY}/environments/${name}/deployment-branch-policies?per_page=100")
    jq -e '
        .total_count == 1 and
        .branch_policies[0].name == "main" and
        .branch_policies[0].type == "branch"
    ' <<<"$policies" >/dev/null \
        || die "${name} environment branch policy differs"
}

validate_environment release-authority-source
validate_environment release-authority
[[ $(gh api "/repos/${GITHUB_REPOSITORY}/immutable-releases" --jq '.enabled') == true ]] \
    || die 'immutable releases are not enabled'

rulesets=$(gh api \
    "/repos/${GITHUB_REPOSITORY}/rulesets?includes_parents=true")
ruleset_ids=$(jq -r '
    .[] |
    select(.name == "release-authority-tags" and
           .target == "tag" and
           .enforcement == "active") |
    .id
' <<<"$rulesets")
[[ $(sed '/^$/d' <<<"$ruleset_ids" | wc -l) -eq 1 ]] \
    || die 'one exact active authority-tag ruleset is required'
ruleset=$(gh api \
    "/repos/${GITHUB_REPOSITORY}/rulesets/${ruleset_ids}")
jq -e '
    .name == "release-authority-tags" and
    .target == "tag" and
    .enforcement == "active" and
    .conditions.ref_name.include == ["refs/tags/authority-v1-g*"] and
    .conditions.ref_name.exclude == [] and
    ([.rules[].type] | sort) == [
      "creation",
      "deletion",
      "non_fast_forward",
      "update"
    ] and
    (.bypass_actors | length) == 1 and
    .bypass_actors[0].actor_type == "RepositoryRole" and
    .bypass_actors[0].actor_id == 5 and
    .bypass_actors[0].bypass_mode == "always"
' <<<"$ruleset" >/dev/null \
    || die 'authority-tag immutability or repository-owner publisher bypass differs'

printf 'release authority repository, automated environments, and tag policy verified\n'
