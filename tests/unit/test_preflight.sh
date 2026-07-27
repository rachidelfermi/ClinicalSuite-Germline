#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=bin/preflight.sh
source "$REPOSITORY_ROOT/bin/preflight.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT
CLINICAL_COLOR=never
common_init preflight-unit '' 1 0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

test_aggregation_and_json_escape() {
    preflight_reset
    preflight_pass unit 'successful check'
    preflight_fail_check unit 'failure "with quotes"'
    preflight_warn_check unit $'warning with\nnewline'
    [[ ${#PREFLIGHT_ERRORS[@]} -eq 1 ]] || fail 'error was not aggregated'
    [[ ${#PREFLIGHT_WARNINGS[@]} -eq 1 ]] || fail 'warning was not aggregated'
    preflight_json_escape $'quote" tab\t newline\n'
    [[ "$PREFLIGHT_RESULT" == 'quote\" tab\t newline\n' ]] || fail 'JSON escaping failed'
}

test_fastq_pair_keys() {
    local r1 r2 fastq1="$TEST_ROOT/id_R1.fastq" fastq2="$TEST_ROOT/id_R2.fastq"

    r1="$(preflight_fastq_pair_key '/data/sample_R1_001.fastq.gz' 1)"
    r2="$(preflight_fastq_pair_key '/data/sample_R2_001.fastq.gz' 2)"
    [[ "$r1" == "$r2" ]] || fail 'matching FASTQ pair keys differ'
    assert_fails preflight_fastq_pair_key '/data/sample.fastq.gz' 1
    printf '@instrument.read/1\nA\n+\n!\n' >"$fastq1"
    printf '@instrument.read/2\nT\n+\n!\n' >"$fastq2"
    [[ "$(preflight_fastq_first_id "$fastq1")" == instrument.read ]] ||
        fail 'R1 FASTQ identifier normalization failed'
    [[ "$(preflight_fastq_first_id "$fastq2")" == instrument.read ]] ||
        fail 'R2 FASTQ identifier normalization failed'
}

test_resource_path_safety() {
    preflight_resolve_resource_path \
        /reference bundle/GRCh38_full_analysis_set_plus_decoy_hla.fa
    [[ "$PREFLIGHT_RESULT" == \
        /reference/bundle/GRCh38_full_analysis_set_plus_decoy_hla.fa ]] ||
        fail 'relative resource path failed'
    assert_fails preflight_resolve_resource_path /reference ../escape
    assert_fails preflight_resolve_resource_path /reference https://example.invalid/data
}

test_stage_boundaries() {
    preflight_reset
    preflight_set_stage variant-filtering || fail 'variant-filtering stage was rejected'
    [[ "$PREFLIGHT_STAGE_MODULE" -eq 13 &&
        "$PREFLIGHT_STAGE_NAME" == VARIANT_FILTERING ]] ||
        fail 'variant-filtering stage mapping is incorrect'
    preflight_stage_requirement 14 MANDATORY
    [[ "$PREFLIGHT_RESULT" == FUTURE ]] ||
        fail 'Module 14 resource was not deferred at Module 13'
    preflight_set_stage annotation || fail 'annotation stage was rejected'
    preflight_stage_requirement 14 MANDATORY
    [[ "$PREFLIGHT_RESULT" == MANDATORY ]] ||
        fail 'Module 14 resource was not mandatory at annotation'
    [[ "$(preflight_resource_first_module database REVEL)" -eq 15 ]] ||
        fail 'REVEL was not classified as a Module 15 resource'
    [[ "$(preflight_image_first_module gatk)" -eq 7 ]] ||
        fail 'GATK was not classified for Module 7 BQSR'
    assert_fails preflight_set_stage unknown-stage
}

test_disk_policy() {
    preflight_reset
    DISK_SPACE_POLICY=WARNING
    preflight_check_disk_space_path test "$TEST_ROOT" 999999
    [[ ${#PREFLIGHT_ERRORS[@]} -eq 0 && ${#PREFLIGHT_WARNINGS[@]} -eq 1 ]] ||
        fail 'WARNING disk policy did not warn'
    preflight_reset
    DISK_SPACE_POLICY=ERROR
    preflight_check_disk_space_path test "$TEST_ROOT" 999999
    [[ ${#PREFLIGHT_ERRORS[@]} -eq 1 ]] || fail 'ERROR disk policy did not fail'
}

test_report_writers() {
    preflight_reset
    PREFLIGHT_OUTPUT_DIR="$TEST_ROOT/report"
    create_directory "$PREFLIGHT_OUTPUT_DIR"
    preflight_pass unit 'report success'
    preflight_warning 'optional item missing'
    preflight_info_check unit 'future item deferred'
    preflight_write_reports
    [[ -s "$PREFLIGHT_OUTPUT_DIR/preflight_report.txt" ]] || fail 'text report missing'
    jq -e '.schema_version == "1.1" and .status == "PASS" and
        .warning_count == 1 and .information_count == 1 and
        .execution_module == 13' \
        "$PREFLIGHT_OUTPUT_DIR/preflight.json" >/dev/null || fail 'JSON report is invalid'
}

test_cli_contract() {
    "$REPOSITORY_ROOT/bin/preflight.sh" --help >/dev/null
    local status
    set +e
    "$REPOSITORY_ROOT/bin/preflight.sh" >/dev/null 2>&1
    status=$?
    set -e
    [[ $status -eq 64 ]] || fail "missing arguments returned $status"
}

main() {
    test_aggregation_and_json_escape
    test_fastq_pair_keys
    test_resource_path_safety
    test_stage_boundaries
    test_disk_policy
    test_report_writers
    test_cli_contract
    printf 'PASS: preflight unit tests\n'
}

main "$@"
