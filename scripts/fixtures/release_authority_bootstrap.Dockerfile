ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260727T000000Z bookworm main' \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends jq mawk util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=root:root bootstrap-release-authority-genesis-v2.sh /bootstrap/bootstrap-release-authority-genesis-v2.sh
COPY --chown=root:root release-authority-manifest.sh /bootstrap/release-authority-manifest.sh
COPY --chown=root:root release-authority-fake-cosign.sh /usr/local/bin/cosign
COPY --chown=root:root release-authority-bootstrap-driver.sh /bootstrap/driver.sh
COPY --chown=1000:1000 fixture/ /fixture/
COPY --chown=root:root expected-shipper/ /expected/
COPY --chown=1000:1000 operator-ssh/ /home/sean/.ssh/

RUN install -d -o 1000 -g 1000 -m 0755 /home/sean \
    && chown 1000:1000 /home/sean \
    && chown 1000:1000 /home/sean/.ssh \
    && chmod 0700 /home/sean/.ssh \
    && chmod 0600 /home/sean/.ssh/id_ed25519 \
    && chmod 0555 \
      /bootstrap/bootstrap-release-authority-genesis-v2.sh \
      /bootstrap/release-authority-manifest.sh \
      /bootstrap/driver.sh \
    && chmod 0755 /usr/local/bin/cosign \
    && chmod 0500 /fixture \
    && chmod 0400 \
      /fixture/release-authority-v2.json \
      /fixture/release-authority-v2.json.cosign.bundle \
    && chmod 0500 \
      /fixture/syntaur-build-authority-provision \
      /fixture/syntaur-ship-linux-x86_64 \
      /fixture/syntaur-verify-linux-x86_64 \
    && chmod 0500 /expected/syntaur-ship-linux-x86_64

ENTRYPOINT ["/bootstrap/driver.sh"]
