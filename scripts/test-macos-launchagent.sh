#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd -P)
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
fixture_home="$fixture_root/home"
mkdir -m 700 "$fixture_home"
fixture_bin="$fixture_home/install & <quoted> ' bin"
cat > "$fixture_root/render.sh" <<'RENDER'
. "$1"
INSTALL_DIR=$2
BINARY=syntaur
write_macos_launchagent
RENDER
render() {
  env HOME="$fixture_home" SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 \
    /bin/sh "$fixture_root/render.sh" "$repository/install.sh" "$fixture_bin"
}
render
plist="$fixture_home/Library/LaunchAgents/dev.syntaur.gateway.plist"
python3 - "$plist" "$fixture_bin/syntaur" <<'PY'
import plistlib,pathlib,sys,stat,os
p=pathlib.Path(sys.argv[1]); d=plistlib.loads(p.read_bytes())
assert d=={'Label':'dev.syntaur.gateway','ProgramArguments':[sys.argv[2]],
           'RunAtLoad':True,'KeepAlive':True,'EnvironmentVariables':{'SYNTAUR_LAUNCHER_OWNS_UI':'1','SYNTAUR_OWNER_UIDGID':f'{os.getuid()}:{os.getgid()}'}}
assert stat.S_IMODE(p.stat().st_mode)==0o600
PY
rm "$plist"
printf 'preserve\n' > "$fixture_root/protected"
ln -s "$fixture_root/protected" "$plist"
if render; then echo 'FAIL: followed a plist alias' >&2; exit 1; fi
test "$(cat "$fixture_root/protected")" = preserve
test -L "$plist"
printf 'PASS Mac LaunchAgent exact executable/XML/private mode and alias refusal; no OS job started\n'
