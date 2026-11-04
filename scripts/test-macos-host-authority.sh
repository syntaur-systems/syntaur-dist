#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd -P)
fragment_file="${1:-$repository/install.sh}"
if [ ! -f "$fragment_file" ]; then
  echo "Fragment file not found: $fragment_file" >&2
  exit 1
fi

extract_func() {
  local func_name="$1"
  python3 -c "
import sys

target = sys.argv[1]
found = False
lines = []
with open(sys.argv[2], 'r', encoding='utf-8') as f:
    text = f.read()
marker = chr(60) * 2 + chr(39) + 'MACOS_HOST_ROOT' + chr(39) + ' || return 1\n'
assert text.count(marker) == 1
text = text.split(marker, 1)[1].split('\nMACOS_HOST_ROOT\n', 1)[0]
for line in text.splitlines(keepends=True):
        if not found:
            if line.startswith(target + '() {'):
                found = True
                lines.append(line)
        else:
            lines.append(line)
            if line == '}\n':
                break
if not found:
    sys.exit(f'Function {target} not found')
sys.stdout.write(''.join(lines))
" "$func_name" "$fragment_file"
}

loaded_func_src="$(extract_func loaded_host_matches)"
entry_func_src="$(extract_func entry)"

run_loaded_test() {
  local output="$1"
  local prog="$2"
  bash -c "
$loaded_func_src
base='/Library/Application Support/Syntaur/LinkTor'
job='/Library/LaunchDaemons/dev.syntaur.link-tor.plist'
loaded_host_matches \"\$1\" \"\$2\"
" _ "$output" "$prog"
}

prog="/usr/local/libexec/syntaur/link-hosts/1.0.0/syntaur-link-tor"
valid_output="$(cat <<EOF
arguments = {
    $prog
}
path = /Library/LaunchDaemons/dev.syntaur.link-tor.plist
program = $prog
username = _syntaur_tor
group = _syntaur_link
SYNTAUR_LINK_TOR_CONFIG => /Library/Application Support/Syntaur/LinkTor/private/host.json
EOF
)"

# 1. Valid output matches
run_loaded_test "$valid_output" "$prog" || { echo "Valid output failed" >&2; exit 1; }

# 2. Changed program
bad_prog="${valid_output/program = $prog/program = /other/path}"
if run_loaded_test "$bad_prog" "$prog"; then echo "Changed program accepted" >&2; exit 1; fi

# 3. Changed path
bad_path="${valid_output/path = \/Library/path = \/Other}"
if run_loaded_test "$bad_path" "$prog"; then echo "Changed path accepted" >&2; exit 1; fi

# 4. Changed user
bad_user="${valid_output/username = _syntaur_tor/username = _other}"
if run_loaded_test "$bad_user" "$prog"; then echo "Changed user accepted" >&2; exit 1; fi

# 5. Changed group
bad_group="${valid_output/group = _syntaur_link/group = _other}"
if run_loaded_test "$bad_group" "$prog"; then echo "Changed group accepted" >&2; exit 1; fi

# 6. Changed config
bad_config="${valid_output/SYNTAUR_LINK_TOR_CONFIG => \/Library/SYNTAUR_LINK_TOR_CONFIG => \/Other}"
if run_loaded_test "$bad_config" "$prog"; then echo "Changed config accepted" >&2; exit 1; fi

# 7. Extra argument
bad_extra_arg="$(cat <<EOF
arguments = {
    $prog
    --extra-arg
}
path = /Library/LaunchDaemons/dev.syntaur.link-tor.plist
program = $prog
username = _syntaur_tor
group = _syntaur_link
SYNTAUR_LINK_TOR_CONFIG => /Library/Application Support/Syntaur/LinkTor/private/host.json
EOF
)"
if run_loaded_test "$bad_extra_arg" "$prog"; then echo "Extra argument accepted" >&2; exit 1; fi

# 8. Duplicate role/config fields are ambiguous even when their values match.
for field in 'username = _syntaur_tor' 'group = _syntaur_link' 'SYNTAUR_LINK_TOR_CONFIG => /Library/Application Support/Syntaur/LinkTor/private/host.json'; do
  bad_dup="${valid_output}"$'\n'"$field"
  if run_loaded_test "$bad_dup" "$prog"; then echo "Duplicate field accepted" >&2; exit 1; fi
done

# 9. Incomplete args block (unclosed brace)
bad_unclosed="$(cat <<EOF
arguments = {
    $prog
path = /Library/LaunchDaemons/dev.syntaur.link-tor.plist
program = $prog
username = _syntaur_tor
group = _syntaur_link
SYNTAUR_LINK_TOR_CONFIG => /Library/Application Support/Syntaur/LinkTor/private/host.json
EOF
)"
if run_loaded_test "$bad_unclosed" "$prog"; then echo "Incomplete args accepted" >&2; exit 1; fi

# Darwin-only entry function tests
if [ "$(uname -s)" = "Darwin" ]; then
  test_dir="$(mktemp -d)"
  trap 'rm -rf "$test_dir"' EXIT

  uid="$(id -u)"
  gid="$(id -g)"
  target_file="$test_dir/temp600.txt"
  touch "$target_file"
  chmod 600 "$target_file"

  run_entry_test() {
    local f_path="$1" f_kind="$2" f_uid="$3" f_gid="$4" f_mode="$5"
    bash -c "
$entry_func_src
entry \"\$1\" \"\$2\" \"\$3\" \"\$4\" \"\$5\"
" _ "$f_path" "$f_kind" "$f_uid" "$f_gid" "$f_mode"
  }

  # Valid 600 regular file
  run_entry_test "$target_file" f "$uid" "$gid" 600 || { echo "Darwin entry valid file failed" >&2; exit 1; }

  # Wrong mode
  if run_entry_test "$target_file" f "$uid" "$gid" 644; then echo "Wrong mode accepted" >&2; exit 1; fi

  # Symlink (alias)
  symlink_target="$test_dir/symlink.txt"
  ln -s "$target_file" "$symlink_target"
  if run_entry_test "$symlink_target" f "$uid" "$gid" 600; then echo "Symlink accepted" >&2; exit 1; fi

  # Hardlink
  hardlink_target="$test_dir/hardlink.txt"
  ln "$target_file" "$hardlink_target"
  if run_entry_test "$target_file" f "$uid" "$gid" 600; then echo "Hardlinked file accepted" >&2; exit 1; fi
fi

echo "PASS synthetic loaded-HOST guards; Darwin file roles checked when available; no OS job/account calls."
