#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd -P)
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
fixture_bin="$fixture_root/install with spaces"
fixture_home="$fixture_root/home"
fixture_xdg="$fixture_root/config with spaces"
fixture_log="$fixture_root/launched"
mkdir -p "$fixture_bin" "$fixture_home" "$fixture_xdg"
for name in syntaur-engine syntaur-viewer; do
  cat > "$fixture_bin/$name" <<'STUB'
#!/bin/sh
test -z "${SYNTAUR_URL+x}"
test -z "${SYNTAUR_OPEN_URL+x}"
test -z "${SYNTAUR_SESSION_TOKEN+x}"
test -z "${SYNTAUR_TS_AUTHKEY+x}"
{
  basename "$0"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi
} > "$SYNTAUR_LAUNCH_TEST_LOG"
STUB
  chmod +x "$fixture_bin/$name"
done
cat > "$fixture_root/render.sh" <<'RENDER'
. "$1"
MODE=$2
PLATFORM=$3
APP_LAUNCHER=$4
write_app_launcher
RENDER
render() {
  env SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1 /bin/sh "$fixture_root/render.sh" \
    "$repository/install.sh" "$1" "$2" "$fixture_bin/syntaur-open"
  sh -n "$fixture_bin/syntaur-open"
}
launch() {
  env HOME="$fixture_home" XDG_CONFIG_HOME="$fixture_xdg" PATH=/usr/bin:/bin \
    SYNTAUR_LAUNCH_TEST_LOG="$fixture_log" \
    SYNTAUR_URL=https://retired.example/ SYNTAUR_OPEN_URL=https://retired.example/ \
    SYNTAUR_SESSION_TOKEN=synthetic-retired-token SYNTAUR_TS_AUTHKEY=synthetic-retired-key \
    "$fixture_bin/syntaur-open"
}
expect() {
  printf '%s\n' "$@" > "$fixture_root/expected"
  cmp "$fixture_root/expected" "$fixture_log"
}
render connect linux
launch
expect syntaur-viewer
mkdir -p "$fixture_xdg/syntaur"
printf '{}\n' > "$fixture_xdg/syntaur/link-profile.json"
launch
expect syntaur-engine --link --width 1440 --height 950
render connect macos
launch
expect syntaur-viewer
mkdir -p "$fixture_home/Library/Application Support/Syntaur"
printf '{}\n' > "$fixture_home/Library/Application Support/Syntaur/link-profile.json"
launch
expect syntaur-engine --link --width 1440 --height 950
render server linux
launch
expect syntaur-engine --url http://127.0.0.1:18789 --width 1440 --height 950
rm "$fixture_bin/syntaur-engine"
launch
expect syntaur-viewer --local-owner
render connect linux
launch
expect syntaur-viewer
printf 'PASS: seven native launcher scenarios; retired connection variables never reached a client\n'
