#!/usr/bin/env bash
# Validate installed ClinicalSuite Conda environments before locking or packing.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
# shellcheck source=envs/lib.sh
source "$SCRIPT_DIR/lib.sh"

MAMBA_BIN="${MAMBA_BIN:-$(command -v mamba 2>/dev/null || true)}"
REPORT_FILE="${ENV_VALIDATION_REPORT:-$SCRIPT_DIR/environment_validation_report.txt}"
declare -i FAILURES=0 CHECKS=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

record_check() {
    local environment="$1" label="$2" expected="$3" expected_status="$4"
    shift 4
    local prefix="$SCRIPT_DIR/$environment" output status result=PASS

    ((CHECKS += 1))
    if output="$("$SCRIPT_DIR/activate.sh" "$prefix" -- "$@" 2>&1)"; then
        status=0
    else
        status=$?
    fi
    if (( status != expected_status )) || ! grep -Eq -- "$expected" <<<"$output"; then
        result=FAIL
        ((FAILURES += 1))
    fi
    {
        printf '[%s] %s :: %s\n' "$result" "$environment" "$label"
        printf '  command:'
        printf ' %q' "$@"
        printf '\n  expected_status: %s\n  actual_status: %s\n' \
            "$expected_status" "$status"
        printf '  output: %s\n' "${output//$'\n'/ | }"
    } >>"$REPORT_FILE"
}

validate_environment_integrity() {
    local environment="$1" prefix="$SCRIPT_DIR/$environment" output

    ((CHECKS += 1))
    if [[ ! -d "$prefix/conda-meta" || ! -x "$prefix/bin" ]]; then
        printf '[FAIL] %s :: activation/integrity\n' "$environment" >>"$REPORT_FILE"
        ((FAILURES += 1))
        return
    fi
    if output="$("$MAMBA_BIN" list --prefix "$prefix" 2>&1)" &&
        grep -Eq '(List of packages in environment|# packages in environment at)' \
            <<<"$output"; then
        printf '[PASS] %s :: activation/integrity\n' "$environment" >>"$REPORT_FILE"
    else
        printf '[FAIL] %s :: activation/integrity\n' "$environment" >>"$REPORT_FILE"
        ((FAILURES += 1))
    fi
}

main() {
    local environment

    [[ -x "$MAMBA_BIN" ]] || die 'MAMBA_BIN must identify an executable Mamba'
    : >"$REPORT_FILE"
    {
        printf 'ClinicalSuite V2 Conda environment validation report\n'
        printf 'Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Mamba: %s\n\n' "$("$MAMBA_BIN" --version)"
    } >>"$REPORT_FILE"
    for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
        validate_environment_integrity "$environment"
    done
    clinical_environment_each_runtime_check record_check
    {
        printf '\nChecks: %s\nFailures: %s\n' "$CHECKS" "$FAILURES"
        (( FAILURES == 0 )) && printf 'Status: PASS\n' || printf 'Status: FAIL\n'
        (( FAILURES == 0 )) && printf 'overall: PASS\n' || printf 'overall: FAIL\n'
    } >>"$REPORT_FILE"
    (( FAILURES == 0 )) || die "$FAILURES environment validation check(s) failed; see $REPORT_FILE"
    printf 'PASS: %s Conda environment checks; report: %s\n' "$CHECKS" "$REPORT_FILE"
}

main "$@"
