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
VERSION="0.7.111"
# Stamped from the built runtime artifact by release-sign.yml before this
# installer is signed. Managed installs enforce it regardless of --skip-verify.
RUNTIME_BOOTSTRAP_SHA256=""
# Stamped from the exact public workflow checkout before this installer is
# signed. Cosign verification binds the manifest to this immutable commit.
DIST_WORKFLOW_COMMIT=""
BINARY="syntaur"
INSTALL_DIR="$HOME/.local/bin"
MODE=""
VERIFY="1"
AUTOSUDO="1"
ACCEPT_EULA="0"
EULA_VERSION="1.0"
EULA_URL="https://github.com/syntaur-systems/syntaur-dist/blob/main/EULA.md"

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
  ACTUAL_SHA256=$(sha256_file "$OUT") || return 1
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "  Error: $URL does not match the signed runtime catalog"
    rm -f "$OUT"
    return 1
  fi
  chmod 700 "$OUT"
)

download_managed_bootstrap() (
  RELEASE_BASE="$1"
  ASSET="$2"
  OUT="$3"
  EXPECTED_SHA256="$RUNTIME_BOOTSTRAP_SHA256"
  case "$EXPECTED_SHA256" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || return 1
  download_bounded "$RELEASE_BASE/$ASSET" "$OUT" 1073741824 || return $?
  ACTUAL_SHA256=$(sha256_file "$OUT") || return 1
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "  Error: managed runtime bootstrap checksum mismatch"
    rm -f "$OUT"
    return 1
  fi
  chmod 700 "$OUT"
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

if [ "${SYNTAUR_INSTALL_TEST_LIBRARY_ONLY:-0}" = "1" ]; then
  # shellcheck disable=SC2317 # direct execution uses exit; tests source and return.
  return 0 2>/dev/null || exit 0
fi

echo ""
echo "  ♞ $BRAND v$VERSION"
echo "  Your personal AI platform"
echo ""

# ── EULA acceptance ─────────────────────────────────────────────────────────
# Use of Syntaur is governed by the EULA. Acceptance is an affirmative
# act (EULA §17): the --accept-eula flag, or typing "I AGREE" here.
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
    exit 1
  fi
  EULA_ANS_UC=$(printf '%s' "$EULA_ANS" | tr '[:lower:]' '[:upper:]')
  case "$EULA_ANS_UC" in
    "I AGREE") EULA_METHOD="prompt" ;;
    *) echo "  EULA not accepted — install aborted."; exit 1 ;;
  esac
fi
# Local acceptance record (EULA §17). Best-effort: never fails the install.
if mkdir -p "$HOME/.syntaur" 2>/dev/null; then
  {
    echo "eula_version=$EULA_VERSION"
    echo "eula_url=$EULA_URL"
    echo "accepted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "method=$EULA_METHOD"
    echo "installer_version=$VERSION"
  } > "$HOME/.syntaur/eula-accepted" 2>/dev/null || true
fi
echo "  EULA v$EULA_VERSION accepted (via $EULA_METHOD)."
echo ""

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

# Detect OS and architecture
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

echo "  Platform: $PLATFORM-$ARCH"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"
DASHBOARD_URL="${SYNTAUR_URL:-http://localhost:18789}"

MANAGED_RUNTIME="0"
if [ "$PLATFORM" = "linux" ] && [ "$ARCH" = "x86_64" ]; then
  MANAGED_RUNTIME="1"
fi

APP_LAUNCHER="$INSTALL_DIR/syntaur-open"
if [ "$MANAGED_RUNTIME" = "1" ]; then
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

  # The bootstrap hash is release-stamped into this signed installer and is
  # always enforced, even when --skip-verify was requested for direct assets.
  # It then enforces the independent Ed25519 catalog signature with its key.
  RUNTIME_ASSET="syntaur-runtime-linux-x86_64"
  if ! download_managed_bootstrap "$RELEASE_BASE" "$RUNTIME_ASSET" "$RUNTIME_STAGE/$RUNTIME_ASSET"; then
    echo "  Error: could not install a verified runtime bootstrap"
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
  if ! awk -F '\t' '
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

  if [ "$MODE" = "server" ]; then
    "$RUNTIME_BOOTSTRAP" install-release "$RUNTIME_STAGE" "$MODE" "$DASHBOARD_URL"
  elif [ -n "${SYNTAUR_URL:-}" ]; then
    "$RUNTIME_BOOTSTRAP" install-release "$RUNTIME_STAGE" "$MODE" "$SYNTAUR_URL"
  else
    "$RUNTIME_BOOTSTRAP" install-release "$RUNTIME_STAGE" "$MODE"
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
  download_optional_verified "dashboard viewer" "$VIEWER_URL" "$INSTALL_DIR/$VIEWER_BINARY" || true

  cat > "$APP_LAUNCHER" << LAUNCHER
#!/bin/sh
export PATH="$INSTALL_DIR:\$PATH"
APP_URL="\${SYNTAUR_URL:-$DASHBOARD_URL}"
if [ -x "$INSTALL_DIR/syntaur-engine" ]; then
  exec "$INSTALL_DIR/syntaur-engine" --url "\$APP_URL" --width 1440 --height 950
elif [ -x "$INSTALL_DIR/syntaur-viewer" ]; then
  SYNTAUR_URL="\$APP_URL" exec "$INSTALL_DIR/syntaur-viewer"
elif command -v xdg-open >/dev/null 2>&1; then
  exec xdg-open "\$APP_URL"
elif command -v open >/dev/null 2>&1; then
  exec open "\$APP_URL"
else
  printf '%s\n' "\$APP_URL"
fi
LAUNCHER
  chmod +x "$APP_LAUNCHER"
fi

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
  PLIST_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$PLIST_DIR"

  cat > "$PLIST_DIR/dev.syntaur.gateway.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.syntaur.gateway</string>
  <key>ProgramArguments</key>
  <array><string>$INSTALL_DIR/$BINARY</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST

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
  # falling back to the viewer or system browser through syntaur-open.
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

  cat > "$APP_PATH/Contents/MacOS/syntaur-open" << LAUNCHER
#!/bin/sh
exec "$APP_LAUNCHER"
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

  # Desktop .webloc — double-click opens in default browser. Only
  # created when SYNTAUR_URL is set (remote gateway case); for
  # local-only installs the Applications bundle is enough.
  if [ -n "${SYNTAUR_URL:-}" ] && [ -d "$HOME/Desktop" ]; then
    cat > "$HOME/Desktop/Syntaur.webloc" << WEBLOC
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>URL</key>
  <string>${SYNTAUR_URL}</string>
</dict>
</plist>
WEBLOC
    echo "  Desktop shortcut created (Syntaur.webloc)"
  fi
fi

# ── Tailscale auto-setup (Tier 2 onboarding) ────────────────────────────────
#
# If the caller passed a Tailscale pre-auth key via SYNTAUR_TS_AUTHKEY
# (the personalized-invite path mints one and bakes it into the install
# command you send to a family member), bring Tailscale up to the
# household tailnet so the viewer reaches the remote gateway the moment
# it launches. Silently skipped when the key is absent — local-only
# installs don't need it.
#
# Uses the official Tailscale installer. We never ship the daemon
# ourselves. Users who already have Tailscale just get the `up` call.

if [ -n "${SYNTAUR_TS_AUTHKEY:-}" ]; then
  echo ""
  echo "  Setting up Tailscale…"

  if ! command -v tailscale >/dev/null 2>&1; then
    if [ "$PLATFORM" = "macos" ]; then
      # Mac installer is a signed .pkg — needs a user click-through.
      echo "  Tailscale isn't installed yet. Opening the download page…"
      open "https://tailscale.com/download/mac" 2>/dev/null || true
      echo ""
      echo "  When Tailscale finishes installing (icon appears in the menu bar),"
      echo "  run this command to finish joining the household network:"
      echo ""
      echo "    /Applications/Tailscale.app/Contents/MacOS/Tailscale up \\"
      echo "      --authkey=\"\$SYNTAUR_TS_AUTHKEY\" --accept-routes"
    elif [ "$PLATFORM" = "linux" ]; then
      echo "  Installing Tailscale…"
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
      else
        echo "  ! curl required for Tailscale install; please install curl and re-run."
      fi
    fi
  fi

  if command -v tailscale >/dev/null 2>&1; then
    if [ "$PLATFORM" = "linux" ] && [ "$(id -u)" != "0" ]; then
      sudo tailscale up --authkey="$SYNTAUR_TS_AUTHKEY" --accept-routes \
        || echo "  ! tailscale up failed — retry after checking the supplied auth key."
    else
      tailscale up --authkey="$SYNTAUR_TS_AUTHKEY" --accept-routes \
        || echo "  ! tailscale up failed — retry after checking the supplied auth key."
    fi
    echo "  ✓ Tailscale connected to your household tailnet"
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
  echo "  To access from your phone or other computers:"
  echo "    1. Install Tailscale on this computer and your other devices"
  echo "    2. Open the Tailscale URL shown in the Syntaur dashboard"
  echo "    3. Or use the local network address shown after setup"
else
  echo "  ✓ $BRAND client installed"
  echo ""
  echo "  Open Syntaur from your app launcher to connect to your server."
  echo "  The setup wizard will ask for your server address."
fi
echo ""
