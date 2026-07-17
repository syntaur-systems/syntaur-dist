#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

expected_eula_sha=3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720
actual_eula_sha=$(sha256sum "$repository/EULA.md" | awk '{print $1}')
[ "$actual_eula_sha" = "$expected_eula_sha" ]
grep -Fxq "EULA_SHA256=\"$expected_eula_sha\"" "$repository/install.sh"

load_installer_library() {
  export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  # shellcheck source=/dev/null
  . "$repository/install.sh"
  unset SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
}

assert_rejected() {
  if "$@"; then
    echo "unexpected acceptance: $*" >&2
    return 1
  fi
}

write_legacy_record() {
  record=$1
  mkdir -p "$(dirname "$record")"
  chmod 700 "$(dirname "$record")"
  cat >"$record" <<'EOF'
eula_version=1.0
eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md
accepted_at=2026-07-17T13:58:33Z
method=flag
installer_version=0.7.114
EOF
  chmod 644 "$record"
}

(
  HOME="$temporary/legacy"
  export HOME
  load_installer_library
  record="$HOME/.syntaur/eula-accepted"
  write_legacy_record "$record"
  before=$(sha256sum "$record" | awk '{print $1}')
  assert_rejected eula_record_is_current "$record"
  # shellcheck disable=SC2031,SC2034 # sourced function consumes this subshell global.
  ACCEPT_EULA=1
  output=$(ensure_eula_acceptance </dev/null)
  after=$(sha256sum "$record" | awk '{print $1}')
  [ "$before" != "$after" ]
  printf '%s\n' "$output" | grep -Fq 'EULA v1.0 accepted (via flag).'
  eula_record_is_current "$record"
)

(
  HOME="$temporary/current"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  persist_eula_acceptance prompt
  record="$HOME/.syntaur/eula-accepted"
  eula_record_is_current "$record"
  [ "$(portable_stat_mode "$record")" = 600 ]
  [ "$(find "$HOME/.syntaur" -maxdepth 1 -name '.eula-accepted.tmp.*' | wc -l)" -eq 0 ]
)

sh_home="$temporary/posix-sh"
sh_record="$sh_home/.syntaur/eula-accepted"
(
  HOME="$sh_home"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  persist_eula_acceptance flag
)
sh_before=$(sha256sum "$sh_record" | awk '{print $1}')
sh_output=$(
  HOME="$sh_home" SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 \
    /bin/sh -c '. "$1/install.sh"; ensure_eula_acceptance </dev/null' sh "$repository"
)
sh_after=$(sha256sum "$sh_record" | awk '{print $1}')
[ "$sh_before" = "$sh_after" ]
printf '%s\n' "$sh_output" | grep -Fq 'EULA v1.0 previously accepted; continuing.'

(
  HOME="$temporary/mismatch"
  export HOME
  load_installer_library
  mkdir -p "$HOME/.syntaur"
  chmod 700 "$HOME/.syntaur"
  record="$HOME/.syntaur/eula-accepted"
  cat >"$record" <<'EOF'
record_format=1
eula_version=1.0
eula_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
eula_url=https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md
accepted_at=2026-07-17T13:58:33Z
method=flag
installer_version=0.7.114
EOF
  chmod 600 "$record"
  assert_rejected eula_record_is_current "$record"
  # shellcheck disable=SC2031,SC2034 # sourced function consumes this subshell global.
  ACCEPT_EULA=1
  ensure_eula_acceptance >/dev/null
  eula_record_is_current "$record"
  grep -Fxq "eula_sha256=$expected_eula_sha" "$record"
)

(
  HOME="$temporary/malformed"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  persist_eula_acceptance flag
  record="$HOME/.syntaur/eula-accepted"
  printf 'method=flag\n' >>"$record"
  assert_rejected eula_record_is_current "$record"
  sed -i 's|^accepted_at=.*$|accepted_at=not-a-time|' "$record"
  assert_rejected eula_record_is_current "$record"
  dd if=/dev/zero of="$record" bs=4097 count=1 status=none
  assert_rejected eula_record_is_current "$record"
)

(
  HOME="$temporary/permissions"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  persist_eula_acceptance flag
  record="$HOME/.syntaur/eula-accepted"
  chmod 666 "$record"
  assert_rejected eula_record_is_current "$record"
  chmod 600 "$record"
  chmod 722 "$HOME/.syntaur"
  assert_rejected eula_record_is_current "$record"
)

(
  HOME="$temporary/record-symlink"
  export HOME
  load_installer_library
  mkdir -p "$HOME/.syntaur"
  chmod 700 "$HOME/.syntaur"
  target="$temporary/symlink-target"
  printf 'do-not-change\n' >"$target"
  ln -s "$target" "$HOME/.syntaur/eula-accepted"
  assert_rejected eula_record_is_current "$HOME/.syntaur/eula-accepted"
  persist_eula_acceptance flag
  [ ! -L "$HOME/.syntaur/eula-accepted" ]
  grep -Fxq 'do-not-change' "$target"
  eula_record_is_current "$HOME/.syntaur/eula-accepted"
)

(
  HOME="$temporary/directory-symlink"
  export HOME
  load_installer_library
  mkdir -p "$HOME" "$temporary/foreign-directory"
  ln -s "$temporary/foreign-directory" "$HOME/.syntaur"
  assert_rejected persist_eula_acceptance flag
  [ ! -e "$temporary/foreign-directory/eula-accepted" ]
)

(
  HOME="$temporary/future-version"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  record="$HOME/.syntaur/eula-accepted"
  persist_eula_acceptance flag
  export EULA_VERSION=2.0
  assert_rejected eula_record_is_current "$record"
)

printf 'EULA acceptance tests passed\n'
