#!/usr/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
    printf 'usage: %s BASE_COMMIT HEAD_COMMIT\n' "$0" >&2
    exit 2
fi

base=$1
head=$2
for commit in "$base" "$head"; do
    [[ $commit =~ ^[0-9a-f]{40}$ ]]
    git cat-file -e "$commit^{commit}"
done

saw_change=false
installer_only=true
while IFS= read -r -d '' path; do
    saw_change=true
    case "$path" in
        install.sh | install.ps1) ;;
        *) installer_only=false ;;
    esac
done < <(git diff --name-only -z "$base" "$head")

if [[ $saw_change == true && $installer_only == true ]]; then
    printf 'installer-only\n'
else
    printf 'full\n'
fi
