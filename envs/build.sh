#!/usr/bin/env bash
# Build, validate, lock, and pack ClinicalSuite Conda environments with Mamba.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
# shellcheck source=envs/lib.sh
source "$SCRIPT_DIR/lib.sh"

MAMBA_BIN="${MAMBA_BIN:-$(command -v mamba 2>/dev/null || true)}"
CONDA_PACK_BIN="${CONDA_PACK_BIN:-$(command -v conda-pack 2>/dev/null || true)}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

environment_specs() {
    awk '
        /^dependencies:/ {in_dependencies=1; next}
        in_dependencies && /^  - [A-Za-z0-9_.-]+=/ {
            sub(/^  - /, ""); print
        }
    ' "$1"
}

build_environment() {
    local environment="$1" prefix="$SCRIPT_DIR/$environment"
    local spec_file="$SCRIPT_DIR/$environment.yml"
    local -a packages=()

    [[ -r "$spec_file" ]] || die "missing environment specification: $spec_file"
    mapfile -t packages < <(environment_specs "$spec_file")
    (( ${#packages[@]} > 0 )) || die "no pinned packages in $spec_file"
    if [[ -d "$prefix/conda-meta" ]]; then
        printf 'REPAIR: %s\n' "$environment"
        "$MAMBA_BIN" install --yes --prefix "$prefix" --strict-channel-priority \
            --override-channels \
            --channel conda-forge --channel bioconda "${packages[@]}"
    else
        [[ ! -e "$prefix" ]] || die "partial environment path is not repairable: $prefix"
        printf 'CREATE: %s\n' "$environment"
        "$MAMBA_BIN" create --yes --prefix "$prefix" --strict-channel-priority \
            --override-channels \
            --channel conda-forge --channel bioconda "${packages[@]}"
    fi
    if [[ "$environment" == deepvariant ]]; then
        local runtime_package
        runtime_package="$("$SCRIPT_DIR/build_deepvariant_runtime.sh")"
        "$MAMBA_BIN" install --yes --prefix "$prefix" --override-channels \
            --strict-channel-priority --channel conda-forge --channel bioconda \
            "$runtime_package"
    fi
}

freeze_environment() {
    local environment="$1" prefix="$SCRIPT_DIR/$environment"
    local lock_temp="$SCRIPT_DIR/.$environment.lock.tmp.$$"
    local yml_temp="$SCRIPT_DIR/.$environment.yml.tmp.$$"

    "$MAMBA_BIN" list --explicit --prefix "$prefix" >"$lock_temp"
    "$MAMBA_BIN" env export --prefix "$prefix" --no-builds |
        awk '$1 != "prefix:"' >"$yml_temp"
    mv -- "$lock_temp" "$SCRIPT_DIR/$environment.lock"
    mv -- "$yml_temp" "$SCRIPT_DIR/$environment.yml"
}

pack_environment() {
    local environment="$1" prefix="$SCRIPT_DIR/$environment"
    local archive="$SCRIPT_DIR/$environment.tar.gz"
    local temporary="$SCRIPT_DIR/.$environment.tar.gz.tmp.$$"

    rm -f -- "$temporary"
    "$CONDA_PACK_BIN" --prefix "$prefix" --output "$temporary" --force
    mv -- "$temporary" "$archive"
}

write_archive_checksums() {
    local environment
    (
        cd -- "$SCRIPT_DIR"
        for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
            sha256sum "$environment.tar.gz"
        done
    ) >"$SCRIPT_DIR/archive_checksums.sha256"
}

main() {
    local environment conda_pack_version conda_pack_major conda_pack_minor
    local -a selected=("${CLINICAL_ENVIRONMENTS[@]}")

    [[ -x "$MAMBA_BIN" ]] || die 'MAMBA_BIN must identify an executable Mamba'
    [[ -x "$CONDA_PACK_BIN" ]] || die 'CONDA_PACK_BIN must identify conda-pack'
    conda_pack_version="$("$CONDA_PACK_BIN" --version 2>/dev/null | awk '{print $2}')"
    [[ "$conda_pack_version" =~ ^([0-9]+)\.([0-9]+) ]] ||
        die 'cannot determine conda-pack version'
    conda_pack_major="${BASH_REMATCH[1]}"
    conda_pack_minor="${BASH_REMATCH[2]}"
    (( conda_pack_major > 0 || conda_pack_minor >= 8 )) ||
        die 'conda-pack 0.8 or newer is required'
    if (( $# > 0 )); then
        selected=("$@")
    fi
    for environment in "${selected[@]}"; do
        clinical_environment_first_module "$environment" >/dev/null ||
            die "unknown environment: $environment"
        build_environment "$environment"
    done

    # Locking and packing are deliberately gated behind complete validation.
    MAMBA_BIN="$MAMBA_BIN" "$SCRIPT_DIR/validate.sh"
    for environment in "${selected[@]}"; do
        freeze_environment "$environment"
        pack_environment "$environment"
    done
    if (( ${#selected[@]} == ${#CLINICAL_ENVIRONMENTS[@]} )); then
        write_archive_checksums
    fi
    printf 'PASS: validated, locked, and packed environments: %s\n' "${selected[*]}"
}

main "$@"
