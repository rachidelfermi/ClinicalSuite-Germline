#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly PREFLIGHT="$REPOSITORY_ROOT/bin/preflight.sh"
# shellcheck source=tests/helpers/preflight_fixture.sh
source "$REPOSITORY_ROOT/tests/helpers/preflight_fixture.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

run_failure_case() {
    local root="$1"
    local expected="$2"
    shift 2
    local status

    set +e
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" "$@" >/dev/null 2>&1
    status=$?
    set -e
    [[ $status -eq 69 ]] || fail "expected preflight status 69, found $status"
    grep -Eqi -- "$expected" "$root/preflight-output/preflight_report.txt" ||
        fail "report does not contain expected failure: $expected"
    jq -e '.status == "FAIL" and .error_count > 0' \
        "$root/preflight-output/preflight.json" >/dev/null || fail 'failure JSON is invalid'
}

test_success() {
    local root="$TEST_ROOT/success"

    preflight_fixture_create "$root" WGS
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" >/dev/null
    jq -e '.status == "PASS" and .error_count == 0' \
        "$root/preflight-output/preflight.json" >/dev/null || fail 'success JSON is invalid'
    [[ -r "$root/runs/RUN_001/resolved_config/clinical.conf" ]] ||
        fail 'resolved configuration was not created'
    "$REPOSITORY_ROOT/run.sh" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --preflight-dir "$root/run-preflight" --preflight-only >/dev/null
}

test_missing_fastq() {
    local root="$TEST_ROOT/missing-fastq"

    preflight_fixture_create "$root" WGS
    mv "$root/data/sample_R2.fastq.gz" "$root/data/removed_R2.fastq.gz"
    run_failure_case "$root" 'Missing FASTQ|fastq_r2'
}

test_missing_environment() {
    local root="$TEST_ROOT/missing-environment"

    preflight_fixture_create "$root" WGS
    mv "$root/envs/qc" "$root/envs/qc.missing"
    run_failure_case "$root" 'Missing MANDATORY Conda environment:.*qc'
}

test_future_database_is_informational() {
    local root="$TEST_ROOT/future-database"

    preflight_fixture_create "$root" WGS
    mv "$root/databases/clinvar.vcf.gz" "$root/databases/clinvar.missing"
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" --stage VARIANT_FILTERING >/dev/null
    jq -e '.status == "PASS" and .error_count == 0 and
        .execution_module == 13 and .information_count > 0' \
        "$root/preflight-output/preflight.json" >/dev/null ||
        fail 'future database absence did not remain informational'
    grep -Fq 'FUTURE resource missing or unreadable: CLINVAR' \
        "$root/preflight-output/preflight_report.txt" ||
        fail 'future database was not identified in the report'
}

test_annotation_database_is_mandatory() {
    local root="$TEST_ROOT/annotation-database"

    preflight_fixture_create "$root" WGS
    mv "$root/databases/clinvar.vcf.gz" "$root/databases/clinvar.missing"
    run_failure_case "$root" 'MANDATORY resource missing.*CLINVAR' \
        --stage ANNOTATION
}

test_future_environment_is_informational() {
    local root="$TEST_ROOT/future-environment"

    preflight_fixture_create "$root" WGS
    mv "$root/envs/annotation" "$root/envs/annotation.missing"
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" --stage VARIANT_FILTERING >/dev/null
    grep -Fq 'Missing FUTURE Conda environment:' \
        "$root/preflight-output/preflight_report.txt" ||
        fail 'future environment was not reported as informational'
}

test_future_database_manifest_is_informational() {
    local root="$TEST_ROOT/future-database-manifest"

    preflight_fixture_create "$root" WGS
    mv "$root/databases/database_manifest.tsv" \
        "$root/databases/database_manifest.tsv.future"
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" --stage VARIANT_FILTERING >/dev/null
    grep -Fq 'Missing database manifest for Module 13 (VARIANT_FILTERING)' \
        "$root/preflight-output/preflight_report.txt" ||
        fail 'future database manifest absence was not informational'
}

test_acmg_stage_boundary() {
    local root_before="$TEST_ROOT/acmg-before"
    local root_at="$TEST_ROOT/acmg-at"
    local fasta_checksum

    preflight_fixture_create "$root_before" WGS
    fasta_checksum="$(
        preflight_fixture_checksum \
            "$root_before/references/GRCh38_full_analysis_set_plus_decoy_hla.fa"
    )"
    printf 'ACMG_RULES\tacmg-rules\tDIRECTORY\tMANDATORY\tGRCh38\ttest-v1\t-\t%s\n' \
        "$fasta_checksum" >>"$root_before/databases/database_manifest.tsv"
    "$PREFLIGHT" --config "$root_before/clinical.conf" \
        --samples "$root_before/samples.tsv" \
        --output-dir "$root_before/preflight-output" --stage ANNOTATION >/dev/null
    grep -Fq 'FUTURE resource missing or unreadable: ACMG_RULES' \
        "$root_before/preflight-output/preflight_report.txt" ||
        fail 'ACMG resource was not deferred before Module 15'

    preflight_fixture_create "$root_at" WGS
    fasta_checksum="$(
        preflight_fixture_checksum \
            "$root_at/references/GRCh38_full_analysis_set_plus_decoy_hla.fa"
    )"
    printf 'ACMG_RULES\tacmg-rules\tDIRECTORY\tMANDATORY\tGRCh38\ttest-v1\t-\t%s\n' \
        "$fasta_checksum" >>"$root_at/databases/database_manifest.tsv"
    run_failure_case "$root_at" \
        'MANDATORY resource directory missing or empty: ACMG_RULES' --stage ACMG
}

test_unreadable_fastq() {
    local root="$TEST_ROOT/unreadable-fastq"

    preflight_fixture_create "$root" WGS
    chmod 000 "$root/data/sample_R1.fastq.gz"
    run_failure_case "$root" 'Invalid path|Unreadable.*FASTQ|fastq_r1'
    chmod 0600 "$root/data/sample_R1.fastq.gz"
}

test_invalid_permissions() {
    local root="$TEST_ROOT/permissions"

    preflight_fixture_create "$root" WGS
    chmod 0550 "$root/scratch"
    run_failure_case "$root" 'not writable|SCRATCH_DIR'
    chmod 0750 "$root/scratch"
}

test_malformed_configuration() {
    local root="$TEST_ROOT/malformed"

    preflight_fixture_create "$root" WGS
    printf 'REFERENCE_PATH=unknown\n' >>"$root/clinical.conf"
    run_failure_case "$root" 'Unknown key|REFERENCE_PATH'
}

test_incompatible_reference() {
    local root="$TEST_ROOT/incompatible-reference"

    preflight_fixture_create "$root" WGS
    printf '>chr2\nACGT\n' \
        >"$root/references/GRCh38_full_analysis_set_plus_decoy_hla.fa"
    run_failure_case "$root" 'Reference indexes are inconsistent|Checksum mismatch: GRCH38_FASTA'
}

test_unsupported_reference_identity() {
    local root="$TEST_ROOT/unsupported-reference"

    preflight_fixture_create "$root" WGS
    sed -i \
        's/GRCh38_full_analysis_set_plus_decoy_hla-20150309/unsupported-reference/g' \
        "$root/references/reference_manifest.tsv"
    run_failure_case "$root" \
        'Unsupported reference version for GRCH38_FASTA: unsupported-reference'
}

test_unsupported_reference_basename() {
    local root="$TEST_ROOT/unsupported-reference-basename"

    preflight_fixture_create "$root" WGS
    mv "$root/references/GRCh38_full_analysis_set_plus_decoy_hla.fa" \
        "$root/references/unsupported-reference.fa"
    sed -i \
        's/GRCh38_full_analysis_set_plus_decoy_hla\.fa\t/unsupported-reference.fa\t/' \
        "$root/references/reference_manifest.tsv"
    run_failure_case "$root" \
        'Unsupported GRCh38 FASTA: unsupported-reference.fa'
}

test_aggregated_failures() {
    local root="$TEST_ROOT/aggregated"
    local status report

    preflight_fixture_create "$root" WGS
    mv "$root/envs/qc" "$root/envs/qc.missing"
    mv "$root/references/known_indels.vcf.gz" "$root/references/known_indels.missing"
    set +e
    "$PREFLIGHT" --config "$root/clinical.conf" --samples "$root/samples.tsv" \
        --output-dir "$root/preflight-output" >/dev/null 2>&1
    status=$?
    set -e
    [[ $status -eq 69 ]] || fail "aggregate case returned $status"
    report="$(<"$root/preflight-output/preflight_report.txt")"
    [[ "$report" == *'Missing MANDATORY Conda environment:'*qc* ]] ||
        fail 'aggregate report omitted missing environment'
    [[ "$report" == *'MANDATORY resource missing or unreadable: KNOWN_INDELS'* ]] ||
        fail 'aggregate report omitted missing current-stage reference'
}

main() {
    test_success
    test_missing_fastq
    test_missing_environment
    test_future_database_is_informational
    test_annotation_database_is_mandatory
    test_future_environment_is_informational
    test_future_database_manifest_is_informational
    test_acmg_stage_boundary
    test_unreadable_fastq
    test_invalid_permissions
    test_malformed_configuration
    test_incompatible_reference
    test_unsupported_reference_identity
    test_unsupported_reference_basename
    test_aggregated_failures
    printf 'PASS: preflight integration tests\n'
}

main "$@"
