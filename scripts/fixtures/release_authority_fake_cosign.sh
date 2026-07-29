#!/usr/bin/bash
set -euo pipefail

[[ ${1:-} == verify-blob ]]
manifest=${!#}
[[ -f $manifest && ! -L $manifest ]]
if [[ ${MUTATE_OPERATOR_SOURCE_ON_VERIFY:-0} == 1 ]]; then
    source_dir=${BOOTSTRAP_FIXTURE_SOURCE_DIR:-/fixture}
    chmod u+w "$source_dir/syntaur-ship-linux-x86_64"
    printf 'operator mutation after root snapshot\n' \
        >>"$source_dir/syntaur-ship-linux-x86_64"
    chmod 0500 "$source_dir/syntaur-ship-linux-x86_64"
fi
