#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

expected_eula_sha=3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720
actual_eula_sha=$(sha256sum "$repository/EULA.md" | awk '{print $1}')
[ "$actual_eula_sha" = "$expected_eula_sha" ]
grep -Fxq "EULA_SHA256=\"$expected_eula_sha\"" "$repository/install.sh"
dist_commit=$(sed -nE 's/^DIST_WORKFLOW_COMMIT="([0-9a-f]{40})"$/\1/p' "$repository/install.sh")
[ "${#dist_commit}" -eq 40 ]
eula_source_commit=$(sed -nE 's/^EULA_SOURCE_COMMIT="([0-9a-f]{40})"$/\1/p' "$repository/install.sh")
[ "${#eula_source_commit}" -eq 40 ]
expected_eula_url="https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$eula_source_commit/EULA.md"
historical_eula_url="https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md"
grep -Fxq 'EULA_URL="https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$EULA_SOURCE_COMMIT/EULA.md"' "$repository/install.sh"
pinned_eula_sha=$(git -C "$repository" show "$eula_source_commit:EULA.md" | sha256sum | awk '{print $1}')
[ "$pinned_eula_sha" = "$expected_eula_sha" ]

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

write_historical_record() {
  record=$1
  mkdir -p "$(dirname "$record")"
  chmod 700 "$(dirname "$record")"
  {
    printf 'record_format=1\n'
    printf 'eula_version=1.0\n'
    printf 'eula_sha256=%s\n' "$expected_eula_sha"
    printf 'eula_url=%s\n' "$historical_eula_url"
    printf 'accepted_at=2026-07-17T13:58:33Z\n'
    printf 'method=prompt\n'
    printf 'installer_version=0.7.114\n'
  } >"$record"
  chmod 600 "$record"
}

(
  HOME="$temporary/historical"
  export HOME
  load_installer_library
  # shellcheck disable=SC2031,SC2034 # sourced function consumes this subshell global.
  ACCEPT_EULA=1
  record="$HOME/.syntaur/eula-accepted"
  write_historical_record "$record"
  before_without_url=$(sed '4d' "$record" | sha256sum | awk '{print $1}')
  output=$(ensure_eula_acceptance </dev/null)
  after_without_url=$(sed '4d' "$record" | sha256sum | awk '{print $1}')
  [ "$before_without_url" = "$after_without_url" ]
  grep -Fxq "eula_url=$expected_eula_url" "$record"
  grep -Fxq 'accepted_at=2026-07-17T13:58:33Z' "$record"
  grep -Fxq 'method=prompt' "$record"
  grep -Fxq 'installer_version=0.7.114' "$record"
  printf '%s\n' "$output" | grep -Fq 'EULA v1.0 previously accepted; continuing.'
  first_hash=$(sha256sum "$record" | awk '{print $1}')
  ensure_eula_acceptance </dev/null >/dev/null
  second_hash=$(sha256sum "$record" | awk '{print $1}')
  [ "$first_hash" = "$second_hash" ]
  [ "$(find "$HOME/.syntaur" -maxdepth 1 \( -name '.eula-accepted.tmp.*' -o -name '.eula-accepted.backup.*' \) | wc -l)" -eq 0 ]
)

(
  HOME="$temporary/legacy"
  export HOME
  load_installer_library
  record="$HOME/.syntaur/eula-accepted"
  write_legacy_record "$record"
  before=$(sha256sum "$record" | awk '{print $1}')
  assert_rejected eula_record_is_current "$record"
  assert_rejected migrate_historical_eula_record "$record"
  [ "$before" = "$(sha256sum "$record" | awk '{print $1}')" ]
  # shellcheck disable=SC2031,SC2034 # sourced function consumes this subshell global.
  ACCEPT_EULA=1
  output=$(ensure_eula_acceptance </dev/null)
  after=$(sha256sum "$record" | awk '{print $1}')
  [ "$before" != "$after" ]
  printf '%s\n' "$output" | grep -Fq 'EULA v1.0 accepted (via flag).'
  eula_record_is_current "$record"
  grep -Fxq "eula_url=$expected_eula_url" "$record"
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

(
  HOME="$temporary/new-dist-commit"
  export HOME
  load_installer_library
  mkdir -p "$HOME"
  persist_eula_acceptance flag
  record="$HOME/.syntaur/eula-accepted"
  before=$(sha256sum "$record" | awk '{print $1}')
  DIST_WORKFLOW_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$DIST_WORKFLOW_COMMIT" = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]
  [ "$EULA_URL" = "$expected_eula_url" ]
  eula_record_is_current "$record"
  # shellcheck disable=SC2031,SC2034 # sourced function consumes this subshell global.
  ACCEPT_EULA=1
  output=$(ensure_eula_acceptance </dev/null)
  after=$(sha256sum "$record" | awk '{print $1}')
  [ "$before" = "$after" ]
  printf '%s\n' "$output" | grep -Fq 'EULA v1.0 previously accepted; continuing.'
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
    /bin/sh -c '. "$1/install.sh"; ACCEPT_EULA=1; ensure_eula_acceptance </dev/null' sh "$repository"
)
sh_after=$(sha256sum "$sh_record" | awk '{print $1}')
[ "$sh_before" = "$sh_after" ]
printf '%s\n' "$sh_output" | grep -Fq 'EULA v1.0 previously accepted; continuing.'

sh_migration_home="$temporary/posix-sh-migration"
sh_migration_record="$sh_migration_home/.syntaur/eula-accepted"
write_historical_record "$sh_migration_record"
sh_migration_before=$(sed '4d' "$sh_migration_record" | sha256sum | awk '{print $1}')
sh_migration_output=$(
  HOME="$sh_migration_home" SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 \
    /bin/sh -c '. "$1/install.sh"; ACCEPT_EULA=1; ensure_eula_acceptance </dev/null' sh "$repository"
)
[ "$sh_migration_before" = "$(sed '4d' "$sh_migration_record" | sha256sum | awk '{print $1}')" ]
grep -Fxq "eula_url=$expected_eula_url" "$sh_migration_record"
printf '%s\n' "$sh_migration_output" | grep -Fq 'EULA v1.0 previously accepted; continuing.'

for near_url in \
  'https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/main/EULA.md' \
  'https://github.com/syntaur-systems/syntaur-dist/blob/main/eula.md' \
  'https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md?download=1'
do
  near_home="$temporary/near-$(printf '%s' "$near_url" | sha256sum | cut -c1-8)"
  HOME="$near_home"
  export HOME
  load_installer_library
  near_record="$HOME/.syntaur/eula-accepted"
  write_historical_record "$near_record"
  sed -i "s|^eula_url=.*$|eula_url=$near_url|" "$near_record"
  near_before=$(sha256sum "$near_record" | awk '{print $1}')
  assert_rejected migrate_historical_eula_record "$near_record"
  [ "$near_before" = "$(sha256sum "$near_record" | awk '{print $1}')" ]
done

case_number=0
for mutation in \
  's/^record_format=.*/record_format=2/' \
  's/^eula_version=.*/eula_version=2.0/' \
  's/^eula_sha256=.*/eula_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
  's/^accepted_at=.*/accepted_at=not-a-time/' \
  's/^method=.*/method=automatic/' \
  's/^installer_version=.*/installer_version=01.7.114/'
do
  case_number=$((case_number + 1))
  HOME="$temporary/historical-field-$case_number"
  export HOME
  load_installer_library
  field_record="$HOME/.syntaur/eula-accepted"
  write_historical_record "$field_record"
  sed -i "$mutation" "$field_record"
  field_before=$(sha256sum "$field_record" | awk '{print $1}')
  assert_rejected migrate_historical_eula_record "$field_record"
  [ "$field_before" = "$(sha256sum "$field_record" | awk '{print $1}')" ]
done

(
  HOME="$temporary/historical-unsafe"
  export HOME
  load_installer_library
  record="$HOME/.syntaur/eula-accepted"
  write_historical_record "$record"
  before=$(sha256sum "$record" | awk '{print $1}')
  chmod 666 "$record"
  assert_rejected migrate_historical_eula_record "$record"
  [ "$before" = "$(sha256sum "$record" | awk '{print $1}')" ]
  chmod 600 "$record"
  chmod 722 "$HOME/.syntaur"
  assert_rejected migrate_historical_eula_record "$record"
  [ "$before" = "$(sha256sum "$record" | awk '{print $1}')" ]
)

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
  persist_eula_acceptance flag
  sed -i 's|^eula_url=.*$|eula_url=https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/main/EULA.md|' "$record"
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
  target="$temporary/symlink-target/eula-accepted"
  write_historical_record "$target"
  target_before=$(sha256sum "$target" | awk '{print $1}')
  ln -s "$target" "$HOME/.syntaur/eula-accepted"
  assert_rejected eula_record_is_current "$HOME/.syntaur/eula-accepted"
  assert_rejected migrate_historical_eula_record "$HOME/.syntaur/eula-accepted"
  [ "$target_before" = "$(sha256sum "$target" | awk '{print $1}')" ]
  persist_eula_acceptance flag
  [ ! -L "$HOME/.syntaur/eula-accepted" ]
  [ "$target_before" = "$(sha256sum "$target" | awk '{print $1}')" ]
  eula_record_is_current "$HOME/.syntaur/eula-accepted"
)

(
  HOME="$temporary/directory-symlink"
  export HOME
  load_installer_library
  mkdir -p "$HOME" "$temporary/foreign-directory"
  write_historical_record "$temporary/foreign-directory/eula-accepted"
  foreign_before=$(sha256sum "$temporary/foreign-directory/eula-accepted" | awk '{print $1}')
  ln -s "$temporary/foreign-directory" "$HOME/.syntaur"
  assert_rejected migrate_historical_eula_record "$HOME/.syntaur/eula-accepted"
  assert_rejected persist_eula_acceptance flag
  [ "$foreign_before" = "$(sha256sum "$temporary/foreign-directory/eula-accepted" | awk '{print $1}')" ]
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
