#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd -P)
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
fixture_home="$fixture_root/home"
mkdir -m 700 "$fixture_home"
fixture_bin="$fixture_home/install & <quoted> ' bin"
cat > "$fixture_root/render.sh" <<'RENDER'
SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
. "$1/install.sh"
INSTALL_DIR=$2
BINARY=syntaur
write_macos_launchagent
RENDER
render() {
  env HOME="$fixture_home" SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 \
    /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin"
}

# 1. Existing legacy agent plist render without tuple
render
plist="$fixture_home/Library/LaunchAgents/dev.syntaur.gateway.plist"
python3 - "$plist" "$fixture_bin/syntaur" <<'PY'
import plistlib,pathlib,sys,stat,os
p=pathlib.Path(sys.argv[1]); d=plistlib.loads(p.read_bytes())
assert d=={'Label':'dev.syntaur.gateway','ProgramArguments':[sys.argv[2]],
           'RunAtLoad':True,'KeepAlive':True,'EnvironmentVariables':{'HOME':str(p.parent.parent.parent),'SYNTAUR_LAUNCHER_OWNS_UI':'1','SYNTAUR_OWNER_UIDGID':f'{os.getuid()}:{os.getgid()}'}}
assert stat.S_IMODE(p.stat().st_mode)==0o600
PY
rm "$plist"

# 2. Existing alias guard verification
printf 'preserve\n' > "$fixture_root/protected"
ln -s "$fixture_root/protected" "$plist"
if render; then echo 'FAIL: followed a plist alias' >&2; exit 1; fi
test "$(cat "$fixture_root/protected")" = preserve
test -L "$plist"
rm "$plist"

# 3. Complete tuple rendering with XML special chars & Unicode in pin & path
other_uid=$(( $(id -u) + 100 ))
other_gid=501
env HOME="$fixture_home" SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 \
  MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid" \
  MACOS_TOR_SOCKET="/var/run/syntaur & <socket> 🚀.sock" \
  MACOS_TOR_GATEWAY_PIN="/etc/syntaur/pin & <val> '\" 🔐" \
  /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin"

python3 - "$plist" "$fixture_bin/syntaur" "$other_uid" "$other_gid" <<'PY'
import plistlib,pathlib,sys,stat,os
p=pathlib.Path(sys.argv[1]); d=plistlib.loads(p.read_bytes())
assert d=={
    'Label': 'dev.syntaur.gateway',
    'ProgramArguments': [sys.argv[2]],
    'RunAtLoad': True,
    'KeepAlive': True,
    'EnvironmentVariables': {
        'HOME': str(p.parent.parent.parent),
        'SYNTAUR_LAUNCHER_OWNS_UI': '1',
        'SYNTAUR_LINK_TOR_GATEWAY_PIN': "/etc/syntaur/pin & <val> '\" 🔐",
        'SYNTAUR_LINK_TOR_GID': sys.argv[4],
        'SYNTAUR_LINK_TOR_SOCKET': '/var/run/syntaur & <socket> 🚀.sock',
        'SYNTAUR_LINK_TOR_UID': sys.argv[3],
        'SYNTAUR_OWNER_UIDGID': f'{os.getuid()}:{os.getgid()}',
    }
}
assert stat.S_IMODE(p.stat().st_mode)==0o600
PY
rm "$plist"

# 4. Partial tuple and invalid tuple validation before mutation
# Empty directory check to ensure refusal occurs before mutation
empty_target_dir="$fixture_root/empty_home"
mkdir -m 700 "$empty_target_dir"
test_refusal() {
  if env HOME="$empty_target_dir" "$@" /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin" >"$fixture_root/refusal-output" 2>/dev/null; then
    echo "FAIL: Expected command to fail: $*" >&2
    exit 1
  fi
  # Verify no directory/plist was created
  if [ -e "$empty_target_dir/Library" ]; then
    echo "FAIL: Directory mutated before refusal" >&2
    exit 1
  fi
  test ! -s "$fixture_root/refusal-output"
}

test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid"
test_refusal MACOS_TOR_UID="0" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$(id -u)" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="0" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="notnumeric" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="4294967296" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="9999999999999999999999" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="0501" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="0501" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="relative/sock" MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN="relative/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET=$'/tmp/bad\nsock' MACOS_TOR_GATEWAY_PIN="/tmp/pin"
test_refusal MACOS_TOR_UID="$other_uid" MACOS_TOR_GID="$other_gid" MACOS_TOR_SOCKET="/tmp/sock" MACOS_TOR_GATEWAY_PIN=$'/tmp/bad\npin'

# 5. Pure daemon renderer validation & invalid input produces no stdout
daemon_out=$( (
  SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
  # shellcheck source=install.sh
  . "$repository/install.sh"
  render_macos_tor_launchdaemon "/usr/local/bin/syntaur & <host> 🚀" "/etc/syntaur/tor & <config> ⚙️.cfg"
) )

python3 - "$daemon_out" <<'PY'
import plistlib,sys
d=plistlib.loads(sys.argv[1].encode('utf-8'))
assert d=={
    'Label': 'dev.syntaur.link-tor',
    'ProgramArguments': ['/usr/local/bin/syntaur & <host> 🚀'],
    'UserName': '_syntaur_tor',
    'GroupName': '_syntaur_link',
    'RunAtLoad': True,
    'KeepAlive': True,
    'Umask': 63,
    'EnvironmentVariables': {
        'SYNTAUR_LINK_TOR_CONFIG': '/etc/syntaur/tor & <config> ⚙️.cfg'
    }
}
PY

for invalid in relative/path $'/tmp/bad\npath'; do
  if (
    SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
    export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
    # shellcheck source=install.sh
  . "$repository/install.sh"
    render_macos_tor_launchdaemon "$invalid" /etc/syntaur/tor.cfg
  ) >"$fixture_root/invalid-output" 2>/dev/null; then
    echo 'FAIL: invalid daemon path succeeded' >&2; exit 1
  fi
  test ! -s "$fixture_root/invalid-output"
done
(
  SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
  # shellcheck source=install.sh
  . "$repository/install.sh"
  for value in 1 2147483648 4294967295; do macos_u32_id "$value" || exit 1; done
  for value in 0501 4294967296 999999999999999999999; do
    if macos_u32_id "$value"; then exit 1; fi
  done
)
# 6. The exact pre-administrator stage validator: one positive control and
# independently changed digest, alias, size and release-name negative cases.
(
  SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
  # shellcheck source=install.sh
  . "$repository/install.sh"
  stage="$fixture_root/host-stage"
  printf 'fixture bytes only, never executed\n' >"$stage"
  digest=$(sha256_file "$stage")
  validate_macos_host_stage "$stage" "$digest" 0.7.326 || exit 1
  for wrong in bad 0000000000000000000000000000000000000000000000000000000000000000; do
    if validate_macos_host_stage "$stage" "$wrong" 0.7.326; then exit 1; fi
  done
  ln -s "$stage" "$stage.alias"
  if validate_macos_host_stage "$stage.alias" "$digest" 0.7.326; then exit 1; fi
  if validate_macos_host_stage "$stage" "$digest" ../unsafe; then exit 1; fi
  : >"$stage.empty"
  empty_digest=$(sha256_file "$stage.empty")
  if validate_macos_host_stage "$stage.empty" "$empty_digest" 0.7.326; then exit 1; fi
  # These overrides intentionally end with this disposable fixture subshell.
  # shellcheck disable=SC2030
  HOME="$empty_target_dir"
  # shellcheck disable=SC2030
  SYNTAUR_INSTALL_TEST_FORBID_SUDO=1
  if provision_macos_tor_host "$stage" "$digest"; then exit 1; fi
  test ! -e "$HOME/Library"
)
# 7. Maintenance uses the installed Viewer as one argument and propagates a
# refusal. These command fixtures never signal a host job or prove a restart.
maintenance_bin="$fixture_home/maintenance bin"
mkdir -m 700 "$maintenance_bin"
cat >"$maintenance_bin/syntaur-viewer" <<'VIEWER'
#!/bin/sh
printf '%s|%s\n' "$#" "$1" >>"$SYNTAUR_FIXTURE_VIEWER_LOG"
exit "${SYNTAUR_FIXTURE_VIEWER_EXIT:-0}"
VIEWER
chmod 700 "$maintenance_bin/syntaur-viewer"
maintenance() (
  SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
  export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
  . "$repository/install.sh"
  INSTALL_DIR="$maintenance_bin"
  restart_macos_server_if_running
)
export SYNTAUR_FIXTURE_VIEWER_LOG="$fixture_root/maintenance-calls"
maintenance
test "$(cat "$SYNTAUR_FIXTURE_VIEWER_LOG")" = '1|--server-restart'
export SYNTAUR_FIXTURE_VIEWER_EXIT=23
if maintenance >"$fixture_root/maintenance-output" 2>&1; then
  echo 'FAIL: maintenance refusal was hidden' >&2; exit 1
fi
test "$(wc -l <"$SYNTAUR_FIXTURE_VIEWER_LOG" | tr -d ' ')" = 2
grep -q 'installation is incomplete' "$fixture_root/maintenance-output"
unset SYNTAUR_FIXTURE_VIEWER_EXIT
mv "$maintenance_bin/syntaur-viewer" "$maintenance_bin/real-viewer"
ln -s real-viewer "$maintenance_bin/syntaur-viewer"
if maintenance; then echo 'FAIL: maintenance followed a Viewer alias' >&2; exit 1; fi
test "$(wc -l <"$SYNTAUR_FIXTURE_VIEWER_LOG" | tr -d ' ')" = 2
printf 'PASS Mac LaunchAgent, LaunchDaemon, stage and installed-maintenance command fixtures; no live job action\n'
