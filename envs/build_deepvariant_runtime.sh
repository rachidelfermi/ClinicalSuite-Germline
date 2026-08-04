#!/usr/bin/env bash
# Package the official DeepVariant CPU runtime as a relocatable Conda artifact.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly VERSION=1.10.0
readonly BUILD=0
readonly OCI_DIGEST=962e5a83b1d76aae6990625d47102785f791603f2138aa1fa9aa4fb6a2eecbe6
readonly EXPECTED_SIF_SHA256=1f50ff9cf9739770246e7b4461fe73939e7d81b2be5d958cce2948955a0e0f47
readonly SQUASHFS_OFFSET=40960
readonly WORK_DIR="$SCRIPT_DIR/.build/deepvariant-runtime"
readonly PACKAGE="$SCRIPT_DIR/.build/clinicalsuite-deepvariant-runtime-$VERSION-$BUILD.tar.bz2"
DEEPVARIANT_SIF="${DEEPVARIANT_SIF:-$SCRIPT_DIR/../containers/deepvariant.sif}"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

write_wrapper() {
    local name="$1"
    {
        printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n'
        printf 'prefix="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"\n'
        printf 'exec "$prefix/bin/python" "$prefix/share/clinicalsuite-deepvariant-runtime-%s/%s.zip" "$@"\n' \
            "$VERSION" "$name"
    } >"$WORK_DIR/package/bin/$name"
    chmod 0755 "$WORK_DIR/package/bin/$name"
}

main() {
    local source_dir package_dir share_dir name actual_sha256
    local -a binaries=(
        make_examples call_variants postprocess_variants vcf_stats_report
        runtime_by_region_vis
    )

    [[ -r "$DEEPVARIANT_SIF" ]] || die "official DeepVariant source SIF is missing: $DEEPVARIANT_SIF"
    command -v unsquashfs >/dev/null 2>&1 ||
        die 'unsquashfs is required on the development packaging host'
    actual_sha256="$(sha256sum "$DEEPVARIANT_SIF" | awk '{print $1}')"
    [[ "$actual_sha256" == "$EXPECTED_SIF_SHA256" ]] ||
        die 'DeepVariant source SIF checksum mismatch'

    rm -rf -- "$WORK_DIR"
    source_dir="$WORK_DIR/source"
    package_dir="$WORK_DIR/package"
    share_dir="$package_dir/share/clinicalsuite-deepvariant-runtime-$VERSION"
    mkdir -p -- "$source_dir" "$package_dir/bin" "$share_dir" "$package_dir/info"
    for name in run_deepvariant.py \
        make_examples.zip call_variants.zip postprocess_variants.zip \
        vcf_stats_report.zip runtime_by_region_vis.zip; do
        unsquashfs -o "$SQUASHFS_OFFSET" -cat "$DEEPVARIANT_SIF" \
            "opt/deepvariant/bin/$name" >"$source_dir/$name"
    done

    cp -- "$source_dir"/*.zip "$share_dir/"
    cp -- "$source_dir/run_deepvariant.py" "$share_dir/"
    # Only launcher paths are made relocatable; the official executable ZIPs
    # remain byte-for-byte unchanged and models stay external.
    sed -i \
        -e '/import tempfile/a DEEPVARIANT_BIN_DIR = os.path.dirname(os.path.realpath(__file__))' \
        -e "s#'/opt/deepvariant/bin/make_examples'#os.path.join(DEEPVARIANT_BIN_DIR, 'make_examples')#" \
        -e "s#f'/opt/deepvariant/bin/{binary_name}'#os.path.join(DEEPVARIANT_BIN_DIR, binary_name)#" \
        -e "s#'/opt/deepvariant/bin/postprocess_variants'#os.path.join(DEEPVARIANT_BIN_DIR, 'postprocess_variants')#" \
        -e "s#'/opt/deepvariant/bin/vcf_stats_report'#os.path.join(DEEPVARIANT_BIN_DIR, 'vcf_stats_report')#" \
        -e "s#'/opt/deepvariant/bin/runtime_by_region_vis'#os.path.join(DEEPVARIANT_BIN_DIR, 'runtime_by_region_vis')#" \
        "$share_dir/run_deepvariant.py"

    for name in "${binaries[@]}"; do write_wrapper "$name"; done
    {
        printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n'
        printf 'prefix="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"\n'
        printf 'exec "$prefix/bin/python" -u "$prefix/share/clinicalsuite-deepvariant-runtime-%s/run_deepvariant.py" "$@"\n' \
            "$VERSION"
    } >"$package_dir/bin/run_deepvariant"
    chmod 0755 "$package_dir/bin/run_deepvariant"

    {
        printf '{\n'
        printf '  "name": "clinicalsuite-deepvariant-runtime",\n'
        printf '  "version": "%s",\n' "$VERSION"
        printf '  "build": "%s", "build_number": %s,\n' "$BUILD" "$BUILD"
        printf '  "subdir": "linux-64", "arch": "x86_64", "platform": "linux",\n'
        printf '  "depends": ["deepvariant 1.10.0"]\n}\n'
    } >"$package_dir/info/index.json"
    (cd -- "$package_dir" && find bin share -type f -printf '%p\n' | sort >info/files)
    mkdir -p -- "$(dirname -- "$PACKAGE")"
    (cd -- "$package_dir" && tar -cjf "$PACKAGE" info bin share)
    printf '%s\n' "$PACKAGE"
    printf '%s  google/deepvariant@sha256:%s\n' "$EXPECTED_SIF_SHA256" "$OCI_DIGEST" \
        >"$SCRIPT_DIR/.build/deepvariant-runtime-source.sha256"
}

main "$@"
