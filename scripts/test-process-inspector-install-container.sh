#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# Immutable Ubuntu 24.04 manifest. Rotate only after the full harness passes.
image=ubuntu@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54
container_inspector=

command -v docker >/dev/null

if [[ -n ${SYNTAUR_TEST_PROCESS_INSPECTOR:-} ]]; then
  if [[ ! -f $SYNTAUR_TEST_PROCESS_INSPECTOR ]] \
      || [[ -L $SYNTAUR_TEST_PROCESS_INSPECTOR ]]; then
    echo 'external process inspector must be a regular non-symlink file' >&2
    exit 1
  fi
  inspector=$(realpath -e -- "$SYNTAUR_TEST_PROCESS_INSPECTOR")
  case "$inspector" in
    "$repository"/*)
      container_inspector="/repo/${inspector#"$repository"/}"
      ;;
    *)
      echo 'external process inspector must be inside the read-only repository mount' >&2
      exit 1
      ;;
  esac
fi

# Docker's default bounded set omits SYS_PTRACE. Add only that missing
# capability; the fixture still proves the installed helper receives exactly
# cap_sys_ptrace=ep, drops it, and emits the expected protocol.
docker run --rm \
  --cap-add=SYS_PTRACE \
  --env "SYNTAUR_TEST_PROCESS_INSPECTOR=$container_inspector" \
  --mount "type=bind,src=$repository,dst=/repo,readonly" \
  "$image" \
  bash -c '
    set -euo pipefail

    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      acl \
      build-essential \
      libcap2-bin \
      sudo >/dev/null

    useradd --create-home --shell /bin/bash --uid 1001 runner
    cat >/etc/sudoers.d/syntaur-process-inspector-test <<'"'"'EOF'"'"'
runner ALL=(root) NOPASSWD: /usr/bin/chmod, /usr/bin/chown, /usr/bin/env, /usr/bin/find, /usr/bin/install, /usr/bin/ln, /usr/bin/mktemp, /usr/bin/mv, /usr/bin/rm, /usr/bin/setfacl, /usr/bin/sha256sum, /usr/bin/sync, /usr/sbin/setcap
EOF
    chmod 0440 /etc/sudoers.d/syntaur-process-inspector-test

    exec runuser --user runner -- \
      env \
        HOME=/home/runner \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        bash -c "cd /repo && bash scripts/test-process-inspector-install.sh"
  '
