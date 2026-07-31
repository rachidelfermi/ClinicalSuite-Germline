#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

readonly PROGRAM_NAME="${0##*/}"
readonly EX_USAGE=64
readonly EX_UNAVAILABLE=69
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly PREFLIGHT_SCRIPT="$SCRIPT_DIR/bin/preflight.sh"
readonly QC_SCRIPT="$SCRIPT_DIR/bin/qc.sh"
readonly ALIGNMENT_SCRIPT="$SCRIPT_DIR/bin/alignment.sh"

###############################################################################
# USER INTERFACE
###############################################################################

print_usage() {
    printf 'Usage: %s --config FILE --samples FILE [OPTIONS]\n' "$PROGRAM_NAME"
    printf '\n'
    printf 'Options:\n'
    printf '  --preflight-only       stop successfully after preflight\n'
    printf '  --preflight-dir DIR    override preflight report directory\n'
    printf '  -h, --help             show this help\n'
    printf '\nClinicalSuite V2 currently executes through Module 7 alignment and BAM processing.\n'
}

print_not_available() {
    printf 'ClinicalSuite V2 requires validated configuration and sample inputs.\n' >&2
}

###############################################################################
# MAIN
###############################################################################

main() {
    local config_file='' samples_file='' preflight_dir='' preflight_only=false
    local status
    local -a preflight_arguments=()

    if (( $# == 0 )); then
        print_not_available
        return "$EX_UNAVAILABLE"
    fi

    if [[ "$1" == -h || "$1" == --help ]]; then
        if (( $# != 1 )); then
            printf 'ERROR: --help does not accept additional arguments.\n' >&2
            return "$EX_USAGE"
        fi
        print_usage
        return 0
    fi
    while (( $# > 0 )); do
        case "$1" in
            --config)
                (( $# >= 2 )) || { printf 'ERROR: --config requires a value\n' >&2; return "$EX_USAGE"; }
                config_file="$2"; shift 2
                ;;
            --samples)
                (( $# >= 2 )) || { printf 'ERROR: --samples requires a value\n' >&2; return "$EX_USAGE"; }
                samples_file="$2"; shift 2
                ;;
            --preflight-dir)
                (( $# >= 2 )) || { printf 'ERROR: --preflight-dir requires a value\n' >&2; return "$EX_USAGE"; }
                preflight_dir="$2"; shift 2
                ;;
            --preflight-only) preflight_only=true; shift ;;
            *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; return "$EX_USAGE" ;;
        esac
    done
    [[ -n "$config_file" ]] || { printf 'ERROR: --config is required\n' >&2; return "$EX_USAGE"; }
    [[ -n "$samples_file" ]] || { printf 'ERROR: --samples is required\n' >&2; return "$EX_USAGE"; }

    preflight_arguments=(
        --config "$config_file"
        --samples "$samples_file"
        --stage ALIGNMENT
    )
    [[ -z "$preflight_dir" ]] || preflight_arguments+=(--output-dir "$preflight_dir")
    if "$PREFLIGHT_SCRIPT" "${preflight_arguments[@]}"; then
        status=0
    else
        status=$?
    fi
    (( status == 0 )) || return "$status"
    if [[ "$preflight_only" == true ]]; then
        return 0
    fi
    if "$QC_SCRIPT" --config "$config_file" --samples "$samples_file"; then
        status=0
    else
        status=$?
    fi
    (( status == 0 )) || return "$status"
    if "$ALIGNMENT_SCRIPT" --config "$config_file" --samples "$samples_file"; then
        status=0
    else
        status=$?
    fi
    (( status == 0 )) || return "$status"
    printf 'ClinicalSuite completed through Module 7 alignment and BAM processing.\n'
}

main "$@"
