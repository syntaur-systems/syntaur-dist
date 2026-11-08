#!/bin/sh
# Syntaur installer — https://syntaur.app
#
# Recommended install (verified):
#   wget https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.sh
#   sh install.sh --server           # reads signed checksums + cosign bundle from release
#
# Alternative (developer convenience, *not* verified — warns you loudly):
#   curl -sSL https://github.com/syntaur-systems/syntaur-dist/releases/latest/download/install.sh | sh
#
# Flags:
#   --server          install the gateway + service unit
#   --connect         install only the client/browser (points at an existing server)
#   --accept-eula     accept the EULA non-interactively (required when no TTY is available)
#   --skip-verify     bypass checksum + signature verification (developer use; WARNS)
#   --no-sudo         skip the package-manager step that installs GStreamer plugins
set -e

BRAND="Syntaur"
# MUST match the VERSION file at repo root. Run `scripts/sync-version.sh`
# before tagging a release so this string and install.ps1 stay in sync with
# the workspace version in Cargo.toml. install.sh ships standalone (users
# curl|sh it), so it can't read the VERSION file at runtime.
VERSION="0.7.348"
# Stamped from the built runtime artifact by release-sign.yml before this
# installer is signed. Managed installs enforce it regardless of --skip-verify.
RUNTIME_BOOTSTRAP_SHA256="81b1e295ff327800f240538f4d39a1186f9b4c17841999285f6f18c980f24079"
# Stamped from the matching helper asset. This pin remains mandatory even
# when --skip-verify is used for developer-only direct assets.
PROCESS_INSPECTOR_SHA256="9d79957f289793a205b7e29f7014084a58367f17aa3c92de094969ad30c5d36d"
# Stamped from the exact public workflow checkout before this installer is
# signed. Cosign verification binds the manifest to this immutable commit.
DIST_WORKFLOW_COMMIT="7a91d021f3b9cd90c67553d6f962e4774293f750"
# Immutable provenance for the exact EULA bytes below. This changes only when
# EULA_VERSION or EULA_SHA256 changes, never for an ordinary product release.
EULA_SOURCE_COMMIT="8811aa006673caa5082a7c9343e83c0b7ac51d16"
BINARY="syntaur"
INSTALL_DIR="$HOME/.local/bin"
MODE=""
VERIFY="1"
AUTOSUDO="1"
ACCEPT_EULA="0"
EULA_VERSION="1.0"
EULA_URL="https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/$EULA_SOURCE_COMMIT/EULA.md"
EULA_HISTORICAL_URL="https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md"
EULA_SHA256="3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720"
EULA_RECORD_FORMAT="1"
EULA_RECORD_MAX_BYTES="4096"

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --server)       MODE="server" ;;
    --connect)      MODE="connect" ;;
    --accept-eula)  ACCEPT_EULA="1" ;;
    --skip-verify)  VERIFY="0" ;;
    --no-sudo)      AUTOSUDO="0" ;;
  esac
done

# ── Release-integrity helpers (Phase 2.2 of the security plan) ──────────────
#
# download_verified <binary-url> <target-path>
#   Downloads the binary, alongside its sibling `checksums.txt` +
#   `checksums.txt.cosign.bundle` from the same release directory.
#   Verifies:
#     1. sha256 against checksums.txt
#     2. cosign signature of checksums.txt against the pinned workflow commit
#   Aborts with a loud error on any mismatch. `--skip-verify` bypasses
#   everything and prints a RED WARNING so it can't happen silently.
#
# Binaries are downloaded from the PUBLIC distribution repo
# (syntaur-systems/syntaur-dist). They are built from the private source
# and signed keyless by syntaur-dist's public release-sign.yml workflow,
# which publishes checksums.txt + *.cosign.bundle alongside every
# release; this function assumes that layout. The signing identity is
# the dist workflow @ its main ref (workflow_dispatch/repository_dispatch
# runs there), NOT a per-tag ref.

REPO_URL="https://github.com/syntaur-systems/syntaur-dist"
COSIGN_IDENT="https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-sign.yml@refs/heads/main"
COSIGN_ISSUER="https://token.actions.githubusercontent.com"

_fetch() {
  # $1 url, $2 out
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    echo "Error: need curl or wget"
    return 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Error: need sha256sum or shasum" >&2
    return 1
  fi
}

checksum_manifest_digest() {
  MANIFEST="$1"
  ASSET="$2"
  DIGEST=$(awk -v asset="$ASSET" '
    $2 == asset { count += 1; digest = $1; if (NF != 2) invalid = 1 }
    END {
      if (count != 1 || invalid) exit 1
      print digest
    }
  ' "$MANIFEST") || return 1
  case "$DIGEST" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#DIGEST}" -eq 64 ] || return 1
  printf '%s\n' "$DIGEST"
}

download_verified() (
  BIN_URL="$1"
  OUT="$2"
  BASE_URL=$(dirname "$BIN_URL")
  BIN_NAME=$(basename "$BIN_URL")
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT INT TERM

  echo "  → Downloading $BIN_NAME"
  download_bounded "$BIN_URL" "$TMP/$BIN_NAME" 1073741824 || return $?

  if [ "$VERIFY" = "0" ]; then
    printf "  \033[1;31m!!!\033[0m \033[1m--skip-verify:\033[0m installing unverified binary. DO NOT use in production.\n"
    mv "$TMP/$BIN_NAME" "$OUT"
    chmod +x "$OUT"
    return 0
  fi

  # Fetch checksums.txt + its cosign bundle.
  if ! download_bounded "$BASE_URL/checksums.txt" "$TMP/checksums.txt" 2097152 2>/dev/null; then
    echo ""
    echo "  ✗ checksums.txt missing on this release — cannot verify."
    echo "    Re-run with --skip-verify only if you accept the risk."
    return 1
  fi
  if ! download_bounded "$BASE_URL/checksums.txt.cosign.bundle" "$TMP/checksums.txt.cosign.bundle" 2097152 2>/dev/null; then
    echo ""
    echo "  ✗ checksums.txt cosign bundle missing on this release — cannot verify."
    echo "    Re-run with --skip-verify only if you accept the risk."
    return 1
  fi

  # Step 1: SHA-256 match.
  EXPECTED_SHA256=$(checksum_manifest_digest "$TMP/checksums.txt" "$BIN_NAME") || {
    echo ""
    echo "  ✗ checksums.txt has no unique canonical entry for $BIN_NAME — ABORT."
    return 1
  }
  ACTUAL_SHA256=$(sha256_file "$TMP/$BIN_NAME") || return 1
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo ""
    echo "  ✗ SHA-256 mismatch for $BIN_NAME — ABORT."
    echo "    Expected hash in checksums.txt did not match the downloaded binary."
    echo "    This could mean: a corrupted download, a malicious proxy, OR a"
    echo "    compromised release asset. Report to security@syntaur.app."
    return 1
  fi
  echo "  ✓ SHA-256 verified"

  # Step 2: fail closed unless the manifest is tied to the exact workflow commit.
  case "$DIST_WORKFLOW_COMMIT" in
    ''|*[!0-9a-f]*)
      echo ""
      echo "  ✗ installer has no valid pinned workflow commit — ABORT."
      return 1
      ;;
  esac
  if [ "${#DIST_WORKFLOW_COMMIT}" -ne 40 ]; then
    echo ""
    echo "  ✗ installer has no valid pinned workflow commit — ABORT."
    return 1
  fi
  if ! command -v cosign >/dev/null 2>&1; then
    echo ""
    echo "  ✗ cosign is required for verified installation — ABORT."
    echo "    Install it from https://docs.sigstore.dev/system_config/installation/"
    echo "    Re-run with --skip-verify only if you accept the risk."
    return 1
  fi
  if cosign verify-blob \
      --bundle "$TMP/checksums.txt.cosign.bundle" \
      --certificate-identity "$COSIGN_IDENT" \
      --certificate-oidc-issuer "$COSIGN_ISSUER" \
      --certificate-github-workflow-sha "$DIST_WORKFLOW_COMMIT" \
      "$TMP/checksums.txt" >/dev/null 2>&1; then
    echo "  ✓ cosign signature verified"
  else
    echo ""
    echo "  ✗ cosign signature verification FAILED — ABORT."
    echo "    The release artifact could not be cryptographically tied to the"
    echo "    Syntaur GitHub Actions signing identity. DO NOT run this binary."
    return 1
  fi

  mv "$TMP/$BIN_NAME" "$OUT"
  chmod +x "$OUT"
)

download_optional_verified() {
  LABEL="$1"
  BIN_URL="$2"
  OUT="$3"

  echo "  Installing $LABEL..."
  set +e
  download_verified "$BIN_URL" "$OUT"
  CODE=$?
  set -e

  if [ "$CODE" -eq 0 ]; then
    return 0
  fi
  if [ "$CODE" -eq 44 ]; then
    echo "  ($LABEL download skipped — not yet published for this platform)"
    return 1
  fi

  echo ""
  echo "  ✗ Could not install a verified $LABEL."
  echo "    Refusing to continue after a verification failure."
  exit 1
}

# Bounded release download used by the managed-runtime bootstrap. The file
# size limit is applied in a subshell before curl/wget starts, then checked
# again before the private temporary file is published.
download_bounded() (
  URL="$1"
  OUT="$2"
  MAX_SIZE="$3"

  case "$MAX_SIZE" in
    ''|0|*[!0-9]*) echo "  Error: invalid download size limit"; return 1 ;;
  esac
  if [ "$MAX_SIZE" -gt 1073741824 ]; then
    echo "  Error: download size limit exceeds the runtime ceiling"
    return 1
  fi

  TMP_FILE=$(mktemp "${OUT}.part.XXXXXX") || return 1
  trap 'rm -f "$TMP_FILE"' EXIT HUP INT TERM
  FILE_BLOCKS=$(( (MAX_SIZE + 511) / 512 ))
  ulimit -f "$FILE_BLOCKS" || return 1
  _fetch "$URL" "$TMP_FILE" || return 44
  ACTUAL_SIZE=$(wc -c < "$TMP_FILE" | tr -d '[:space:]')
  if [ "$ACTUAL_SIZE" -gt "$MAX_SIZE" ]; then
    echo "  Error: downloaded file exceeds its size limit"
    return 1
  fi
  chmod 600 "$TMP_FILE"
  mv "$TMP_FILE" "$OUT"
)

# The original signed target and signature are carried into the same private
# stage as the catalog. install-release verifies their independent trust bytes
# and compatibility before A/B activation; a failed download is never legacy
# catalog-only authorization.
download_product_release_target() (
  PRODUCT_RELEASE_BASE=$1
  PRODUCT_STAGE=$2
  PRODUCT_MODE=$3
  case "$PRODUCT_MODE" in
    server|connect) ;;
    *) return 2 ;;
  esac
  PRODUCT_TARGET_NAME="syntaur-product-release-target-v2-linux-x86_64-${PRODUCT_MODE}.bin"
  download_bounded "$PRODUCT_RELEASE_BASE/$PRODUCT_TARGET_NAME" "$PRODUCT_STAGE/$PRODUCT_TARGET_NAME" 16384 || return $?
  download_bounded "$PRODUCT_RELEASE_BASE/$PRODUCT_TARGET_NAME.sig" "$PRODUCT_STAGE/$PRODUCT_TARGET_NAME.sig" 129 || return $?
)

download_bounded_exact() (
  URL="$1"
  OUT="$2"
  EXPECTED_SIZE="$3"
  MAX_SIZE="$4"
  EXPECTED_SHA256="$5"

  download_bounded "$URL" "$OUT" "$MAX_SIZE" || return $?
  ACTUAL_SIZE=$(wc -c < "$OUT" | tr -d '[:space:]')
  if [ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]; then
    echo "  Error: $URL has size $ACTUAL_SIZE, expected $EXPECTED_SIZE"
    rm -f "$OUT"
    return 1
  fi
  ACTUAL_SHA256=$(/usr/bin/sha256sum -- "$OUT" 2>/dev/null | /usr/bin/awk '{print $1}') || return 1
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "  Error: $URL does not match the signed runtime catalog"
    rm -f "$OUT"
    return 1
  fi
  chmod 700 "$OUT"
)

download_pinned_release_asset() (
  RELEASE_BASE="$1"
  ASSET="$2"
  OUT="$3"
  EXPECTED_SHA256="$4"
  LABEL="$5"
  case "$EXPECTED_SHA256" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || return 1
  download_bounded "$RELEASE_BASE/$ASSET" "$OUT" 1073741824 || return $?
  ACTUAL_SHA256=$(sha256_file "$OUT") || return 1
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "  Error: $LABEL checksum mismatch"
    rm -f "$OUT"
    return 1
  fi
  chmod 700 "$OUT"
)

download_managed_bootstrap() {
  download_pinned_release_asset "$1" "$2" "$3" "$RUNTIME_BOOTSTRAP_SHA256" "managed runtime bootstrap"
}

ensure_process_inspector_cap_tools() {
  if command -v setcap >/dev/null 2>&1 && command -v getcap >/dev/null 2>&1; then
    return 0
  fi

  CAP_MANAGER=""
  CAP_PACKAGE=""
  CAP_INSTALL_COMMAND=""
  if command -v pacman >/dev/null 2>&1; then
    CAP_MANAGER="pacman"
    CAP_PACKAGE="libcap"
    CAP_INSTALL_COMMAND="sudo pacman -S --needed libcap"
  elif command -v apt-get >/dev/null 2>&1; then
    CAP_MANAGER="apt"
    CAP_PACKAGE="libcap2-bin"
    CAP_INSTALL_COMMAND="sudo apt-get update && sudo apt-get install libcap2-bin"
  elif command -v dnf >/dev/null 2>&1; then
    CAP_MANAGER="dnf"
    CAP_PACKAGE="libcap"
    CAP_INSTALL_COMMAND="sudo dnf install libcap"
  elif command -v zypper >/dev/null 2>&1; then
    CAP_MANAGER="zypper"
    CAP_PACKAGE="libcap-progs"
    CAP_INSTALL_COMMAND="sudo zypper install libcap-progs"
  fi
  if [ -z "$CAP_MANAGER" ]; then
    echo "  Error: setcap and getcap are required; install your distribution's libcap tools package."
    return 1
  fi
  if [ "$AUTOSUDO" = "0" ] || [ ! -x /usr/bin/sudo ]; then
    echo "  Error: setcap and getcap are required for the managed runtime."
    echo "  Install them, then rerun: $CAP_INSTALL_COMMAND"
    return 1
  fi

  echo "  Installing required capability tools ($CAP_PACKAGE)..."
  /usr/bin/sudo -v || return 1
  case "$CAP_MANAGER" in
    pacman) /usr/bin/sudo pacman -S --needed --noconfirm "$CAP_PACKAGE" || return 1 ;;
    apt)
      /usr/bin/sudo apt-get update || return 1
      /usr/bin/sudo apt-get install -y --no-install-recommends "$CAP_PACKAGE" || return 1
      ;;
    dnf) /usr/bin/sudo dnf install -y "$CAP_PACKAGE" || return 1 ;;
    zypper) /usr/bin/sudo zypper --non-interactive install "$CAP_PACKAGE" || return 1 ;;
  esac
  command -v setcap >/dev/null 2>&1 && command -v getcap >/dev/null 2>&1
}

process_inspector_acl_free() (
  ENTRY="$1"
  PERMISSIONS=$(LC_ALL=C /usr/bin/ls -ld -- "$ENTRY" 2>/dev/null | /usr/bin/awk '{print $1}') || return 1
  case "$PERMISSIONS" in ''|*+) return 1 ;; esac
)

validate_process_inspector_directory() (
  DIRECTORY="$1"
  [ -d "$DIRECTORY" ] && [ ! -L "$DIRECTORY" ] || return 1
  METADATA=$(LC_ALL=C /usr/bin/stat -c '%u:%g:%a:%F' -- "$DIRECTORY" 2>/dev/null) || return 1
  OLD_IFS=$IFS
  IFS=:
  read -r PI_UID PI_GID PI_MODE PI_KIND <<EOF
$METADATA
EOF
  IFS=$OLD_IFS
  [ "$PI_UID" = 0 ] && [ "$PI_GID" = 0 ] && [ "$PI_KIND" = "directory" ] || return 1
  case "$PI_MODE" in
    ''|*[!0-7]*|*[2367][0-7]|*[0-7][2367]) return 1 ;;
  esac
  process_inspector_acl_free "$DIRECTORY"
)

validate_process_inspector_file() (
  INSPECTOR="$1"
  EXPECTED_SHA256="$2"
  GETCAP_BIN="$3"
  [ -f "$INSPECTOR" ] && [ ! -L "$INSPECTOR" ] || return 1
  METADATA=$(LC_ALL=C /usr/bin/stat -c '%u:%g:%a:%h:%F' -- "$INSPECTOR" 2>/dev/null) || return 1
  [ "$METADATA" = "0:0:755:1:regular file" ] || return 1
  process_inspector_acl_free "$INSPECTOR" || return 1
  ACTUAL_SHA256=$(/usr/bin/sha256sum -- "$INSPECTOR" 2>/dev/null | /usr/bin/awk '{print $1}') || return 1
  [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || return 1
  CAPABILITY=$(LC_ALL=C "$GETCAP_BIN" -n "$INSPECTOR" 2>/dev/null) || return 1
  [ "$CAPABILITY" = "$INSPECTOR cap_sys_ptrace=ep" ]
)

validate_process_inspector_protocol() (
  INSPECTOR="$1"
  PROBE_DIRECTORY="$2"
  PROBE=$(/usr/bin/mktemp "$PROBE_DIRECTORY/process-inspector-probe.XXXXXX") || return 1
  trap '/usr/bin/rm -f -- "$PROBE"' EXIT HUP INT TERM
  chmod 600 "$PROBE"
  "$INSPECTOR" "$$" >"$PROBE" 2>/dev/null || return 1
  SIZE=$(/usr/bin/wc -c <"$PROBE" | /usr/bin/tr -d '[:space:]') || return 1
  case "$SIZE" in ''|*[!0-9]*) return 1 ;; esac
  [ "$SIZE" -ge 21 ] && [ "$SIZE" -le 4116 ] || return 1
  MAGIC=$(/usr/bin/dd if="$PROBE" bs=1 count=16 status=none | /usr/bin/od -An -tx1 | /usr/bin/tr -d '[:space:]') || return 1
  [ "$MAGIC" = "53594e544155522d50492d5631000000" ] || return 1
  LENGTH_BYTES=$(/usr/bin/dd if="$PROBE" bs=1 skip=16 count=4 status=none | /usr/bin/od -An -tu1) || return 1
  # shellcheck disable=SC2086 # four decimal protocol bytes intentionally split into argv fields.
  set -- $LENGTH_BYTES
  [ "$#" -eq 4 ] || return 1
  BYTE_1=$1
  BYTE_2=$2
  BYTE_3=$3
  BYTE_4=$4
  for BYTE in "$BYTE_1" "$BYTE_2" "$BYTE_3" "$BYTE_4"; do
    case "$BYTE" in ''|*[!0-9]*) return 1 ;; esac
    [ "$BYTE" -le 255 ] || return 1
  done
  LENGTH=$((BYTE_1 * 16777216 + BYTE_2 * 65536 + BYTE_3 * 256 + BYTE_4))
  [ "$LENGTH" -ge 1 ] && [ "$LENGTH" -le 4096 ] || return 1
  [ "$SIZE" -eq $((20 + LENGTH)) ] || return 1
  FIRST=$(/usr/bin/dd if="$PROBE" bs=1 skip=20 count=1 status=none | /usr/bin/od -An -tu1 | /usr/bin/tr -d '[:space:]') || return 1
  [ "$FIRST" = 47 ] || return 1
  NON_NUL=$(/usr/bin/dd if="$PROBE" bs=1 skip=20 count="$LENGTH" status=none | /usr/bin/tr -d '\000' | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]') || return 1
  [ "$NON_NUL" = "$LENGTH" ]
)

provision_process_inspector() (
  STAGED_INSPECTOR="$1"
  EXPECTED_SHA256="$2"
  RELEASE_VERSION="$3"
  INSPECTOR_ROOT="$4"
  PROBE_DIRECTORY="$5"

  case "$EXPECTED_SHA256" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || return 1
  safe_release_component "$RELEASE_VERSION" || return 1
  case "$RELEASE_VERSION" in [0-9]*.[0-9]*.[0-9]*) ;; *) return 1 ;; esac
  [ -f "$STAGED_INSPECTOR" ] && [ ! -L "$STAGED_INSPECTOR" ] || return 1
  STAGED_SHA256=$(/usr/bin/sha256sum -- "$STAGED_INSPECTOR" 2>/dev/null | /usr/bin/awk '{print $1}') || return 1
  [ "$STAGED_SHA256" = "$EXPECTED_SHA256" ] || return 1
  [ -d "$PROBE_DIRECTORY" ] && [ ! -L "$PROBE_DIRECTORY" ] || return 1
  [ "$INSPECTOR_ROOT" = "/usr/local/libexec/syntaur/process-inspectors" ] || return 1
  if [ "$(id -u)" = 0 ]; then
    echo "  Error: run the installer as your ordinary account; it uses sudo only for the narrow helper."
    return 1
  fi

  SETCAP_BIN=/usr/sbin/setcap
  GETCAP_BIN=/usr/sbin/getcap
  [ -x "$SETCAP_BIN" ] || SETCAP_BIN=/sbin/setcap
  [ -x "$GETCAP_BIN" ] || GETCAP_BIN=/sbin/getcap
  [ -x "$SETCAP_BIN" ] && [ -x "$GETCAP_BIN" ] || {
    echo "  Error: setcap and getcap are required for the managed runtime"
    return 1
  }

  VERSION_DIRECTORY="$INSPECTOR_ROOT/$RELEASE_VERSION"
  DESTINATION="$VERSION_DIRECTORY/syntaur-process-inspector"
  for DIRECTORY in / /usr /usr/local; do
    validate_process_inspector_directory "$DIRECTORY" || {
      echo "  Error: process inspector ancestor authority is unsafe: $DIRECTORY"
      return 1
    }
  done

  if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    for DIRECTORY in \
      /usr/local/libexec \
      /usr/local/libexec/syntaur \
      /usr/local/libexec/syntaur/process-inspectors \
      "$VERSION_DIRECTORY"
    do
      validate_process_inspector_directory "$DIRECTORY" || {
        echo "  Error: process inspector directory authority is unsafe: $DIRECTORY"
        return 1
      }
    done
    if ! validate_process_inspector_file "$DESTINATION" "$EXPECTED_SHA256" "$GETCAP_BIN" \
        || ! validate_process_inspector_protocol "$DESTINATION" "$PROBE_DIRECTORY"; then
      echo "  Error: the immutable process inspector for v$RELEASE_VERSION is invalid"
      return 1
    fi
    echo "  ✓ Reusing the authenticated process inspector for v$RELEASE_VERSION"
    return 0
  fi

  if [ "${SYNTAUR_INSTALL_TEST_LIBRARY_ONLY:-0}" = 1 ] \
     && [ "${SYNTAUR_INSTALL_TEST_FORBID_SUDO:-0}" = 1 ]; then
    echo "  Error: test forbids privilege escalation"
    return 1
  fi
  [ -x /usr/bin/sudo ] || {
    echo "  Error: sudo is required to install the narrow process inspector"
    return 1
  }
  /usr/bin/sudo -v || return 1
  ROOT_PREFIX=/usr/bin/sudo

  run_process_inspector_root() {
    if [ -n "$ROOT_PREFIX" ]; then
      "$ROOT_PREFIX" -n "$@"
    else
      "$@"
    fi
  }

  for DIRECTORY in \
    /usr/local/libexec \
    /usr/local/libexec/syntaur \
    /usr/local/libexec/syntaur/process-inspectors \
    "$VERSION_DIRECTORY"
  do
    if [ -e "$DIRECTORY" ] || [ -L "$DIRECTORY" ]; then
      validate_process_inspector_directory "$DIRECTORY" || {
        echo "  Error: process inspector directory authority is unsafe: $DIRECTORY"
        return 1
      }
    else
      run_process_inspector_root /usr/bin/install --directory --mode=0755 --owner=root --group=root -- "$DIRECTORY" || return 1
      validate_process_inspector_directory "$DIRECTORY" || return 1
    fi
  done

  if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    echo "  Error: process inspector destination appeared during publication"
    return 1
  fi
  run_process_inspector_root /usr/bin/find "$VERSION_DIRECTORY" \
    -maxdepth 1 -type f -name '.syntaur-process-inspector.*' -delete || return 1
  ROOT_TEMP=$(run_process_inspector_root /usr/bin/mktemp --tmpdir="$VERSION_DIRECTORY" .syntaur-process-inspector.XXXXXX) || return 1
  case "$ROOT_TEMP" in "$VERSION_DIRECTORY"/.syntaur-process-inspector.*) ;; *) return 1 ;; esac
  # shellcheck disable=SC2329 # invoked by the signal and EXIT traps below.
  cleanup_process_inspector_temp() {
    if [ -n "${ROOT_TEMP:-}" ]; then
      run_process_inspector_root /usr/bin/rm --force -- "$ROOT_TEMP" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_process_inspector_temp EXIT
  trap 'cleanup_process_inspector_temp; exit 129' HUP
  trap 'cleanup_process_inspector_temp; exit 130' INT
  trap 'cleanup_process_inspector_temp; exit 143' TERM
  run_process_inspector_root /usr/bin/install --mode=0755 --owner=root --group=root -- "$STAGED_INSPECTOR" "$ROOT_TEMP" || return 1
  ROOT_SHA256=$(run_process_inspector_root /usr/bin/sha256sum -- "$ROOT_TEMP" | /usr/bin/awk '{print $1}') || return 1
  [ "$ROOT_SHA256" = "$EXPECTED_SHA256" ] || return 1
  run_process_inspector_root "$SETCAP_BIN" cap_sys_ptrace=ep "$ROOT_TEMP" || return 1
  ROOT_SHA256=$(run_process_inspector_root /usr/bin/sha256sum -- "$ROOT_TEMP" | /usr/bin/awk '{print $1}') || return 1
  [ "$ROOT_SHA256" = "$EXPECTED_SHA256" ] || return 1
  validate_process_inspector_file "$ROOT_TEMP" "$EXPECTED_SHA256" "$GETCAP_BIN" || return 1
  validate_process_inspector_protocol "$ROOT_TEMP" "$PROBE_DIRECTORY" || return 1
  run_process_inspector_root /usr/bin/sync -- "$ROOT_TEMP" || return 1
  if [ "${SYNTAUR_INSTALL_TEST_LIBRARY_ONLY:-0}" = 1 ] \
     && [ -n "${SYNTAUR_INSTALL_TEST_BEFORE_PUBLISH_READY:-}" ]; then
    : >"$SYNTAUR_INSTALL_TEST_BEFORE_PUBLISH_READY"
    WAIT_COUNT=0
    while [ ! -f "${SYNTAUR_INSTALL_TEST_BEFORE_PUBLISH_CONTINUE:-}" ]; do
      WAIT_COUNT=$((WAIT_COUNT + 1))
      [ "$WAIT_COUNT" -le 100 ] || return 1
      sleep 0.05
    done
  fi
  if ! run_process_inspector_root /usr/bin/mv --no-clobber --no-target-directory -- "$ROOT_TEMP" "$DESTINATION"; then
    echo "  Error: could not publish the process inspector"
    return 1
  fi
  if [ -e "$ROOT_TEMP" ] || [ -L "$ROOT_TEMP" ]; then
    echo "  Error: process inspector destination already exists"
    return 1
  fi
  ROOT_TEMP=""
  run_process_inspector_root /usr/bin/sync -- "$VERSION_DIRECTORY" || return 1
  validate_process_inspector_file "$DESTINATION" "$EXPECTED_SHA256" "$GETCAP_BIN" || return 1
  validate_process_inspector_protocol "$DESTINATION" "$PROBE_DIRECTORY" || return 1
  echo "  ✓ Installed the authenticated process inspector for v$RELEASE_VERSION"
)

safe_release_component() {
  VALUE="$1"
  case "$VALUE" in
    ''|.*|*..*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#VALUE}" -le 160 ]
}

valid_release_size() {
  VALUE="$1"
  case "$VALUE" in
    ''|0|0[0-9]*|*[!0-9]*) return 1 ;;
  esac
  [ "$VALUE" -le 1073741824 ]
}

validate_stage_requirement() {
  REQ_TAG="$1"
  REQ_ASSET="$2"
  REQ_STAGED="$3"
  REQ_SHA256="$4"
  REQ_SIZE="$5"
  REQ_MAX_SIZE="$6"

  safe_release_component "$REQ_TAG" || return 1
  case "$REQ_TAG" in v[0-9]*.[0-9]*.[0-9]*) ;; *) return 1 ;; esac
  safe_release_component "$REQ_ASSET" || return 1
  safe_release_component "$REQ_STAGED" || return 1
  case "$REQ_SHA256" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#REQ_SHA256}" -eq 64 ] || return 1
  valid_release_size "$REQ_SIZE" || return 1
  valid_release_size "$REQ_MAX_SIZE" || return 1
  [ "$REQ_SIZE" -le "$REQ_MAX_SIZE" ]
}

portable_stat_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1" 2>/dev/null
}

portable_stat_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

portable_stat_size() {
  stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null
}

safe_eula_entry() {
  EULA_ENTRY_PATH="$1"
  EULA_ENTRY_KIND="$2"
  [ ! -L "$EULA_ENTRY_PATH" ] || return 1
  case "$EULA_ENTRY_KIND" in
    directory) [ -d "$EULA_ENTRY_PATH" ] || return 1 ;;
    file) [ -f "$EULA_ENTRY_PATH" ] || return 1 ;;
    *) return 1 ;;
  esac
  EULA_ENTRY_UID=$(portable_stat_uid "$EULA_ENTRY_PATH") || return 1
  [ "$EULA_ENTRY_UID" = "$(id -u)" ] || return 1
  EULA_ENTRY_MODE=$(portable_stat_mode "$EULA_ENTRY_PATH") || return 1
  case "$EULA_ENTRY_MODE" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) return 1 ;;
  esac
  [ $((0$EULA_ENTRY_MODE & 0022)) -eq 0 ]
}

canonical_eula_timestamp() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
    *) return 1 ;;
  esac
}

canonical_installer_version() {
  EULA_VERSION_VALUE="$1"
  case "$EULA_VERSION_VALUE" in *[!0-9.]*|'') return 1 ;; esac
  EULA_VERSION_MAJOR=${EULA_VERSION_VALUE%%.*}
  EULA_VERSION_REMAINDER=${EULA_VERSION_VALUE#*.}
  [ "$EULA_VERSION_REMAINDER" != "$EULA_VERSION_VALUE" ] || return 1
  EULA_VERSION_MINOR=${EULA_VERSION_REMAINDER%%.*}
  EULA_VERSION_PATCH=${EULA_VERSION_REMAINDER#*.}
  [ "$EULA_VERSION_PATCH" != "$EULA_VERSION_REMAINDER" ] || return 1
  case "$EULA_VERSION_PATCH" in *.*) return 1 ;; esac
  for EULA_VERSION_FIELD in "$EULA_VERSION_MAJOR" "$EULA_VERSION_MINOR" "$EULA_VERSION_PATCH"; do
    case "$EULA_VERSION_FIELD" in
      ''|*[!0-9]*|0[0-9]*) return 1 ;;
    esac
  done
}

eula_record_matches_url() {
  EULA_RECORD_PATH="$1"
  EULA_RECORD_EXPECTED_URL="$2"
  EULA_RECORD_DIR=${EULA_RECORD_PATH%/*}
  safe_eula_entry "$EULA_RECORD_DIR" directory || return 1
  safe_eula_entry "$EULA_RECORD_PATH" file || return 1
  EULA_RECORD_SIZE=$(portable_stat_size "$EULA_RECORD_PATH") || return 1
  case "$EULA_RECORD_SIZE" in ''|*[!0-9]*) return 1 ;; esac
  [ "$EULA_RECORD_SIZE" -gt 0 ] && [ "$EULA_RECORD_SIZE" -le "$EULA_RECORD_MAX_BYTES" ] || return 1

  EULA_RECORD_SCHEMA=""
  EULA_RECORD_VERSION=""
  EULA_RECORD_SHA256=""
  EULA_RECORD_URL=""
  EULA_RECORD_ACCEPTED_AT=""
  EULA_RECORD_METHOD=""
  EULA_RECORD_INSTALLER_VERSION=""
  EULA_RECORD_LINE_NUMBER=0
  while IFS= read -r EULA_RECORD_LINE || [ -n "$EULA_RECORD_LINE" ]; do
    EULA_RECORD_LINE_NUMBER=$((EULA_RECORD_LINE_NUMBER + 1))
    case "$EULA_RECORD_LINE_NUMBER:$EULA_RECORD_LINE" in
      1:record_format=*) EULA_RECORD_SCHEMA=${EULA_RECORD_LINE#record_format=} ;;
      2:eula_version=*) EULA_RECORD_VERSION=${EULA_RECORD_LINE#eula_version=} ;;
      3:eula_sha256=*) EULA_RECORD_SHA256=${EULA_RECORD_LINE#eula_sha256=} ;;
      4:eula_url=*) EULA_RECORD_URL=${EULA_RECORD_LINE#eula_url=} ;;
      5:accepted_at=*) EULA_RECORD_ACCEPTED_AT=${EULA_RECORD_LINE#accepted_at=} ;;
      6:method=*) EULA_RECORD_METHOD=${EULA_RECORD_LINE#method=} ;;
      7:installer_version=*) EULA_RECORD_INSTALLER_VERSION=${EULA_RECORD_LINE#installer_version=} ;;
      *) return 1 ;;
    esac
  done < "$EULA_RECORD_PATH"

  [ "$EULA_RECORD_LINE_NUMBER" -eq 7 ] || return 1
  [ "$EULA_RECORD_SCHEMA" = "$EULA_RECORD_FORMAT" ] || return 1
  [ "$EULA_RECORD_SHA256" = "$EULA_SHA256" ] || return 1
  [ "$EULA_RECORD_VERSION" = "$EULA_VERSION" ] || return 1
  [ "$EULA_RECORD_URL" = "$EULA_RECORD_EXPECTED_URL" ] || return 1
  canonical_eula_timestamp "$EULA_RECORD_ACCEPTED_AT" || return 1
  case "$EULA_RECORD_METHOD" in flag|prompt) ;; *) return 1 ;; esac
  canonical_installer_version "$EULA_RECORD_INSTALLER_VERSION"
}

eula_record_is_current() {
  eula_record_matches_url "$1" "$EULA_URL"
}

persist_eula_acceptance() {
  EULA_METHOD_TO_RECORD="$1"
  EULA_ACCEPTED_AT_TO_RECORD=${2:-}
  EULA_INSTALLER_VERSION_TO_RECORD=${3:-}
  case "$EULA_METHOD_TO_RECORD" in flag|prompt) ;; *) return 1 ;; esac
  if [ -n "$EULA_ACCEPTED_AT_TO_RECORD" ] || [ -n "$EULA_INSTALLER_VERSION_TO_RECORD" ]; then
    [ -n "$EULA_ACCEPTED_AT_TO_RECORD" ] && [ -n "$EULA_INSTALLER_VERSION_TO_RECORD" ] || return 1
    canonical_eula_timestamp "$EULA_ACCEPTED_AT_TO_RECORD" || return 1
    canonical_installer_version "$EULA_INSTALLER_VERSION_TO_RECORD" || return 1
  else
    EULA_ACCEPTED_AT_TO_RECORD=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1
    EULA_INSTALLER_VERSION_TO_RECORD=$VERSION
    canonical_installer_version "$EULA_INSTALLER_VERSION_TO_RECORD" || return 1
  fi
  EULA_SYNTAUR_DIR="$HOME/.syntaur"
  EULA_ACCEPTANCE_RECORD="$EULA_SYNTAUR_DIR/eula-accepted"
  if [ -e "$EULA_SYNTAUR_DIR" ] || [ -L "$EULA_SYNTAUR_DIR" ]; then
    safe_eula_entry "$EULA_SYNTAUR_DIR" directory || return 1
  else
    EULA_OLD_UMASK=$(umask)
    umask 077
    mkdir "$EULA_SYNTAUR_DIR" 2>/dev/null || {
      umask "$EULA_OLD_UMASK"
      return 1
    }
    umask "$EULA_OLD_UMASK"
    safe_eula_entry "$EULA_SYNTAUR_DIR" directory || return 1
  fi
  if [ -L "$EULA_ACCEPTANCE_RECORD" ]; then
    rm -f "$EULA_ACCEPTANCE_RECORD" || return 1
  elif [ -e "$EULA_ACCEPTANCE_RECORD" ] && [ ! -f "$EULA_ACCEPTANCE_RECORD" ]; then
    return 1
  fi
  EULA_RECORD_TEMP=$(mktemp "$EULA_SYNTAUR_DIR/.eula-accepted.tmp.XXXXXX") || return 1
  chmod 600 "$EULA_RECORD_TEMP" || {
    rm -f "$EULA_RECORD_TEMP"
    return 1
  }
  if ! {
    printf 'record_format=%s\n' "$EULA_RECORD_FORMAT"
    printf 'eula_version=%s\n' "$EULA_VERSION"
    printf 'eula_sha256=%s\n' "$EULA_SHA256"
    printf 'eula_url=%s\n' "$EULA_URL"
    printf 'accepted_at=%s\n' "$EULA_ACCEPTED_AT_TO_RECORD"
    printf 'method=%s\n' "$EULA_METHOD_TO_RECORD"
    printf 'installer_version=%s\n' "$EULA_INSTALLER_VERSION_TO_RECORD"
  } > "$EULA_RECORD_TEMP"; then
    rm -f "$EULA_RECORD_TEMP"
    return 1
  fi
  if ! mv -f "$EULA_RECORD_TEMP" "$EULA_ACCEPTANCE_RECORD"; then
    rm -f "$EULA_RECORD_TEMP"
    return 1
  fi
  safe_eula_entry "$EULA_ACCEPTANCE_RECORD" file
}

migrate_historical_eula_record() {
  EULA_MIGRATION_RECORD="$1"
  [ "$EULA_MIGRATION_RECORD" = "$HOME/.syntaur/eula-accepted" ] || return 1
  eula_record_matches_url "$EULA_MIGRATION_RECORD" "$EULA_HISTORICAL_URL" || return 1
  EULA_MIGRATION_ACCEPTED_AT=$EULA_RECORD_ACCEPTED_AT
  EULA_MIGRATION_METHOD=$EULA_RECORD_METHOD
  EULA_MIGRATION_INSTALLER_VERSION=$EULA_RECORD_INSTALLER_VERSION
  persist_eula_acceptance \
    "$EULA_MIGRATION_METHOD" \
    "$EULA_MIGRATION_ACCEPTED_AT" \
    "$EULA_MIGRATION_INSTALLER_VERSION" || return 1
  eula_record_is_current "$EULA_MIGRATION_RECORD"
}

ensure_eula_acceptance() {
  EULA_ACCEPTANCE_RECORD="$HOME/.syntaur/eula-accepted"
  if eula_record_is_current "$EULA_ACCEPTANCE_RECORD" || \
      migrate_historical_eula_record "$EULA_ACCEPTANCE_RECORD"; then
    echo "  EULA v$EULA_VERSION previously accepted; continuing."
    echo ""
    return 0
  fi

  EULA_METHOD=""
  if [ "$ACCEPT_EULA" = "1" ]; then
    EULA_METHOD="flag"
  else
    echo "  Installing $BRAND requires accepting the End User License Agreement (v$EULA_VERSION):"
    echo "    $EULA_URL"
    echo ""
    if [ -t 0 ]; then
      printf '  Type "I AGREE" to accept (anything else aborts): '
      read -r EULA_ANS || EULA_ANS=""
    elif ( : < /dev/tty ) 2>/dev/null; then
      printf '  Type "I AGREE" to accept (anything else aborts): ' > /dev/tty
      read -r EULA_ANS < /dev/tty || EULA_ANS=""
    else
      echo "  No terminal available to accept interactively."
      echo "  Re-run with --accept-eula after reading the EULA at the URL above."
      return 1
    fi
    EULA_ANS_UC=$(printf '%s' "$EULA_ANS" | tr '[:lower:]' '[:upper:]')
    case "$EULA_ANS_UC" in
      "I AGREE") EULA_METHOD="prompt" ;;
      *) echo "  EULA not accepted — install aborted."; return 1 ;;
    esac
  fi
  if ! persist_eula_acceptance "$EULA_METHOD"; then
    echo "  Warning: EULA acceptance could not be stored securely; this install will continue,"
    echo "  but a future installer may need to ask again."
  fi
  echo "  EULA v$EULA_VERSION accepted (via $EULA_METHOD)."
  echo ""
}

configure_link_transport() (
  umask 077
  SNOWFLAKE_HELPER="$INSTALL_DIR/syntaur-snowflake-client"

  if [ "$PLATFORM" = "macos" ]; then
    LINK_TOR_DIR="$HOME/Library/Application Support/Syntaur/link-tor"
  else
    LINK_TOR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/syntaur/link-tor"
  fi
  LINK_TOR_STATE="$LINK_TOR_DIR/state"
  LINK_TOR_CACHE="$LINK_TOR_DIR/cache"
  LINK_TOR_CONFIG="$LINK_TOR_DIR/client.json"

  [ ! -L "$(dirname "$LINK_TOR_DIR")" ] || return 1

  # Updates preserve bridge choices and enrollment. Never replace an existing
  # config, including when two installers race.
  if [ -e "$LINK_TOR_CONFIG" ] || [ -L "$LINK_TOR_CONFIG" ]; then
    safe_eula_entry "$LINK_TOR_DIR" directory &&
      safe_eula_entry "$LINK_TOR_CONFIG" file || return 1
    CONFIG_SIZE=$(portable_stat_size "$LINK_TOR_CONFIG") || return 1
    [ "$CONFIG_SIZE" -gt 0 ] && [ "$CONFIG_SIZE" -le 65536 ] || return 1
    return 0
  fi

  for DIRECTORY in "$(dirname "$LINK_TOR_DIR")" "$LINK_TOR_DIR" "$LINK_TOR_STATE" "$LINK_TOR_CACHE"; do
    if [ -L "$DIRECTORY" ] || { [ -e "$DIRECTORY" ] && [ ! -d "$DIRECTORY" ]; }; then
      echo "  Error: unsafe Syntaur Link configuration path: $DIRECTORY"
      return 1
    fi
    mkdir -p "$DIRECTORY"
    safe_eula_entry "$DIRECTORY" directory || {
      echo "  Error: unsafe Syntaur Link directory ownership or permissions"
      return 1
    }
    chmod 700 "$DIRECTORY"
  done

  for JSON_PATH in "$LINK_TOR_STATE" "$LINK_TOR_CACHE" "$SNOWFLAKE_HELPER"; do
    case "$JSON_PATH" in /*) ;; *) echo "  Error: Syntaur Link paths must be absolute"; return 1 ;; esac
    CLEAN_PATH=$(printf '%s' "$JSON_PATH" | LC_ALL=C tr -d '[:cntrl:]')
    if [ "$CLEAN_PATH" != "$JSON_PATH" ]; then
      echo "  Error: Syntaur Link paths may not contain control characters"
      return 1
    fi
  done
  json_escape() {
    LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
  }
  STATE_JSON=$(printf '%s' "$LINK_TOR_STATE" | json_escape)
  CACHE_JSON=$(printf '%s' "$LINK_TOR_CACHE" | json_escape)
  SNOWFLAKE_JSON=$(printf '%s' "$SNOWFLAKE_HELPER" | json_escape)

  TEMP_CONFIG=$(mktemp "$LINK_TOR_DIR/.client.json.XXXXXX") || return 1
  trap 'rm -f "$TEMP_CONFIG"' EXIT HUP INT TERM
  cat > "$TEMP_CONFIG" <<EOF
{
  "schema": 2,
  "state_dir": "$STATE_JSON",
  "cache_dir": "$CACHE_JSON",
  "bridge_bundle": {
    "schema": 1,
    "transport": "snowflake",
    "bridge_lines": [
      "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443 utls-imitate=hellorandomizedalpn",
      "Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443 utls-imitate=hellorandomizedalpn"
    ]
  },
  "transport_binary": "$SNOWFLAKE_JSON",
  "bundled_transport": true
}
EOF
  chmod 600 "$TEMP_CONFIG"
  if ! ln "$TEMP_CONFIG" "$LINK_TOR_CONFIG" 2>/dev/null; then
    safe_eula_entry "$LINK_TOR_CONFIG" file || return 1
  fi
  safe_eula_entry "$LINK_TOR_CONFIG" file || return 1
  rm -f "$TEMP_CONFIG"
  trap - EXIT HUP INT TERM
  echo "  Syntaur Link transport configuration installed."
)

write_app_launcher() {
  case "$MODE" in server|connect) ;; *) return 1 ;; esac
  case "$PLATFORM" in linux|macos) ;; *) return 1 ;; esac
  {
    printf '#!/bin/sh\nINSTALL_MODE=%s\nAPP_PLATFORM=%s\n' "$MODE" "$PLATFORM"
    cat <<'LAUNCHER'
APP_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd) || exit 1
export PATH="$APP_DIR:$PATH"
# Retired URL and bearer variables cannot select a remote customer path.
unset SYNTAUR_URL SYNTAUR_OPEN_URL SYNTAUR_SESSION_TOKEN SYNTAUR_TS_AUTHKEY
if [ "$INSTALL_MODE" = "server" ]; then
  if [ "$APP_PLATFORM" = "macos" ]; then
    exec "$APP_DIR/syntaur-viewer" --server
  fi
  if [ -x "$APP_DIR/syntaur-engine" ]; then
    exec "$APP_DIR/syntaur-engine" --url http://127.0.0.1:18789 --width 1440 --height 950
  fi
  exec "$APP_DIR/syntaur-viewer" --local-owner
fi
if [ "$APP_PLATFORM" = "macos" ]; then
  LINK_PROFILE="$HOME/Library/Application Support/Syntaur/link-profile.json"
else
  LINK_PROFILE="${XDG_CONFIG_HOME-$HOME/.config}/syntaur/link-profile.json"
fi
if [ -f "$LINK_PROFILE" ] && [ -x "$APP_DIR/syntaur-engine" ]; then
  exec "$APP_DIR/syntaur-engine" --link --width 1440 --height 950
fi
exec "$APP_DIR/syntaur-viewer"
LAUNCHER
  } > "$APP_LAUNCHER"
  chmod +x "$APP_LAUNCHER"
}

# The same selected-user LaunchAgent used by the native Mac server launcher.
# It owns background restart; the Viewer owns the single setup window.
macos_xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

macos_absolute_path() {
  p="$1"
  [ -n "$p" ] || return 1
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    *[[:cntrl:]]*) return 1 ;;
  esac
  return 0
}

macos_u32_id() {
  val="$1"
  case "$val" in
    ''|*[!0-9]*) return 1 ;;
    0[0-9]*) return 1 ;;
  esac
  [ ${#val} -le 10 ] || return 1
  if [ ${#val} -eq 10 ]; then
    [ "$val" -le 4294967295 ] || return 1
  fi
  return 0
}

render_macos_tor_launchdaemon() (
  host_exec="$1"
  cfg_path="$2"

  macos_absolute_path "$host_exec" || return 1
  macos_absolute_path "$cfg_path" || return 1

  exec_xml=$(macos_xml_escape "$host_exec") || return 1
  cfg_xml=$(macos_xml_escape "$cfg_path") || return 1

  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.syntaur.link-tor</string>
  <key>ProgramArguments</key><array><string>$exec_xml</string></array>
  <key>UserName</key><string>_syntaur_tor</string>
  <key>GroupName</key><string>_syntaur_link</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>Umask</key><integer>63</integer>
  <key>EnvironmentVariables</key><dict>
    <key>SYNTAUR_LINK_TOR_CONFIG</key><string>$cfg_xml</string>
  </dict>
</dict></plist>
PLIST
)

# Provision only the existing isolated HOST. Gateway remains a user LaunchAgent.
# The caller authenticates the asset before this narrow administrator boundary;
# the root copy is hashed again before launchd can execute it.
validate_macos_host_stage() (
  macos_absolute_path "$1" || return 1
  safe_release_component "$3" || return 1
  case "$2" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#2}" -eq 64 ] || return 1
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  stage_size=$(portable_stat_size "$1") || return 1
  [ "$stage_size" -gt 0 ] && [ "$stage_size" -le 1073741824 ] || return 1
  [ "$(sha256_file "$1")" = "$2" ]
)

provision_macos_tor_host() {
  MACOS_HOST_STAGE=$1
  MACOS_HOST_SHA=$2
  macos_absolute_path "$HOME" || return 1
  validate_macos_host_stage "$MACOS_HOST_STAGE" "$MACOS_HOST_SHA" "$VERSION" || return 1
  [ "$(id -u)" -ne 0 ] || return 1
  [ "${SYNTAUR_INSTALL_TEST_FORBID_SUDO:-0}" != 1 ] || return 1
  MACOS_HOST_PLIST=$(render_macos_tor_launchdaemon \
    "/usr/local/libexec/syntaur/link-hosts/$VERSION/syntaur-link-tor" \
    '/Library/Application Support/Syntaur/LinkTor/private/host.json') || return 1
  /usr/bin/sudo -v || return 1
  # Pass data as arguments, never interpolate it into the privileged program.
  /usr/bin/sudo -n /bin/sh -s -- "$MACOS_HOST_STAGE" "$MACOS_HOST_SHA" \
    "$VERSION" "$(id -u)" "$HOME" "$MACOS_HOST_PLIST" <<'MACOS_HOST_ROOT' || return 1
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
stage=$1; digest=$2; version=$3; gateway_uid=$4; gateway_home=$5; plist_body=$6
[ "$(id -u)" = 0 ] || exit 1
case "$digest" in ''|*[!0-9a-f]*) exit 1 ;; esac
[ "${#digest}" = 64 ] || exit 1
case "$version" in ''|.*|*..*|*[!A-Za-z0-9._-]*) exit 1 ;; esac
case "$gateway_uid" in ''|0|0*|*[!0-9]*) exit 1 ;; esac
owner=$(/usr/bin/id -un "$gateway_uid")
case "$owner" in ''|*[!A-Za-z0-9_.-]*) exit 1 ;; esac
registered_home=$(/usr/bin/dscl . -read "/Users/$owner" NFSHomeDirectory)
[ "$registered_home" = "NFSHomeDirectory: $gateway_home" ] || exit 1
[ -d "$gateway_home" ] && [ ! -L "$gateway_home" ] || exit 1
[ "$(cd -P "$gateway_home" && pwd)" = "$gateway_home" ] || exit 1
[ "$(/usr/bin/stat -f '%u' "$gateway_home")" = "$gateway_uid" ] || exit 1
base='/Library/Application Support/Syntaur/LinkTor'
codebase=/usr/local/libexec/syntaur/link-hosts
code="$codebase/$version"
host="$code/syntaur-link-tor"
job=/Library/LaunchDaemons/dev.syntaur.link-tor.plist
agent="$gateway_home/Library/LaunchAgents/dev.syntaur.gateway.plist"

# Refuse aliases, ACL grants and wrong roles. Never repair another owner's tree.
entry() {
  path=$1; kind=$2; uid=$3; gid=$4; mode=$5
  [ ! -L "$path" ] || return 1
  case "$kind" in d) [ -d "$path" ] ;; f) [ -f "$path" ] ;; *) return 1 ;; esac || return 1
  entry_metadata=$(/usr/bin/stat -f '%u:%g:%p' "$path") || return 1
  entry_permissions=${entry_metadata##*:}
  case "$entry_permissions" in ''|*[!0-7]*) return 1 ;; esac
  [ "${entry_metadata%:*}" = "$uid:$gid" ] || return 1
  [ $((0$entry_permissions & 07777)) -eq $((0$mode)) ] || return 1
  [ "$(/bin/ls -lde "$path" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 ] || return 1
  if [ "$kind" = f ]; then [ "$(/usr/bin/stat -f '%l' "$path")" = 1 ] || return 1; fi
}
root_ancestor() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(/usr/bin/stat -f '%u' "$1")" = 0 ] || return 1
  permissions=$(/usr/bin/stat -f '%Lp' "$1")
  [ $((0$permissions & 0022)) -eq 0 ] || return 1
  [ "$(/bin/ls -lde "$1" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 ]
}
loaded_host_matches() {
  [ "${#1}" -le 65536 ] || return 1
  printf '%s\n' "$1" | /usr/bin/awk -v program="$2" -v path="$job" -v config="$base/private/host.json" '
    { sub(/^[ \t]+/, "") }
    $0 == "arguments = {" {blocks++; in_args=1; next}
    in_args {if ($0 == "}") {in_args=0} else {args++; if ($0 != program) bad=1}; next}
    /^path = / {if ($0 != "path = " path) bad=1; paths++}
    /^program = / {if ($0 != "program = " program) bad=1; programs++}
    /^username = / {if ($0 != "username = _syntaur_tor") bad=1; users++}
    /^group = / {if ($0 != "group = _syntaur_link") bad=1; groups++}
    /^SYNTAUR_LINK_TOR_CONFIG => / {if ($0 != "SYNTAUR_LINK_TOR_CONFIG => " config) bad=1; configs++}
    END {exit bad || in_args || blocks != 1 || args != 1 || paths != 1 || programs != 1 || users != 1 || groups != 1 || configs != 1}
  '
}
for path in / /Library '/Library/Application Support' /Library/LaunchDaemons /usr /usr/local; do
  root_ancestor "$path" || exit 1
done
for path in '/Library/Application Support/Syntaur' "$base" /usr/local/libexec /usr/local/libexec/syntaur "$codebase" "$code"; do
  if [ -e "$path" ] || [ -L "$path" ]; then entry "$path" d 0 0 755 || exit 1; fi
done
if [ -e "$job" ] || [ -L "$job" ]; then
  entry "$job" f 0 0 644 || exit 1
  [ "$(/usr/bin/plutil -extract Label raw -o - "$job")" = dev.syntaur.link-tor ] || exit 1
  [ "$(/usr/bin/plutil -extract UserName raw -o - "$job")" = _syntaur_tor ] || exit 1
  [ "$(/usr/bin/plutil -extract GroupName raw -o - "$job")" = _syntaur_link ] || exit 1
  [ "$(/usr/bin/plutil -extract EnvironmentVariables.SYNTAUR_LINK_TOR_CONFIG raw -o - "$job")" = "$base/private/host.json" ] || exit 1
  previous_program=$(/usr/bin/plutil -extract ProgramArguments.0 raw -expect string -o - "$job")
  case "$previous_program" in "$codebase"/*/syntaur-link-tor) ;; *) exit 1 ;; esac
  previous_version=${previous_program#"$codebase"/}; previous_version=${previous_version%/syntaur-link-tor}
  case "$previous_version" in ''|.*|*..*|*[!A-Za-z0-9._-]*) exit 1 ;; esac
  entry "$codebase/$previous_version" d 0 0 755 || exit 1
  entry "$previous_program" f 0 0 755 || exit 1
fi
if [ -e "$agent" ] || [ -L "$agent" ]; then
  [ ! -L "$agent" ] && [ -f "$agent" ] || exit 1
  [ "$(/usr/bin/stat -f '%u' "$agent")" = "$gateway_uid" ] || exit 1
  # A UID is insufficient: the same user can have unrelated QA HOME directories.
  if previous_home=$(/usr/bin/plutil -extract EnvironmentVariables.HOME raw -o - "$agent" 2>/dev/null); then
    [ "$previous_home" = "$gateway_home" ] || exit 1
  fi
fi
for path in '/Library/Application Support/Syntaur' "$base" /usr/local/libexec /usr/local/libexec/syntaur "$codebase" "$code"; do
  if [ ! -e "$path" ]; then /usr/bin/install -d -m 755 -o root -g wheel "$path"; fi
  entry "$path" d 0 0 755 || exit 1
done
# One standard installer lock, removed on every ordinary return; never force it.
/bin/mkdir "$base/.install-lock" || exit 1
temp=''; config_temp=''; job_temp=''; group_record=''; publish_started=0; publish_committed=0
had_job=0; was_running=0; new_roles=0; private_published=0; created_private=0
new_user_uuid=''; new_group_uuid=''
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$publish_started" = 1 ] && [ "$publish_committed" = 0 ]; then
    # Same exact admitted job, including when a signal interrupts publication.
    rollback_safe=1; already_old=0
    if loaded=$(/bin/launchctl print system/dev.syntaur.link-tor 2>/dev/null); then
      if [ "$had_job" = 1 ] && loaded_host_matches "$loaded" "$previous_program"; then
        already_old=1
      elif loaded_host_matches "$loaded" "$host"; then
        /bin/launchctl bootout system "$job" || rollback_safe=0
      else rollback_safe=0; fi
    else
      status=$?; [ "$status" = 113 ] || rollback_safe=0
    fi
    if [ "$rollback_safe" = 0 ]; then
      result=1
    elif [ "$had_job" = 1 ]; then
      /bin/cp "$backup" "$job" && /bin/chmod 644 "$job" || result=1
      if [ "$was_running" = 1 ] && [ "$already_old" = 0 ]; then /bin/launchctl bootstrap system "$job" || result=1; fi
    elif [ -e "$job" ]; then /bin/rm "$job" || result=1; fi
  fi
  if [ "$new_roles" = 1 ] && [ "$private_published" = 0 ]; then
    # Fresh incomplete identities only, identified by the UUIDs generated in
    # this invocation before their records were created. Never remove adoptees.
    if [ "$created_private" = 1 ]; then
      for leaf in ipc private/cache private/state private; do
        if [ -d "$base/$leaf" ] && [ ! -L "$base/$leaf" ]; then /bin/rmdir "$base/$leaf" || result=1; fi
      done
    fi
    if [ -e "$base/private" ] || [ -L "$base/private" ]; then
      result=1
    elif [ "$(/usr/bin/dscl . -read /Users/_syntaur_tor GeneratedUID 2>/dev/null)" = "GeneratedUID: $new_user_uuid" ]; then
      /usr/bin/dscl . -delete /Users/_syntaur_tor || result=1
    fi
    if [ ! -e "$base/private" ] && [ ! -L "$base/private" ] && [ "$(/usr/bin/dscl . -read /Groups/_syntaur_link GeneratedUID 2>/dev/null)" = "GeneratedUID: $new_group_uuid" ]; then
      /usr/bin/dscl . -delete /Groups/_syntaur_link || result=1
    fi
  fi
  [ -z "$temp" ] || /bin/rm -f "$temp"
  [ -z "$config_temp" ] || /bin/rm -f "$config_temp"
  [ -z "$job_temp" ] || /bin/rm -f "$job_temp"
  [ -z "$group_record" ] || /bin/rm -f "$group_record"
  /bin/rmdir "$base/.install-lock" || result=1
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

group_exists=0; user_exists=0
matches=$(/usr/bin/dscl . -search /Groups RecordName _syntaur_link) || exit 1
[ -z "$matches" ] || group_exists=1
matches=$(/usr/bin/dscl . -search /Users RecordName _syntaur_tor) || exit 1
[ -z "$matches" ] || user_exists=1
[ "$group_exists" = "$user_exists" ] || exit 1
if [ "$group_exists" = 0 ]; then
  # A lost account must never cause adoption of existing private state.
  [ ! -e "$base/private" ] && [ ! -L "$base/private" ] || exit 1
  [ ! -e "$base/ipc" ] && [ ! -L "$base/ipc" ] || exit 1
  shared_gid=''; sidecar_uid=''
  for candidate in $(/usr/bin/jot 100 400); do
    matches=$(/usr/bin/dscl /Search -search /Groups PrimaryGroupID "$candidate") || exit 1
    if [ -z "$matches" ]; then shared_gid=$candidate; break; fi
  done
  for candidate in $(/usr/bin/jot 100 400); do
    matches=$(/usr/bin/dscl /Search -search /Users UniqueID "$candidate") || exit 1
    if [ -z "$matches" ]; then sidecar_uid=$candidate; break; fi
  done
  [ -n "$shared_gid" ] && [ -n "$sidecar_uid" ] && [ "$sidecar_uid" != "$gateway_uid" ] || exit 1
  new_user_uuid=$(/usr/bin/uuidgen); new_group_uuid=$(/usr/bin/uuidgen); new_roles=1
  /usr/bin/dscl . -create /Groups/_syntaur_link GeneratedUID "$new_group_uuid"
  /usr/bin/dscl . -create /Groups/_syntaur_link PrimaryGroupID "$shared_gid"
  /usr/bin/dscl . -create /Groups/_syntaur_link RealName 'Syntaur Link IPC'
  /usr/bin/dscl . -create /Groups/_syntaur_link Password '*'
  /usr/bin/dscl . -create /Users/_syntaur_tor GeneratedUID "$new_user_uuid"
  /usr/bin/dscl . -create /Users/_syntaur_tor UniqueID "$sidecar_uid"
  /usr/bin/dscl . -create /Users/_syntaur_tor PrimaryGroupID "$shared_gid"
  /usr/bin/dscl . -create /Users/_syntaur_tor UserShell /usr/bin/false
  /usr/bin/dscl . -create /Users/_syntaur_tor NFSHomeDirectory /var/empty
  /usr/bin/dscl . -create /Users/_syntaur_tor RealName 'Syntaur Link Tor'
  /usr/bin/dscl . -create /Users/_syntaur_tor IsHidden 1
  /usr/bin/dscl . -create /Users/_syntaur_tor Password '*'
fi
sidecar_uid=$(/usr/bin/id -u _syntaur_tor)
[ "$(/usr/bin/dscl . -read /Users/_syntaur_tor RecordName)" = 'RecordName: _syntaur_tor' ] || exit 1
[ "$(/usr/bin/dscl . -read /Groups/_syntaur_link RecordName)" = 'RecordName: _syntaur_link' ] || exit 1
shared_gid=$(/usr/bin/dscl . -read /Groups/_syntaur_link PrimaryGroupID)
shared_gid=${shared_gid#PrimaryGroupID: }
case "$sidecar_uid" in ''|0|0*|*[!0-9]*) exit 1 ;; esac
case "$shared_gid" in ''|0|0*|*[!0-9]*) exit 1 ;; esac
[ "$sidecar_uid" != "$gateway_uid" ] || exit 1
[ "$(/usr/bin/id -g _syntaur_tor)" = "$shared_gid" ] || exit 1
[ "$(/usr/bin/dscl . -read /Users/_syntaur_tor UserShell)" = 'UserShell: /usr/bin/false' ] || exit 1
[ "$(/usr/bin/dscl . -read /Users/_syntaur_tor NFSHomeDirectory)" = 'NFSHomeDirectory: /var/empty' ] || exit 1
[ "$(/usr/bin/dscl . -read /Users/_syntaur_tor Password)" = 'Password: *' ] || exit 1
hidden_record=$(/usr/bin/dscl . -read /Users/_syntaur_tor IsHidden) || exit 1
[ "$hidden_record" = 'dsAttrTypeNative:IsHidden: 1' ] || exit 1
# Reverse mappings include every active DirectoryService search source. Primary
# GID membership is implicit and must not admit another local/network account.
users=$(/usr/bin/dscl /Search -list /Users UniqueID) || exit 1
groups=$(/usr/bin/dscl /Search -list /Groups PrimaryGroupID) || exit 1
[ "$(printf '%s\n' "$users" | /usr/bin/awk -v id="$sidecar_uid" '$2 == id {print $1}')" = _syntaur_tor ] || exit 1
[ "$(printf '%s\n' "$groups" | /usr/bin/awk -v id="$shared_gid" '$2 == id {print $1}')" = _syntaur_link ] || exit 1
primary_users=$(/usr/bin/dscl /Search -list /Users PrimaryGroupID) || exit 1
printf '%s\n' "$primary_users" | /usr/bin/awk -v id="$shared_gid" -v owner="$owner" \
  '$2 == id && $1 != "_syntaur_tor" && $1 != owner {bad=1} END {exit bad}' || exit 1
# Existing configuration binds the selected owner before group membership or
# private state can be changed. Keep any existing bridge choice byte-for-byte.
config="$base/private/host.json"
if [ -e "$base/private" ] && [ ! -e "$config" ]; then exit 1; fi
if [ -e "$config" ] || [ -L "$config" ]; then
  entry "$base/private" d "$sidecar_uid" "$shared_gid" 700 || exit 1
  entry "$config" f "$sidecar_uid" "$shared_gid" 400 || exit 1
  [ "$(/usr/bin/plutil -extract gateway_uid raw -expect integer -o - "$config")" = "$gateway_uid" ] || exit 1
fi
# Read one complete valid local record. A failed directory read is not an
# absent optional attribute; subsequent missing-key checks use this frozen file.
group_record=$(/usr/bin/mktemp "$base/.group.XXXXXX")
/usr/bin/dscl -plist . -read /Groups/_syntaur_link >"$group_record"
[ "$(/usr/bin/stat -f '%z' "$group_record")" -le 65536 ] || exit 1
/usr/bin/plutil -lint "$group_record" >/dev/null
owner_uuid=$(/usr/bin/dscl . -read "/Users/$owner" GeneratedUID)
owner_uuid=${owner_uuid#GeneratedUID: }
for attribute in GroupMembership GroupMembers NestedGroups; do
  key="dsAttrTypeStandard:$attribute"
  if kind=$(/usr/bin/plutil -type "$key" "$group_record" 2>/dev/null); then
    [ "$kind" = array ] || exit 1
    count=$(/usr/bin/plutil -extract "$key" raw -expect array -o - "$group_record")
    case "$count" in 0) ;; 1)
      member=$(/usr/bin/plutil -extract "$key.0" raw -expect string -o - "$group_record")
      case "$attribute" in
        GroupMembership) [ "$member" = "$owner" ] || exit 1 ;;
        GroupMembers) [ "$member" = "$owner_uuid" ] || exit 1 ;;
        *) exit 1 ;;
      esac ;;
      *) exit 1 ;;
    esac
  fi
done
/usr/sbin/dseditgroup -o edit -a "$owner" -t user _syntaur_link
/usr/sbin/dseditgroup -o checkmember -m "$owner" _syntaur_link >/dev/null

for leaf in private private/state private/cache ipc; do
  uid=$sidecar_uid; mode=700
  if [ "$leaf" = ipc ]; then uid=$gateway_uid; mode=2770; fi
  path="$base/$leaf"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    /usr/bin/install -d -m "$mode" -o "$uid" -g "$shared_gid" "$path"
    if [ "$leaf" = private ]; then created_private=1; fi
  fi
  entry "$path" d "$uid" "$shared_gid" "$mode" || exit 1
done
config="$base/private/host.json"
if [ -e "$config" ] || [ -L "$config" ]; then
  entry "$config" f "$sidecar_uid" "$shared_gid" 400 || exit 1
  [ "$(/usr/bin/plutil -extract schema raw -expect integer -o - "$config")" = 4 ] || exit 1
  [ "$(/usr/bin/plutil -extract gateway_uid raw -expect integer -o - "$config")" = "$gateway_uid" ] || exit 1
  [ "$(/usr/bin/plutil -extract shared_gid raw -expect integer -o - "$config")" = "$shared_gid" ] || exit 1
  [ "$(/usr/bin/plutil -extract virtual_port raw -expect integer -o - "$config")" = 443 ] || exit 1
  [ "$(/usr/bin/plutil -extract service_nickname raw -expect string -o - "$config")" = syntaur ] || exit 1
  for pair in state_dir:private/state cache_dir:private/cache status_path:private/status.json control_socket:ipc/gateway.sock gateway_pin_path:ipc/gateway-pin.json; do
    key=${pair%%:*}; relative=${pair#*:}
    [ "$(/usr/bin/plutil -extract "$key" raw -expect string -o - "$config")" = "$base/$relative" ] || exit 1
  done
else
  config_temp=$(/usr/bin/mktemp "$base/.host.json.XXXXXX")
  /bin/cat >"$config_temp" <<CONFIG
{"schema":4,"state_dir":"$base/private/state","cache_dir":"$base/private/cache","status_path":"$base/private/status.json","control_socket":"$base/ipc/gateway.sock","gateway_pin_path":"$base/ipc/gateway-pin.json","service_nickname":"syntaur","virtual_port":443,"gateway_uid":$gateway_uid,"shared_gid":$shared_gid,"bridge_bundle":null}
CONFIG
  /usr/sbin/chown "$sidecar_uid:$shared_gid" "$config_temp"
  /bin/chmod 400 "$config_temp"
  /bin/ln "$config_temp" "$config"
  private_published=1
  /bin/rm "$config_temp"; config_temp=''
fi
private_published=1
if [ -e "$host" ] || [ -L "$host" ]; then
  entry "$host" f 0 0 755 || exit 1
  [ "$(/usr/bin/shasum -a 256 "$host" | /usr/bin/awk '{print $1}')" = "$digest" ] || exit 1
else
  temp=$(/usr/bin/mktemp "$code/.host.XXXXXX")
  # Copy bytes only into a root-private file. A mutable staging alias must
  # neither import ACLs nor expose unexpected root-readable bytes to users.
  /bin/dd if="$stage" of="$temp" bs=1048576 count=1025 2>/dev/null
  entry "$temp" f 0 0 600 || exit 1
  [ "$(/usr/bin/shasum -a 256 "$temp" | /usr/bin/awk '{print $1}')" = "$digest" ] || exit 1
  /bin/chmod 755 "$temp"
  /bin/ln "$temp" "$host"
  /bin/rm "$temp"; temp=''
fi
job_temp=$(/usr/bin/mktemp /Library/LaunchDaemons/.dev.syntaur.link-tor.XXXXXX)
printf '%s\n' "$plist_body" >"$job_temp"
/usr/bin/plutil -lint "$job_temp" >/dev/null
/bin/chmod 644 "$job_temp"
entry "$job_temp" f 0 0 644 || exit 1
backup="$base/launchdaemon.previous.plist"
if [ -e "$backup" ] || [ -L "$backup" ]; then entry "$backup" f 0 0 600 || exit 1; fi
if [ -e "$job" ]; then
  had_job=1
  /bin/cp "$job" "$backup"
  /bin/chmod 600 "$backup"
  entry "$backup" f 0 0 600 || exit 1
fi
if loaded=$(/bin/launchctl print system/dev.syntaur.link-tor 2>/dev/null); then
  [ -f "$job" ] || exit 1
  loaded_host_matches "$loaded" "$previous_program" || exit 1
  was_running=1
  publish_started=1
  /bin/launchctl bootout system "$job"
else
  status=$?; [ "$status" = 113 ] || exit 1
fi
publish_started=1
/bin/mv -f "$job_temp" "$job"; job_temp=''
/bin/launchctl bootstrap system "$job"
publish_committed=1
MACOS_HOST_ROOT
  MACOS_TOR_UID=$(/usr/bin/id -u _syntaur_tor) || return 1
  MACOS_TOR_GID=$(/usr/bin/dscl . -read /Groups/_syntaur_link PrimaryGroupID) || return 1
  MACOS_TOR_GID=${MACOS_TOR_GID#PrimaryGroupID: }
  MACOS_TOR_SOCKET='/Library/Application Support/Syntaur/LinkTor/ipc/gateway.sock'
  MACOS_TOR_GATEWAY_PIN='/Library/Application Support/Syntaur/LinkTor/ipc/gateway-pin.json'
  export MACOS_TOR_UID MACOS_TOR_GID MACOS_TOR_SOCKET MACOS_TOR_GATEWAY_PIN
}

# Speech destinations remain data for the Gateway's existing private-address
# validator. Keep the selected user's exact, bounded values across updates.
macos_speech_host_valid() (
  LC_ALL=C
  export LC_ALL
  [ -n "$1" ] && [ "${#1}" -le 1024 ] || return 1
  case "$1" in *[[:space:][:cntrl:]]*) return 1 ;; esac
)

macos_previous_speech_host() (
  previous_plist="$1"
  previous_key="$2"
  /usr/bin/plutil -lint -s "$previous_plist" >/dev/null 2>&1 || return 1
  previous_env_type=$(/usr/bin/plutil -type EnvironmentVariables "$previous_plist" 2>/dev/null) || return 1
  [ "$previous_env_type" = dictionary ] || return 1
  previous_environment=$(/usr/bin/plutil -extract EnvironmentVariables xml1 -o - "$previous_plist" 2>/dev/null) || return 1
  case "$previous_environment" in *"<key>$previous_key</key>"*) ;; *) return 0 ;; esac
  previous_type=$(/usr/bin/plutil -type "EnvironmentVariables.$previous_key" "$previous_plist" 2>/dev/null) || return 1
  [ "$previous_type" = string ] || return 1
  # The sentinel preserves trailing newlines so validation cannot strip them.
  previous_value=$(/usr/bin/plutil -extract "EnvironmentVariables.$previous_key" raw -expect string -n -o - "$previous_plist" 2>/dev/null && printf '.') || return 1
  previous_value=${previous_value%.}
  macos_speech_host_valid "$previous_value" || return 1
  printf '%s' "$previous_value"
)

write_macos_launchagent() (
  macos_absolute_path "$HOME" || return 1
  HOME_XML=$(macos_xml_escape "$HOME") || return 1
  if [ "${SYNTAUR_STT_HOST+x}" = x ]; then macos_speech_host_valid "$SYNTAUR_STT_HOST" || return 1; fi
  if [ "${SYNTAUR_TTS_HOST+x}" = x ]; then macos_speech_host_valid "$SYNTAUR_TTS_HOST" || return 1; fi
  has_uid=0; has_gid=0; has_sock=0; has_pin=0
  [ -n "${MACOS_TOR_UID+x}" ] && has_uid=1
  [ -n "${MACOS_TOR_GID+x}" ] && has_gid=1
  [ -n "${MACOS_TOR_SOCKET+x}" ] && has_sock=1
  [ -n "${MACOS_TOR_GATEWAY_PIN+x}" ] && has_pin=1

  tuple_count=$((has_uid + has_gid + has_sock + has_pin))
  if [ "$tuple_count" -ne 0 ] && [ "$tuple_count" -ne 4 ]; then
    return 1
  fi

  if [ "$tuple_count" -eq 4 ]; then
    macos_u32_id "$MACOS_TOR_UID" || return 1
    macos_u32_id "$MACOS_TOR_GID" || return 1

    cur_uid=$(id -u) || return 1
    if [ "$MACOS_TOR_UID" -eq 0 ] || [ "$MACOS_TOR_UID" -eq "$cur_uid" ]; then
      return 1
    fi
    if [ "$MACOS_TOR_GID" -eq 0 ]; then
      return 1
    fi

    macos_absolute_path "$MACOS_TOR_SOCKET" || return 1
    macos_absolute_path "$MACOS_TOR_GATEWAY_PIN" || return 1

    TOR_UID_XML=$(macos_xml_escape "$MACOS_TOR_UID") || return 1
    TOR_GID_XML=$(macos_xml_escape "$MACOS_TOR_GID") || return 1
    TOR_SOCKET_XML=$(macos_xml_escape "$MACOS_TOR_SOCKET") || return 1
    TOR_PIN_XML=$(macos_xml_escape "$MACOS_TOR_GATEWAY_PIN") || return 1
  fi

  safe_eula_entry "$HOME" directory || return 1
  PLIST_DIR="$HOME/Library/LaunchAgents"
  for DIRECTORY in "$HOME/Library" "$PLIST_DIR"; do
    if [ ! -e "$DIRECTORY" ] && [ ! -L "$DIRECTORY" ]; then
      mkdir -m 700 "$DIRECTORY" || return 1
    fi
    safe_eula_entry "$DIRECTORY" directory || return 1
  done
  PLIST_DEST="$PLIST_DIR/dev.syntaur.gateway.plist"
  previous_stt=''
  previous_tts=''
  if [ -e "$PLIST_DEST" ] || [ -L "$PLIST_DEST" ]; then
    safe_eula_entry "$PLIST_DEST" file || return 1
    previous_stt=$(macos_previous_speech_host "$PLIST_DEST" SYNTAUR_STT_HOST) || return 1
    previous_tts=$(macos_previous_speech_host "$PLIST_DEST" SYNTAUR_TTS_HOST) || return 1
  fi
  speech_stt=${SYNTAUR_STT_HOST-$previous_stt}
  speech_tts=${SYNTAUR_TTS_HOST-$previous_tts}
  GATEWAY_XML_PATH=$(macos_xml_escape "$INSTALL_DIR/$BINARY") || return 1
  TEMP_PLIST=$(mktemp "$PLIST_DIR/.dev.syntaur.gateway.XXXXXX") || return 1
  trap 'rm -f "$TEMP_PLIST"' EXIT HUP INT TERM
  chmod 600 "$TEMP_PLIST"

  {
    cat <<HEADER
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.syntaur.gateway</string>
  <key>ProgramArguments</key><array><string>$GATEWAY_XML_PATH</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key><dict>
    <key>SYNTAUR_LAUNCHER_OWNS_UI</key><string>1</string>
    <key>HOME</key><string>$HOME_XML</string>
HEADER
    if [ -n "$speech_stt" ]; then
      SPEECH_STT_XML=$(macos_xml_escape "$speech_stt") || exit 1
      printf '    <key>SYNTAUR_STT_HOST</key><string>%s</string>\n' "$SPEECH_STT_XML"
    fi
    if [ -n "$speech_tts" ]; then
      SPEECH_TTS_XML=$(macos_xml_escape "$speech_tts") || exit 1
      printf '    <key>SYNTAUR_TTS_HOST</key><string>%s</string>\n' "$SPEECH_TTS_XML"
    fi
    if [ "$tuple_count" -eq 4 ]; then
      cat <<VARS
    <key>SYNTAUR_LINK_TOR_GATEWAY_PIN</key><string>$TOR_PIN_XML</string>
    <key>SYNTAUR_LINK_TOR_GID</key><string>$TOR_GID_XML</string>
    <key>SYNTAUR_LINK_TOR_SOCKET</key><string>$TOR_SOCKET_XML</string>
    <key>SYNTAUR_LINK_TOR_UID</key><string>$TOR_UID_XML</string>
VARS
    fi
    cat <<FOOTER
    <key>SYNTAUR_OWNER_UIDGID</key><string>$(id -u):$(id -g)</string>
  </dict>
</dict></plist>
FOOTER
  } > "$TEMP_PLIST"

  if [ -e "$PLIST_DEST" ] || [ -L "$PLIST_DEST" ]; then
    safe_eula_entry "$PLIST_DEST" file || return 1
  fi
  mv -f "$TEMP_PLIST" "$PLIST_DEST" || return 1
  safe_eula_entry "$PLIST_DEST" file || return 1
  trap - EXIT HUP INT TERM
)


# Change the installed job only after the old definition and its socket peer
# have been authenticated and retired by the existing native maintenance path.
# Keep one exact prior plist until the replacement is verified. This restores
# configuration only; downloaded code and the separate HOST have their own scope.
update_macos_launchagent() (
  macos_absolute_path "$HOME" || return 1
  agent_dir="$HOME/Library/LaunchAgents"
  agent="$agent_dir/dev.syntaur.gateway.plist"
  safe_eula_entry "$HOME" directory || return 1
  for directory in "$HOME/Library" "$agent_dir"; do
    if [ ! -e "$directory" ] && [ ! -L "$directory" ]; then
      (umask 077; mkdir "$directory") || return 1
    fi
    safe_eula_entry "$directory" directory || return 1
  done
  safe_eula_entry "$agent_dir" directory || return 1
  safe_eula_entry "$INSTALL_DIR" directory || return 1
  viewer="$INSTALL_DIR/syntaur-viewer"
  safe_eula_entry "$viewer" file && [ -x "$viewer" ] || return 1
  lock="$agent_dir/.dev.syntaur.gateway.update-lock"
  (umask 077; mkdir "$lock") || return 1
  prior_exists=0
  if [ -e "$agent" ] || [ -L "$agent" ]; then
    safe_eula_entry "$agent" file || { rmdir "$lock"; return 1; }
    prior_exists=1
  fi
  backup=''; stopped=0; stop_attempted=0; committed=0
  prior_digest=''; expected_digest=''
  if [ "$prior_exists" = 1 ]; then
    prior_digest=$(sha256_file "$agent") || { rmdir "$lock"; return 1; }
    expected_digest=$prior_digest
  fi
  cleanup_agent_update() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$committed" = 0 ] && [ "$stopped" = 1 ]; then
      # A failed start may still have loaded a job. Never restore an old plist
      # underneath it, or overwrite a configuration changed by another actor.
      restored=0
      if safe_eula_entry "$agent" file \
         && [ "$(sha256_file "$agent")" = "$expected_digest" ]; then
        stop_result=0
        "$viewer" --server-stop || stop_result=$?
        if [ "$stop_result" = 0 ] || [ "$stop_result" = 3 ]; then
          if safe_eula_entry "$agent" file \
             && [ "$(sha256_file "$agent")" = "$expected_digest" ] \
             && safe_eula_entry "$backup" file \
             && [ "$(sha256_file "$backup")" = "$prior_digest" ] \
             && mv -f "$backup" "$agent"; then
            backup=''
            if "$viewer" --server-start; then restored=1; fi
          fi
        fi
      fi
      [ "$restored" = 1 ] || echo "  Error: the previous Mac server configuration was not restored; installation is incomplete." >&2
    fi
    if [ -n "$backup" ]; then
      if [ "$committed" = 1 ] || [ "$stop_attempted" = 0 ]; then
        rm -f "$backup" || result=1
      else
        echo "  Previous Mac server configuration retained at: $backup" >&2
      fi
    fi
    rmdir "$lock" || result=1
    exit "$result"
  }
  trap cleanup_agent_update EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [ "$prior_exists" = 1 ]; then
    backup=$(mktemp "$agent_dir/.dev.syntaur.gateway.previous.XXXXXX") || exit 1
    chmod 600 "$backup" && cat "$agent" >"$backup" || exit 1
    safe_eula_entry "$backup" file || exit 1
    [ "$(sha256_file "$backup")" = "$prior_digest" ] || exit 1
  fi
  stop_attempted=1
  stop_result=0
  "$viewer" --server-stop || stop_result=$?
  case "$stop_result" in
    0) [ "$prior_exists" = 1 ] || exit 1; stopped=1 ;;
    3) ;; # No loaded job: preserve that state after rendering the new plist.
    *) echo "  Error: the Mac server could not be stopped safely; installation is incomplete." >&2; exit 1 ;;
  esac
  if [ "$prior_exists" = 1 ]; then
    safe_eula_entry "$agent" file || exit 1
    [ "$(sha256_file "$agent")" = "$expected_digest" ] || exit 1
  else
    [ ! -e "$agent" ] && [ ! -L "$agent" ] || exit 1
  fi
  write_macos_launchagent || exit 1
  expected_digest=$(sha256_file "$agent") || exit 1
  if [ "$stopped" = 1 ]; then "$viewer" --server-start || exit 1; fi
  safe_eula_entry "$agent" file || exit 1
  [ "$(sha256_file "$agent")" = "$expected_digest" ] || exit 1
  committed=1
)

if [ "${SYNTAUR_INSTALL_TEST_LIBRARY_ONLY:-0}" = "1" ]; then
  # shellcheck disable=SC2317 # direct execution uses exit; tests source and return.
  return 0 2>/dev/null || exit 0
fi

# Resolve platform authority before any user-state mutation. Managed Linux
# installs must run as the target account and elevate only the narrow helper.
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
  linux)  PLATFORM="linux" ;;
  darwin) PLATFORM="macos" ;;
  *)      echo "Error: Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64)
    if [ "$PLATFORM" = "macos" ]; then
      ARCH="arm64"
    else
      ARCH="aarch64"
    fi
    ;;
  *) echo "Error: Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Public macOS releases support Apple Silicon only.
if [ "$PLATFORM" = "macos" ] && [ "$ARCH" = "x86_64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
    ARCH="arm64"
  else
    echo "Error: Syntaur for macOS requires Apple Silicon (M1 or newer). Intel Macs are unsupported."
    exit 1
  fi
fi

MANAGED_RUNTIME="0"
if [ "$PLATFORM" = "linux" ] && [ "$ARCH" = "x86_64" ]; then
  MANAGED_RUNTIME="1"
fi
if [ "$MANAGED_RUNTIME" = "1" ] && [ "$(id -u)" = 0 ]; then
  echo "  Error: run this installer as your ordinary account, not root."
  echo "  It requests sudo only for the narrow system helper and required packages."
  exit 1
fi

echo ""
echo "  ♞ $BRAND v$VERSION"
echo "  Your personal AI platform"
echo ""

# A valid exact-version record is durable affirmative acceptance. Changed,
# malformed, or unsafe records fall through to a fresh explicit acceptance.
ensure_eula_acceptance || exit 1

# If no mode specified, ask
if [ -z "$MODE" ]; then
  echo "  How would you like to use Syntaur?"
  echo ""
  echo "  1) Run the server on this computer"
  echo "     Your AI runs here. Access from phone, laptop, any device."
  echo "     (This computer needs to stay on.)"
  echo ""
  echo "  2) Connect to my Syntaur server"
  echo "     Syntaur is already running elsewhere. Just install the client."
  echo ""
  printf "  Choose [1/2]: "
  read -r CHOICE
  case "$CHOICE" in
    2) MODE="connect" ;;
    *) MODE="server" ;;
  esac
  echo ""
fi

echo "  Platform: $PLATFORM-$ARCH"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"
DASHBOARD_URL="http://127.0.0.1:18789"

APP_LAUNCHER="$INSTALL_DIR/syntaur-open"
if [ "$MANAGED_RUNTIME" = "1" ]; then
  if ! ensure_process_inspector_cap_tools; then
    echo "  Error: the managed runtime requires Linux capability tools."
    exit 1
  fi
  echo "  Installing the signed managed runtime..."
  RUNTIME_STAGE=$(mktemp -d "/tmp/syntaur-install-${VERSION}.XXXXXX")
  chmod 700 "$RUNTIME_STAGE"
  cleanup_runtime_stage() {
    rm -rf "$RUNTIME_STAGE"
  }
  trap cleanup_runtime_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  CATALOG_NAME="syntaur-runtime-catalog-v1.json"
  CATALOG_SIGNATURE_NAME="syntaur-runtime-catalog-v1.json.sig"
  RELEASE_BASE="${REPO_URL}/releases/download/v${VERSION}"
  download_bounded "$RELEASE_BASE/$CATALOG_NAME" "$RUNTIME_STAGE/$CATALOG_NAME" 262144 || {
    echo "  Error: the signed runtime catalog is unavailable"
    exit 1
  }
  download_bounded "$RELEASE_BASE/$CATALOG_SIGNATURE_NAME" "$RUNTIME_STAGE/$CATALOG_SIGNATURE_NAME" 129 || {
    echo "  Error: the runtime catalog signature is unavailable"
    exit 1
  }

  if ! download_product_release_target "$RELEASE_BASE" "$RUNTIME_STAGE" "$MODE"; then
    echo "  Error: the signed product update target is unavailable"
    exit 1
  fi

  # The bootstrap hash is release-stamped into this signed installer and is
  # always enforced, even when --skip-verify was requested for direct assets.
  # It then enforces the independent Ed25519 catalog signature with its key.
  RUNTIME_ASSET="syntaur-runtime-linux-x86_64"
  if ! download_managed_bootstrap "$RELEASE_BASE" "$RUNTIME_ASSET" "$RUNTIME_STAGE/$RUNTIME_ASSET"; then
    echo "  Error: could not install a verified runtime bootstrap"
    exit 1
  fi
  PROCESS_INSPECTOR_ASSET="syntaur-process-inspector-linux-x86_64"
  if ! download_pinned_release_asset \
      "$RELEASE_BASE" \
      "$PROCESS_INSPECTOR_ASSET" \
      "$RUNTIME_STAGE/$PROCESS_INSPECTOR_ASSET" \
      "$PROCESS_INSPECTOR_SHA256" \
      "process inspector"; then
    echo "  Error: could not authenticate the narrow process inspector"
    exit 1
  fi

  # The release asset name is transport-facing. The CLI accepts only a
  # canonical supervisor invocation name, and then verifies its own mapped
  # executable against the signed catalog before emitting any requirements.
  RUNTIME_BOOTSTRAP="$RUNTIME_STAGE/syntaur-runtime-$VERSION"
  cp "$RUNTIME_STAGE/$RUNTIME_ASSET" "$RUNTIME_BOOTSTRAP"
  chmod 700 "$RUNTIME_BOOTSTRAP"
  REQUIREMENTS="$RUNTIME_STAGE/stage-requirements.tsv"
  if ! "$RUNTIME_BOOTSTRAP" stage-requirements "$RUNTIME_STAGE" "$MODE" > "$REQUIREMENTS"; then
    echo "  Error: the runtime rejected the signed release catalog"
    exit 1
  fi
  if ! /usr/bin/awk -F '\t' '
      NF != 7 || $1 != "syntaur-stage-v1" { exit 1 }
      END { if (NR == 0) exit 1 }
    ' "$REQUIREMENTS"; then
    echo "  Error: invalid runtime stage-requirements protocol"
    exit 1
  fi

  TAB=$(printf '\t')
  SEEN_STAGE_NAMES="|"
  while IFS="$TAB" read -r PROTOCOL REQ_TAG REQ_ASSET REQ_STAGED REQ_SHA256 REQ_SIZE REQ_MAX_SIZE; do
    if [ "$PROTOCOL" != "syntaur-stage-v1" ] \
       || ! validate_stage_requirement "$REQ_TAG" "$REQ_ASSET" "$REQ_STAGED" "$REQ_SHA256" "$REQ_SIZE" "$REQ_MAX_SIZE"; then
      echo "  Error: unsafe runtime stage requirement"
      exit 1
    fi
    case "$SEEN_STAGE_NAMES" in
      *"|$REQ_STAGED|"*) echo "  Error: duplicate runtime stage name"; exit 1 ;;
    esac
    SEEN_STAGE_NAMES="${SEEN_STAGE_NAMES}${REQ_STAGED}|"
    echo "  → Downloading $REQ_ASSET from $REQ_TAG"
    download_bounded_exact \
      "${REPO_URL}/releases/download/${REQ_TAG}/${REQ_ASSET}" \
      "$RUNTIME_STAGE/$REQ_STAGED" \
      "$REQ_SIZE" \
      "$REQ_MAX_SIZE" \
      "$REQ_SHA256" || {
        echo "  Error: a release payload did not match the signed catalog"
        exit 1
      }
  done < "$REQUIREMENTS"

  if ! provision_process_inspector \
      "$RUNTIME_STAGE/$PROCESS_INSPECTOR_ASSET" \
      "$PROCESS_INSPECTOR_SHA256" \
      "$VERSION" \
      "/usr/local/libexec/syntaur/process-inspectors" \
      "$RUNTIME_STAGE"; then
    echo "  Error: could not provision the narrow process inspector"
    exit 1
  fi
  rm -f "$RUNTIME_STAGE/$PROCESS_INSPECTOR_ASSET"

  RUNTIME_INSTALL_OK=0
  if [ "$MODE" = "server" ]; then
    if "$RUNTIME_BOOTSTRAP" install-release "$RUNTIME_STAGE" "$MODE" "$DASHBOARD_URL"; then
      RUNTIME_INSTALL_OK=1
    fi
  else
    if "$RUNTIME_BOOTSTRAP" install-release "$RUNTIME_STAGE" "$MODE"; then
      RUNTIME_INSTALL_OK=1
    fi
  fi
  if [ "$RUNTIME_INSTALL_OK" -ne 1 ]; then
    # The helper is signed, immutable, and version-addressed. Retaining it is
    # race-safe; a later retry can authenticate and reuse the exact file.
    echo "  Error: managed runtime installation failed."
    exit 1
  fi
  if [ ! -x "$APP_LAUNCHER" ]; then
    echo "  Error: managed runtime installation did not publish syntaur-open"
    exit 1
  fi
else
  # Direct installation remains available for macOS and Linux architectures
  # that do not yet have a catalog-backed managed-runtime target.
  if [ "$MODE" = "server" ]; then
    DOWNLOAD_URL="${REPO_URL}/releases/download/v${VERSION}/syntaur-gateway-${PLATFORM}-${ARCH}"
    echo "  Installing $BRAND server..."

    download_verified "$DOWNLOAD_URL" "$INSTALL_DIR/$BINARY" || {
      echo ""
      echo "  ✗ Could not install a verified server binary."
      echo "    If the release doesn't carry signed checksums yet, re-run with"
      echo "    --skip-verify to proceed at your own risk."
      exit 1
    }
  fi

  ENGINE_BINARY="syntaur-engine"
  ENGINE_URL="${REPO_URL}/releases/download/v${VERSION}/syntaur-engine-${PLATFORM}-${ARCH}"
  download_optional_verified "native browser engine" "$ENGINE_URL" "$INSTALL_DIR/$ENGINE_BINARY" || true

  CLIP_BINARY="syntaur-clip-write"
  CLIP_URL="${REPO_URL}/releases/download/v${VERSION}/syntaur-clip-write-${PLATFORM}-${ARCH}"
  download_optional_verified "clipboard helper" "$CLIP_URL" "$INSTALL_DIR/$CLIP_BINARY" || true

  VIEWER_BINARY="syntaur-viewer"
  VIEWER_URL="${REPO_URL}/releases/download/v${VERSION}/syntaur-viewer-${PLATFORM}-${ARCH}"
  download_verified "$VIEWER_URL" "$INSTALL_DIR/$VIEWER_BINARY" || exit 1

  for LINK_BINARY in syntaur-link-client-tor syntaur-link-probe syntaur-snowflake-client; do
    download_verified "${REPO_URL}/releases/download/v${VERSION}/${LINK_BINARY}-${PLATFORM}-${ARCH}" \
      "$INSTALL_DIR/$LINK_BINARY" || exit 1
  done

  write_app_launcher || exit 1
fi

if [ "$PLATFORM" = macos ] && [ "$MODE" = server ]; then
  echo "  Installing the isolated Syntaur Link server service (administrator consent required)..."
  MACOS_HOST_TEMP=$(mktemp -d)
  trap 'rm -rf "$MACOS_HOST_TEMP"' EXIT HUP INT TERM
  # An administrator-owned executable always requires authenticated release
  # bytes. Developer --skip-verify cannot cross this privilege boundary.
  if ! ( VERIFY=1; download_verified \
      "${REPO_URL}/releases/download/v${VERSION}/syntaur-link-tor-macos-arm64" \
      "$MACOS_HOST_TEMP/syntaur-link-tor" ); then
    echo "  Error: no authenticated Mac Link server service is available."
    exit 1
  fi
  MACOS_HOST_DIGEST=$(sha256_file "$MACOS_HOST_TEMP/syntaur-link-tor") || exit 1
  provision_macos_tor_host "$MACOS_HOST_TEMP/syntaur-link-tor" "$MACOS_HOST_DIGEST" || {
    echo "  Error: the isolated Mac Link server service could not be installed safely."
    exit 1
  }
  rm -rf "$MACOS_HOST_TEMP"
  trap - EXIT HUP INT TERM
fi

configure_link_transport || {
  echo "  Error: could not safely configure Syntaur Link"
  exit 1
}

ICON_PNG="$INSTALL_DIR/syntaur-icon.png"
ICON_ICNS="$INSTALL_DIR/syntaur-icon.icns"
download_optional_verified "launcher icon" "${REPO_URL}/releases/download/v${VERSION}/syntaur-icon.png" "$ICON_PNG" || true
if [ "$PLATFORM" = "macos" ]; then
  download_optional_verified "macOS launcher icon" "${REPO_URL}/releases/download/v${VERSION}/syntaur-icon.icns" "$ICON_ICNS" || true
fi

# Ensure the WebKitGTK viewer can actually decode audio. On many distros
# the base `webkit2gtk` / `webkitgtk-6.0` package does NOT pull in
# `gst-plugins-good`, which is where autoaudiosink / pulsesink live.
# Without them, the first <audio>.play() call segfaults the WebKit
# render process (confirmed on CachyOS 2026-04-19). Detect the package
# manager and install the known-required GStreamer plugins.
#
# We treat three packages as the baseline:
#   gst-plugins-good  — audiosinks + mp3/wav/flac parsers
#   gst-plugins-bad   — extra decoders (aac, more)
#   gst-libav         — ffmpeg-backed decoders, covers everything else
#
# All three are in the standard repos of the distros Syntaur supports.
if [ "$PLATFORM" = "linux" ]; then
  echo "  Checking Linux media/input runtime packages…"
  NEED_PKGS=""
  MGR=""

  if command -v pacman >/dev/null 2>&1; then
    # Arch / CachyOS / Manjaro / EndeavourOS
    MGR="pacman"
    for pkg in gst-plugins-good gst-plugins-bad gst-libav bubblewrap libxkbcommon; do
      if ! pacman -Q "$pkg" >/dev/null 2>&1; then
        NEED_PKGS="$NEED_PKGS $pkg"
      fi
    done
  elif command -v apt-get >/dev/null 2>&1; then
    # Debian / Ubuntu / Linux Mint
    MGR="apt"
    for pkg in gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav bubblewrap libxkbcommon-x11-0; do
      if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        NEED_PKGS="$NEED_PKGS $pkg"
      fi
    done
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL / Rocky / Alma
    MGR="dnf"
    for pkg in gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-libav bubblewrap libxkbcommon-x11; do
      if ! rpm -q "$pkg" >/dev/null 2>&1; then
        NEED_PKGS="$NEED_PKGS $pkg"
      fi
    done
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE
    MGR="zypper"
    for pkg in gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-libav bubblewrap libxkbcommon-x11-0; do
      if ! rpm -q "$pkg" >/dev/null 2>&1; then
        NEED_PKGS="$NEED_PKGS $pkg"
      fi
    done
  fi

  if [ -n "$NEED_PKGS" ] && [ -n "$MGR" ]; then
    echo "  Missing runtime packages:$NEED_PKGS"
    if [ "$AUTOSUDO" = "0" ]; then
      echo "  --no-sudo was passed; skipping installation. Run this manually:"
      case "$MGR" in
        pacman) echo "    sudo pacman -S $NEED_PKGS" ;;
        apt)    echo "    sudo apt-get install $NEED_PKGS" ;;
        dnf)    echo "    sudo dnf install $NEED_PKGS" ;;
        zypper) echo "    sudo zypper install $NEED_PKGS" ;;
      esac
      INSTALL_FAILED=1
    else
      printf "  Install now with sudo? [Y/n] "
      read -r CONFIRM
      case "$CONFIRM" in
        n|N|no|No)
          echo "  Skipped. Install manually if music playback crashes the viewer or the native browser cannot start."
          INSTALL_FAILED=1
          ;;
        *)
          echo "  Installing so media playback and the native browser work out of the box…"
          # shellcheck disable=SC2086 # values are fixed package names collected above
          case "$MGR" in
            pacman) sudo pacman -S --needed --noconfirm $NEED_PKGS || INSTALL_FAILED=1 ;;
            apt)    sudo apt-get install -y $NEED_PKGS || INSTALL_FAILED=1 ;;
            dnf)    sudo dnf install -y $NEED_PKGS || INSTALL_FAILED=1 ;;
            zypper) sudo zypper install -y $NEED_PKGS || INSTALL_FAILED=1 ;;
          esac
          ;;
      esac
    fi
    if [ -n "$INSTALL_FAILED" ]; then
      echo ""
      echo "  Couldn't install runtime packages automatically."
      echo "  Music playback or native browser startup may fail until these are installed:"
      case "$MGR" in
        pacman) echo "    sudo pacman -S $NEED_PKGS" ;;
        apt)    echo "    sudo apt-get install $NEED_PKGS" ;;
        dnf)    echo "    sudo dnf install $NEED_PKGS" ;;
        zypper) echo "    sudo zypper install $NEED_PKGS" ;;
      esac
      echo ""
    else
      echo "  ✓ Linux runtime packages ready"
    fi
  elif [ -z "$MGR" ]; then
    echo "  (unfamiliar package manager — if media playback or native browser startup fails,"
    echo "   install gst-plugins-good / gst-plugins-bad / gst-libav / libxkbcommon-x11 via your distro)"
  else
    echo "  ✓ Linux runtime packages already installed"
  fi
fi

# Check if install dir is in PATH
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo "  Adding $INSTALL_DIR to PATH..."
    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
      bash) echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.bashrc" ;;
      zsh)  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.zshrc" ;;
      fish) echo "fish_add_path $HOME/.local/bin" >> "$HOME/.config/fish/config.fish" 2>/dev/null ;;
    esac
    export PATH="$INSTALL_DIR:$PATH"
    ;;
esac

# Install systemd service (server mode, Linux only)
if [ "$MODE" = "server" ] && [ "$PLATFORM" = "linux" ] && [ "$MANAGED_RUNTIME" != "1" ] && command -v systemctl >/dev/null 2>&1; then
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR"

  cat > "$UNIT_DIR/syntaur.service" << UNIT
[Unit]
Description=Syntaur AI Platform
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/$BINARY
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT

  systemctl --user daemon-reload
  systemctl --user enable syntaur.service
  echo "  Systemd service installed (syntaur.service)"
fi

# macOS launchd plist (server mode only)
if [ "$MODE" = "server" ] && [ "$PLATFORM" = "macos" ]; then
  update_macos_launchagent || { echo "  Error: unsafe Syntaur LaunchAgent update; installation is incomplete."; exit 1; }
  echo "  LaunchAgent installed (dev.syntaur.gateway)"
fi

if [ "$PLATFORM" = "linux" ]; then
  if [ -f "$ICON_PNG" ]; then
    for size in 48 64 128 256 512 1024; do
      ICON_DIR="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
      mkdir -p "$ICON_DIR"
      cp "$ICON_PNG" "$ICON_DIR/syntaur.png"
    done
    echo "  Branded launcher icon installed"
  else
    # Fallback icon for old releases that did not publish syntaur-icon.png.
    ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
    mkdir -p "$ICON_DIR"
    cat > "$ICON_DIR/syntaur.svg" << 'ICON'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0ea5e9"/>
      <stop offset="100%" stop-color="#0369a1"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="12" fill="#0a0a0a"/>
  <path d="M16 44 C16 38 20 34 26 34 L38 34 C44 34 48 38 48 44 L48 48 C48 52 44 52 42 48 L40 44 L38 48 C36 52 32 52 30 48 L28 44 L26 48 C24 52 20 52 18 48 L16 44Z" fill="url(#g)"/>
  <path d="M30 34 L30 20 C30 16 32 14 34 14 L34 14 C36 14 38 16 38 20 L38 34" fill="url(#g)"/>
  <circle cx="34" cy="11" r="5" fill="url(#g)"/>
  <path d="M36 20 L46 16 L48 14" stroke="url(#g)" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M16 38 C12 36 10 32 12 28" stroke="url(#g)" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>
ICON

    # Generate PNG icons for KDE/XFCE (SVG alone is not enough)
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import struct, zlib, os
def create_png(size, path):
    raw = b''
    for y in range(size):
        raw += b'\x00'
        for x in range(size):
            t = y / size
            r = int(14 + t * (3 - 14))
            g = int(165 + t * (105 - 165))
            b = int(233 + t * (161 - 233))
            cx, cy = abs(x - size//2), abs(y - size//2)
            corner = size//2 - size//8
            if cx > corner and cy > corner:
                if ((cx - corner)**2 + (cy - corner)**2)**0.5 > size//8:
                    raw += bytes([0, 0, 0, 0]); continue
            raw += bytes([r, g, b, 255])
    def chunk(ct, d):
        c = ct + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    hdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', hdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f: f.write(png)
for s in [48, 64, 128, 256]:
    d = os.path.expanduser('~/.local/share/icons/hicolor/%dx%d/apps' % (s, s))
    os.makedirs(d, exist_ok=True)
    create_png(s, d + '/syntaur.png')
" 2>/dev/null && echo "  PNG icons generated"
    fi
  fi

  # Install .desktop file in app launcher
  APP_DIR="$HOME/.local/share/applications"
  mkdir -p "$APP_DIR"
  cat > "$APP_DIR/syntaur.desktop" << DESKTOP
[Desktop Entry]
Name=Syntaur
Comment=Your personal AI platform
Exec=$APP_LAUNCHER
Icon=syntaur
Type=Application
Categories=Utility;Development;
StartupNotify=false
DESKTOP

  # Install .desktop file on desktop
  DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  if [ -d "$DESKTOP_DIR" ]; then
    cp "$APP_DIR/syntaur.desktop" "$DESKTOP_DIR/syntaur.desktop"
    chmod +x "$DESKTOP_DIR/syntaur.desktop"

    # GNOME trust
    gio set "$DESKTOP_DIR/syntaur.desktop" metadata::trusted true 2>/dev/null || true

    # KDE Plasma trust
    if command -v kwriteconfig5 >/dev/null 2>&1; then
      kwriteconfig5 --file "$DESKTOP_DIR/syntaur.desktop" --group "Desktop Entry" --key "X-KDE-RunOnDisconnect" "false" 2>/dev/null
    fi
  fi

  # Update icon caches
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  kbuildsycoca5 2>/dev/null || true

  echo "  Application shortcut installed (find 'Syntaur' in your app launcher and on your desktop)"
fi

if [ "$PLATFORM" = "macos" ]; then
  # Create a lightweight .app that launches the bundled Syntaur browser,
  # using the existing local-setup or enrolled Link launch path.
  APP_PATH="$HOME/Applications/Syntaur.app"
  mkdir -p "$APP_PATH/Contents/MacOS"
  mkdir -p "$APP_PATH/Contents/Resources"

  cat > "$APP_PATH/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Syntaur</string>
  <key>CFBundleDisplayName</key><string>Syntaur</string>
  <key>CFBundleIdentifier</key><string>dev.syntaur.app</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>syntaur-open</string>
  <key>CFBundleIconFile</key><string>icon.icns</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

  cat > "$APP_PATH/Contents/MacOS/syntaur-open" << 'LAUNCHER'
#!/bin/sh
exec "$HOME/.local/bin/syntaur-open"
LAUNCHER
  chmod +x "$APP_PATH/Contents/MacOS/syntaur-open"

  if [ -f "$ICON_ICNS" ]; then
    cp "$ICON_ICNS" "$APP_PATH/Contents/Resources/icon.icns"
    echo "  Branded application icon installed"
  elif [ -f "$ICON_PNG" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$APP_PATH/Contents/Resources/icon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null 2>&1 || true
    sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1 || true
    sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null 2>&1 || true
    sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1 || true
    sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null 2>&1 || true
    sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null 2>&1 || true
    sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null 2>&1 || true
    sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1 || true
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/icon.icns" >/dev/null 2>&1 || true
    rm -rf "$ICONSET"
  fi

  # Copy SVG as a resource (macOS Spotlight can index it; for a proper icon
  # you'd convert to .icns, but the .app still works without one)
  cat > "$APP_PATH/Contents/Resources/icon.svg" << 'ICON'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0ea5e9"/>
      <stop offset="100%" stop-color="#0369a1"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="12" fill="#0a0a0a"/>
  <path d="M16 44 C16 38 20 34 26 34 L38 34 C44 34 48 38 48 44 L48 48 C48 52 44 52 42 48 L40 44 L38 48 C36 52 32 52 30 48 L28 44 L26 48 C24 52 20 52 18 48 L16 44Z" fill="url(#g)"/>
  <path d="M30 34 L30 20 C30 16 32 14 34 14 L34 14 C36 14 38 16 38 20 L38 34" fill="url(#g)"/>
  <circle cx="34" cy="11" r="5" fill="url(#g)"/>
  <path d="M36 20 L46 16 L48 14" stroke="url(#g)" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M16 38 C12 36 10 32 12 28" stroke="url(#g)" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>
ICON

  echo "  Application shortcut installed (find 'Syntaur' in ~/Applications or Spotlight)"
  # Earlier installers created this browser shortcut for the retired URL.
  # Replace only that regular Syntaur shortcut after the native app exists.
  LEGACY_WEBLOC="$HOME/Desktop/Syntaur.webloc"
  if [ -f "$LEGACY_WEBLOC" ] && [ ! -L "$LEGACY_WEBLOC" ] \
     && /usr/bin/grep -q '<key>URL</key>' "$LEGACY_WEBLOC"; then
    rm -f -- "$LEGACY_WEBLOC"
    if [ ! -e "$HOME/Desktop/Syntaur.app" ] && [ ! -L "$HOME/Desktop/Syntaur.app" ]; then
      ln -s "$APP_PATH" "$HOME/Desktop/Syntaur.app"
    fi
  fi



fi

echo ""
if [ "$MODE" = "server" ]; then
  echo "  ✓ $BRAND server installed"
  echo ""
  echo "  To start:"
  if [ "$PLATFORM" = "linux" ]; then
    echo "    systemctl --user start syntaur"
  else
    echo "    $BINARY"
  fi
  echo ""
  echo "  Open Syntaur from your app launcher or go to:"
  echo "    $DASHBOARD_URL"
  echo ""
  echo "  Install Syntaur on your other devices and choose Connect."
else
  echo "  ✓ $BRAND client installed"
  echo ""
  echo "  Open Syntaur from your app launcher to connect to your server."
  echo "  Syntaur will guide you through pairing with your household."
fi
echo ""
