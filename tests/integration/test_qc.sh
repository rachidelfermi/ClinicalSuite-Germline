#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
cleanup_test_root() {
    if [[ "${KEEP_TEST_OUTPUT:-0}" == 1 ]]; then
        printf 'Preserved test output: %s\n' "$TEST_ROOT" >&2
        return
    fi
    chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
    rm -rf -- "$TEST_ROOT"
}
trap cleanup_test_root EXIT

mkdir -p "$TEST_ROOT"/{runs,references,databases,envs,profiles/test-wgs-v1,scratch,data,intervals}
printf '@read1/1\nACGTACGT\n+\n!!!!!!!!\n' | gzip -n >"$TEST_ROOT/data/test_R1.fastq.gz"
printf '@read1/2\nTGCATGCA\n+\n!!!!!!!!\n' | gzip -n >"$TEST_ROOT/data/test_R2.fastq.gz"
printf 'chr1\t0\t8\n' >"$TEST_ROOT/intervals/reportable.bed"
cat >"$TEST_ROOT/profiles/test-wgs-v1/qc.conf" <<'EOF'
PROFILE_ID=test-wgs-v1
PROFILE_VERSION=1.0.0
SUPPORTED_ASSAYS=WGS
SUPPORTED_PLATFORMS=ILLUMINA
FASTP_MODE=PASS_THROUGH
FASTQC_FAIL_POLICY=REVIEW
FASTQC_WARNING_POLICY=REVIEW
MIN_READ_PAIRS=1
EOF
cat >"$TEST_ROOT/clinical.conf" <<EOF
RUN_ID=QC_INTEGRATION
RUN_ROOT=runs
REFERENCE_DIR=references
DATABASE_DIR=databases
ENV_DIR=$REPOSITORY_ROOT/envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=test-wgs-v1
SCRATCH_DIR=scratch
MAMBA_BIN=${MAMBA_BIN:-/home/bio/anaconda3/envs/mamba/bin/mamba}
THREADS=2
MIN_RUN_FREE_GB=0
MIN_SCRATCH_FREE_GB=0
EOF
cat >"$TEST_ROOT/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
TEST	WGS	ILLUMINA	data/test_R1.fastq.gz	data/test_R2.fastq.gz	LIB1	FLOWCELL.1	TEST_CENTER	TEST.FC.1	UNKNOWN	NA	intervals/reportable.bed
EOF

"$REPOSITORY_ROOT/bin/qc.sh" \
    --config "$TEST_ROOT/clinical.conf" \
    --samples "$TEST_ROOT/samples.tsv" \
    --output-dir "$TEST_ROOT/qc" --quiet

[[ -s "$TEST_ROOT/qc/multiqc/multiqc_report.html" ]]
[[ -s "$TEST_ROOT/qc/samples/TEST/raw_fastqc/TEST_R1_fastqc.zip" ]]
[[ -s "$TEST_ROOT/qc/samples/TEST/fastp/TEST.fastp.json" ]]
grep -Fq $'TEST\t' "$TEST_ROOT/qc/qc_status.tsv"
grep -Fq $'TEST\tsamples/TEST/final/test_R1.fastq.gz\tsamples/TEST/final/test_R2.fastq.gz' \
    "$TEST_ROOT/qc/final_fastq.tsv"
signature_before="$(awk -F= '$1 == "signature" {print $2}' "$TEST_ROOT/qc/.complete")"
"$REPOSITORY_ROOT/bin/qc.sh" \
    --config "$TEST_ROOT/clinical.conf" \
    --samples "$TEST_ROOT/samples.tsv" \
    --output-dir "$TEST_ROOT/qc" --quiet
signature_after="$(awk -F= '$1 == "signature" {print $2}' "$TEST_ROOT/qc/.complete")"
[[ "$signature_before" == "$signature_after" ]]

chmod u+w "$TEST_ROOT/qc/qc_status.tsv"
printf '# corruption check\n' >>"$TEST_ROOT/qc/qc_status.tsv"
set +e
"$REPOSITORY_ROOT/bin/qc.sh" \
    --config "$TEST_ROOT/clinical.conf" \
    --samples "$TEST_ROOT/samples.tsv" \
    --output-dir "$TEST_ROOT/qc" --quiet >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 69 ]]

printf 'PASS: QC integration test\n'
