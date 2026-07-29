#!/usr/bin/bash
set -euo pipefail
umask 077

bootstrap_root=${BOOTSTRAP_FIXTURE_BOOTSTRAP_ROOT:-/bootstrap}
source_dir=${BOOTSTRAP_FIXTURE_SOURCE_DIR:-/fixture}
expected_dir=${BOOTSTRAP_FIXTURE_EXPECTED_DIR:-/expected}
bootstrap="$bootstrap_root/bootstrap-release-authority-genesis-v2.sh"
operator_uid=${BOOTSTRAP_FIXTURE_OPERATOR_UID:-1000}
operator_gid=${BOOTSTRAP_FIXTURE_OPERATOR_GID:-1000}
args=(
    --source-dir "$source_dir"
    --expected-manifest-sha256 "$EXPECTED_MANIFEST_SHA256"
    --expected-workflow-commit "$EXPECTED_WORKFLOW_COMMIT"
    --expected-authority-version "$EXPECTED_AUTHORITY_VERSION"
    --expected-authority-commit "$EXPECTED_AUTHORITY_COMMIT"
    --expected-shipper-sha256 "$EXPECTED_SHIPPER_SHA256"
    --expected-verifier-sha256 "$EXPECTED_VERIFIER_SHA256"
    --expected-provisioner-sha256 "$EXPECTED_PROVISIONER_SHA256"
    --expected-helper-sha256 "$EXPECTED_HELPER_SHA256"
)

if [[ $operator_uid == 0 && $operator_gid == 0 ]]; then
    "$bootstrap" verify "${args[@]}"
else
    setpriv --reuid "$operator_uid" --regid "$operator_gid" --clear-groups \
        "$bootstrap" verify "${args[@]}"
fi

SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    MUTATE_OPERATOR_SOURCE_ON_VERIFY=1 \
    "$bootstrap" install "${args[@]}"
[[ $(sha256sum /usr/local/bin/syntaur-ship | awk '{print $1}') \
    == "$EXPECTED_SHIPPER_SHA256" ]]
[[ $(sha256sum /opt/syntaur-build-authority-provision | awk '{print $1}') \
    == "$EXPECTED_PROVISIONER_SHA256" ]]
[[ $(sha256sum "$source_dir/syntaur-ship-linux-x86_64" | awk '{print $1}') \
    != "$EXPECTED_SHIPPER_SHA256" ]]
[[ ! -e /run/syntaur-release-authority-genesis-v2.snapshot ]]

chmod 0700 "$source_dir"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$expected_dir/syntaur-ship-linux-x86_64" \
    "$source_dir/syntaur-ship-linux-x86_64"
chmod 0500 "$source_dir"
SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${args[@]}"

install -d -o root -g root -m 0700 \
    /run/syntaur-release-authority-genesis-v2.snapshot
if SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${args[@]}"; then
    printf 'stale root snapshot was unexpectedly accepted\n' >&2
    exit 1
fi

printf 'V2 genesis bootstrap behavioral fixture passed\n'
