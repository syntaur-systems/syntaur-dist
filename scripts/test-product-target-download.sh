#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
export SYNTAUR_INSTALL_TEST_LIBRARY_ONLY=1
source "$repository/install.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
# The transport fixture records exact origin/name/limit and preserves the
# original document bytes. It does not impersonate the runtime verifier.
download_bounded() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$temporary/calls"
  case "$1" in
    *.bin.sig) [[ ${failure:-} != signature ]] || return 44; printf 'original signature' > "$2" ;;
    *.bin) [[ ${failure:-} != target ]] || return 44; printf 'original signed target' > "$2" ;;
    *) return 2 ;;
  esac
}
base='https://github.com/syntaur-systems/syntaur-dist/releases/download/v0.7.249'
for mode in server connect; do
  mkdir -m700 "$temporary/$mode"
  : > "$temporary/calls"
  download_product_release_target "$base" "$temporary/$mode" "$mode"
  target="syntaur-product-release-target-v2-linux-x86_64-$mode.bin"
  [[ $(wc -l < "$temporary/calls") == 2 ]]
  grep -Fqx "$base/$target"$'\t'"$temporary/$mode/$target"$'\t16384' "$temporary/calls"
  grep -Fqx "$base/$target.sig"$'\t'"$temporary/$mode/$target.sig"$'\t129' "$temporary/calls"
  [[ $(cat "$temporary/$mode/$target") == 'original signed target' ]]
  [[ $(cat "$temporary/$mode/$target.sig") == 'original signature' ]]
done
for failure in target signature; do
  mkdir -m700 "$temporary/$failure"
  : > "$temporary/calls"
  set +e
  download_product_release_target "$base" "$temporary/$failure" connect
  result=$?
  set -e
  [[ $result == 44 ]] # no catalog-only fallback, even for HTTP/notfound code44.
  [[ ! -e "$temporary/$failure/syntaur-product-release-target-v2-linux-x86_64-connect.bin.sig" ]]
done
: > "$temporary/calls"
if download_product_release_target "$base" "$temporary" '../invalid'; then
  echo 'invalid install mode accepted' >&2; exit 1
fi
[[ ! -s "$temporary/calls" ]]
echo 'product target download: both modes, exact originals/bounds and failure admission PASS'
