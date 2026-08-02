ARG BASE_IMAGE=rust@sha256:4ec71e955e6c08aeb238885083222ddff79d82eb87654a96c76e38e94da1a53b
FROM ${BASE_IMAGE}

RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260727T000000Z bookworm main' \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends jq mawk util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN ! getent passwd sean >/dev/null 2>&1 \
    && ! getent passwd 1000 >/dev/null 2>&1 \
    && ! getent group sean >/dev/null 2>&1 \
    && ! getent group 1000 >/dev/null 2>&1 \
    && printf '%s\n' \
      'sean:x:1000:1000:Syntaur fixture operator:/home/sean:/usr/sbin/nologin' \
      >> /etc/passwd \
    && printf '%s\n' 'sean:x:1000:' >> /etc/group \
    && [ "$(getent passwd sean)" = \
      'sean:x:1000:1000:Syntaur fixture operator:/home/sean:/usr/sbin/nologin' ] \
    && [ "$(getent passwd 1000)" = \
      'sean:x:1000:1000:Syntaur fixture operator:/home/sean:/usr/sbin/nologin' ] \
    && [ "$(getent group sean)" = 'sean:x:1000:' ] \
    && [ "$(getent group 1000)" = 'sean:x:1000:' ]

COPY --chown=root:root bootstrap-release-authority-genesis-v2.sh /bootstrap/bootstrap-release-authority-genesis-v2.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-recovery-v1.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh
COPY --chown=root:root bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh
COPY --chown=root:root recover-release-authority-g10-g11-canary-root-v1.sh /bootstrap/recover-release-authority-g10-g11-canary-root-v1.sh.source
COPY --chown=root:root recover-release-authority-g11-g12-canary-root-v1.sh /bootstrap/recover-release-authority-g11-g12-canary-root-v1.sh.source
COPY --chown=root:root release-authority-manifest.sh /bootstrap/release-authority-manifest.sh
COPY --chown=root:root release-authority-fake-cosign.sh /usr/local/bin/cosign
COPY --chown=root:root release-authority-bootstrap-driver.sh /bootstrap/driver.sh
COPY --chown=root:root release-authority-g10-g11-driver.sh /bootstrap/g10-g11-driver.sh
COPY --chown=root:root release-authority-g11-g12-driver.sh /bootstrap/g11-g12-driver.sh
COPY --chown=1000:1000 fixture/ /fixture/
COPY --chown=1000:1000 fixture-g2/ /fixture-g2/
COPY --chown=1000:1000 fixture-g3/ /fixture-g3/
COPY --chown=1000:1000 fixture-g4/ /fixture-g4/
COPY --chown=1000:1000 fixture-g5/ /fixture-g5/
COPY --chown=1000:1000 fixture-g6/ /fixture-g6/
COPY --chown=1000:1000 fixture-g7/ /fixture-g7/
COPY --chown=1000:1000 fixture-g8/ /fixture-g8/
COPY --chown=1000:1000 fixture-g9/ /fixture-g9/
COPY --chown=1000:1000 fixture-g10/ /fixture-g10/
COPY --chown=root:root expected-shipper/ /expected/
COPY --chown=root:root recovery-predecessor/ /recovery-predecessor/
COPY --chown=1000:1000 operator-ssh/ /home/sean/.ssh/

RUN install -d -o 1000 -g 1000 -m 0755 /home/sean \
    && chown 1000:1000 /home/sean \
    && chown 1000:1000 /home/sean/.ssh \
    && chmod 0700 /home/sean/.ssh \
    && chmod 0600 /home/sean/.ssh/id_ed25519 \
    && chmod 0555 \
      /bootstrap/bootstrap-release-authority-genesis-v2.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-recovery-v1.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-recovery-v2.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-recovery-v3.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-recovery-v4.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-recovery-v6.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-recovery-v7.sh \
      /bootstrap/bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-g8-g9-g10-recovery-v8.sh \
      /bootstrap/recover-release-authority-g10-g11-canary-root-v1.sh.source \
      /bootstrap/recover-release-authority-g11-g12-canary-root-v1.sh.source \
      /bootstrap/release-authority-manifest.sh \
      /bootstrap/driver.sh \
      /bootstrap/g10-g11-driver.sh \
      /bootstrap/g11-g12-driver.sh \
    && chmod 0755 /usr/local/bin/cosign \
    && chmod 0500 /fixture \
    && chmod 0400 \
      /fixture/release-authority-v2.json \
      /fixture/release-authority-v2.json.cosign.bundle \
    && chmod 0500 \
      /fixture/syntaur-build-authority-provision \
      /fixture/syntaur-ship-linux-x86_64 \
      /fixture/syntaur-verify-linux-x86_64 \
    && chmod 0500 /expected/syntaur-ship-linux-x86_64 \
    && chmod 0500 /fixture-g2 /fixture-g3 /fixture-g4 /fixture-g5 /fixture-g6 /fixture-g7 /fixture-g8 /fixture-g9 /fixture-g10 \
    && chmod 0400 \
      /fixture-g2/release-authority-v2.json \
      /fixture-g2/release-authority-v2.json.cosign.bundle \
      /fixture-g3/release-authority-v2.json \
      /fixture-g3/release-authority-v2.json.cosign.bundle \
      /fixture-g4/release-authority-v2.json \
      /fixture-g4/release-authority-v2.json.cosign.bundle \
      /fixture-g5/release-authority-v2.json \
      /fixture-g5/release-authority-v2.json.cosign.bundle \
      /fixture-g6/release-authority-v2.json \
      /fixture-g6/release-authority-v2.json.cosign.bundle \
      /fixture-g7/release-authority-v2.json \
      /fixture-g7/release-authority-v2.json.cosign.bundle \
      /fixture-g8/release-authority-v2.json \
      /fixture-g8/release-authority-v2.json.cosign.bundle \
      /fixture-g9/release-authority-v2.json \
      /fixture-g9/release-authority-v2.json.cosign.bundle \
      /fixture-g10/release-authority-v2.json \
      /fixture-g10/release-authority-v2.json.cosign.bundle \
    && chmod 0500 \
      /fixture-g2/syntaur-build-authority-provision \
      /fixture-g2/syntaur-ship-linux-x86_64 \
      /fixture-g2/syntaur-verify-linux-x86_64 \
      /fixture-g3/syntaur-build-authority-provision \
      /fixture-g3/syntaur-ship-linux-x86_64 \
      /fixture-g3/syntaur-verify-linux-x86_64 \
      /fixture-g4/syntaur-build-authority-provision \
      /fixture-g4/syntaur-ship-linux-x86_64 \
      /fixture-g4/syntaur-verify-linux-x86_64 \
      /fixture-g5/syntaur-build-authority-provision \
      /fixture-g5/syntaur-ship-linux-x86_64 \
      /fixture-g5/syntaur-verify-linux-x86_64 \
      /fixture-g6/syntaur-build-authority-provision \
      /fixture-g6/syntaur-ship-linux-x86_64 \
      /fixture-g6/syntaur-verify-linux-x86_64 \
      /fixture-g7/syntaur-build-authority-provision \
      /fixture-g7/syntaur-ship-linux-x86_64 \
      /fixture-g7/syntaur-verify-linux-x86_64 \
      /fixture-g8/syntaur-build-authority-provision \
      /fixture-g8/syntaur-ship-linux-x86_64 \
      /fixture-g8/syntaur-verify-linux-x86_64 \
      /fixture-g9/syntaur-build-authority-provision \
      /fixture-g9/syntaur-ship-linux-x86_64 \
      /fixture-g9/syntaur-verify-linux-x86_64 \
      /fixture-g10/syntaur-build-authority-provision \
      /fixture-g10/syntaur-ship-linux-x86_64 \
      /fixture-g10/syntaur-verify-linux-x86_64 \
      /recovery-predecessor/syntaur-ship

ENTRYPOINT ["/bootstrap/driver.sh"]
