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

  # Special bits must not disappear from the validator's mode observation.
  chmod 1600 "$target_file"
  if run_entry_test "$target_file" f "$uid" "$gid" 600; then echo "Unexpected special mode bit accepted" >&2; exit 1; fi
  chmod 600 "$target_file"

  # Hardlink
  hardlink_target="$test_dir/hardlink.txt"
  ln "$target_file" "$hardlink_target"
  if run_entry_test "$target_file" f "$uid" "$gid" 600; then echo "Hardlinked file accepted" >&2; exit 1; fi
fi

# Hidden account attribute regression tests
extract_hidden_guard() {
  python3 - "$fragment_file" <<'PY'
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    text = f.read()

marker = chr(60) * 2 + chr(39) + 'MACOS_HOST_ROOT' + chr(39) + ' || return 1\n'
assert text.count(marker) == 1
body = text.split(marker, 1)[1].split('\nMACOS_HOST_ROOT\n', 1)[0]

old_pattern = '[ "$(/usr/bin/dscl . -read /Users/_syntaur_tor IsHidden)" = \'IsHidden: 1\' ] || exit 1'
new_line1 = 'hidden_record=$(/usr/bin/dscl . -read /Users/_syntaur_tor IsHidden) || exit 1'
new_line2 = '[ "$hidden_record" = \'dsAttrTypeNative:IsHidden: 1\' ] || exit 1'

if new_line1 in body and new_line2 in body:
    guard = f'{new_line1}\n{new_line2}\n'
elif old_pattern in body:
    guard = f'{old_pattern}\n'
else:
    sys.exit('Hidden guard not found')
sys.stdout.write(guard.replace('/usr/bin/dscl . -read /Users/_syntaur_tor IsHidden',
                              'dscl_stub . -read /Users/_syntaur_tor IsHidden'))
PY
}

hidden_guard_src="$(extract_hidden_guard)"

run_hidden_guard_test() {
  local mock_stdout="$1"
  local mock_exit_code="${2:-0}"
  # shellcheck disable=SC2016 # Fixture arguments belong to the child shell.
  bash -c '
set -e
mock_stdout=$1
mock_exit_code=$2
dscl_stub() {
  if [ "$*" != ". -read /Users/_syntaur_tor IsHidden" ]; then
    echo "Unexpected dscl invocation" >&2
    return 1
  fi
  printf "%s\n" "$mock_stdout"
  return "$mock_exit_code"
}
eval "$3"
' _ "$mock_stdout" "$mock_exit_code" "$hidden_guard_src"
}

# 1. Valid native-qualified output must pass on parent fix (and fails on old single-line guard)
run_hidden_guard_test "dsAttrTypeNative:IsHidden: 1" 0 || { echo "Valid native IsHidden output failed" >&2; exit 1; }

# 2. Unqualified IsHidden: 1 must fail
if run_hidden_guard_test "IsHidden: 1" 0; then
  echo "Unqualified IsHidden: 1 accepted" >&2
  exit 1
fi

# 3. Native 0 must fail
if run_hidden_guard_test "dsAttrTypeNative:IsHidden: 0" 0; then
  echo "dsAttrTypeNative:IsHidden: 0 accepted" >&2
  exit 1
fi

# 4. Native 01 must fail
if run_hidden_guard_test "dsAttrTypeNative:IsHidden: 01" 0; then
  echo "dsAttrTypeNative:IsHidden: 01 accepted" >&2
  exit 1
fi

# 5. Extra appended line must fail
bad_appended_output="$(cat <<EOF
dsAttrTypeNative:IsHidden: 1
extra_line: true
EOF
)"
if run_hidden_guard_test "$bad_appended_output" 0; then
  echo "Appended extra line accepted" >&2
  exit 1
fi

# 6. Empty output must fail
if run_hidden_guard_test "" 0; then
  echo "Empty output accepted" >&2
  exit 1
fi

# 7. Nonzero exit with valid-looking output must fail
if run_hidden_guard_test "dsAttrTypeNative:IsHidden: 1" 1; then
  echo "Nonzero command exit accepted" >&2
  exit 1
fi

# Directory mode regression tests
if [ "$(uname -s)" = "Darwin" ]; then
extract_creation_loop() {
  python3 - "$fragment_file" <<'PY'
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    text = f.read()

marker = chr(60) * 2 + chr(39) + 'MACOS_HOST_ROOT' + chr(39) + ' || return 1\n'
assert text.count(marker) == 1
body = text.split(marker, 1)[1].split('\nMACOS_HOST_ROOT\n', 1)[0]

start_token = 'for leaf in private private/state private/cache ipc; do'
end_token = '\ndone'

if start_token not in body:
    sys.exit('Creation loop start token not found')

loop_part = body.split(start_token, 1)[1]
if end_token not in loop_part:
    sys.exit('Creation loop end token not found')

loop_body = start_token + loop_part.split(end_token, 1)[0] + end_token + '\n'

sys.stdout.write(loop_body)
PY
}

creation_loop_src="$(extract_creation_loop)"

run_creation_loop_test() {
  local base_dir="$1"
  local cur_uid
  local cur_gid
  cur_uid="$(id -u)"
  cur_gid="$(id -g)"

  # shellcheck disable=SC2016 # The child owns fixture parameters and source.
  bash -c '
set -euo pipefail
base=$1
sidecar_uid=$2
gateway_uid=$2
shared_gid=$3
entry_src=$4
loop_src=$5

eval "$entry_src"
eval "$loop_src"
' _ "$base_dir" "$cur_uid" "$cur_gid" "$entry_func_src" "$creation_loop_src"
}

get_octal_mode() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

st = os.stat(sys.argv[1])
sys.stdout.write(oct(stat.S_IMODE(st.st_mode))[2:])
PY
}

# 1. Fresh directory creation: new loop must succeed and yield 2770 for ipc
fresh_test_dir="$test_dir/fresh-mode"
mkdir "$fresh_test_dir"
if ! run_creation_loop_test "$fresh_test_dir"; then
  rm -rf "$fresh_test_dir"
  echo "Creation loop failed on fresh directories" >&2
  exit 1
fi
ipc_mode="$(get_octal_mode "$fresh_test_dir/ipc")"
rm -rf "$fresh_test_dir"
if [ "$ipc_mode" != "2770" ]; then
  echo "ipc directory mode expected 2770 but got $ipc_mode" >&2
  exit 1
fi

# 2. Pre-existing mismatched ipc directory (0770): must refuse and NOT be repaired
preexist_test_dir="$test_dir/preexist-mode"
mkdir "$preexist_test_dir"
mkdir -p "$preexist_test_dir/ipc"
chmod 0770 "$preexist_test_dir/ipc"
if run_creation_loop_test "$preexist_test_dir"; then
  rm -rf "$preexist_test_dir"
  echo "Pre-existing 770 ipc directory was accepted unexpectedly" >&2
  exit 1
fi
preexist_ipc_mode="$(get_octal_mode "$preexist_test_dir/ipc")"
rm -rf "$preexist_test_dir"
if [ "$preexist_ipc_mode" != "770" ]; then
  echo "Pre-existing 770 ipc directory was modified to $preexist_ipc_mode" >&2
  exit 1
fi
fi

echo "PASS synthetic loaded-HOST guards; Darwin file roles checked when available; no OS job/account calls."
