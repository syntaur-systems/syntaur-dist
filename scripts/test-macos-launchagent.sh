#!/usr/bin/env bash
set -euo pipefail
unset SYNTAUR_STT_HOST SYNTAUR_TTS_HOST
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
# 8. Explicit speech routes must survive rendering, without changing the Tor
# tuple or forwarding arbitrary variables into the selected user's job.
env HOME="$fixture_home" SYNTAUR_STT_HOST='127.0.0.1:10300' \
  SYNTAUR_TTS_HOST='voice&test.local:10400' SYNTAUR_UNRELATED_SETTING=do-not-forward \
  /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin"
python3 - "$plist" <<'PY'
import pathlib,plistlib,sys
env=plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())['EnvironmentVariables']
assert env['SYNTAUR_STT_HOST']=='127.0.0.1:10300'
assert env['SYNTAUR_TTS_HOST']=='voice&test.local:10400'
assert 'SYNTAUR_UNRELATED_SETTING' not in env
PY
cp "$plist" "$fixture_root/speech-before"
for invalid in '' ' ' $'host:10300\n' $'host\t:10300' "$(printf '%1025s' x)"; do
  if env HOME="$fixture_home" SYNTAUR_STT_HOST="$invalid" \
      /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin"; then
    echo 'FAIL: invalid speech setting accepted' >&2; exit 1
  fi
  cmp "$plist" "$fixture_root/speech-before"
done

# Previous-plist extraction is an actual macOS plutil path. These cases run
# against that production helper on Mac; Linux does not claim that coverage.
if [ "$(uname -s)" = Darwin ]; then
  render
  cmp "$plist" "$fixture_root/speech-before"
  env HOME="$fixture_home" SYNTAUR_STT_HOST='127.0.0.1:20300' \
    /bin/sh "$fixture_root/render.sh" "$repository" "$fixture_bin"
  python3 - "$plist" <<'PY'
import pathlib,plistlib,sys
p=pathlib.Path(sys.argv[1]); d=plistlib.loads(p.read_bytes()); env=d['EnvironmentVariables']
assert env['SYNTAUR_STT_HOST']=='127.0.0.1:20300'
assert env['SYNTAUR_TTS_HOST']=='voice&test.local:10400'
PY
  for kind in number trailing_newline empty; do
    python3 - "$plist" "$kind" <<'PY'
import pathlib,plistlib,sys
p=pathlib.Path(sys.argv[1]);d=plistlib.loads(p.read_bytes())
d['EnvironmentVariables']['SYNTAUR_STT_HOST']={'number':10300,'trailing_newline':'host:10300\n','empty':''}[sys.argv[2]]
p.write_bytes(plistlib.dumps(d))
PY
    cp "$plist" "$fixture_root/invalid-speech-before"
    if render; then echo 'FAIL: invalid retained speech setting accepted' >&2; exit 1; fi
    cmp "$plist" "$fixture_root/invalid-speech-before"
  done
  echo 'PASS actual macOS speech-setting preservation, override and refusal'
else
  echo 'NOT RUN macOS-only previous-plist speech extraction on this host'
fi
# Configuration-update fixtures use a fake Viewer with the same strict
# loaded-definition check. No launchctl, live service, HTTP or account is used.
for scenario in fresh_loaded fresh absent loaded stop_refused write_failed start_failed rollback_stop_refused rollback_changed rollback_backup_changed success_changed; do
  case_root="$fixture_root/update-$scenario"
  mkdir -m 700 "$case_root"
  mkdir -m 700 "$case_root/bin" "$case_root/Library" "$case_root/Library/LaunchAgents"
  case_agent="$case_root/Library/LaunchAgents/dev.syntaur.gateway.plist"
  if [ "$scenario" != fresh ] && [ "$scenario" != fresh_loaded ]; then printf 'old-definition\n' >"$case_agent"; chmod 600 "$case_agent"; fi
  if [ "$scenario" != fresh ] && [ "$scenario" != absent ]; then printf 'old-definition\n' >"$case_root/loaded"; fi
  cat >"$case_root/bin/syntaur-viewer" <<'FAKE_VIEWER'
#!/bin/sh
set -eu
[ "$#" = 1 ] || exit 64
agent="$HOME/Library/LaunchAgents/dev.syntaur.gateway.plist"
printf '%s\n' "$1" >>"$HOME/events"
case "$1" in
  --server-stop)
    [ "$SYNTAUR_UPDATE_SCENARIO" != stop_refused ] || exit 23
    if [ ! -e "$HOME/loaded" ]; then exit 3; fi
    cmp "$HOME/loaded" "$agent" || exit 24
    if [ "$SYNTAUR_UPDATE_SCENARIO" = rollback_stop_refused ] && grep -q new-definition "$HOME/loaded"; then exit 23; fi
    new_job=0
    if grep -q new-definition "$HOME/loaded"; then new_job=1; fi
    rm "$HOME/loaded"
    if [ "$SYNTAUR_UPDATE_SCENARIO" = rollback_changed ] && [ "$new_job" = 1 ]; then printf 'external-definition\n' >"$agent"; fi
    ;;
  --server-start)
    [ ! -e "$HOME/loaded" ] || exit 25
    cp "$agent" "$HOME/loaded"
    if [ "$SYNTAUR_UPDATE_SCENARIO" = success_changed ]; then printf 'external-definition\n' >"$agent"; fi
    if [ "$SYNTAUR_UPDATE_SCENARIO" = rollback_backup_changed ]; then
      for backup in "$HOME"/Library/LaunchAgents/.dev.syntaur.gateway.previous.*; do printf 'changed-backup\n' >"$backup"; done
    fi
    case "$SYNTAUR_UPDATE_SCENARIO" in
      start_failed|rollback_stop_refused|rollback_changed|rollback_backup_changed)
        if grep -q new-definition "$agent"; then exit 26; fi ;;
    esac
    ;;
  *) exit 64 ;;
esac
FAKE_VIEWER
  chmod 700 "$case_root/bin/syntaur-viewer"
  update_status=0
  env HOME="$case_root" SYNTAUR_UPDATE_SCENARIO="$scenario" \
      SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 /bin/sh -s -- "$repository/install.sh" >"$case_root/result" 2>&1 <<'UPDATE' || update_status=$?
set -eu
. "$1"
INSTALL_DIR="$HOME/bin"
write_macos_launchagent() {
  printf 'write\n' >>"$HOME/events"
  [ "$SYNTAUR_UPDATE_SCENARIO" != write_failed ] || return 27
  printf 'new-definition\n' >"$HOME/Library/LaunchAgents/dev.syntaur.gateway.plist"
  chmod 600 "$HOME/Library/LaunchAgents/dev.syntaur.gateway.plist"
}
update_macos_launchagent
UPDATE
  case "$scenario" in
    fresh_loaded)
      test "$update_status" != 0
      test ! -e "$case_agent"
      test "$(cat "$case_root/events")" = --server-stop
      test "$(cat "$case_root/loaded")" = old-definition ;;
    fresh)
      test "$update_status" = 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite'
      test ! -e "$case_root/loaded"
      test "$(cat "$case_agent")" = new-definition ;;
    absent)
      test "$update_status" = 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite'
      test ! -e "$case_root/loaded"
      test "$(cat "$case_agent")" = new-definition ;;
    loaded)
      test "$update_status" = 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-start'
      cmp "$case_agent" "$case_root/loaded"
      test "$(cat "$case_agent")" = new-definition ;;
    stop_refused)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = --server-stop
      cmp "$case_agent" "$case_root/loaded"
      test "$(cat "$case_agent")" = old-definition ;;
    write_failed)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-stop\n--server-start'
      cmp "$case_agent" "$case_root/loaded"
      test "$(cat "$case_agent")" = old-definition ;;
    start_failed)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-start\n--server-stop\n--server-start'
      cmp "$case_agent" "$case_root/loaded"
      test "$(cat "$case_agent")" = old-definition ;;
    success_changed)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-start'
      test "$(cat "$case_agent")" = external-definition
      test "$(cat "$case_root/loaded")" = new-definition ;;
    rollback_changed|rollback_backup_changed)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-start\n--server-stop'
      test ! -e "$case_root/loaded"
      if [ "$scenario" = rollback_changed ]; then test "$(cat "$case_agent")" = external-definition
      else test "$(cat "$case_agent")" = new-definition; fi
      grep -q 'previous Mac server configuration was not restored' "$case_root/result" ;;
    rollback_stop_refused)
      test "$update_status" != 0
      test "$(cat "$case_root/events")" = $'--server-stop\nwrite\n--server-start\n--server-stop'
      cmp "$case_agent" "$case_root/loaded"
      test "$(cat "$case_agent")" = new-definition
      grep -q 'previous Mac server configuration was not restored' "$case_root/result" ;;
  esac
  test ! -e "$case_root/Library/LaunchAgents/.dev.syntaur.gateway.update-lock"
  echo "PASS synthetic Mac configuration update: $scenario"
done

printf 'PASS Mac LaunchAgent, LaunchDaemon, stage, installed-maintenance and explicit speech fixtures; no live job action\n'
