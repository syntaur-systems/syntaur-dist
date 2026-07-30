#!/usr/bin/bash
set -euo pipefail

[[ $# -eq 10 ]]
[[ $1 == verify-blob ]]
[[ $2 == --bundle ]]
bundle=$3
[[ $4 == --certificate-identity ]]
[[ $5 == \
    https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main ]]
[[ $6 == --certificate-oidc-issuer ]]
[[ $7 == https://token.actions.githubusercontent.com ]]
[[ $8 == --certificate-github-workflow-sha ]]
[[ $9 =~ ^[0-9a-f]{40}$ ]]
manifest=${10}
[[ -f $manifest && ! -L $manifest ]]
[[ -f $bundle && ! -L $bundle ]]
[[ $(jq -er '.mediaType' "$bundle") == \
    application/vnd.dev.sigstore.bundle.v0.3+json ]]
[[ $(jq -er '.workflow_commit' "$manifest") == "$9" ]]
if [[ ${MUTATE_OPERATOR_SOURCE_ON_VERIFY:-0} == 1 ]]; then
    source_dir=${BOOTSTRAP_FIXTURE_SOURCE_DIR:-/fixture}
    chmod u+w "$source_dir/syntaur-ship-linux-x86_64"
    printf 'operator mutation after root snapshot\n' \
        >>"$source_dir/syntaur-ship-linux-x86_64"
    chmod 0500 "$source_dir/syntaur-ship-linux-x86_64"
fi
