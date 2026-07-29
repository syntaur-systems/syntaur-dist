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
[[ $(<"$codeowners") == '* @syntaur-systems/release-authority-reviewers' ]] \
    || die 'CODEOWNERS does not bind the exact authority-reviewer team'

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
    .required_pull_request_reviews.dismiss_stale_reviews == true and
    .required_pull_request_reviews.require_code_owner_reviews == true and
    .required_pull_request_reviews.require_last_push_approval == true and
    .required_pull_request_reviews.required_approving_review_count >= 1 and
    ((.required_pull_request_reviews.bypass_pull_request_allowances.users // [])
      | length) == 0 and
    ((.required_pull_request_reviews.bypass_pull_request_allowances.teams // [])
      | length) == 0 and
    ((.required_pull_request_reviews.bypass_pull_request_allowances.apps // [])
      | length) == 0 and
    .required_conversation_resolution.enabled == true and
    .required_linear_history.enabled == true and
    .allow_force_pushes.enabled == false and
    .allow_deletions.enabled == false
' <<<"$protection" >/dev/null \
    || die 'main pull-request or history protection is incomplete'

team=$(gh api \
    "/orgs/syntaur-systems/teams/release-authority-reviewers")
[[ $(jq -r '.privacy' <<<"$team") == closed ]] \
    || die 'authority-reviewer team must be visible'
team_repository=$(gh api \
    "/orgs/syntaur-systems/teams/release-authority-reviewers/repos/${GITHUB_REPOSITORY}")
jq -e '
    .full_name == "syntaur-systems/syntaur-dist" and
    .role_name == "write" and
    .permissions.admin == false and
    .permissions.maintain == false and
    .permissions.push == true
' <<<"$team_repository" >/dev/null \
    || die 'authority-reviewer team lacks explicit repository write access'
members=$(gh api --paginate \
    "/orgs/syntaur-systems/teams/release-authority-reviewers/members?per_page=100" \
    --jq '.[].login')
[[ $(sed '/^$/d' <<<"$members" | sort -u | wc -l) -ge 2 ]] \
    || die 'authority-reviewer team lacks two distinct people'
grep -Fxv "$GITHUB_ACTOR" <<<"$members" >/dev/null \
    || die 'authority-reviewer team has no reviewer distinct from the actor'

validate_environment() {
    local name=$1
    local environment policies
    environment=$(gh api \
        "/repos/${GITHUB_REPOSITORY}/environments/${name}")
    jq -e '
        .can_admins_bypass == false and
        .deployment_branch_policy.protected_branches == false and
        .deployment_branch_policy.custom_branch_policies == true and
        (.protection_rules | length) == 2 and
        ([.protection_rules[].type] | sort) ==
          ["branch_policy", "required_reviewers"] and
        ([.protection_rules[] |
          select(.type == "required_reviewers")] | length) == 1 and
        ([.protection_rules[] |
          select(.type == "required_reviewers")][0].prevent_self_review) == true and
        ([.protection_rules[] |
          select(.type == "required_reviewers")][0].reviewers | length) == 1 and
        ([.protection_rules[] |
          select(.type == "required_reviewers")][0].reviewers[0].type) == "Team" and
        ([.protection_rules[] |
          select(.type == "required_reviewers")][0].reviewers[0].reviewer.slug) ==
          "release-authority-reviewers"
    ' <<<"$environment" >/dev/null \
        || die "${name} environment reviewer policy differs"
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
publisher_app=$(gh api /apps/syntaur-release-authority-publisher)
publisher_app_id=$(jq -er '.id' <<<"$publisher_app")
jq -e '
    .slug == "syntaur-release-authority-publisher" and
    .permissions.contents == "write" and
    .permissions.attestations == "read" and
    all(
      .permissions | to_entries[];
      (.key == "contents" and .value == "write") or
      (.key == "attestations" and .value == "read") or
      (.key == "metadata" and .value == "read")
    )
' <<<"$publisher_app" >/dev/null \
    || die 'publisher App permissions exceed Contents write and Attestations read'
jq -e --argjson publisher_app_id "$publisher_app_id" '
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
    .bypass_actors[0].actor_type == "Integration" and
    .bypass_actors[0].actor_id == $publisher_app_id and
    .bypass_actors[0].bypass_mode == "always"
' <<<"$ruleset" >/dev/null \
    || die 'authority-tag immutability or dedicated publisher bypass differs'

printf 'release authority repository, reviewer, both environments, and tag policy verified\n'
