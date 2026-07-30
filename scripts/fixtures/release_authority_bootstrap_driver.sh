#!/usr/bin/bash
set -euo pipefail
umask 077

bootstrap_root=${BOOTSTRAP_FIXTURE_BOOTSTRAP_ROOT:-/bootstrap}
source_dir=${BOOTSTRAP_FIXTURE_SOURCE_DIR:-/fixture}
expected_dir=${BOOTSTRAP_FIXTURE_EXPECTED_DIR:-/expected}
bootstrap="$bootstrap_root/bootstrap-release-authority-genesis-v2.sh"
operator_uid=${BOOTSTRAP_FIXTURE_OPERATOR_UID:-1000}
operator_gid=${BOOTSTRAP_FIXTURE_OPERATOR_GID:-1000}
expected_rustsec_commit=$(printf 'd%.0s' {1..40})
args=(
    --source-dir "$source_dir"
    --expected-manifest-sha256 "$EXPECTED_MANIFEST_SHA256"
    --expected-workflow-commit "$EXPECTED_WORKFLOW_COMMIT"
    --expected-authority-version "$EXPECTED_AUTHORITY_VERSION"
    --expected-authority-commit "$EXPECTED_AUTHORITY_COMMIT"
    --expected-shipper-sha256 "$EXPECTED_SHIPPER_SHA256"
    --expected-verifier-sha256 "$EXPECTED_VERIFIER_SHA256"
    --expected-provisioner-sha256 "$EXPECTED_PROVISIONER_SHA256"
    --expected-helper-sha256 "$EXPECTED_HELPER_SHA256"
)
install_args=(
    "${args[@]}"
    --expected-rustsec-db-commit "$expected_rustsec_commit"
)
engine_commit=$(printf 'c%.0s' {1..40})

if [[ $operator_uid == 0 && $operator_gid == 0 ]]; then
    "$bootstrap" verify "${args[@]}"
else
    setpriv --reuid "$operator_uid" --regid "$operator_gid" --clear-groups \
        "$bootstrap" verify "${args[@]}"
fi

install -d -o "$operator_uid" -g "$operator_gid" -m 0700 \
    /home/sean/.syntaur \
    /home/sean/.syntaur/ship
printf '#!/usr/bin/bash\nexit 0\n# reviewed predecessor\n' \
    >/opt/syntaur-build-authority-provision
printf '#!/usr/bin/bash\nexit 0\n# reviewed validator predecessor\n' \
    >/opt/syntaur-genesis-validator
chown root:root /opt/syntaur-build-authority-provision
chown root:root /opt/syntaur-genesis-validator
chmod 0755 /opt/syntaur-build-authority-provision
chmod 0755 /opt/syntaur-genesis-validator
current_provisioner_sha256=$(
    sha256sum /opt/syntaur-build-authority-provision | awk '{print $1}'
)
current_validator_sha256=$(
    sha256sum /opt/syntaur-genesis-validator | awk '{print $1}'
)

SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    MUTATE_OPERATOR_SOURCE_ON_VERIFY=1 \
    "$bootstrap" stage-build-authority "${args[@]}" \
    --expected-current-provisioner-sha256 "$current_provisioner_sha256" \
    --expected-current-validator-sha256 "$current_validator_sha256"
[[ $(sha256sum /opt/syntaur-build-authority-provision | awk '{print $1}') \
    == "$EXPECTED_PROVISIONER_SHA256" ]]
[[ $(sha256sum /opt/syntaur-genesis-validator | awk '{print $1}') \
    == "$EXPECTED_SHIPPER_SHA256" ]]
[[ ! -e /etc/syntaur/release-authority ]]
[[ $(stat -c '%u:%g:%a:%h:%s' /etc/syntaur/syntaur-ship-mutation.lock) \
    == "0:$operator_gid:440:1:0" ]]
[[ $(sha256sum "$source_dir/syntaur-ship-linux-x86_64" | awk '{print $1}') \
    != "$EXPECTED_SHIPPER_SHA256" ]]
[[ ! -e /run/syntaur-release-authority-genesis-v2.snapshot ]]

chmod 0700 "$source_dir"
install -o "$operator_uid" -g "$operator_gid" -m 0500 \
    "$expected_dir/syntaur-ship-linux-x86_64" \
    "$source_dir/syntaur-ship-linux-x86_64"
chmod 0500 "$source_dir"

# Recover the exact two-link inode left by a kill between lock publication and
# removal of its private temporary link.
ln /etc/syntaur/syntaur-ship-mutation.lock \
    /etc/syntaur/.syntaur-lock.fixture-crash
[[ $(stat -c '%h' /etc/syntaur/syntaur-ship-mutation.lock) -eq 2 ]]

# Resume an exact provisioner stage left by a kill before its final rename.
printf '#!/usr/bin/bash\nexit 0\n# reviewed predecessor\n' \
    >/opt/syntaur-build-authority-provision
chown root:root /opt/syntaur-build-authority-provision
chmod 0755 /opt/syntaur-build-authority-provision
install -o root -g root -m 0755 \
    "$source_dir/syntaur-build-authority-provision" \
    /opt/.syntaur-build-authority-provision.bootstrap-v2-g1
printf '#!/usr/bin/bash\nexit 0\n# reviewed validator predecessor\n' \
    >/opt/syntaur-genesis-validator
chown root:root /opt/syntaur-genesis-validator
chmod 0755 /opt/syntaur-genesis-validator
install -o root -g root -m 0755 \
    "$source_dir/syntaur-ship-linux-x86_64" \
    /opt/.syntaur-genesis-validator.bootstrap-v2-g1
SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" stage-build-authority "${args[@]}" \
    --expected-current-provisioner-sha256 "$current_provisioner_sha256" \
    --expected-current-validator-sha256 "$current_validator_sha256"
[[ $(stat -c '%h' /etc/syntaur/syntaur-ship-mutation.lock) -eq 1 ]]
[[ ! -e /etc/syntaur/.syntaur-lock.fixture-crash ]]
[[ $(sha256sum /opt/syntaur-build-authority-provision | awk '{print $1}') \
    == "$EXPECTED_PROVISIONER_SHA256" ]]
[[ $(sha256sum /opt/syntaur-genesis-validator | awk '{print $1}') \
    == "$EXPECTED_SHIPPER_SHA256" ]]

evidence_dir=/home/sean/genesis-evidence
install -d -o "$operator_uid" -g "$operator_gid" -m 0700 "$evidence_dir"
evidence="$evidence_dir/genesis-validation.json"
sha256_label() {
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}
source_tree=$(printf '1%.0s' {1..40})
engine_tree=$(printf '2%.0s' {1..40})
source_export_sha=$(sha256_label source-export)
source_sealed_sha=$(sha256_label source-sealed-export)
engine_export_sha=$(sha256_label engine-export)
engine_sealed_sha=$(sha256_label engine-sealed-export)
control_plane_sha=$(sha256_label shipper-control-plane)
build_toolchain_sha=$(sha256_label shipper-build-toolchain)
build_rustflags_sha=$(sha256_label shipper-rustflags)
platform_image_sha=$(sha256_label platform-image)
platform_manifest_sha=$(sha256_label platform-manifest)
dependencies_image_sha=$(sha256_label dependencies-image)
dependencies_manifest_sha=$(sha256_label dependencies-manifest)
source_image_sha=$(sha256_label source-image)
source_manifest_sha=$(sha256_label source-manifest)
source_cargo_lock_sha=$(sha256_label source-cargo-lock)
engine_cargo_lock_sha=$(sha256_label engine-cargo-lock)
rust_toolchain_tree_sha=$(sha256_label rust-toolchain-tree)
cargo_vendor_tree_sha=$(sha256_label cargo-vendor-tree)
system_usr_tree_sha=$(sha256_label system-usr-tree)
system_etc_tree_sha=$(sha256_label system-etc-tree)
cargo_config_sha=$(sha256_label cargo-config)
ort_cache_tree_sha=$(sha256_label ort-cache-tree)
frame_sysroot_tree_sha=$(sha256_label frame-sysroot-tree)
rustsec_tree_sha=$(sha256_label rustsec-tree)
cargo_audit_sha=$(sha256_label cargo-audit)
rustc_vv_sha=$(sha256_label rustc-vv)
gateway_sha=$(sha256_label artifact-rust-openclaw)
mace_sha=$(sha256_label artifact-mace)
isolation_sha=$(sha256_label artifact-syntaur-isolation-tests)
browser_sha=$(sha256_label artifact-syntaur-browser)
captcha_sha=$(sha256_label artifact-rust-captcha-bridge)
social_sha=$(sha256_label artifact-rust-social-manager)
compose_sha=$(sha256_label artifact-runtime-compose)
images_sha=$(sha256_label artifact-runtime-images)
entrypoint_sha=$(sha256_label artifact-runtime-entrypoint)
tailscale_sha=$(sha256_label artifact-runtime-tailscale-entrypoint)
searxng_sha=$(sha256_label artifact-runtime-searxng-settings)
frame_sha=$(sha256_label artifact-syntaur-frame)
runtime_generation_id=$(sha256_label runtime-generation)
runtime_manifest_sha=$(sha256_label runtime-generation-manifest)
production_generation_id=$(sha256_label production-generation)
jq -cn \
    --arg version "$EXPECTED_AUTHORITY_VERSION" \
    --arg source "$EXPECTED_AUTHORITY_COMMIT" \
    --arg engine "$engine_commit" \
    --arg rustsec "$expected_rustsec_commit" \
    --arg shipper "$EXPECTED_SHIPPER_SHA256" \
    --arg provisioner "$EXPECTED_PROVISIONER_SHA256" \
    --arg source_tree "$source_tree" \
    --arg engine_tree "$engine_tree" \
    --arg source_export "$source_export_sha" \
    --arg source_sealed "$source_sealed_sha" \
    --arg engine_export "$engine_export_sha" \
    --arg engine_sealed "$engine_sealed_sha" \
    --arg control_plane "$control_plane_sha" \
    --arg build_toolchain "$build_toolchain_sha" \
    --arg build_rustflags "$build_rustflags_sha" \
    --arg platform_image "$platform_image_sha" \
    --arg platform_manifest "$platform_manifest_sha" \
    --arg dependencies_image "$dependencies_image_sha" \
    --arg dependencies_manifest "$dependencies_manifest_sha" \
    --arg source_image "$source_image_sha" \
    --arg source_manifest "$source_manifest_sha" \
    --arg source_cargo_lock "$source_cargo_lock_sha" \
    --arg engine_cargo_lock "$engine_cargo_lock_sha" \
    --arg rust_toolchain_tree "$rust_toolchain_tree_sha" \
    --arg cargo_vendor_tree "$cargo_vendor_tree_sha" \
    --arg system_usr_tree "$system_usr_tree_sha" \
    --arg system_etc_tree "$system_etc_tree_sha" \
    --arg cargo_config "$cargo_config_sha" \
    --arg ort_cache_tree "$ort_cache_tree_sha" \
    --arg frame_sysroot_tree "$frame_sysroot_tree_sha" \
    --arg rustsec_tree "$rustsec_tree_sha" \
    --arg cargo_audit "$cargo_audit_sha" \
    --arg rustc_vv "$rustc_vv_sha" \
    --arg gateway "$gateway_sha" \
    --arg mace "$mace_sha" \
    --arg isolation "$isolation_sha" \
    --arg browser "$browser_sha" \
    --arg captcha "$captcha_sha" \
    --arg social "$social_sha" \
    --arg compose "$compose_sha" \
    --arg images "$images_sha" \
    --arg entrypoint "$entrypoint_sha" \
    --arg tailscale "$tailscale_sha" \
    --arg searxng "$searxng_sha" \
    --arg frame "$frame_sha" \
    --arg runtime_generation "$runtime_generation_id" \
    --arg runtime_manifest "$runtime_manifest_sha" \
    --arg production_generation "$production_generation_id" \
    --argjson shipper_size \
        "$(stat -c '%s' "$expected_dir/syntaur-ship-linux-x86_64")" \
    '{
      schema:"syntaur.genesis-validation.v1",
      authorizing:false,
      completed_at:"2026-07-29T00:00:00Z",
      host:"claudevm",
      version:$version,
      source:{
        commit:$source,
        tree:$source_tree,
        workspace:"/tmp/source",
        export_tree_sha256:$source_export,
        sealed_export_tree_sha256:$source_sealed
      },
      engine:{
        commit:$engine,
        tree:$engine_tree,
        workspace:"/tmp/engine",
        export_tree_sha256:$engine_export,
        sealed_export_tree_sha256:$engine_sealed
      },
      source_date_epoch:1,
      shipper:{
        schema:1,
        executable_sha256:$shipper,
        executable_size:$shipper_size,
        build_source_commit:$source,
        control_plane_sha256:$control_plane,
        build_toolchain_sha256:$build_toolchain,
        build_rustflags_sha256:$build_rustflags,
        build_target:"x86_64-unknown-linux-gnu",
        build_profile:"release",
        clean_build:true
      },
      build_authority:{
        schema:4,
        platform_image_sha256:$platform_image,
        platform_manifest_sha256:$platform_manifest,
        dependencies_image_sha256:$dependencies_image,
        dependencies_manifest_sha256:$dependencies_manifest,
        source_image_sha256:$source_image,
        source_manifest_sha256:$source_manifest,
        source_commit:$source,
        source_version:$version,
        source_date_epoch:1,
        source_tree_sha256:$source_export,
        source_cargo_lock_sha256:$source_cargo_lock,
        engine_commit:$engine,
        engine_tree_sha256:$engine_export,
        engine_cargo_lock_sha256:$engine_cargo_lock,
        rust_toolchain_tree_sha256:$rust_toolchain_tree,
        cargo_vendor_tree_sha256:$cargo_vendor_tree,
        system_usr_tree_sha256:$system_usr_tree,
        tar_sha256:"3ee2c3c0b4dd9aacebfd2f0fbae44bad36348203acff78a44888dd58c05f811c",
        system_etc_tree_sha256:$system_etc_tree,
        cargo_config_sha256:$cargo_config,
        ort_cache_tree_sha256:$ort_cache_tree,
        frame_sysroot_tree_sha256:$frame_sysroot_tree,
        rustsec_tree_sha256:$rustsec_tree,
        rustsec_provenance_schema:1,
        rustsec_db_remote:"https://github.com/RustSec/advisory-db.git",
        rustsec_db_ref:"refs/heads/main",
        rustsec_db_commit:$rustsec,
        cargo_audit_sha256:$cargo_audit,
        rustc_vv_sha256:$rustc_vv,
        host_target:"x86_64-unknown-linux-gnu"
      },
      reproducibility_builds:2,
      artifacts:[
        {id:"rust-openclaw",path:"bin/rust-openclaw",sha256:$gateway,size:1},
        {id:"mace",path:"bin/mace",sha256:$mace,size:2},
        {id:"syntaur-isolation-tests",path:"bin/syntaur-isolation-tests",sha256:$isolation,size:3},
        {id:"syntaur_browser",path:"bin/syntaur_browser",sha256:$browser,size:4},
        {id:"rust-captcha-bridge",path:"bin/rust-captcha-bridge",sha256:$captcha,size:5},
        {id:"rust-social-manager",path:"bin/rust-social-manager",sha256:$social,size:6},
        {id:"runtime-compose",path:"runtime/docker-compose-prod.yml",sha256:$compose,size:7},
        {id:"runtime-images",path:"runtime/release-images.env",sha256:$images,size:8},
        {id:"runtime-entrypoint",path:"runtime/entrypoint.sh",sha256:$entrypoint,size:9},
        {id:"runtime-tailscale-entrypoint",path:"runtime/tailscale-sidecar-entrypoint.sh",sha256:$tailscale,size:10},
        {id:"runtime-searxng-settings",path:"runtime/searxng-settings.yml",sha256:$searxng,size:11},
        {id:"syntaur-frame",path:"frame/syntaur-frame",sha256:$frame,size:12}
      ],
      runtime_generation_id:$runtime_generation,
      runtime_generation_manifest_sha256:$runtime_manifest,
      production_generation_id:$production_generation,
      mac_target:"sean@192.168.1.58",
      mac_gateway_url:"http://192.168.1.58:18789",
      mac_smoke:{
        completed_at:"2026-07-29T00:00:00Z",
        version:$version,
        source_commit:$source,
        gateway_sha256:$gateway,
        frame_sha256:$frame,
        frame_size:12,
        frame_elf_machine:183,
        production_generation_id:$production_generation,
        runtime_generation_id:$runtime_generation,
        runtime_generation_manifest_sha256:$runtime_manifest,
        canary_seconds:45
      },
      persistent_authority:{
        build_authority_root_preexisting:false,
        exact_catalog_preexisting:false,
        global_mutation_lock_preexisting:true,
        installed_provisioner_sha256:$provisioner,
        build_authority_root_present_after:true,
        exact_catalog_present_after:true,
        global_mutation_lock_present_after:true
      },
      release_authority_root_absent:true
    }' >"$evidence"
chown "$operator_uid:$operator_gid" "$evidence"
chmod 0400 "$evidence"
chmod 0500 "$evidence_dir"
evidence_sha256=$(sha256sum "$evidence" | awk '{print $1}')

# Model the exact immutable catalog and mounted manifests retained by the real
# provisioner before Genesis emits success evidence.
authority_root=/opt/syntaur-build-authority
catalog="$authority_root/catalog/$EXPECTED_AUTHORITY_COMMIT-$engine_commit.json"
install -d -o root -g "$operator_gid" -m 0750 \
    "$authority_root" \
    "$authority_root/catalog" \
    "$authority_root/images" \
    "$authority_root/mounts"

install_layer_fixture() {
    local image_label=$1
    local image_digest=$2
    local manifest_label=$3
    local manifest_digest=$4
    local relative=$5
    local image="$authority_root/images/$image_digest.squashfs"
    local manifest="$authority_root/mounts/$image_digest/$relative"
    printf '%s' "$image_label" >"$image"
    chown "root:$operator_gid" "$image"
    chmod 0440 "$image"
    install -d -o root -g root -m 0755 \
        "$(dirname "$manifest")"
    printf '%s' "$manifest_label" >"$manifest"
    chown root:root "$manifest"
    chmod 0444 "$manifest"
    [[ $(sha256sum "$image" | awk '{print $1}') == "$image_digest" ]]
    [[ $(sha256sum "$manifest" | awk '{print $1}') == "$manifest_digest" ]]
}
install_layer_fixture \
    platform-image "$platform_image_sha" \
    platform-manifest "$platform_manifest_sha" \
    opt/authority/manifests/platform.json
install_layer_fixture \
    dependencies-image "$dependencies_image_sha" \
    dependencies-manifest "$dependencies_manifest_sha" \
    opt/authority/manifests/dependencies.json
install_layer_fixture \
    source-image "$source_image_sha" \
    source-manifest "$source_manifest_sha" \
    opt/authority/manifests/source.json
jq -c '.build_authority | {
  schema,source_commit,engine_commit,rustsec_provenance_schema,
  rustsec_db_remote,rustsec_db_ref,rustsec_db_commit,
  platform_image_sha256,platform_manifest_sha256,
  dependencies_image_sha256,dependencies_manifest_sha256,
  source_image_sha256,source_manifest_sha256
}' "$evidence" >"$catalog"
chown "root:$operator_gid" "$catalog"
chmod 0440 "$catalog"

assert_installed_authority_layout() {
    local authority=/etc/syntaur/release-authority
    local generation="$authority/release-authority/generation-1"
    local genesis="$authority/genesis"
    local actual expected name
    expected=$(printf '%s\n' \
        genesis \
        release-authority \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit | LC_ALL=C sort)
    actual=$(find "$authority" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)
    [[ $actual == "$expected" ]]
    [[ $(stat -c '%u:%g:%a' "$authority") == 0:0:755 ]]
    [[ $(stat -c '%u:%g:%a' "$genesis") == 0:0:555 ]]
    expected=$(printf '%s\n' \
        genesis-install-receipt-v1.json \
        genesis-validation.json | LC_ALL=C sort)
    actual=$(find "$genesis" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)
    [[ $actual == "$expected" ]]
    [[ $(stat -c '%u:%g:%a' "$authority/release-authority") == 0:0:755 ]]
    [[ $(find "$authority/release-authority" \
        -mindepth 1 -maxdepth 1 -printf '%f\n') == generation-1 ]]
    [[ $(stat -c '%u:%g:%a' "$generation") == 0:0:555 ]]

    expected=$(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C sort)
    actual=$(find "$generation" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)
    [[ $actual == "$expected" ]]
    for name in \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit; do
        [[ $(stat -c '%u:%g:%a:%h' "$generation/$name") == 0:0:444:1 ]]
    done
    for name in genesis-validation.json genesis-install-receipt-v1.json; do
        [[ $(stat -c '%u:%g:%a:%h' "$genesis/$name") == 0:0:444:1 ]]
    done
    for name in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        [[ $(stat -c '%u:%g:%a:%h' "$generation/$name") == 0:0:555:1 ]]
    done
    cmp -s "$authority/release-authority-v2.json" \
        "$generation/release-authority-v2.json"
    cmp -s "$authority/release-authority-v2.json.cosign.bundle" \
        "$generation/release-authority-v2.json.cosign.bundle"
    [[ $(sha256sum "$generation/syntaur-build-authority-provision" \
        | awk '{print $1}') == "$EXPECTED_PROVISIONER_SHA256" ]]
    [[ $(sha256sum "$generation/syntaur-ship-linux-x86_64" \
        | awk '{print $1}') == "$EXPECTED_SHIPPER_SHA256" ]]
    [[ $(sha256sum "$generation/syntaur-verify-linux-x86_64" \
        | awk '{print $1}') == "$EXPECTED_VERIFIER_SHA256" ]]
    [[ $(sha256sum "$genesis/genesis-validation.json" \
        | awk '{print $1}') == "$evidence_sha256" ]]
    jq -e \
        --arg authority "$EXPECTED_AUTHORITY_COMMIT" \
        --arg manifest "$EXPECTED_MANIFEST_SHA256" \
        --arg evidence_digest "$evidence_sha256" \
        --arg engine "$engine_commit" \
        --arg rustsec "$expected_rustsec_commit" \
        --arg shipper "$EXPECTED_SHIPPER_SHA256" \
        --arg provisioner "$EXPECTED_PROVISIONER_SHA256" \
        '
        keys == ([
          "schema","authority_commit","manifest_sha256",
          "genesis_evidence_sha256","engine_commit","rustsec_db_commit",
          "shipper_sha256","provisioner_sha256"
        ] | sort) and
        .schema == "syntaur.genesis-install-receipt.v1" and
        .authority_commit == $authority and
        .manifest_sha256 == $manifest and
        .genesis_evidence_sha256 == $evidence_digest and
        .engine_commit == $engine and
        .rustsec_db_commit == $rustsec and
        .shipper_sha256 == $shipper and
        .provisioner_sha256 == $provisioner
        ' "$genesis/genesis-install-receipt-v1.json" >/dev/null
}

assert_no_bootstrap_transients() {
    local transient
    for transient in \
        /run/syntaur-release-authority-genesis-v2.snapshot \
        /etc/syntaur/.release-authority.bootstrap-v2-g1 \
        /usr/local/bin/.syntaur-ship.authority-bootstrap-v2-g1 \
        /opt/.syntaur-build-authority-provision.bootstrap-v2-g1 \
        /opt/.syntaur-genesis-validator.bootstrap-v2-g1; do
        [[ ! -e "$transient" && ! -L "$transient" ]]
    done
}

expect_invalid_evidence() {
    local label=$1
    local filter=$2
    local invalid="$evidence_dir/invalid-$label.json"
    chmod 0700 "$evidence_dir"
    if [[ $filter == two-records ]]; then
        {
            tr -d '\n' <"$evidence"
            printf ' '
            tr -d '\n' <"$evidence"
            printf '\n'
        } >"$invalid"
    elif [[ $filter == duplicate-keys ]]; then
        {
            printf '{"authorizing":true,'
            tail -c +2 "$evidence"
        } >"$invalid"
    else
        jq -c "$filter" "$evidence" >"$invalid"
    fi
    chown "$operator_uid:$operator_gid" "$invalid"
    chmod 0400 "$invalid"
    chmod 0500 "$evidence_dir"
    local invalid_sha256
    invalid_sha256=$(sha256sum "$invalid" | awk '{print $1}')
    if SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
        "$bootstrap" install "${install_args[@]}" \
            --genesis-evidence "$invalid" \
            --expected-genesis-evidence-sha256 "$invalid_sha256" \
            --expected-genesis-engine-commit "$engine_commit"; then
        printf 'invalid Genesis evidence was accepted: %s\n' "$label" >&2
        exit 1
    fi
    [[ ! -e /etc/syntaur/release-authority ]]
    [[ ! -e /usr/local/bin/syntaur-ship ]]
    assert_no_bootstrap_transients
    chmod 0700 "$evidence_dir"
    rm -f "$invalid"
    chmod 0500 "$evidence_dir"
}

expect_invalid_evidence two-records two-records
expect_invalid_evidence duplicate-keys duplicate-keys
expect_invalid_evidence gateway-link \
    '.mac_smoke.gateway_sha256 = ("0" * 64)'
expect_invalid_evidence frame-link \
    '.mac_smoke.frame_size = 2'
expect_invalid_evidence generation-link \
    '.mac_smoke.runtime_generation_id = ("0" * 64)'
expect_invalid_evidence source-tree-link \
    '.build_authority.source_tree_sha256 = ("0" * 64)'
expect_invalid_evidence rustsec-link \
    '.build_authority.rustsec_db_commit = .source.commit'
expect_invalid_evidence layer-swap \
    '.build_authority.dependencies_image_sha256 =
        .build_authority.platform_image_sha256'

expect_persistent_authority_rejected() {
    local label=$1
    if SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
        "$bootstrap" install "${install_args[@]}" \
            --genesis-evidence "$evidence" \
            --expected-genesis-evidence-sha256 "$evidence_sha256" \
            --expected-genesis-engine-commit "$engine_commit"; then
        printf 'invalid persistent authority was accepted: %s\n' "$label" >&2
        exit 1
    fi
    [[ ! -e /etc/syntaur/release-authority ]]
    [[ ! -e /usr/local/bin/syntaur-ship ]]
    assert_no_bootstrap_transients
}

catalog_record=$(<"$catalog")
replace_catalog_fixture() (
    local catalog_dir replacement
    catalog_dir=${catalog%/*}
    replacement=$(mktemp \
        "$catalog_dir/.syntaur-catalog-fixture.XXXXXX")
    trap 'if [[ -n ${replacement:-} ]]; then rm -f -- "$replacement"; fi' EXIT
    cat >"$replacement"
    chown "root:$operator_gid" "$replacement"
    chmod 0440 "$replacement"
    [[ $(stat -c '%u:%g:%a:%h' "$replacement") \
        == "0:$operator_gid:440:1" ]]
    mv -fT -- "$replacement" "$catalog"
    replacement=
    trap - EXIT
)
printf '%s\n%s\n' "$catalog_record" "$catalog_record" \
    | replace_catalog_fixture
expect_persistent_authority_rejected multi-record-catalog
printf '%s\n' "$catalog_record" | replace_catalog_fixture

platform_image="$authority_root/images/$platform_image_sha.squashfs"
hidden_platform_image="$authority_root/images/.fixture-missing-platform-image"
mv "$platform_image" "$hidden_platform_image"
expect_persistent_authority_rejected missing-platform-layer
mv "$hidden_platform_image" "$platform_image"

# Resume an exact shipper stage left by a kill before its final rename.
install -o root -g root -m 0755 \
    "$expected_dir/syntaur-ship-linux-x86_64" \
    /usr/local/bin/.syntaur-ship.authority-bootstrap-v2-g1
SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${install_args[@]}" \
    --genesis-evidence "$evidence" \
    --expected-genesis-evidence-sha256 "$evidence_sha256" \
    --expected-genesis-engine-commit "$engine_commit"
[[ $(sha256sum /usr/local/bin/syntaur-ship | awk '{print $1}') \
    == "$EXPECTED_SHIPPER_SHA256" ]]
[[ ! -e /opt/syntaur-genesis-validator ]]
assert_installed_authority_layout

# Prove both the bootstrap and the independent fixture reject an inexact
# published tree, rather than relying on the fixture status executable alone.
install -o root -g root -m 0444 /dev/null \
    /etc/syntaur/release-authority/unexpected-fixture-file
if SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${install_args[@]}" \
        --genesis-evidence "$evidence" \
        --expected-genesis-evidence-sha256 "$evidence_sha256" \
        --expected-genesis-engine-commit "$engine_commit"; then
    printf '%s\n' 'inexact installed authority layout was accepted' >&2
    exit 1
fi
rm -f /etc/syntaur/release-authority/unexpected-fixture-file
assert_installed_authority_layout

chmod 0700 "$evidence_dir"
alternate_evidence="$evidence_dir/alternate-valid-genesis.json"
jq -c \
    '.completed_at = "2026-07-29T00:00:01Z"' \
    "$evidence" >"$alternate_evidence"
chown "$operator_uid:$operator_gid" "$alternate_evidence"
chmod 0400 "$alternate_evidence"
chmod 0500 "$evidence_dir"
alternate_evidence_sha256=$(
    sha256sum "$alternate_evidence" | awk '{print $1}'
)
if SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${install_args[@]}" \
        --genesis-evidence "$alternate_evidence" \
        --expected-genesis-evidence-sha256 "$alternate_evidence_sha256" \
        --expected-genesis-engine-commit "$engine_commit"; then
    printf '%s\n' \
        'installed Genesis receipt accepted alternate valid evidence' >&2
    exit 1
fi
assert_installed_authority_layout
chmod 0700 "$evidence_dir"
rm -f "$alternate_evidence"
chmod 0500 "$evidence_dir"

SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${install_args[@]}" \
    --genesis-evidence "$evidence" \
    --expected-genesis-evidence-sha256 "$evidence_sha256" \
    --expected-genesis-engine-commit "$engine_commit"
assert_installed_authority_layout

install -d -o root -g root -m 0700 \
    /run/syntaur-release-authority-genesis-v2.snapshot
SUDO_UID="$operator_uid" SUDO_GID="$operator_gid" \
    "$bootstrap" install "${install_args[@]}" \
    --genesis-evidence "$evidence" \
    --expected-genesis-evidence-sha256 "$evidence_sha256" \
    --expected-genesis-engine-commit "$engine_commit"
[[ ! -e /run/syntaur-release-authority-genesis-v2.snapshot ]]

printf 'V2 genesis bootstrap behavioral fixture passed\n'
