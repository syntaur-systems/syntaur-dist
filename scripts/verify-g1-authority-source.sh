#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 6 ]] || {
    printf 'usage: verify-g1-authority-source.sh REPO COMMIT PARENT PARENT_TREE VERSION TOML_PARSER\n' >&2
    exit 2
}

repo=$1
commit=$2
parent=$3
parent_tree=$4
version=$5
toml_parser=$6
scratch=$(mktemp -d)
cleanup() {
    rm -rf "$scratch"
}
trap cleanup EXIT

for revision in "$commit" "$parent" "$parent_tree"; do
    [[ $revision =~ ^[0-9a-f]{40}$ ]] || {
        printf 'G1 source verifier received an invalid Git object ID\n' >&2
        exit 1
    }
done
[[ $version == 0.7.114 ]] || {
    printf 'G1 authority version must be exactly 0.7.114\n' >&2
    exit 1
}
[[ $toml_parser == /* && -f $toml_parser && ! -L $toml_parser \
    && -x $toml_parser ]] || {
    printf 'G1 source verifier requires the pinned regular TOML parser\n' >&2
    exit 1
}
[[ $(sha256sum "$toml_parser" | awk '{print $1}') \
    == d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b ]] || {
    printf 'G1 TOML parser differs from pinned yq v4.53.2\n' >&2
    exit 1
}

read -r -a ancestry <<<"$(git -C "$repo" rev-list --parents -n 1 "$commit")"
[[ ${#ancestry[@]} -eq 2 \
    && ${ancestry[0]} == "$commit" \
    && ${ancestry[1]} == "$parent" ]] || {
    printf 'G1 must have exactly the reviewed parent\n' >&2
    exit 1
}
[[ $(git -C "$repo" rev-parse "$parent^{tree}") == "$parent_tree" ]] || {
    printf 'G1 parent tree differs from the reviewed baseline\n' >&2
    exit 1
}
git -C "$repo" show "$commit:VERSION" >"$scratch/VERSION"
if ! cmp -s "$scratch/VERSION" <(printf '%s' "$version") \
    && ! cmp -s "$scratch/VERSION" <(printf '%s\n' "$version"); then
    printf 'G1 VERSION differs from the reviewed authority version\n' >&2
    exit 1
fi

has_validator=false
has_date_shim=false
has_git_shim=false
has_provisioner=false
changed_count=0
while IFS= read -r -d '' changed_path; do
    printf '%s' "$changed_path" | iconv -f UTF-8 -t UTF-8 >/dev/null || {
        printf 'G1 changed path is not UTF-8\n' >&2
        exit 1
    }
    changed_count=$((changed_count + 1))
    case $changed_path in
        Cargo.lock|RUSTSEC_DB_COMMIT|RUSTSEC_DB_TREE_SHA256|\
        docs/security/release-authority-promotion-policy.md|\
        scripts/check-runtime-paths.sh|\
        scripts/provision-syntaur-build-authority.sh|\
        syntaur-ship/*|\
        crates/syntaur-verify/*|\
        scripts/tests/test-syntaur-build-authority-*.sh)
            ;;
        *)
            printf 'G1 contains non-authority path %s\n' "$changed_path" >&2
            exit 1
            ;;
    esac
    case $changed_path in
        syntaur-ship/src/genesis_validation.rs) has_validator=true ;;
        syntaur-ship/build-tools/date) has_date_shim=true ;;
        syntaur-ship/build-tools/git) has_git_shim=true ;;
        scripts/provision-syntaur-build-authority.sh) has_provisioner=true ;;
    esac
done < <(
    git -C "$repo" diff-tree \
        --no-commit-id \
        --name-only \
        --no-renames \
        -r \
        -z \
        "$commit"
)
((changed_count > 0))
"$has_validator"
"$has_date_shim"
"$has_git_shim"
"$has_provisioner"

require_commit_blob() {
    local required_path=$1
    local expected_mode=$2
    local tree_entry metadata actual_path trailing
    local actual_mode actual_type actual_oid metadata_trailing

    tree_entry=$(git -C "$repo" ls-tree "$commit" -- "$required_path")
    [[ -n $tree_entry ]] || {
        printf 'G1 required path %s is absent from the candidate tree\n' \
            "$required_path" >&2
        exit 1
    }
    IFS=$'\t' read -r metadata actual_path trailing <<<"$tree_entry"
    IFS=' ' read -r \
        actual_mode actual_type actual_oid metadata_trailing <<<"$metadata"
    [[ -z ${trailing:-} \
        && -z ${metadata_trailing:-} \
        && $actual_path == "$required_path" \
        && $actual_mode == "$expected_mode" \
        && $actual_type == blob \
        && $actual_oid =~ ^[0-9a-f]{40}$ ]] || {
        printf 'G1 required path %s is not an exact %s regular blob\n' \
            "$required_path" "$expected_mode" >&2
        exit 1
    }
}

require_commit_blob syntaur-ship/src/genesis_validation.rs 100644
require_commit_blob syntaur-ship/build-tools/date 100755
require_commit_blob syntaur-ship/build-tools/git 100755
require_commit_blob scripts/provision-syntaur-build-authority.sh 100755

normalize_non_authority_lock_packages() {
    "$toml_parser" -p=toml -o=json '.' "$1" \
        | jq -e '
            if type != "object" or (.package | type) != "array" then
                error("G1 Cargo.lock lacks package entries")
            else
                all(.package[];
                    if type != "object" or (.name | type) != "string" then
                        error("G1 Cargo.lock package lacks a string name")
                    else
                        true
                    end
                )
            end
        ' >/dev/null
    "$toml_parser" -p=toml -o=yaml --no-colors \
        '.package |= map(
            select(.name != "syntaur-ship" and .name != "syntaur-verify")
        ) | sort_keys(..)' \
        "$1"
}

git -C "$repo" show "$parent:Cargo.lock" >"$scratch/parent.raw.lock"
git -C "$repo" show "$commit:Cargo.lock" >"$scratch/candidate.raw.lock"
normalize_non_authority_lock_packages \
    "$scratch/parent.raw.lock" >"$scratch/parent.filtered.lock"
normalize_non_authority_lock_packages \
    "$scratch/candidate.raw.lock" >"$scratch/candidate.filtered.lock"
cmp -s "$scratch/parent.filtered.lock" "$scratch/candidate.filtered.lock" || {
    printf 'G1 Cargo.lock changes non-authority package identity\n' >&2
    exit 1
}

printf 'G1 authority-only source verified: commit=%s parent=%s\n' \
    "$commit" "$parent"
