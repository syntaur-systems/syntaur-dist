#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd -P)
installer=${1:-$repository/install.sh}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
cat >"$fixture/bin/uname" <<'UNAME'
#!/bin/sh
case "$1" in -s) echo Darwin;; -m) echo arm64;; *) exit 1;; esac
UNAME
chmod 700 "$fixture/bin/uname"
python3 - "$installer" "$fixture/tail.sh" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); marker='# Resolve platform authority before any user-state mutation.'
assert s.count(marker)==1
Path(sys.argv[2]).write_text(s[s.index(marker):])
PYCODE
cat >"$fixture/run.sh" <<'RUN'
#!/bin/sh
set -e
SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY
. "$1"
MODE=$TEST_MODE
VERIFY=0
ensure_eula_acceptance() { return 0; }
download_verified() (
  name=${1##*/}
  printf 'download %s verify=%s\n' "$name" "$VERIFY" >>"$TEST_EVENTS"
  case "$name" in
    syntaur-link-tor-macos-arm64)
      [ "$VERIFY" = 1 ] || return 97
      [ "$TEST_CASE" != host-failure ] || return 44
      ;;
    syntaur-gateway-macos-arm64)
      [ "$TEST_CASE" != gateway-failure ] || return 44
      ;;
  esac
  printf 'new %s\n' "$name" >"$2"
)
download_optional_verified() { download_verified "$2" "$3"; }
sha256_file() { printf '%064d\n' 0; }
write_app_launcher() { printf 'new launcher\n' >"$INSTALL_DIR/syntaur-open"; }
provision_macos_tor_host() {
  printf 'provision\n' >>"$TEST_EVENTS"
  [ "$(cat "$1")" = 'new syntaur-link-tor-macos-arm64' ] || return 98
  [ "$2" = "$(printf '%064d' 0)" ] || return 99
  # Deliberately stop before any real privileged or service action.
  return 1
}
configure_link_transport() { return 1; }
. "$2"
RUN
for case_name in host-failure staged-reuse gateway-failure connect; do
  case_root="$fixture/$case_name"
  mkdir -p "$case_root/home/.local/bin" "$case_root/stages" "$case_root/before"
  for name in syntaur syntaur-engine syntaur-clip-write syntaur-viewer syntaur-link-client-tor syntaur-link-probe syntaur-snowflake-client syntaur-open; do
    printf 'original %s\n' "$name" >"$case_root/home/.local/bin/$name"
    cp "$case_root/home/.local/bin/$name" "$case_root/before/$name"
  done
  mode=server
  [ "$case_name" != connect ] || mode=connect
  set +e
  env PATH="$fixture/bin:$PATH" HOME="$case_root/home" TMPDIR="$case_root/stages" \
    TEST_CASE="$case_name" TEST_MODE="$mode" TEST_EVENTS="$case_root/events" \
    /bin/sh "$fixture/run.sh" "$installer" "$fixture/tail.sh" >"$case_root/output" 2>&1
  result=$?
  set -e
  [ "$result" = 1 ] || { cat "$case_root/output"; echo "Unexpected fixture exit $case_name: $result" >&2; exit 1; }
  python3 - "$case_root" "$case_name" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); case=sys.argv[2]; events=(p/'events').read_text().splitlines()
host='download syntaur-link-tor-macos-arm64 verify=1'
assert not list((p/'stages').iterdir()), f'{case}: temporary HOST stage leaked'
if case in ('host-failure','gateway-failure'):
    for original in (p/'before').iterdir():
        assert (p/'home/.local/bin'/original.name).read_bytes()==original.read_bytes(), f'{case}: changed {original.name} before required downloads completed'
    assert 'provision' not in events
if case=='host-failure':
    assert events==[host], events
elif case=='gateway-failure':
    assert events==[host,'download syntaur-gateway-macos-arm64 verify=0'], events
elif case=='staged-reuse':
    assert events[0]==host and events.count(host)==1 and events[-1]=='provision', events
    assert len(events)==9, events
    for original in (p/'before').iterdir():
        assert (p/'home/.local/bin'/original.name).read_bytes()!=original.read_bytes(), original.name
else:
    assert not any('syntaur-link-tor-macos-arm64' in e or e=='provision' for e in events), events
PYCODE
  echo "PASS $case_name"
done
echo 'Mac HOST prefetch fixture: 4 mocked cases; no network, privilege or live service actions.'
