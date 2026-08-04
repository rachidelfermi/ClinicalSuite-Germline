#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly VALIDATOR="$REPOSITORY_ROOT/config/validate.sh"
readonly PARSER="$REPOSITORY_ROOT/config/parser.sh"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_contains() {
    local text="$1"
    local expected="$2"

    [[ "$text" == *"$expected"* ]] || fail "output does not contain: $expected"
}

make_fixture() {
    local name="$1"
    local root="$TEST_ROOT/$name"

    mkdir -p "$root"/{runs,references,databases,envs,profiles,scratch,data,intervals}
    printf '@read1\nACGT\n+\n!!!!\n' >"$root/data/sample_R1.fastq.gz"
    printf '@read2\nTGCA\n+\n!!!!\n' >"$root/data/sample_R2.fastq.gz"
    printf 'chr1\t0\t100\n' >"$root/intervals/capture.bed"
    printf 'chr1\t0\t100\n' >"$root/intervals/reportable.bed"

    cat >"$root/clinical.conf" <<'EOF'
RUN_ID=RUN_001
RUN_ROOT=runs
REFERENCE_DIR=references
DATABASE_DIR=databases
ENV_DIR=envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=wgs-v1.0
SCRATCH_DIR=scratch
MAMBA_BIN=/bin/true
EOF
    cat >"$root/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
HG002	WGS	ILLUMINA	data/sample_R1.fastq.gz	data/sample_R2.fastq.gz	LIB001	FC01.L1	CENTER1	HG002.FC01.L1	XY	NA	intervals/reportable.bed
EOF
    printf '%s\n' "$root"
}

test_valid_configuration_and_exports() {
    local root
    root="$(make_fixture valid)"

    # shellcheck source=config/parser.sh
    # shellcheck disable=SC1090
    source "$PARSER"
    # A second source must be harmless for embedding in downstream modules.
    # shellcheck disable=SC1090
    source "$PARSER"
    clinical_validate "$root/clinical.conf" "$root/samples.tsv" || {
        clinical_print_errors >&2
        fail 'valid fixture was rejected'
    }
    [[ "$RUN_ROOT" == "$root/runs" ]] || fail 'RUN_ROOT was not made absolute'
    [[ "$SAMPLES_TSV" == "$root/samples.tsv" ]] || fail 'SAMPLES_TSV was not made absolute'
    [[ "$THREADS" == 8 && "$MEMORY_GB" == 32 ]] || fail 'operational defaults were not applied'
    [[ "${CLINICAL_SAMPLES[HG002.fastq_r1]}" == "$root/data/sample_R1.fastq.gz" ]] || \
        fail 'manifest FASTQ path was not made absolute'
}

test_schema_and_examples_are_synchronized() {
    local key
    local header expected_header separator column
    declare -A schema_keys=()
    declare -A example_keys=()

    while IFS=$'\t' read -r key _; do
        [[ "$key" == key ]] && continue
        schema_keys["$key"]=1
    done <"$REPOSITORY_ROOT/config/schemas/clinical.conf.schema.tsv"
    while IFS='=' read -r key _; do
        [[ "$key" == \#* || -z "$key" ]] && continue
        example_keys["$key"]=1
    done <"$REPOSITORY_ROOT/config/clinical.conf.example"
    for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
        [[ -v "schema_keys[$key]" ]] || fail "$key is missing from the config schema"
        [[ -v "example_keys[$key]" ]] || fail "$key is missing from clinical.conf.example"
    done
    [[ ${#schema_keys[@]} -eq ${#CLINICAL_CONFIG_KEYS[@]} ]] || fail 'config schema has extra keys'
    [[ ${#example_keys[@]} -eq ${#CLINICAL_CONFIG_KEYS[@]} ]] || fail 'config example has extra keys'

    IFS= read -r header <"$REPOSITORY_ROOT/config/samples.tsv.example"
    expected_header=''
    separator=''
    for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
        expected_header+="$separator$column"
        separator=$'\t'
    done
    [[ "$header" == "$expected_header" ]] || fail 'samples.tsv.example header differs from parser schema'
}

test_aggregated_errors() {
    local root output status
    root="$(make_fixture aggregate)"
    cat >"$root/clinical.conf" <<'EOF'
RUN_ID=RUN_001
RUN_ID=RUN_002
RUN_ROOT=runs
DATABASE_DIR=
ENV_DIR=envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=wgs-v1.0
SCRATCH_DIR=scratch
MAMBA_BIN=/bin/true
REFERENCE_PATH=references
THREADS=many
MALFORMED_LINE
EOF
    cat >"$root/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
HG002	WGSS	ONT	data/sample_R1.fastq.gz	data/missing_R2.fastq.gz	LIB 1	FC01.L1	CENTER1	HG002.FC01.L1	XY	NA	intervals/reportable.bed
HG002	WGS	ILLUMINA	data/sample_R1.fastq.gz	data/sample_R2.fastq.gz	LIB002	FC01.L2	CENTER1	HG002.FC01.L2	XY	NA	intervals/reportable.bed
EOF

    set +e
    output="$($VALIDATOR --config "$root/clinical.conf" --samples "$root/samples.tsv" --check-only 2>&1)"
    status=$?
    set -e
    [[ $status -eq 2 ]] || fail "aggregate validation returned $status instead of 2"
    assert_contains "$output" 'Configuration validation failed.'
    assert_contains "$output" 'Missing key:'
    assert_contains "$output" 'REFERENCE_DIR'
    assert_contains "$output" 'Unknown key:'
    assert_contains "$output" 'REFERENCE_PATH'
    assert_contains "$output" 'Duplicate key:'
    assert_contains "$output" 'Empty mandatory value:'
    assert_contains "$output" 'Malformed configuration:'
    assert_contains "$output" 'Invalid assay:'
    assert_contains "$output" 'Invalid platform:'
    assert_contains "$output" 'Invalid read-group field:'
    assert_contains "$output" 'Missing FASTQ:'
    assert_contains "$output" 'Duplicate sample:'
}

test_manifest_schema_errors() {
    local root output status
    root="$(make_fixture schema)"
    cat >"$root/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	unexpected
HG002	WGS	ILLUMINA	data/sample_R1.fastq.gz	data/sample_R2.fastq.gz	LIB001	FC01.L1	CENTER1	HG002.FC01.L1	XY	NA	value
EOF
    set +e
    output="$($VALIDATOR --config "$root/clinical.conf" --samples "$root/samples.tsv" --check-only 2>&1)"
    status=$?
    set -e
    [[ $status -eq 2 ]] || fail 'malformed header was accepted'
    assert_contains "$output" 'Unknown column:'
    assert_contains "$output" 'unexpected'
    assert_contains "$output" 'Missing column:'
    assert_contains "$output" 'reportable_intervals'
}

test_invalid_and_missing_paths() {
    local root output status
    root="$(make_fixture paths)"
    sed -i 's|REFERENCE_DIR=references|REFERENCE_DIR=https://example.invalid/reference|' \
        "$root/clinical.conf"
    sed -i 's|data/sample_R2.fastq.gz|data/absent_R2.fastq.gz|' "$root/samples.tsv"
    set +e
    output="$($VALIDATOR --config "$root/clinical.conf" --samples "$root/samples.tsv" --check-only 2>&1)"
    status=$?
    set -e
    [[ $status -eq 2 ]] || fail 'invalid paths were accepted'
    assert_contains "$output" 'Invalid path:'
    assert_contains "$output" 'REFERENCE_DIR=https://example.invalid/reference'
    assert_contains "$output" 'Missing FASTQ:'
}

test_wes_capture_is_required() {
    local root output status
    root="$(make_fixture wes)"
    sed -i $'s/HG002\tWGS/HG002\tWES/' "$root/samples.tsv"
    set +e
    output="$($VALIDATOR --config "$root/clinical.conf" --samples "$root/samples.tsv" --check-only 2>&1)"
    status=$?
    set -e
    [[ $status -eq 2 ]] || fail 'WES without capture intervals was accepted'
    assert_contains "$output" 'Invalid interval:'
    assert_contains "$output" 'capture_intervals is required for WES'
}

test_cli_contract() {
    local status

    set +e
    "$VALIDATOR" >/dev/null 2>&1
    status=$?
    set -e
    [[ $status -eq 64 ]] || fail "missing CLI arguments returned $status"
    "$VALIDATOR" --help >/dev/null
}

main() {
    test_valid_configuration_and_exports
    test_schema_and_examples_are_synchronized
    test_aggregated_errors
    test_manifest_schema_errors
    test_invalid_and_missing_paths
    test_wes_capture_is_required
    test_cli_contract
    printf 'PASS: configuration unit tests\n'
}

main "$@"
