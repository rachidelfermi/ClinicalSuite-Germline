#!/usr/bin/env bash
# End-to-end Module 7 smoke test with the real HG002 fixture and locked reference.

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly REFERENCE_DIR="${CLINICAL_TEST_REFERENCE_DIR:-/home/bio/Genomics/GRCh38/sd}"
readonly FASTQ_DIR="$REPOSITORY_ROOT/tests/data/fastq"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
cleanup_test_root() {
    if [[ "${KEEP_TEST_OUTPUT:-0}" == 1 ]]; then
        printf 'Preserved HG002 Module 7 validation: %s\n' "$TEST_ROOT" >&2
        return
    fi
    chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
    rm -rf -- "$TEST_ROOT"
}
trap cleanup_test_root EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_validation_inputs() {
    local path
    local -a required=(
        "$REFERENCE_DIR/reference_manifest.tsv"
        "$REFERENCE_DIR/GRCh38_full_analysis_set_plus_decoy_hla.fa"
        "$REFERENCE_DIR/GRCh38_full_analysis_set_plus_decoy_hla.fa.fai"
        "$REFERENCE_DIR/GRCh38_full_analysis_set_plus_decoy_hla.fa.dict"
        "$REFERENCE_DIR/known-sites/Homo_sapiens_assembly38.known_indels.vcf.gz"
        "$REFERENCE_DIR/known-sites/Homo_sapiens_assembly38.known_indels.vcf.gz.tbi"
        "$REFERENCE_DIR/known-sites/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
        "$REFERENCE_DIR/known-sites/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi"
        "$FASTQ_DIR/HG002_test_R1.fastq.gz"
        "$FASTQ_DIR/HG002_test_R2.fastq.gz"
        "$REPOSITORY_ROOT/containers/qc.sif"
        "$REPOSITORY_ROOT/containers/alignment.sif"
        "$REPOSITORY_ROOT/containers/gatk.sif"
    )
    for path in "${required[@]}"; do
        [[ -s "$path" ]] || fail "required real-validation input is missing: $path"
    done
}

write_configuration() {
    mkdir -p "$TEST_ROOT"/{runs,databases,profiles/hg002-wgs,scratch,intervals}
    cat >"$TEST_ROOT/profiles/hg002-wgs/qc.conf" <<'EOF'
PROFILE_ID=hg002-wgs
PROFILE_VERSION=1.0.0
SUPPORTED_ASSAYS=WGS
SUPPORTED_PLATFORMS=ILLUMINA
FASTP_MODE=PASS_THROUGH
FASTQC_FAIL_POLICY=REVIEW
FASTQC_WARNING_POLICY=REVIEW
MIN_READ_PAIRS=1
EOF
    printf 'chr1\t0\t248956422\n' >"$TEST_ROOT/intervals/reportable.bed"
    cat >"$TEST_ROOT/clinical.conf" <<EOF
RUN_ID=HG002_MODULE7_VALIDATION
RUN_ROOT=$TEST_ROOT/runs
REFERENCE_DIR=$REFERENCE_DIR
DATABASE_DIR=$TEST_ROOT/databases
CONTAINER_DIR=$REPOSITORY_ROOT/containers
ASSAY_PROFILE_DIR=$TEST_ROOT/profiles
ASSAY_PROFILE=hg002-wgs
SCRATCH_DIR=$TEST_ROOT/scratch
APPTAINER_BIN=/usr/bin/apptainer
REFERENCE_BUILD=GRCh38
THREADS=4
MEMORY_GB=8
MIN_RUN_FREE_GB=0
MIN_SCRATCH_FREE_GB=0
EOF
    cat >"$TEST_ROOT/samples.tsv" <<EOF
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
HG002	WGS	ILLUMINA	$FASTQ_DIR/HG002_test_R1.fastq.gz	$FASTQ_DIR/HG002_test_R2.fastq.gz	HG002_LIB1	HG002_D1_S1_L001	NIST	HG002.D1.S1.L001	XY	NA	$TEST_ROOT/intervals/reportable.bed
EOF
}

compare_reproducible_outputs() {
    local first="$1"
    local second="$2"
    local relative first_sha second_sha
    local -a paths=(
        samples/HG002/HG002.sorted.bam
        samples/HG002/HG002.duplicates_marked.bam
        samples/HG002/HG002.duplicate_metrics.txt
        samples/HG002/HG002.recal.table
        samples/HG002/HG002.analysis_ready.bam
        samples/HG002/HG002.analysis_ready.bam.bai
        samples/HG002/validation/validation.tsv
    )

    for relative in "${paths[@]}"; do
        first_sha="$(sha256sum "$first/$relative" | awk '{print $1}')"
        second_sha="$(sha256sum "$second/$relative" | awk '{print $1}')"
        [[ "$first_sha" == "$second_sha" ]] ||
            fail "non-reproducible Module 7 artifact: $relative"
    done
}

main() {
    local time_report="$TEST_ROOT/module7.time.txt"
    local first="$TEST_ROOT/alignment-a"
    local second="$TEST_ROOT/alignment-b"
    local bam_sha_before bam_sha_after

    "$REPOSITORY_ROOT/bin/alignment.sh" --help >/dev/null
    require_validation_inputs
    (cd -- "$FASTQ_DIR" && sha256sum --check --quiet SHA256SUMS)
    write_configuration

    "$REPOSITORY_ROOT/bin/preflight.sh" \
        --config "$TEST_ROOT/clinical.conf" \
        --samples "$TEST_ROOT/samples.tsv" \
        --output-dir "$TEST_ROOT/preflight" \
        --stage ALIGNMENT >/dev/null
    "$REPOSITORY_ROOT/bin/qc.sh" \
        --config "$TEST_ROOT/clinical.conf" \
        --samples "$TEST_ROOT/samples.tsv" \
        --output-dir "$TEST_ROOT/qc" --quiet

    /usr/bin/time -v -o "$time_report" \
        "$REPOSITORY_ROOT/bin/alignment.sh" \
        --config "$TEST_ROOT/clinical.conf" \
        --samples "$TEST_ROOT/samples.tsv" \
        --qc-dir "$TEST_ROOT/qc" \
        --output-dir "$first" --quiet
    "$REPOSITORY_ROOT/bin/alignment.sh" \
        --config "$TEST_ROOT/clinical.conf" \
        --samples "$TEST_ROOT/samples.tsv" \
        --qc-dir "$TEST_ROOT/qc" \
        --output-dir "$second" --quiet

    compare_reproducible_outputs "$first" "$second"
    bam_sha_before="$(
        sha256sum "$first/samples/HG002/HG002.analysis_ready.bam" |
            awk '{print $1}'
    )"
    "$REPOSITORY_ROOT/bin/alignment.sh" \
        --config "$TEST_ROOT/clinical.conf" \
        --samples "$TEST_ROOT/samples.tsv" \
        --qc-dir "$TEST_ROOT/qc" \
        --output-dir "$first" --quiet
    bam_sha_after="$(
        sha256sum "$first/samples/HG002/HG002.analysis_ready.bam" |
            awk '{print $1}'
    )"
    [[ "$bam_sha_before" == "$bam_sha_after" ]] ||
        fail 'published checkpoint rerun changed the final BAM'

    (
        cd -- "$first"
        sha256sum --check --quiet output_checksums.sha256
    )
    grep -Fq $'picard_validate_pass\ttrue' \
        "$first/samples/HG002/validation/validation.tsv"
    printf 'PASS: HG002 real-reference Module 7 smoke test\n'
    grep -E 'Elapsed \\(wall clock\\)|Maximum resident set size' "$time_report"
}

main "$@"
