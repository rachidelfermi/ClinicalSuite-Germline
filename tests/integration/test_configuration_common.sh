#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=config/parser.sh
source "$REPOSITORY_ROOT/config/parser.sh"
# shellcheck source=bin/common.sh
source "$REPOSITORY_ROOT/bin/common.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT
CLINICAL_COLOR=never

mkdir -p "$TEST_ROOT"/{runs,references,databases,envs,profiles,scratch,data,intervals}
printf '@r1\nA\n+\n!\n' >"$TEST_ROOT/data/R1.fastq.gz"
printf '@r2\nT\n+\n!\n' >"$TEST_ROOT/data/R2.fastq.gz"
printf 'chr1\t0\t1\n' >"$TEST_ROOT/intervals/reportable.bed"
cat >"$TEST_ROOT/clinical.conf" <<'EOF'
RUN_ID=INTEGRATION_001
RUN_ROOT=runs
REFERENCE_DIR=references
DATABASE_DIR=databases
ENV_DIR=envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=wgs-v1.0
SCRATCH_DIR=scratch
MAMBA_BIN=/bin/true
THREADS=6
EOF
cat >"$TEST_ROOT/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
TEST	WGS	ILLUMINA	data/R1.fastq.gz	data/R2.fastq.gz	LIB1	FC1.L1	CENTER1	TEST.FC1.L1	UNKNOWN	NA	intervals/reportable.bed
EOF

clinical_validate "$TEST_ROOT/clinical.conf" "$TEST_ROOT/samples.tsv" || {
    clinical_print_errors >&2
    exit 1
}
[[ "$(config_get THREADS)" == 6 ]]
[[ "$(config_require RUN_ROOT)" == "$TEST_ROOT/runs" ]]
[[ "$(config_require MAMBA_BIN)" == /usr/bin/true ]]

printf 'PASS: configuration/common-library integration test\n'
