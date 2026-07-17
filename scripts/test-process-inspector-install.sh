#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
command -v sudo >/dev/null
command -v setcap >/dev/null
command -v getcap >/dev/null
setfacl_bin=$(command -v setfacl)
getfacl_bin=$(command -v getfacl)

temporary=$(mktemp -d)
root=/usr/local/libexec/syntaur/process-inspectors
versions=()

cleanup() {
  local version
  for version in "${versions[@]}"; do
    sudo -n rm -rf -- "$root/$version"
  done
  rm -rf "$temporary"
}
trap cleanup EXIT

export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
# shellcheck disable=SC1091 # resolved from the canonical repository path above.
source "$repository/install.sh"

staged="$temporary/syntaur-process-inspector"
if [[ -n ${SYNTAUR_TEST_PROCESS_INSPECTOR:-} ]]; then
  cp -- "$SYNTAUR_TEST_PROCESS_INSPECTOR" "$staged"
else
  cc -std=c11 -O2 -Wall -Wextra -Werror \
    "$repository/scripts/fixtures/process_inspector_protocol.c" \
    -o "$staged"
fi
chmod 700 "$staged"
expected=$(sha256sum "$staged" | awk '{print $1}')
probe="$temporary/probe"
mkdir -m 700 "$probe"

version_for() {
  printf '987.%s.%s\n' "$$" "$1"
}

remember_version() {
  versions+=("$1")
}

destination_for() {
  printf '%s/%s/syntaur-process-inspector\n' "$root" "$1"
}

snapshot() {
  local path=$1
  if [[ -L $path ]]; then
    printf 'symlink:%s\n' "$(readlink -- "$path")"
    return
  fi
  stat -c '%u:%g:%a:%h:%F' -- "$path"
  sha256sum -- "$path"
  getcap -n "$path"
  "$getfacl_bin" -cp -- "$path"
}

provision() {
  local version=$1
  provision_process_inspector "$staged" "$expected" "$version" "$root" "$probe"
}

expect_invalid_unchanged() {
  local version=$1 label=$2 destination before after
  destination=$(destination_for "$version")
  before=$(snapshot "$destination")
  if SYNTAUR_INSTALL_TEST_FORBID_SUDO=1 provision "$version" >/dev/null 2>&1; then
    printf '%s\n' "invalid $label process inspector was accepted" >&2
    exit 1
  fi
  after=$(snapshot "$destination")
  [[ $after == "$before" ]] || {
    printf '%s\n' "invalid $label process inspector changed during rejection" >&2
    exit 1
  }
}

wrong_hash_version=$(version_for 1)
remember_version "$wrong_hash_version"
if provision_process_inspector \
    "$staged" \
    "$(printf '0%.0s' {1..64})" \
    "$wrong_hash_version" \
    "$root" \
    "$probe" >/dev/null 2>&1; then
  echo 'wrong staged process inspector hash was accepted' >&2
  exit 1
fi
[[ ! -e $root/$wrong_hash_version ]]

reuse_version=$(version_for 2)
remember_version "$reuse_version"
provision "$reuse_version" >/dev/null
reuse_destination=$(destination_for "$reuse_version")
before_reuse=$(snapshot "$reuse_destination")
SYNTAUR_INSTALL_TEST_FORBID_SUDO=1 provision "$reuse_version" >/dev/null
[[ $(snapshot "$reuse_destination") == "$before_reuse" ]]

mode_version=$(version_for 3)
remember_version "$mode_version"
provision "$mode_version" >/dev/null
sudo -n chmod 0775 -- "$(destination_for "$mode_version")"
expect_invalid_unchanged "$mode_version" mode

capability_version=$(version_for 4)
remember_version "$capability_version"
provision "$capability_version" >/dev/null
sudo -n setcap cap_net_bind_service=ep "$(destination_for "$capability_version")"
expect_invalid_unchanged "$capability_version" capability

owner_version=$(version_for 5)
remember_version "$owner_version"
provision "$owner_version" >/dev/null
sudo -n chown 65534:65534 -- "$(destination_for "$owner_version")"
sudo -n setcap cap_sys_ptrace=ep "$(destination_for "$owner_version")"
expect_invalid_unchanged "$owner_version" owner

link_version=$(version_for 6)
remember_version "$link_version"
provision "$link_version" >/dev/null
sudo -n ln "$(destination_for "$link_version")" "$root/$link_version/extra-link"
expect_invalid_unchanged "$link_version" hardlink

acl_version=$(version_for 7)
remember_version "$acl_version"
provision "$acl_version" >/dev/null
sudo -n "$setfacl_bin" -m u:65534:rx "$(destination_for "$acl_version")"
expect_invalid_unchanged "$acl_version" ACL

symlink_version=$(version_for 8)
remember_version "$symlink_version"
sudo -n install -d -m 0755 -o root -g root -- "$root/$symlink_version"
sudo -n ln -s /bin/true "$(destination_for "$symlink_version")"
expect_invalid_unchanged "$symlink_version" symlink

race_version=$(version_for 9)
remember_version "$race_version"
race_ready="$temporary/race-ready"
race_continue="$temporary/race-continue"
race_log="$temporary/race.log"
(
  SYNTAUR_INSTALL_TEST_BEFORE_PUBLISH_READY="$race_ready" \
  SYNTAUR_INSTALL_TEST_BEFORE_PUBLISH_CONTINUE="$race_continue" \
    provision "$race_version"
) >"$race_log" 2>&1 &
race_pid=$!
for _ in {1..200}; do
  [[ -e $race_ready ]] && break
  kill -0 "$race_pid" 2>/dev/null || {
    cat "$race_log" >&2
    echo 'process inspector race fixture exited before publication gate' >&2
    exit 1
  }
  sleep 0.05
done
[[ -e $race_ready ]]
race_destination=$(destination_for "$race_version")
sudo -n install -m 0755 -o root -g root -- /bin/true "$race_destination"
race_before=$(snapshot "$race_destination")
: >"$race_continue"
if wait "$race_pid"; then
  echo 'process inspector publication replaced a concurrent destination' >&2
  exit 1
fi
[[ $(snapshot "$race_destination") == "$race_before" ]]

posix_version=$(version_for 10)
remember_version "$posix_version"
REPOSITORY="$repository" \
STAGED_INSPECTOR="$staged" \
EXPECTED_SHA256="$expected" \
RELEASE_VERSION="$posix_version" \
INSPECTOR_ROOT="$root" \
PROBE_DIRECTORY="$probe" \
  /bin/sh -c '
    SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
    export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
    . "$REPOSITORY/install.sh"
    provision_process_inspector \
      "$STAGED_INSPECTOR" "$EXPECTED_SHA256" "$RELEASE_VERSION" \
      "$INSPECTOR_ROOT" "$PROBE_DIRECTORY" >/dev/null
    SYNTAUR_INSTALL_TEST_FORBID_SUDO=1
    export SYNTAUR_INSTALL_TEST_FORBID_SUDO
    provision_process_inspector \
      "$STAGED_INSPECTOR" "$EXPECTED_SHA256" "$RELEASE_VERSION" \
      "$INSPECTOR_ROOT" "$PROBE_DIRECTORY" >/dev/null
  '

fixed_tool_version=$(version_for 11)
remember_version "$fixed_tool_version"
# shellcheck disable=SC2329 # resolved indirectly by the sourced installer function.
awk() {
  printf '%064d\n' 0
}
if provision_process_inspector \
    "$staged" \
    "$(printf '0%.0s' {1..64})" \
    "$fixed_tool_version" \
    "$root" \
    "$probe" >/dev/null 2>&1; then
  echo 'process inspector checksum validation used a shell override' >&2
  exit 1
fi
unset -f awk
[[ ! -e $root/$fixed_tool_version ]]

echo 'process inspector installer tests passed'
