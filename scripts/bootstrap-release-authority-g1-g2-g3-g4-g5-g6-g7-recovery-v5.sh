#!/usr/bin/bash
set -euo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

readonly COSIGN=/usr/local/bin/cosign
readonly COSIGN_SHA256=c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74
readonly COSIGN_IDENTITY=https://github.com/syntaur-systems/syntaur-dist/.github/workflows/release-authority.yml@refs/heads/main
readonly COSIGN_ISSUER=https://token.actions.githubusercontent.com
readonly MANIFEST_HELPER_SHA256=76b12e8b14d75e206ec2498448955e33dfc2fc23a315a7c126fdca9c141cfa8d

readonly G1_MANIFEST_SHA256=aa271e4c1478c957c581d13b5d6033ca04f1f3d8a23b580d3e3a1d005bc16ccc
readonly G1_BUNDLE_SHA256=4d467e65249f2e3c31c63d80ba2c8f39b22ad07ecb519d164be09f837e64b3d4
readonly G1_WORKFLOW_COMMIT=151d19a04bb317c66a321679e9294318c220a17e
readonly G1_AUTHORITY_COMMIT=0aca183187912ccc665bfddc3747759c4ecbfc01
readonly G1_AUTHORITY_TREE_SHA256=23ab28f169c3bf638738a83ba3750b5b9e65b6d774d05e7df0e88e40deaa2365
readonly G1_SHIPPER_SHA256=29aadd5109925258b3c2bdd1f4fa6bfd82ef4f9c2f7124aaf871b73909f43d21
readonly G1_VERIFIER_SHA256=6e08950ddd77a345aa8817aac60695193accdfa419012041ccafb8e588d0a990
readonly G1_PROVISIONER_SHA256=09889f917ac51e4b5c0eb5254ea8702edb99a84dceba8dbb1e3d93952e8e4b50

readonly G2_MANIFEST_SHA256=24ab5adcaa78cadc3d3db396ad153c396b8d5cceafab063e67250467bd868e53
readonly G2_BUNDLE_SHA256=3fcacdc91f41732bdc7b3868d712cb16d72607da92554926caa9c865941065e8
readonly G2_WORKFLOW_COMMIT=476083e159c0f1705c8a4efee5a6b71d7cd86188
readonly G2_AUTHORITY_COMMIT=5642d7bc36a4913d42d9bce1120a3a2fe604aca8
readonly G2_AUTHORITY_TREE_SHA256=b48fe9158b51ab69f49b233c6913fd2ec241b6d1446a3c455be15eb3932c1a63
readonly G2_SHIPPER_SHA256=67f7d00959cf2358e3302008a9fe91cd74e5d05f1d1e85070c0c7130e0c1c370
readonly G2_VERIFIER_SHA256=6e08950ddd77a345aa8817aac60695193accdfa419012041ccafb8e588d0a990
readonly G2_PROVISIONER_SHA256=6c04b602730a19c41f96afa88bddc157d8b498c49e7d395827fbd9904b3e8610

readonly G3_MANIFEST_SHA256=42d5ed970680347c64276dc27fc150d42ac929d2e3a790b637bbd6a3351c531d
readonly G3_BUNDLE_SHA256=8b99580513e4b204cc707509414b6bb4767dfcaac47d905a1623b45fd33fd699
readonly G3_WORKFLOW_COMMIT=476083e159c0f1705c8a4efee5a6b71d7cd86188
readonly G3_AUTHORITY_COMMIT=8003e39735ebed5a326ee011001937be64bc340c
readonly G3_AUTHORITY_TREE_SHA256=8a03d3e6085b7316e1cca635a233d5e0ae795d6ddb9b2b4b0c99d1b64e04a14c
readonly G3_SHIPPER_SHA256=26feab6c0c8498d0ec3a60ec2b216d3119fadcd8cc1c847804ddf6c083539a2c
readonly G3_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G3_PROVISIONER_SHA256=6c04b602730a19c41f96afa88bddc157d8b498c49e7d395827fbd9904b3e8610

readonly G4_MANIFEST_SHA256=af9514cfbe39affd5ef44cb34b7678afcc315f946c9a59f46cda4b6a78aa4ac2
readonly G4_BUNDLE_SHA256=ab9fa1edc0471e5e068054381a5cc4fb96d307be8aeac61ef95948d2adbdddc8
readonly G4_WORKFLOW_COMMIT=30bd91e7b2f072c323a7ccd70a1bfdaa007bedc2
readonly G4_AUTHORITY_COMMIT=417e2f6b8e0518ccd314680ba9d68766378e4900
readonly G4_AUTHORITY_TREE_SHA256=0f180e8213f4e4daf91ece560dbe849a6e3c960ff9ab511acd041d5de91d483a
readonly G4_SHIPPER_SHA256=0b7258d997e4ba887c886f0f95d9c26b9accc4c2a2834202330288f44565fb18
readonly G4_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G4_PROVISIONER_SHA256=8788aaad9277e97d466e1645d194597fe5bbf48b79936451532026b88a7219eb

readonly G5_MANIFEST_SHA256=bdafc1712be2f8827df5afab45e4a79b4640f5c0b0e77dee6ee08d45facd329d
readonly G5_BUNDLE_SHA256=e7650de4c9e14ef2182f539aad62a136a791c047632edd034f21eb30b741f3c2
readonly G5_WORKFLOW_COMMIT=9756e0b531556179502f311045f1841f093d0606
readonly G5_AUTHORITY_COMMIT=dc670026daf6765e01f5208b8b823ea47e4b63d5
readonly G5_AUTHORITY_TREE_SHA256=9cb07095581b128bf6619a4684c2cf110a9710e80dd26f28d25dfdd89eb3c6fc
readonly G5_SHIPPER_SHA256=006ec7bbe91c16e8a71b89f5240217e9beaeea15dcf94e17aba32f19da0610db
readonly G5_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G5_PROVISIONER_SHA256=3ffe542e9a6562d01e8c80066be63e560187526bfc9f8412ec281a203ac718b6

readonly G6_MANIFEST_SHA256=1548c783fd09a6e3724397eaf18d0f2e5cb7dcd3db0c4609b31f6c95e11c6fd9
readonly G6_BUNDLE_SHA256=6dd5473286be641aed46647ee1b914c8b7493c6a8b43e0fa6a217b9b561feb5c
readonly G6_WORKFLOW_COMMIT=9756e0b531556179502f311045f1841f093d0606
readonly G6_AUTHORITY_COMMIT=3f57a12d405e793fc69d649146576c5989eea649
readonly G6_AUTHORITY_GIT_TREE=a788f4abe5a9a9fd268af81a8391e98b5ddad129
readonly G6_AUTHORITY_TREE_SHA256=b306be94ab2c7800e58c93203041507477e96b07bcd55b487ec5b68697e53118
readonly G6_SHIPPER_SHA256=2fe1eec53b18b9c38143c4c8824c133e89ef19020b48206c0507e6e6a4caab6d
readonly G6_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G6_PROVISIONER_SHA256=c6755245d7884153c9cbd073d26b6d5940fd13459be46a701d561752afda044e

readonly G7_MANIFEST_SHA256=ac102b18e59027f881e9ddcc387b61a3702020c733b741fc7ab204eb53a20686
readonly G7_BUNDLE_SHA256=265bfe91a40e0b2c491437a2bf9da9a4356e3689a03d88e6e3bb9ebd970a7196
readonly G7_WORKFLOW_COMMIT=24693b082272e77016cc99e0e6d4657f3c191ec6
readonly G7_AUTHORITY_COMMIT=bf9def327af774b4269972e209a7e2914f81d42d
readonly G7_AUTHORITY_GIT_TREE=012ca8444c95ed5b4ca7ab3951ef3db4e59c0e81
readonly G7_AUTHORITY_TREE_SHA256=39262b1b20fda68ce1a6f4e648c32cf1d03805c58750e87aaecb5fa1d02b8867
readonly G7_SOURCE_DATE_EPOCH=1785472113
readonly G7_SHIPPER_SHA256=7779ca3eba33f079f82455955efa812c3eb4c9a7eb903be6f7d74e1906300031
readonly G7_VERIFIER_SHA256=4b050fe880b8dbd4a6d41b24e305837a117c9be7b7a21c6b6e55552f5d6f35a5
readonly G7_PROVISIONER_SHA256=c6755245d7884153c9cbd073d26b6d5940fd13459be46a701d561752afda044e

readonly AUTHORITY_VERSION=0.7.114
readonly BASELINE_RECONSTRUCTION_COMMIT=5642d7bc36a4913d42d9bce1120a3a2fe604aca8
readonly BASELINE_RECONSTRUCTION_GIT_TREE=a1981a0868ba4d9d72128ca0c0d4ee82d466de2d
readonly BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH=1785438256
readonly BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256=2efbaee443b0d6d7f2ac6a0f9a4ad5d627c7e0b6de3c38aa6be4c53d9ec21d97
readonly ENGINE_COMMIT=36f3348fc32c02d0a0091be9ea87b828306941cc
readonly ENGINE_TREE=2983054537a8fe4be36a3a8f7c73973722ed1dd1
readonly ENGINE_CARGO_LOCK_SHA256=644ec3b6d1de81f32602170eb4486c4cab9c8229590a1684a3d590b1a1af861f
readonly RUSTSEC_DB_COMMIT=7c7ccac53056b87f69ac677f15ea2d9a98a6f8e2
readonly RUSTSEC_TREE_SHA256=2eb8a60fee92aa14abcbcf9d3ca3ea65cc68bb0fdbdcdefdbaa21f866629c58d
readonly SYSTEM_USR_TREE_SHA256=17dbd594f9b528d5be5b68be5a31b3e0d9b6414697efe272d5fa1c6b542918e5
readonly TAR_SHA256=3ee2c3c0b4dd9aacebfd2f0fbae44bad36348203acff78a44888dd58c05f811c

readonly AUTHORITY_ROOT=/etc/syntaur/release-authority
readonly GLOBAL_MUTATION_LOCK=/etc/syntaur/syntaur-ship-mutation.lock
readonly BOOTSTRAP_LOCK=/run/lock/syntaur-release-authority-bootstrap.lock
readonly OPERATOR_STATE=/home/sean/.syntaur/ship
readonly INSTALLED_SHIPPER=/usr/local/bin/syntaur-ship
readonly PRE_RECOVERY_SHIPPER_SHA256=ea26a001ec0912478ed1f12c62627fde83890b5b72b48e37169ce33b70dd2080
readonly INSTALLED_PROVISIONER=/opt/syntaur-build-authority-provision
readonly GENESIS_VALIDATOR=/opt/syntaur-genesis-validator
readonly MAC_KNOWN_HOSTS=/etc/syntaur/mac-mini-known-hosts
readonly MAC_KNOWN_HOSTS_SHA256=2a703ea347e6abc8e423df92ba4e2592656cf64fee467083104565a69478b1c1
readonly MAC_IDENTITY=/etc/syntaur/mac-mini-identity-b9b69e39abe1089c1fb5a8a307425003a2fc01585f5b67f35a674e814b5e8d7a
readonly MAC_IDENTITY_SHA256=9b107d62548047fa028a1ab588f00b0894d41bb0399114a5499bc4bfd06df40f
readonly MAC_IDENTITY_SIZE=411
readonly MAC_IDENTITY_PUBLIC_SHA256=b9b69e39abe1089c1fb5a8a307425003a2fc01585f5b67f35a674e814b5e8d7a
readonly MAC_IDENTITY_FINGERPRINT='SHA256:HAUyJtTA+8CYqXxLp9oBlYpRdVpctcb76+n0xTo5EWU'

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly SOURCE_MANIFEST_HELPER="$script_dir/release-authority-manifest.sh"
manifest_helper=$SOURCE_MANIFEST_HELPER

die() {
    printf 'release authority G1-G2-G3-G4-G5-G6-G7 recovery error: %s\n' "$*" >&2
    exit 1
}

usage() {
    /usr/bin/cat >&2 <<'EOF'
Usage:
  bootstrap-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery-v5.sh verify|stage-g7-build-authority|install \
    --g1-dir DIR --g2-dir DIR --g3-dir DIR --g4-dir DIR --g5-dir DIR --g6-dir DIR --g7-dir DIR \
    [--genesis-evidence FILE \
     --expected-genesis-evidence-sha256 HEX \
     --expected-current-shipper-sha256 HEX]

This is the fixed one-time recovery for immutable authority generations
G1 through G7. `verify` is non-mutating. `stage-g7-build-authority`
CAS-installs the exact G7 provisioner and G7 Genesis validator while the
release root remains absent. After external G7 Genesis validation, `install`
atomically publishes the retained G1-G2-G3-G4-G5-G6-G7 chain with G7 active.
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
action=$1
shift
[[ $action == verify || $action == stage-g7-build-authority \
    || $action == install ]] || usage

g1_dir=
g2_dir=
g3_dir=
g4_dir=
g5_dir=
g6_dir=
g7_dir=
genesis_evidence=
expected_genesis_evidence_sha256=
expected_current_shipper_sha256=
while (($# > 0)); do
    [[ $# -ge 2 ]] || usage
    case $1 in
        --g1-dir) g1_dir=$2 ;;
        --g2-dir) g2_dir=$2 ;;
        --g3-dir) g3_dir=$2 ;;
        --g4-dir) g4_dir=$2 ;;
        --g5-dir) g5_dir=$2 ;;
        --g6-dir) g6_dir=$2 ;;
        --g7-dir) g7_dir=$2 ;;
        --genesis-evidence) genesis_evidence=$2 ;;
        --expected-genesis-evidence-sha256)
            expected_genesis_evidence_sha256=$2
            ;;
        --expected-current-shipper-sha256)
            expected_current_shipper_sha256=$2
            ;;
        *) usage ;;
    esac
    shift 2
done

for source_dir in "$g1_dir" "$g2_dir" "$g3_dir" "$g4_dir" "$g5_dir" \
    "$g6_dir" "$g7_dir"; do
    [[ $source_dir == /* ]] || die 'every release directory must be absolute'
    [[ $(readlink -f -- "$source_dir") == "$source_dir" ]] \
        || die 'every release directory must be canonical'
done
[[ $g1_dir != "$g2_dir" && $g1_dir != "$g3_dir" \
    && $g1_dir != "$g4_dir" && $g2_dir != "$g3_dir" \
    && $g1_dir != "$g5_dir" && $g2_dir != "$g4_dir" \
    && $g2_dir != "$g5_dir" && $g3_dir != "$g4_dir" \
    && $g3_dir != "$g5_dir" && $g4_dir != "$g5_dir" \
    && $g1_dir != "$g6_dir" && $g2_dir != "$g6_dir" \
    && $g3_dir != "$g6_dir" && $g4_dir != "$g6_dir" \
    && $g5_dir != "$g6_dir" && $g1_dir != "$g7_dir" \
    && $g2_dir != "$g7_dir" && $g3_dir != "$g7_dir" \
    && $g4_dir != "$g7_dir" && $g5_dir != "$g7_dir" \
    && $g6_dir != "$g7_dir" ]] \
    || die 'release directories must be distinct'

if [[ $action == install ]]; then
    [[ $genesis_evidence == /* ]] \
        || die 'install requires an absolute Genesis evidence path'
    [[ $(readlink -f -- "$genesis_evidence") == "$genesis_evidence" ]] \
        || die 'Genesis evidence path must be canonical'
    [[ $expected_genesis_evidence_sha256 =~ ^[0-9a-f]{64}$ ]] \
        || die 'install requires the independently recorded evidence digest'
    [[ $expected_current_shipper_sha256 =~ ^[0-9a-f]{64}$ ]] \
        || die 'install requires the independently recorded current shipper digest'
    [[ $expected_current_shipper_sha256 == "$PRE_RECOVERY_SHIPPER_SHA256" ]] \
        || die 'the independently recorded current shipper is not the fixed recovery predecessor'
elif [[ -n $genesis_evidence || -n $expected_genesis_evidence_sha256 \
        || -n $expected_current_shipper_sha256 ]]; then
    die 'Genesis and current-shipper inputs are valid only for installation'
fi

operator_uid=$(id -u)
operator_gid=$(id -g)
if [[ $action != verify ]]; then
    [[ $(id -u) -eq 0 && $(id -g) -eq 0 ]] \
        || die 'mutation requires sudo and an all-root effective identity'
    [[ ${SUDO_UID:-} =~ ^[1-9][0-9]*$ && ${SUDO_GID:-} =~ ^[1-9][0-9]*$ ]] \
        || die 'mutation requires concrete non-root SUDO_UID and SUDO_GID'
    operator_uid=$SUDO_UID
    operator_gid=$SUDO_GID
fi

expected_asset_names=$(printf '%s\n' \
    release-authority-v2.json \
    release-authority-v2.json.cosign.bundle \
    syntaur-build-authority-provision \
    syntaur-ship-linux-x86_64 \
    syntaur-verify-linux-x86_64 | LC_ALL=C sort)

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

validate_release_material() {
    local material=$1
    local generation=$2
    local manifest_sha256=$3
    local bundle_sha256=$4
    local workflow_commit=$5
    local authority_commit=$6
    local authority_tree_sha256=$7
    local shipper_sha256=$8
    local verifier_sha256=$9
    local provisioner_sha256=${10}
    local owner_uid=${11}
    local owner_gid=${12}
    local directory_mode=${13}
    local data_mode=${14}
    local executable_mode=${15}
    local actual_names name path

    [[ -d $material && ! -L $material ]] \
        || die "release material is unsafe: generation $generation"
    [[ $(stat -c '%u:%g:%a' "$material") == \
        "$owner_uid:$owner_gid:$directory_mode" ]] \
        || die "release material directory identity differs: generation $generation"
    actual_names=$(find "$material" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual_names == "$expected_asset_names" ]] \
        || die "release material file set differs: generation $generation"
    for name in release-authority-v2.json release-authority-v2.json.cosign.bundle; do
        path="$material/$name"
        [[ -f $path && ! -L $path ]] \
            || die "release data is unsafe: generation $generation $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") == \
            "$owner_uid:$owner_gid:$data_mode:1" ]] \
            || die "release data identity differs: generation $generation $name"
    done
    for name in \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        path="$material/$name"
        [[ -f $path && ! -L $path ]] \
            || die "release executable is unsafe: generation $generation $name"
        [[ $(stat -c '%u:%g:%a:%h' "$path") == \
            "$owner_uid:$owner_gid:$executable_mode:1" ]] \
            || die "release executable identity differs: generation $generation $name"
    done

    local manifest bundle
    manifest="$material/release-authority-v2.json"
    bundle="$material/release-authority-v2.json.cosign.bundle"
    [[ $(sha256_file "$manifest") == "$manifest_sha256" ]] \
        || die "manifest digest differs: generation $generation"
    [[ $(sha256_file "$bundle") == "$bundle_sha256" ]] \
        || die "bundle digest differs: generation $generation"
    [[ $(jq -er '.authority_commit' "$manifest") == "$authority_commit" ]] \
        || die "authority commit differs: generation $generation"
    [[ $(jq -er '.authority_tree_sha256' "$manifest") == \
        "$authority_tree_sha256" ]] \
        || die "authority tree differs: generation $generation"
    [[ $(jq -er '.authority_version' "$manifest") == "$AUTHORITY_VERSION" ]] \
        || die "authority version differs: generation $generation"
    [[ $(jq -er '.shipper_sha256' "$manifest") == "$shipper_sha256" ]] \
        || die "shipper digest differs: generation $generation"
    [[ $(jq -er '.verifier_sha256' "$manifest") == "$verifier_sha256" ]] \
        || die "verifier digest differs: generation $generation"
    [[ $(jq -er '.provisioner_sha256' "$manifest") == "$provisioner_sha256" ]] \
        || die "provisioner digest differs: generation $generation"
    /usr/bin/bash "$manifest_helper" \
        validate "$manifest" 2 "$generation" "$workflow_commit" "$material"
    "$COSIGN" verify-blob \
        --bundle "$bundle" \
        --certificate-identity "$COSIGN_IDENTITY" \
        --certificate-oidc-issuer "$COSIGN_ISSUER" \
        --certificate-github-workflow-sha "$workflow_commit" \
        "$manifest" >/dev/null
}

validate_operator_parent_chain() {
    local source_dir=$1
    local current mode owner
    current=$source_dir
    while [[ $current != / ]]; do
        current=$(dirname "$current")
        [[ -d $current && ! -L $current ]] \
            || die "unsafe release parent: $current"
        mode=$(stat -c '%a' "$current")
        owner=$(stat -c '%u' "$current")
        (( (8#$mode & 8#022) == 0 )) \
            || die "writable release parent: $current"
        [[ $owner == 0 || $owner == "$operator_uid" ]] \
            || die "untrusted release parent owner: $current"
    done
}

validate_cosign() {
    [[ -x $COSIGN && ! -L $COSIGN ]] || die 'pinned Cosign is missing'
    [[ $(stat -c '%u:%g:%a:%h' "$COSIGN") == 0:0:755:1 ]] \
        || die 'pinned Cosign identity differs'
    [[ $(sha256_file "$COSIGN") == "$COSIGN_SHA256" ]] \
        || die 'pinned Cosign digest differs'
}

validate_manifest_helper() {
    [[ -f $manifest_helper && ! -L $manifest_helper ]] \
        || die 'manifest helper is unsafe'
    [[ $(sha256_file "$manifest_helper") == \
        "$MANIFEST_HELPER_SHA256" ]] \
        || die 'manifest helper digest differs'
}

validate_release_chain() {
    local owner_uid=$1
    local owner_gid=$2
    local directory_mode=$3
    local data_mode=$4
    local executable_mode=$5
    local material_g1=$6
    local material_g2=$7
    local material_g3=$8
    local material_g4=$9
    local material_g5=${10}
    local material_g6=${11}
    local material_g7=${12}

    validate_release_material \
        "$material_g1" 1 \
        "$G1_MANIFEST_SHA256" "$G1_BUNDLE_SHA256" \
        "$G1_WORKFLOW_COMMIT" "$G1_AUTHORITY_COMMIT" \
        "$G1_AUTHORITY_TREE_SHA256" "$G1_SHIPPER_SHA256" \
        "$G1_VERIFIER_SHA256" "$G1_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g2" 2 \
        "$G2_MANIFEST_SHA256" "$G2_BUNDLE_SHA256" \
        "$G2_WORKFLOW_COMMIT" "$G2_AUTHORITY_COMMIT" \
        "$G2_AUTHORITY_TREE_SHA256" "$G2_SHIPPER_SHA256" \
        "$G2_VERIFIER_SHA256" "$G2_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g3" 3 \
        "$G3_MANIFEST_SHA256" "$G3_BUNDLE_SHA256" \
        "$G3_WORKFLOW_COMMIT" "$G3_AUTHORITY_COMMIT" \
        "$G3_AUTHORITY_TREE_SHA256" "$G3_SHIPPER_SHA256" \
        "$G3_VERIFIER_SHA256" "$G3_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g4" 4 \
        "$G4_MANIFEST_SHA256" "$G4_BUNDLE_SHA256" \
        "$G4_WORKFLOW_COMMIT" "$G4_AUTHORITY_COMMIT" \
        "$G4_AUTHORITY_TREE_SHA256" "$G4_SHIPPER_SHA256" \
        "$G4_VERIFIER_SHA256" "$G4_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g5" 5 \
        "$G5_MANIFEST_SHA256" "$G5_BUNDLE_SHA256" \
        "$G5_WORKFLOW_COMMIT" "$G5_AUTHORITY_COMMIT" \
        "$G5_AUTHORITY_TREE_SHA256" "$G5_SHIPPER_SHA256" \
        "$G5_VERIFIER_SHA256" "$G5_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g6" 6 \
        "$G6_MANIFEST_SHA256" "$G6_BUNDLE_SHA256" \
        "$G6_WORKFLOW_COMMIT" "$G6_AUTHORITY_COMMIT" \
        "$G6_AUTHORITY_TREE_SHA256" "$G6_SHIPPER_SHA256" \
        "$G6_VERIFIER_SHA256" "$G6_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    validate_release_material \
        "$material_g7" 7 \
        "$G7_MANIFEST_SHA256" "$G7_BUNDLE_SHA256" \
        "$G7_WORKFLOW_COMMIT" "$G7_AUTHORITY_COMMIT" \
        "$G7_AUTHORITY_TREE_SHA256" "$G7_SHIPPER_SHA256" \
        "$G7_VERIFIER_SHA256" "$G7_PROVISIONER_SHA256" \
        "$owner_uid" "$owner_gid" "$directory_mode" \
        "$data_mode" "$executable_mode"
    /usr/bin/bash "$manifest_helper" assert-genesis \
        "$material_g1/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g1/release-authority-v2.json" \
        "$material_g2/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g2/release-authority-v2.json" \
        "$material_g3/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g3/release-authority-v2.json" \
        "$material_g4/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g4/release-authority-v2.json" \
        "$material_g5/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g5/release-authority-v2.json" \
        "$material_g6/release-authority-v2.json"
    /usr/bin/bash "$manifest_helper" assert-successor \
        "$material_g6/release-authority-v2.json" \
        "$material_g7/release-authority-v2.json"
}

validate_manifest_helper
validate_cosign
for source_dir in "$g1_dir" "$g2_dir" "$g3_dir" "$g4_dir" "$g5_dir" \
    "$g6_dir" "$g7_dir"; do
    validate_operator_parent_chain "$source_dir"
done
validate_release_chain \
    "$operator_uid" "$operator_gid" 500 400 500 \
    "$g1_dir" "$g2_dir" "$g3_dir" "$g4_dir" "$g5_dir" "$g6_dir" "$g7_dir"

if [[ $action == verify ]]; then
    printf 'G1-G2-G3-G4-G5-G6-G7 recovery chain verified: active_generation=7 manifest_sha256=%s\n' \
        "$G7_MANIFEST_SHA256"
    exit 0
fi

[[ $(tr -d '\r\n' </etc/hostname) == claudevm ]] \
    || die 'recovery may run only on claudevm'
[[ -d /home/sean && ! -L /home/sean ]] \
    || die 'canonical operator home is unsafe'
[[ $(stat -c '%u:%g' /home/sean) == "$operator_uid:$operator_gid" ]] \
    || die 'canonical operator identity differs'
[[ -d /etc/syntaur && ! -L /etc/syntaur ]] \
    || die '/etc/syntaur must be the exact pre-G1 directory'
[[ $(stat -c '%u:%g:%a' /etc/syntaur) == 0:0:755 ]] \
    || die '/etc/syntaur identity differs'

if [[ $action == install ]]; then
    [[ -f $genesis_evidence && ! -L $genesis_evidence ]] \
        || die 'Genesis evidence is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$genesis_evidence") == \
        "$operator_uid:$operator_gid:400:1" ]] \
        || die 'Genesis evidence identity differs'
    validate_operator_parent_chain "$genesis_evidence"
fi

create_exact_empty_lock() {
    local path=$1
    local owner=$2
    local group=$3
    local mode=$4
    local parent temporary
    parent=$(dirname "$path")
    [[ -d $parent && ! -L $parent ]] \
        || die "lock parent is unsafe: $parent"
    if [[ ! -e $path && ! -L $path ]]; then
        temporary=$(/usr/bin/mktemp "$parent/.syntaur-lock.XXXXXXXX")
        /usr/bin/install -o "$owner" -g "$group" -m "$mode" \
            /dev/null "$temporary"
        /usr/bin/sync -f "$temporary"
        /usr/bin/ln -- "$temporary" "$path" 2>/dev/null || true
        /usr/bin/rm -f -- "$temporary"
        /usr/bin/sync -f "$parent"
    fi
    [[ -f $path && ! -L $path ]] \
        || die "lock is unsafe: $path"
    [[ $(stat -c '%u:%g:%a:%s' "$path") == \
        "$owner:$group:$mode:0" ]] \
        || die "lock identity differs: $path"
    if [[ $(stat -c '%h' "$path") -gt 1 ]]; then
        local identity candidate
        identity=$(stat -c '%d:%i' "$path")
        while IFS= read -r -d '' candidate; do
            if [[ $(stat -c '%d:%i' "$candidate") == "$identity" ]]; then
                /usr/bin/rm -f -- "$candidate"
            fi
        done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 \
            -type f -name '.syntaur-lock.*' -print0)
    fi
    [[ $(stat -c '%h' "$path") == 1 ]] \
        || die "lock link count differs: $path"
}

prepare_locks() {
    [[ -f $GLOBAL_MUTATION_LOCK && ! -L $GLOBAL_MUTATION_LOCK ]] \
        || die 'the preexisting G1 global mutation lock is missing or unsafe'
    [[ $(stat -c '%u:%g:%a:%s' "$GLOBAL_MUTATION_LOCK") == \
        "0:$operator_gid:440:0" ]] \
        || die 'the preexisting G1 global mutation lock identity differs'
    if [[ $(stat -c '%h' "$GLOBAL_MUTATION_LOCK") -gt 1 ]]; then
        local identity candidate
        identity=$(stat -c '%d:%i' "$GLOBAL_MUTATION_LOCK")
        while IFS= read -r -d '' candidate; do
            if [[ $(stat -c '%d:%i' "$candidate") == "$identity" ]]; then
                /usr/bin/rm -f -- "$candidate"
            fi
        done < <(/usr/bin/find /etc/syntaur -mindepth 1 -maxdepth 1 \
            -type f -name '.syntaur-lock.*' -print0)
    fi
    [[ $(stat -c '%h' "$GLOBAL_MUTATION_LOCK") == 1 ]] \
        || die 'the preexisting G1 global mutation lock link count differs'
    create_exact_empty_lock "$BOOTSTRAP_LOCK" 0 0 600
    [[ -d /home/sean/.syntaur && ! -L /home/sean/.syntaur ]] \
        || die 'operator .syntaur directory is unsafe'
    [[ $(stat -c '%u:%g' /home/sean/.syntaur) == \
        "$operator_uid:$operator_gid" ]] \
        || die 'operator .syntaur identity differs'
    if [[ ! -e $OPERATOR_STATE && ! -L $OPERATOR_STATE ]]; then
        /usr/bin/install -d -o "$operator_uid" -g "$operator_gid" -m 0700 \
            "$OPERATOR_STATE"
    fi
    [[ -d $OPERATOR_STATE && ! -L $OPERATOR_STATE ]] \
        || die 'operator ship state is unsafe'
    [[ $(stat -c '%u:%g:%a' "$OPERATOR_STATE") == \
        "$operator_uid:$operator_gid:700" ]] \
        || die 'operator ship state identity differs'
    local local_lock="$OPERATOR_STATE/deploy.lock"
    if [[ ! -e $local_lock && ! -L $local_lock ]]; then
        /usr/bin/install -o "$operator_uid" -g "$operator_gid" -m 0600 \
            /dev/null "$local_lock"
    fi
    [[ -f $local_lock && ! -L $local_lock ]] \
        || die 'operator deployment lock is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$local_lock") == \
        "$operator_uid:$operator_gid:600:1" ]] \
        || die 'operator deployment lock identity differs'
    [[ $(stat -c '%s' "$local_lock") -le 32 ]] \
        || die 'operator deployment lock metadata is oversized'
}

prepare_locks
exec 7<"$GLOBAL_MUTATION_LOCK"
/usr/bin/flock -n 7 || die 'global mutation lock is held'
exec 8<>"$OPERATOR_STATE/deploy.lock"
/usr/bin/flock -n 8 || die 'operator deployment lock is held'
exec 9<>"$BOOTSTRAP_LOCK"
/usr/bin/flock -n 9 || die 'authority bootstrap lock is held'

snapshot=/run/syntaur-release-authority-g1-g2-g3-g4-g5-g6-g7-recovery.snapshot
if [[ -e $snapshot || -L $snapshot ]]; then
    [[ -d $snapshot && ! -L $snapshot ]] \
        || die 'stale recovery snapshot is unsafe'
    [[ $(stat -c '%u:%g:%a' "$snapshot") == 0:0:700 ]] \
        || die 'stale recovery snapshot identity differs'
    [[ $(find "$snapshot" -xdev -print | wc -l) -le 45 ]] \
        || die 'stale recovery snapshot exceeds its bound'
    /usr/bin/chmod -R u+rwX "$snapshot"
    /usr/bin/rm -rf --one-file-system -- "$snapshot"
fi
/usr/bin/install -d -o root -g root -m 0700 "$snapshot"
snapshot_helper="$snapshot/release-authority-manifest.sh"
snapshot_evidence="$snapshot/genesis-validation.json"
for generation in 1 2 3 4 5 6 7; do
    /usr/bin/install -d -o root -g root -m 0700 \
        "$snapshot/generation-$generation"
done

snapshot_file() {
    local source=$1
    local target=$2
    local mode=$3
    local maximum=$4
    /usr/bin/timeout 30 /usr/bin/dd \
        if="$source" of="$target" \
        iflag=nofollow,nonblock,fullblock,count_bytes \
        count="$((maximum + 1))" status=none
    [[ -f $target && ! -L $target ]] \
        || die "snapshot is not regular: $source"
    [[ $(stat -c '%s' "$target") -le $maximum ]] \
        || die "snapshot exceeds its bound: $source"
    /usr/bin/chown root:root "$target"
    /usr/bin/chmod "$mode" "$target"
    [[ $(stat -c '%u:%g:%a:%h' "$target") == "0:0:$mode:1" ]] \
        || die "snapshot identity differs: $source"
    /usr/bin/sync -f "$target"
}

snapshot_release() {
    local source_dir=$1
    local target_dir=$2
    snapshot_file "$source_dir/release-authority-v2.json" \
        "$target_dir/release-authority-v2.json" 400 1048576
    snapshot_file "$source_dir/release-authority-v2.json.cosign.bundle" \
        "$target_dir/release-authority-v2.json.cosign.bundle" 400 4194304
    snapshot_file "$source_dir/syntaur-build-authority-provision" \
        "$target_dir/syntaur-build-authority-provision" 500 16777216
    snapshot_file "$source_dir/syntaur-ship-linux-x86_64" \
        "$target_dir/syntaur-ship-linux-x86_64" 500 268435456
    snapshot_file "$source_dir/syntaur-verify-linux-x86_64" \
        "$target_dir/syntaur-verify-linux-x86_64" 500 268435456
}

snapshot_release "$g1_dir" "$snapshot/generation-1"
snapshot_release "$g2_dir" "$snapshot/generation-2"
snapshot_release "$g3_dir" "$snapshot/generation-3"
snapshot_release "$g4_dir" "$snapshot/generation-4"
snapshot_release "$g5_dir" "$snapshot/generation-5"
snapshot_release "$g6_dir" "$snapshot/generation-6"
snapshot_release "$g7_dir" "$snapshot/generation-7"
snapshot_file "$SOURCE_MANIFEST_HELPER" "$snapshot_helper" 500 1048576
if [[ $action == install ]]; then
    snapshot_file "$genesis_evidence" "$snapshot_evidence" 400 4194304
fi
/usr/bin/sync -f "$snapshot"

manifest_helper=$snapshot_helper
validate_manifest_helper
validate_release_chain \
    0 0 700 400 500 \
    "$snapshot/generation-1" \
    "$snapshot/generation-2" \
    "$snapshot/generation-3" \
    "$snapshot/generation-4" \
    "$snapshot/generation-5" \
    "$snapshot/generation-6" \
    "$snapshot/generation-7"

root_stage=/etc/syntaur/.release-authority.recovery-v5-g1-g2-g3-g4-g5-g6-g7
shipper_stage=/usr/local/bin/.syntaur-ship.recovery-v5-g1-g2-g3-g4-g5-g6-g7
provisioner_stage=/opt/.syntaur-build-authority-provision.recovery-v5-g7
validator_stage=/opt/.syntaur-genesis-validator.recovery-v5-g7

cleanup_transients() {
    local path
    for path in "$snapshot" "$shipper_stage" "$provisioner_stage" \
        "$validator_stage"; do
        if [[ -e $path && ! -L $path ]]; then
            /usr/bin/chmod -R u+rwX "$path" 2>/dev/null || true
            /usr/bin/rm -rf -- "$path"
        fi
    done
}
trap cleanup_transients EXIT

installed_executable_is_exact() {
    local path=$1
    local digest=$2
    local mode=${3:-755}
    [[ -f $path && ! -L $path ]] \
        && [[ $(stat -c '%u:%g:%a:%h' "$path") == "0:0:$mode:1" ]] \
        && [[ $(sha256_file "$path") == "$digest" ]]
}

install_exact_executable() {
    local source=$1
    local temporary=$2
    local destination=$3
    local digest=$4
    local mode=${5:-755}
    if [[ -e $temporary || -L $temporary ]]; then
        [[ -f $temporary && ! -L $temporary ]] \
            || die "executable stage is unsafe: $temporary"
        [[ $(stat -c '%u:%g:%a:%h' "$temporary") == "0:0:$mode:1" ]] \
            || die "executable stage identity differs: $temporary"
        [[ $(sha256_file "$temporary") == "$digest" ]] \
            || die "executable stage digest differs: $temporary"
    else
        /usr/bin/install -o root -g root -m "$mode" "$source" "$temporary"
    fi
    /usr/bin/sync -f "$temporary"
    /usr/bin/mv -Tf "$temporary" "$destination"
    /usr/bin/sync -f "$(dirname "$destination")"
    installed_executable_is_exact "$destination" "$digest" "$mode" \
        || die "installed executable differs: $destination"
}

validate_mac_material() {
    local public_sha256 fingerprint identity_report
    [[ -f $MAC_KNOWN_HOSTS && ! -L $MAC_KNOWN_HOSTS ]] \
        || die 'Mac known-hosts trust is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$MAC_KNOWN_HOSTS") == 0:0:444:1 ]] \
        || die 'Mac known-hosts identity differs'
    [[ $(sha256_file "$MAC_KNOWN_HOSTS") == "$MAC_KNOWN_HOSTS_SHA256" ]] \
        || die 'Mac known-hosts digest differs'
    [[ -f $MAC_IDENTITY && ! -L $MAC_IDENTITY ]] \
        || die 'Mac SSH identity is unsafe'
    [[ $(stat -c '%u:%g:%a:%h:%s' "$MAC_IDENTITY") == \
        "0:$operator_gid:440:1:$MAC_IDENTITY_SIZE" ]] \
        || die 'Mac SSH identity metadata differs'
    [[ $(sha256_file "$MAC_IDENTITY") == "$MAC_IDENTITY_SHA256" ]] \
        || die 'Mac SSH identity digest differs'
    identity_report=$(
        set -euo pipefail
        inspection=$(/usr/bin/mktemp \
            /run/.syntaur-mac-identity-inspection.XXXXXXXX)
        trap '/usr/bin/rm -f -- "$inspection"' EXIT
        /usr/bin/timeout 30 /usr/bin/dd \
            if="$MAC_IDENTITY" \
            of="$inspection" \
            iflag=nofollow,nonblock,fullblock,count_bytes \
            count="$((MAC_IDENTITY_SIZE + 1))" \
            status=none
        /usr/bin/chown root:root "$inspection"
        /usr/bin/chmod 0400 "$inspection"
        [[ $(sha256_file "$inspection") == "$MAC_IDENTITY_SHA256" ]]
        /usr/bin/ssh-keygen -y -f "$inspection" \
            | awk 'NF >= 2 {print $1, $2}' \
            | sha256sum \
            | awk '{print $1}'
        /usr/bin/ssh-keygen -lf "$inspection" | awk 'NR == 1 {print $2}'
    )
    public_sha256=$(sed -n '1p' <<<"$identity_report")
    [[ $public_sha256 == "$MAC_IDENTITY_PUBLIC_SHA256" ]] \
        || die 'Mac SSH identity public key differs'
    fingerprint=$(sed -n '2p' <<<"$identity_report")
    [[ $fingerprint == "$MAC_IDENTITY_FINGERPRINT" ]] \
        || die 'Mac SSH identity fingerprint differs'
}

validate_mac_material

if [[ $action == stage-g7-build-authority ]]; then
    provisioner_state=
    validator_state=
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'G7 staging requires the release root to remain absent'
    if installed_executable_is_exact \
        "$INSTALLED_PROVISIONER" "$G7_PROVISIONER_SHA256"; then
        provisioner_state=g7
    elif installed_executable_is_exact \
        "$INSTALLED_PROVISIONER" "$G6_PROVISIONER_SHA256"; then
        provisioner_state=g6
    else
        die 'installed provisioner is neither the exact G6 predecessor nor G7'
    fi
    if installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$G7_SHIPPER_SHA256"; then
        validator_state=g7
    elif installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$G6_SHIPPER_SHA256"; then
        validator_state=g6
    else
        die 'Genesis validator is neither the exact G6 predecessor nor G7'
    fi
    if [[ $provisioner_state == g6 ]]; then
        install_exact_executable \
            "$snapshot/generation-7/syntaur-build-authority-provision" \
            "$provisioner_stage" "$INSTALLED_PROVISIONER" \
            "$G7_PROVISIONER_SHA256"
    fi
    if [[ $validator_state == g6 ]]; then
        install_exact_executable \
            "$snapshot/generation-7/syntaur-ship-linux-x86_64" \
            "$validator_stage" "$GENESIS_VALIDATOR" \
            "$G7_SHIPPER_SHA256"
    fi
    [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'G7 staging published the release root'
    printf 'G7 Genesis tools staged: provisioner_sha256=%s validator_sha256=%s release_root=absent\n' \
        "$G7_PROVISIONER_SHA256" "$G7_SHIPPER_SHA256"
    exit 0
fi

validate_genesis_evidence() {
    local evidence=$1
    local expected_mode=${2:-400}
    local canonical shipper_size inventory_id inventory_manifest_sha256
    [[ -f $evidence && ! -L $evidence ]] \
        || die 'Genesis evidence snapshot is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$evidence") == "0:0:$expected_mode:1" ]] \
        || die 'Genesis evidence snapshot identity differs'
    [[ $(sha256_file "$evidence") == "$expected_genesis_evidence_sha256" ]] \
        || die 'Genesis evidence digest differs'
    [[ $(wc -l <"$evidence") -eq 1 ]] \
        || die 'Genesis evidence must contain exactly one record'
    canonical=$(jq -ce '.' "$evidence") \
        || die 'Genesis evidence is not valid JSON'
    [[ $(<"$evidence") == "$canonical" ]] \
        || die 'Genesis evidence is not compact canonical JSON'
    shipper_size=$(stat -c '%s' \
        "$snapshot/generation-7/syntaur-ship-linux-x86_64")
    inventory_id=$(
        {
            printf 'syntaur.genesis-baseline-inventory.v1\0'
            jq -cj '
              .baseline_inventory |
              {
                schema,
                contract_sha256,
                members:[.members[] | {id,path,sha256,size,kind,mode}]
              }
            ' "$evidence"
        } | sha256sum | awk '{print $1}'
    )
    inventory_manifest_sha256=$(
        {
            printf 'syntaur.genesis-baseline-inventory-manifest.v1\0'
            jq -cj '
              .baseline_inventory |
              {
                schema,
                contract_sha256,
                inventory_id,
                members:[.members[] | {id,path,sha256,size,kind,mode}]
              }
            ' "$evidence"
        } | sha256sum | awk '{print $1}'
    )
    jq -se \
        --arg version "$AUTHORITY_VERSION" \
        --arg source "$G7_AUTHORITY_COMMIT" \
        --arg source_tree "$G7_AUTHORITY_GIT_TREE" \
        --arg authority_parent_commit "$G6_AUTHORITY_COMMIT" \
        --arg authority_parent_tree "$G6_AUTHORITY_GIT_TREE" \
        --arg baseline_source "$BASELINE_RECONSTRUCTION_COMMIT" \
        --arg baseline_source_tree "$BASELINE_RECONSTRUCTION_GIT_TREE" \
        --arg engine "$ENGINE_COMMIT" \
        --arg engine_tree "$ENGINE_TREE" \
        --arg source_lock "$BASELINE_RECONSTRUCTION_CARGO_LOCK_SHA256" \
        --arg engine_lock "$ENGINE_CARGO_LOCK_SHA256" \
        --arg shipper "$G7_SHIPPER_SHA256" \
        --arg provisioner "$G7_PROVISIONER_SHA256" \
        --arg rustsec "$RUSTSEC_DB_COMMIT" \
        --arg rustsec_tree "$RUSTSEC_TREE_SHA256" \
        --arg usr_tree "$SYSTEM_USR_TREE_SHA256" \
        --arg tar_sha "$TAR_SHA256" \
        --arg inventory_id "$inventory_id" \
        --arg inventory_manifest_sha256 "$inventory_manifest_sha256" \
        --arg identity "$MAC_IDENTITY" \
        --arg identity_sha "$MAC_IDENTITY_SHA256" \
        --arg identity_public_sha "$MAC_IDENTITY_PUBLIC_SHA256" \
        --arg identity_fingerprint "$MAC_IDENTITY_FINGERPRINT" \
        --argjson source_epoch "$G7_SOURCE_DATE_EPOCH" \
        --argjson baseline_source_epoch \
            "$BASELINE_RECONSTRUCTION_SOURCE_DATE_EPOCH" \
        --argjson shipper_size "$shipper_size" \
        --slurpfile manifest \
            "$snapshot/generation-7/release-authority-v2.json" '
        def valid_utc_timestamp:
          type == "string" and
          test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,9})?Z$") and
          (try
            (sub("[.][0-9]{1,9}Z$"; "Z") |
              fromdateiso8601 | type == "number")
            catch false);
        length == 1 and
        (.[0] |
        keys_unsorted == [
          "schema","authorizing","completed_at","host","authority_version",
          "authority_source","authority_parent_commit",
          "authority_parent_tree","baseline_source","engine",
          "authority_source_date_epoch","baseline_source_date_epoch","baseline",
          "shipper","build_authority","reproducibility_builds",
          "baseline_inventory","baseline_inventory_manifest_sha256",
          "validation_artifacts","future_product_protocol",
          "mac_target","mac_gateway_url","mac_smoke",
          "persistent_authority","release_authority_root_absent"
        ] and
        .schema == "syntaur.genesis-validation.v3" and
        .authorizing == false and
        (.completed_at | valid_utc_timestamp) and
        .host == "claudevm" and
        .authority_version == $version and
        (.authority_source | keys_unsorted == [
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ]) and
        .authority_source.commit == $source and
        .authority_source.tree == $source_tree and
        (.authority_source.workspace |
          type == "string" and startswith("/")) and
        (.authority_source.export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.authority_source.sealed_export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        .authority_parent_commit == $authority_parent_commit and
        .authority_parent_tree == $authority_parent_tree and
        (.baseline_source | keys_unsorted == [
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ]) and
        .baseline_source.commit == $baseline_source and
        .baseline_source.tree == $baseline_source_tree and
        (.baseline_source.workspace |
          type == "string" and startswith("/")) and
        .baseline_source.workspace != .authority_source.workspace and
        (.baseline_source.export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.baseline_source.sealed_export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.engine | keys_unsorted == [
          "commit","tree","workspace","export_tree_sha256",
          "sealed_export_tree_sha256"
        ]) and
        .engine.commit == $engine and
        .engine.tree == $engine_tree and
        (.engine.workspace | type == "string" and startswith("/")) and
        .engine.workspace != .authority_source.workspace and
        .engine.workspace != .baseline_source.workspace and
        (.engine.export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        (.engine.sealed_export_tree_sha256 |
          test("^[0-9a-f]{64}$")) and
        .authority_source_date_epoch == $source_epoch and
        $source_epoch > 0 and
        .baseline_source_date_epoch == $baseline_source_epoch and
        $baseline_source_epoch > 0 and
        (.baseline | keys_unsorted == [
          "schema","product_parent_commit","product_parent_tree",
          "product_version","product_source_date_epoch","product_built_at",
          "build_tool_count","date_shim_sha256","git_shim_sha256",
          "engine_commit","engine_tree","member_count","contract_sha256",
          "authorizing"
        ]) and
        .baseline.schema == 1 and
        .baseline.product_parent_commit ==
          "b003360f63707d92fd0df1fd12384282f1c3004f" and
        .baseline.product_parent_tree ==
          "1bf740acd5a7223e98370f668148f01ebfb6eff8" and
        .baseline.product_version == "0.7.114" and
        .baseline.product_source_date_epoch == 1784316447 and
        .baseline.product_built_at == "2026-07-17T19:27:27Z" and
        .baseline.build_tool_count == 2 and
        .baseline.date_shim_sha256 ==
          "8006ad3b0a1eaf63a5d8e80c04e9c7c259a435fdf44c2cd698ac6efbc335abe9" and
        .baseline.git_shim_sha256 ==
          "872bbdd70036c8b3992fa1f404a29ef74483004ca4baec90be8b03f4ea12b5b0" and
        .baseline.engine_commit == $engine and
        .baseline.engine_tree == $engine_tree and
        .baseline.member_count == 5 and
        .baseline.contract_sha256 ==
          "d93f9e3022dc3494434373473f461e2b2b6fba2b238f9335a407a83cd5d5f40c" and
        .baseline.authorizing == false and
        (.shipper | keys_unsorted == [
          "schema","executable_sha256","executable_size","build_source_commit",
          "control_plane_sha256","build_toolchain_sha256",
          "build_rustflags_sha256","build_target","build_profile","clean_build"
        ]) and
        .shipper.schema == 1 and
        .shipper.executable_sha256 == $shipper and
        .shipper.executable_size == $shipper_size and
        .shipper.build_source_commit == $source and
        (.shipper.control_plane_sha256 | test("^[0-9a-f]{64}$")) and
        (.shipper.build_toolchain_sha256 | test("^[0-9a-f]{64}$")) and
        (.shipper.build_rustflags_sha256 | test("^[0-9a-f]{64}$")) and
        .shipper.build_target == "x86_64-unknown-linux-gnu" and
        .shipper.build_profile == "release" and
        .shipper.clean_build == true and
        (.build_authority | keys_unsorted == [
          "schema","platform_image_sha256","platform_manifest_sha256",
          "dependencies_image_sha256","dependencies_manifest_sha256",
          "source_image_sha256","source_manifest_sha256","source_commit",
          "source_version","source_date_epoch","source_tree_sha256",
          "source_cargo_lock_sha256","engine_commit","engine_tree_sha256",
          "engine_cargo_lock_sha256","rust_toolchain_tree_sha256",
          "cargo_vendor_tree_sha256","system_usr_tree_sha256","tar_sha256",
          "system_etc_tree_sha256","cargo_config_sha256","ort_cache_tree_sha256",
          "frame_sysroot_tree_sha256","rustsec_tree_sha256",
          "rustsec_provenance_schema","rustsec_db_remote","rustsec_db_ref",
          "rustsec_db_commit","cargo_audit_sha256","rustc_vv_sha256","host_target"
        ]) and
        .build_authority.schema == 4 and
        .build_authority.source_commit == $baseline_source and
        .build_authority.source_version == $version and
        .build_authority.source_date_epoch ==
          .baseline_source_date_epoch and
        .build_authority.source_tree_sha256 ==
          .baseline_source.export_tree_sha256 and
        .build_authority.source_cargo_lock_sha256 == $source_lock and
        .build_authority.engine_commit == $engine and
        .build_authority.engine_tree_sha256 == .engine.export_tree_sha256 and
        .build_authority.engine_cargo_lock_sha256 == $engine_lock and
        ([
          .build_authority.platform_image_sha256,
          .build_authority.platform_manifest_sha256,
          .build_authority.dependencies_image_sha256,
          .build_authority.dependencies_manifest_sha256,
          .build_authority.source_image_sha256,
          .build_authority.source_manifest_sha256,
          .build_authority.source_cargo_lock_sha256,
          .build_authority.engine_cargo_lock_sha256,
          .build_authority.rust_toolchain_tree_sha256,
          .build_authority.cargo_vendor_tree_sha256,
          .build_authority.system_usr_tree_sha256,
          .build_authority.tar_sha256,
          .build_authority.system_etc_tree_sha256,
          .build_authority.cargo_config_sha256,
          .build_authority.ort_cache_tree_sha256,
          .build_authority.frame_sysroot_tree_sha256,
          .build_authority.rustsec_tree_sha256,
          .build_authority.cargo_audit_sha256,
          .build_authority.rustc_vv_sha256
        ] | all(test("^[0-9a-f]{64}$"))) and
        .build_authority.rustsec_provenance_schema == 1 and
        .build_authority.rustsec_db_remote ==
          "https://github.com/RustSec/advisory-db.git" and
        .build_authority.rustsec_db_ref == "refs/heads/main" and
        .build_authority.rustsec_db_commit == $rustsec and
        .build_authority.rustsec_tree_sha256 == $rustsec_tree and
        .build_authority.system_usr_tree_sha256 == $usr_tree and
        .build_authority.tar_sha256 == $tar_sha and
        .build_authority.host_target == "x86_64-unknown-linux-gnu" and
        .reproducibility_builds == 2 and
        (.baseline_inventory | keys_unsorted == [
          "schema","contract_sha256","inventory_id","members"
        ]) and
        .baseline_inventory.schema == 1 and
        .baseline_inventory.contract_sha256 ==
          .baseline.contract_sha256 and
        .baseline_inventory.inventory_id == $inventory_id and
        (.baseline_inventory.members | type == "array" and length == 5) and
        ([.baseline_inventory.members[] |
          keys_unsorted == ["id","path","sha256","size","kind","mode"]] |
          all) and
        ([.baseline_inventory.members[] | {id,path,kind,mode}] == [
          {id:"rust-openclaw",path:"bin/rust-openclaw",kind:"binary",mode:365},
          {id:"mace",path:"bin/mace",kind:"binary",mode:365},
          {id:"syntaur_browser",path:"bin/syntaur_browser",kind:"binary",mode:365},
          {id:"runtime-compose",path:"runtime/docker-compose-prod.yml",kind:"config",mode:420},
          {id:"runtime-entrypoint",path:"runtime/entrypoint.sh",kind:"script",mode:365}
        ]) and
        ([.baseline_inventory.members[].sha256 |
          test("^[0-9a-f]{64}$")] | all) and
        ([.baseline_inventory.members[].size |
          type == "number" and . > 0 and . <= 1073741824 and floor == .] |
          all) and
        ([.baseline_inventory.members[] |
          select(.id == "runtime-compose")][0] |
          .size == 4817 and
          .sha256 ==
            "2ae3b178f3b0c6cbb539cf61547cc3b26e5030db6a2fe378e64498325ef95390") and
        ([.baseline_inventory.members[] |
          select(.id == "runtime-entrypoint")][0] |
          .size == 2913 and
          .sha256 ==
            "177fc537cf32a42836ba4309a2d24dfa06a99cc1669f9dbc92bc449b9ce1eb8e") and
        .baseline_inventory_manifest_sha256 ==
          $inventory_manifest_sha256 and
        (.validation_artifacts | type == "array" and length == 1) and
        ([.validation_artifacts[] |
          keys_unsorted == ["id","path","sha256","size"]] | all) and
        .validation_artifacts[0].id == "syntaur-isolation-tests" and
        .validation_artifacts[0].path ==
          "validation/syntaur-isolation-tests" and
        (.validation_artifacts[0].sha256 |
          test("^[0-9a-f]{64}$")) and
        (.validation_artifacts[0].size |
          type == "number" and . > 0 and . <= 1073741824 and floor == .) and
        (.future_product_protocol | keys_unsorted == [
          "schema","release_authority_manifest_schema","protocol"
        ]) and
        .future_product_protocol.schema ==
          "syntaur.future-product-protocol.v2" and
        .future_product_protocol.release_authority_manifest_schema == 2 and
        (.future_product_protocol.protocol | keys_unsorted == [
          "schema","provisioner_sha256","production_contract_sha256",
          "production_member_count","receipt_schema","build_authority_schema",
          "promotion_recovery_schema","promotion_recovery_sha256"
        ]) and
        .future_product_protocol.protocol.schema == 1 and
        .future_product_protocol.protocol.provisioner_sha256 == $provisioner and
        .future_product_protocol.protocol.provisioner_sha256 ==
          $manifest[0].provisioner_sha256 and
        .future_product_protocol.protocol.production_contract_sha256 ==
          $manifest[0].production_contract_sha256 and
        .future_product_protocol.protocol.production_member_count ==
          $manifest[0].production_member_count and
        .future_product_protocol.protocol.production_member_count == 12 and
        .future_product_protocol.protocol.receipt_schema ==
          $manifest[0].receipt_schema and
        .future_product_protocol.protocol.receipt_schema == 6 and
        .future_product_protocol.protocol.build_authority_schema ==
          $manifest[0].build_authority_schema and
        .future_product_protocol.protocol.build_authority_schema == 4 and
        .future_product_protocol.protocol.promotion_recovery_schema ==
          $manifest[0].promotion_recovery_schema and
        .future_product_protocol.protocol.promotion_recovery_schema == 1 and
        .future_product_protocol.protocol.promotion_recovery_sha256 ==
          $manifest[0].promotion_recovery_sha256 and
        .mac_target == "sean@192.168.1.58" and
        .mac_gateway_url == "http://192.168.1.58:18789" and
        (.mac_smoke | keys_unsorted == [
          "schema","completed_at","baseline_contract_sha256",
          "baseline_inventory_id","baseline_inventory_manifest_sha256",
          "staged_member_count","gateway_sha256","gateway_size",
          "gateway_version","gateway_source_commit","gateway_built_at",
          "mace_sha256","mace_size","browser_sha256","browser_size",
          "browser_engine_commit","browser_audit_passed","isolation_sha256",
          "isolation_size","isolation_version","ssh_known_hosts_path",
          "ssh_known_hosts_sha256","ssh_host_key_algorithm",
          "ssh_host_key_fingerprint","ssh_identity_path",
          "ssh_identity_sha256","ssh_identity_public_sha256",
          "ssh_identity_fingerprint",
          "exact_stage_shape_verified","canary_seconds"
        ]) and
        .mac_smoke.schema == "syntaur.genesis-baseline-mac-smoke.v1" and
        (.mac_smoke.completed_at | valid_utc_timestamp) and
        .mac_smoke.baseline_contract_sha256 ==
          .baseline.contract_sha256 and
        .mac_smoke.baseline_inventory_id ==
          .baseline_inventory.inventory_id and
        .mac_smoke.baseline_inventory_manifest_sha256 ==
          .baseline_inventory_manifest_sha256 and
        .mac_smoke.staged_member_count == 5 and
        .mac_smoke.gateway_sha256 ==
          .baseline_inventory.members[0].sha256 and
        .mac_smoke.gateway_size ==
          .baseline_inventory.members[0].size and
        .mac_smoke.gateway_version == .baseline.product_version and
        .mac_smoke.gateway_source_commit ==
          .baseline.product_parent_commit and
        .mac_smoke.gateway_built_at == .baseline.product_built_at and
        .mac_smoke.mace_sha256 ==
          .baseline_inventory.members[1].sha256 and
        .mac_smoke.mace_size ==
          .baseline_inventory.members[1].size and
        .mac_smoke.browser_sha256 ==
          .baseline_inventory.members[2].sha256 and
        .mac_smoke.browser_size ==
          .baseline_inventory.members[2].size and
        .mac_smoke.browser_engine_commit == .baseline.engine_commit and
        .mac_smoke.browser_audit_passed == true and
        .mac_smoke.isolation_sha256 ==
          .validation_artifacts[0].sha256 and
        .mac_smoke.isolation_size ==
          .validation_artifacts[0].size and
        .mac_smoke.isolation_version == .baseline.product_version and
        .mac_smoke.ssh_known_hosts_path ==
          "/etc/syntaur/mac-mini-known-hosts" and
        .mac_smoke.ssh_known_hosts_sha256 ==
          "2a703ea347e6abc8e423df92ba4e2592656cf64fee467083104565a69478b1c1" and
        .mac_smoke.ssh_host_key_algorithm == "ssh-ed25519" and
        .mac_smoke.ssh_host_key_fingerprint ==
          "SHA256:/SNqZRbZ8lcIPNZOvWRxvKDRgAtmYAEy4A4KX782ldU" and
        .mac_smoke.ssh_identity_path == $identity and
        .mac_smoke.ssh_identity_sha256 == $identity_sha and
        .mac_smoke.ssh_identity_public_sha256 == $identity_public_sha and
        .mac_smoke.ssh_identity_fingerprint == $identity_fingerprint and
        .mac_smoke.exact_stage_shape_verified == true and
        .mac_smoke.canary_seconds == 45 and
        (.persistent_authority | keys_unsorted == [
          "build_authority_root_preexisting","exact_catalog_preexisting",
          "global_mutation_lock_preexisting","installed_provisioner_sha256",
          "build_authority_root_present_after","exact_catalog_present_after",
          "global_mutation_lock_present_after"
        ]) and
        (.persistent_authority.build_authority_root_preexisting |
          type == "boolean") and
        (.persistent_authority.exact_catalog_preexisting |
          type == "boolean") and
        .persistent_authority.global_mutation_lock_preexisting == true and
        .persistent_authority.installed_provisioner_sha256 == $provisioner and
        .persistent_authority.build_authority_root_present_after == true and
        .persistent_authority.exact_catalog_present_after == true and
        .persistent_authority.global_mutation_lock_present_after == true and
        .release_authority_root_absent == true
        )
        ' "$evidence" >/dev/null \
        || die 'Genesis evidence does not satisfy the exact G7/G2 contract'
}

validate_persistent_build_authority() {
    local evidence=$1
    local root=/opt/syntaur-build-authority
    local catalog canonical rows image_digest manifest_digest relative
    local image manifest
    [[ -d $root && ! -L $root ]] \
        || die 'persistent build-authority root is unsafe'
    [[ $(stat -c '%u:%g:%a' "$root") == "0:$operator_gid:750" ]] \
        || die 'persistent build-authority root identity differs'
    catalog="$root/catalog/$BASELINE_RECONSTRUCTION_COMMIT-$ENGINE_COMMIT.json"
    [[ -f $catalog && ! -L $catalog ]] \
        || die 'exact G2 reconstruction persistent catalog is missing'
    [[ $(stat -c '%u:%g:%a:%h' "$catalog") == \
        "0:$operator_gid:440:1" ]] \
        || die 'exact G2 reconstruction persistent catalog identity differs'
    [[ $(stat -c '%s' "$catalog") -gt 0 \
        && $(stat -c '%s' "$catalog") -le 65536 ]] \
        || die 'exact G2 reconstruction persistent catalog size is invalid'
    [[ $(wc -l <"$catalog") -eq 1 ]] \
        || die 'persistent catalog must contain exactly one record'
    canonical=$(jq -ce '.' "$catalog") \
        || die 'persistent catalog is not valid JSON'
    [[ $(<"$catalog") == "$canonical" ]] \
        || die 'persistent catalog is not canonical JSON'
    jq -se --slurpfile evidence "$evidence" '
      length == 1 and
      (.[0] |
      keys_unsorted == [
        "schema","source_commit","engine_commit","rustsec_provenance_schema",
        "rustsec_db_remote","rustsec_db_ref","rustsec_db_commit",
        "platform_image_sha256","platform_manifest_sha256",
        "dependencies_image_sha256","dependencies_manifest_sha256",
        "source_image_sha256","source_manifest_sha256"
      ] and
      .schema == $evidence[0].build_authority.schema and
      .source_commit == $evidence[0].build_authority.source_commit and
      .engine_commit == $evidence[0].build_authority.engine_commit and
      .rustsec_provenance_schema ==
        $evidence[0].build_authority.rustsec_provenance_schema and
      .rustsec_db_remote == $evidence[0].build_authority.rustsec_db_remote and
      .rustsec_db_ref == $evidence[0].build_authority.rustsec_db_ref and
      .rustsec_db_commit == $evidence[0].build_authority.rustsec_db_commit and
      .platform_image_sha256 ==
        $evidence[0].build_authority.platform_image_sha256 and
      .platform_manifest_sha256 ==
        $evidence[0].build_authority.platform_manifest_sha256 and
      .dependencies_image_sha256 ==
        $evidence[0].build_authority.dependencies_image_sha256 and
      .dependencies_manifest_sha256 ==
        $evidence[0].build_authority.dependencies_manifest_sha256 and
      .source_image_sha256 ==
        $evidence[0].build_authority.source_image_sha256 and
      .source_manifest_sha256 ==
        $evidence[0].build_authority.source_manifest_sha256
      )
    ' "$catalog" >/dev/null \
        || die 'persistent catalog differs from Genesis evidence'
    rows=$(jq -er '
      [
        [.platform_image_sha256,.platform_manifest_sha256,
          "opt/authority/manifests/platform.json"],
        [.dependencies_image_sha256,.dependencies_manifest_sha256,
          "opt/authority/manifests/dependencies.json"],
        [.source_image_sha256,.source_manifest_sha256,
          "opt/authority/manifests/source.json"]
      ][] | @tsv
    ' "$catalog")
    while IFS=$'\t' read -r image_digest manifest_digest relative; do
        image="$root/images/$image_digest.squashfs"
        manifest="$root/mounts/$image_digest/$relative"
        [[ -f $image && ! -L $image ]] \
            || die "persistent image is unsafe: $image_digest"
        [[ $(stat -c '%u:%g:%a:%h' "$image") == \
            "0:$operator_gid:440:1" ]] \
            || die "persistent image identity differs: $image_digest"
        [[ $(sha256_file "$image") == "$image_digest" ]] \
            || die "persistent image digest differs: $image_digest"
        [[ -f $manifest && ! -L $manifest ]] \
            || die "persistent manifest is unavailable: $image_digest"
        [[ $(sha256_file "$manifest") == "$manifest_digest" ]] \
            || die "persistent manifest digest differs: $image_digest"
    done <<<"$rows"
}

genesis_receipt_json() {
    jq -cn \
        --arg authority_commit "$G7_AUTHORITY_COMMIT" \
        --arg manifest_sha256 "$G7_MANIFEST_SHA256" \
        --arg evidence_sha256 "$expected_genesis_evidence_sha256" \
        --arg engine_commit "$ENGINE_COMMIT" \
        --arg rustsec_commit "$RUSTSEC_DB_COMMIT" \
        --arg shipper_sha256 "$G7_SHIPPER_SHA256" \
        --arg provisioner_sha256 "$G7_PROVISIONER_SHA256" \
        '{
          schema:"syntaur.genesis-install-receipt.v1",
          authority_commit:$authority_commit,
          manifest_sha256:$manifest_sha256,
          genesis_evidence_sha256:$evidence_sha256,
          engine_commit:$engine_commit,
          rustsec_db_commit:$rustsec_commit,
          shipper_sha256:$shipper_sha256,
          provisioner_sha256:$provisioner_sha256
        }'
}

validate_genesis_receipt() {
    local receipt=$1
    local canonical expected
    [[ -f $receipt && ! -L $receipt ]] \
        || die 'Genesis receipt is unsafe'
    [[ $(stat -c '%u:%g:%a:%h' "$receipt") == 0:0:444:1 ]] \
        || die 'Genesis receipt identity differs'
    [[ $(wc -l <"$receipt") -eq 1 ]] \
        || die 'Genesis receipt must contain exactly one record'
    canonical=$(jq -ce '.' "$receipt") \
        || die 'Genesis receipt is not valid JSON'
    [[ $(<"$receipt") == "$canonical" ]] \
        || die 'Genesis receipt is not canonical JSON'
    expected=$(genesis_receipt_json)
    [[ $canonical == "$expected" ]] \
        || die 'Genesis receipt differs from the G7 independent record'
}

validate_generation_directory() {
    local generation=$1
    local material=$2
    local directory="$AUTHORITY_ROOT/release-authority/generation-$generation"
    local workflow name actual expected
    case $generation in
        1) workflow=$G1_WORKFLOW_COMMIT ;;
        2) workflow=$G2_WORKFLOW_COMMIT ;;
        3) workflow=$G3_WORKFLOW_COMMIT ;;
        4) workflow=$G4_WORKFLOW_COMMIT ;;
        5) workflow=$G5_WORKFLOW_COMMIT ;;
        6) workflow=$G6_WORKFLOW_COMMIT ;;
        7) workflow=$G7_WORKFLOW_COMMIT ;;
        *) die 'invalid installed authority generation' ;;
    esac
    [[ -d $directory && ! -L $directory ]] \
        || die "installed generation directory is unsafe: $generation"
    [[ $(stat -c '%u:%g:%a' "$directory") == 0:0:555 ]] \
        || die "installed generation directory identity differs: $generation"
    expected=$(printf '%s\n' \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64 \
        trusted-workflow-commit | LC_ALL=C sort)
    actual=$(find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual == "$expected" ]] \
        || die "installed generation file set differs: $generation"
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle trusted-workflow-commit; do
        [[ -f $directory/$name && ! -L $directory/$name ]] \
            || die "installed generation data is unsafe: $generation $name"
        [[ $(stat -c '%u:%g:%a:%h' "$directory/$name") == 0:0:444:1 ]] \
            || die "installed generation data identity differs: $generation $name"
    done
    for name in syntaur-build-authority-provision \
        syntaur-ship-linux-x86_64 syntaur-verify-linux-x86_64; do
        [[ -f $directory/$name && ! -L $directory/$name ]] \
            || die "installed generation executable is unsafe: $generation $name"
        [[ $(stat -c '%u:%g:%a:%h' "$directory/$name") == 0:0:555:1 ]] \
            || die "installed generation executable identity differs: $generation $name"
    done
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        syntaur-build-authority-provision syntaur-ship-linux-x86_64 \
        syntaur-verify-linux-x86_64; do
        /usr/bin/cmp -s "$directory/$name" "$material/$name" \
            || die "installed generation bytes differ: $generation $name"
    done
    [[ $(wc -l <"$directory/trusted-workflow-commit") -eq 1 \
        && $(<"$directory/trusted-workflow-commit") == "$workflow" ]] \
        || die "installed workflow trust differs: $generation"
}

validate_installed_layout() {
    local actual expected name
    [[ -d $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'installed authority root is unsafe'
    [[ $(stat -c '%u:%g:%a' "$AUTHORITY_ROOT") == 0:0:755 ]] \
        || die 'installed authority root identity differs'
    expected=$(printf '%s\n' genesis release-authority \
        release-authority-v2.json \
        release-authority-v2.json.cosign.bundle \
        trusted-workflow-commit | LC_ALL=C sort)
    actual=$(find "$AUTHORITY_ROOT" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | LC_ALL=C sort)
    [[ $actual == "$expected" ]] \
        || die 'installed authority root file set differs'
    [[ -d $AUTHORITY_ROOT/genesis && ! -L $AUTHORITY_ROOT/genesis \
        && $(stat -c '%u:%g:%a' "$AUTHORITY_ROOT/genesis") == 0:0:555 ]] \
        || die 'installed Genesis directory identity differs'
    expected=$(printf '%s\n' genesis-install-receipt-v1.json \
        genesis-validation.json | LC_ALL=C sort)
    actual=$(find "$AUTHORITY_ROOT/genesis" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)
    [[ $actual == "$expected" ]] \
        || die 'installed Genesis file set differs'
    for name in genesis-validation.json genesis-install-receipt-v1.json; do
        [[ -f $AUTHORITY_ROOT/genesis/$name \
            && ! -L $AUTHORITY_ROOT/genesis/$name \
            && $(stat -c '%u:%g:%a:%h' \
                "$AUTHORITY_ROOT/genesis/$name") == 0:0:444:1 ]] \
            || die "installed Genesis proof is unsafe: $name"
    done
    [[ -d $AUTHORITY_ROOT/release-authority \
        && ! -L $AUTHORITY_ROOT/release-authority \
        && $(stat -c '%u:%g:%a' \
            "$AUTHORITY_ROOT/release-authority") == 0:0:755 ]] \
        || die 'installed generation parent identity differs'
    expected=$(printf '%s\n' \
        generation-1 generation-2 generation-3 generation-4 generation-5 \
        generation-6 generation-7 \
        | LC_ALL=C sort)
    actual=$(find "$AUTHORITY_ROOT/release-authority" \
        -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
    [[ $actual == "$expected" ]] \
        || die 'installed generation set differs'
    validate_generation_directory 1 "$snapshot/generation-1"
    validate_generation_directory 2 "$snapshot/generation-2"
    validate_generation_directory 3 "$snapshot/generation-3"
    validate_generation_directory 4 "$snapshot/generation-4"
    validate_generation_directory 5 "$snapshot/generation-5"
    validate_generation_directory 6 "$snapshot/generation-6"
    validate_generation_directory 7 "$snapshot/generation-7"
    for name in release-authority-v2.json \
        release-authority-v2.json.cosign.bundle trusted-workflow-commit; do
        [[ -f $AUTHORITY_ROOT/$name && ! -L $AUTHORITY_ROOT/$name \
            && $(stat -c '%u:%g:%a:%h' "$AUTHORITY_ROOT/$name") == \
                0:0:444:1 ]] \
            || die "installed active authority data is unsafe: $name"
        /usr/bin/cmp -s "$AUTHORITY_ROOT/$name" \
            "$AUTHORITY_ROOT/release-authority/generation-7/$name" \
            || die "installed active authority copy differs: $name"
    done
    validate_genesis_evidence \
        "$AUTHORITY_ROOT/genesis/genesis-validation.json" 444
    validate_genesis_receipt \
        "$AUTHORITY_ROOT/genesis/genesis-install-receipt-v1.json"
    validate_persistent_build_authority \
        "$AUTHORITY_ROOT/genesis/genesis-validation.json"
}

preflight_live_shipper() {
    local authority_root_exists=$1
    if [[ $authority_root_exists == true ]] \
        && installed_executable_is_exact \
            "$INSTALLED_SHIPPER" "$G7_SHIPPER_SHA256" 1755; then
        return
    fi
    installed_executable_is_exact \
        "$INSTALLED_SHIPPER" "$expected_current_shipper_sha256" \
        || die 'current shipper differs from the independent CAS predecessor'
}

run_operator_authority_status() {
    (
        exec 7>&- 8>&- 9>&-
        if [[ $operator_uid == 0 && $operator_gid == 0 ]]; then
            exec /usr/bin/env -i \
                HOME=/home/sean \
                USER=sean \
                LOGNAME=sean \
                PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=C.UTF-8 \
                LC_ALL=C.UTF-8 \
                SYNTAUR_BOOTSTRAP_SINGLE_UID_FIXTURE=1 \
                "$INSTALLED_SHIPPER" authority-status
        fi
        exec /usr/bin/setpriv \
            --reuid "$operator_uid" \
            --regid "$operator_gid" \
            --clear-groups \
            /usr/bin/env -i \
                HOME=/home/sean \
                USER=sean \
                LOGNAME=sean \
                PATH=/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=C.UTF-8 \
                LC_ALL=C.UTF-8 \
                "$INSTALLED_SHIPPER" authority-status
    )
}

remove_exact_genesis_validator() {
    if [[ ! -e $GENESIS_VALIDATOR && ! -L $GENESIS_VALIDATOR ]]; then
        return
    fi
    installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$G7_SHIPPER_SHA256" \
        || die 'G7 Genesis validator changed before retirement'
    /usr/bin/rm -f -- "$GENESIS_VALIDATOR"
    /usr/bin/sync -f /opt
}

validate_genesis_evidence "$snapshot_evidence"
validate_persistent_build_authority "$snapshot_evidence"
validate_mac_material
installed_executable_is_exact \
    "$INSTALLED_PROVISIONER" "$G7_PROVISIONER_SHA256" \
    || die 'install requires the exact staged G7 provisioner'
if [[ ! -e $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]]; then
    installed_executable_is_exact \
        "$GENESIS_VALIDATOR" "$G7_SHIPPER_SHA256" \
        || die 'install requires the exact staged G7 Genesis validator'
fi

authority_root_exists=false
if [[ -e $AUTHORITY_ROOT || -L $AUTHORITY_ROOT ]]; then
    [[ -d $AUTHORITY_ROOT && ! -L $AUTHORITY_ROOT ]] \
        || die 'existing authority root is unsafe'
    [[ $(sha256_file "$AUTHORITY_ROOT/release-authority-v2.json") == \
        "$G7_MANIFEST_SHA256" ]] \
        || die 'a different authority root already exists'
    validate_installed_layout
    authority_root_exists=true
fi
preflight_live_shipper "$authority_root_exists"

if [[ $authority_root_exists == false ]]; then
    if [[ -e $root_stage || -L $root_stage ]]; then
        [[ -d $root_stage && ! -L $root_stage \
            && $(stat -c '%u:%g' "$root_stage") == 0:0 ]] \
            || die 'stale recovery root stage is unsafe'
        /usr/bin/chmod -R u+rwX "$root_stage"
        /usr/bin/rm -rf -- "$root_stage"
    fi
    /usr/bin/install -d -o root -g root -m 0755 \
        "$root_stage" \
        "$root_stage/release-authority" \
        "$root_stage/genesis"
    /usr/bin/install -o root -g root -m 0444 \
        "$snapshot_evidence" \
        "$root_stage/genesis/genesis-validation.json"
    genesis_receipt_json \
        >"$root_stage/genesis/genesis-install-receipt-v1.json"
    /usr/bin/chown root:root \
        "$root_stage/genesis/genesis-install-receipt-v1.json"
    /usr/bin/chmod 0444 \
        "$root_stage/genesis/genesis-install-receipt-v1.json"
    /usr/bin/chmod 0555 "$root_stage/genesis"

    for generation in 1 2 3 4 5 6 7; do
        generation_dir="$root_stage/release-authority/generation-$generation"
        material="$snapshot/generation-$generation"
        case $generation in
            1) workflow=$G1_WORKFLOW_COMMIT ;;
            2) workflow=$G2_WORKFLOW_COMMIT ;;
            3) workflow=$G3_WORKFLOW_COMMIT ;;
            4) workflow=$G4_WORKFLOW_COMMIT ;;
            5) workflow=$G5_WORKFLOW_COMMIT ;;
            6) workflow=$G6_WORKFLOW_COMMIT ;;
            7) workflow=$G7_WORKFLOW_COMMIT ;;
        esac
        /usr/bin/install -d -o root -g root -m 0755 "$generation_dir"
        /usr/bin/install -o root -g root -m 0444 \
            "$material/release-authority-v2.json" \
            "$material/release-authority-v2.json.cosign.bundle" \
            "$generation_dir/"
        printf '%s\n' "$workflow" \
            >"$generation_dir/trusted-workflow-commit"
        /usr/bin/chown root:root \
            "$generation_dir/trusted-workflow-commit"
        /usr/bin/chmod 0444 \
            "$generation_dir/trusted-workflow-commit"
        /usr/bin/install -o root -g root -m 0555 \
            "$material/syntaur-build-authority-provision" \
            "$material/syntaur-ship-linux-x86_64" \
            "$material/syntaur-verify-linux-x86_64" \
            "$generation_dir/"
        /usr/bin/chmod 0555 "$generation_dir"
    done
    /usr/bin/install -o root -g root -m 0444 \
        "$snapshot/generation-7/release-authority-v2.json" \
        "$root_stage/release-authority-v2.json"
    /usr/bin/install -o root -g root -m 0444 \
        "$snapshot/generation-7/release-authority-v2.json.cosign.bundle" \
        "$root_stage/release-authority-v2.json.cosign.bundle"
    printf '%s\n' "$G7_WORKFLOW_COMMIT" \
        >"$root_stage/trusted-workflow-commit"
    /usr/bin/chown root:root "$root_stage/trusted-workflow-commit"
    /usr/bin/chmod 0444 "$root_stage/trusted-workflow-commit"

    while IFS= read -r path; do
        /usr/bin/sync -f "$path"
    done < <(/usr/bin/find "$root_stage" -depth -print)
    /usr/bin/sync -f /etc/syntaur
    /usr/bin/mv -T "$root_stage" "$AUTHORITY_ROOT"
    /usr/bin/sync -f /etc/syntaur
    validate_installed_layout
fi

if ! installed_executable_is_exact \
    "$INSTALLED_SHIPPER" "$G7_SHIPPER_SHA256" 1755; then
    install_exact_executable \
        "$snapshot/generation-7/syntaur-ship-linux-x86_64" \
        "$shipper_stage" "$INSTALLED_SHIPPER" "$G7_SHIPPER_SHA256" 1755
fi
installed_executable_is_exact \
    "$INSTALLED_PROVISIONER" "$G7_PROVISIONER_SHA256" \
    || die 'active G7 provisioner differs'
run_operator_authority_status
remove_exact_genesis_validator
printf 'G1-G2-G3-G4-G5-G6-G7 authority recovery installed: active_generation=7 manifest_sha256=%s\n' \
    "$G7_MANIFEST_SHA256"
