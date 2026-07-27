#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=tests/helpers/preflight_fixture.sh
source "$REPOSITORY_ROOT/tests/helpers/preflight_fixture.sh"

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

preflight_fixture_create "$TEST_ROOT/fixture" WGS
mkdir -p "$TEST_ROOT/fixture/profiles/test-wgs-v1"
cat >"$TEST_ROOT/fixture/profiles/test-wgs-v1/qc.conf" <<'EOF'
PROFILE_ID=test-wgs-v1
PROFILE_VERSION=1.0.0
SUPPORTED_ASSAYS=WGS
SUPPORTED_PLATFORMS=ILLUMINA
FASTP_MODE=PASS_THROUGH
FASTQC_FAIL_POLICY=REVIEW
FASTQC_WARNING_POLICY=REVIEW
MIN_READ_PAIRS=50000
EOF
sed -i "s|^CONTAINER_DIR=.*|CONTAINER_DIR=$REPOSITORY_ROOT/containers|" \
    "$TEST_ROOT/fixture/clinical.conf"
sed -i 's|^APPTAINER_BIN=.*|APPTAINER_BIN=/usr/bin/apptainer|' \
    "$TEST_ROOT/fixture/clinical.conf"
cat >"$TEST_ROOT/fixture/samples.tsv" <<EOF
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
HG002	WGS	ILLUMINA	$REPOSITORY_ROOT/tests/data/fastq/HG002_test_R1.fastq.gz	$REPOSITORY_ROOT/tests/data/fastq/HG002_test_R2.fastq.gz	HG002_LIB1	FLOWCELL1.1	GIAB_TEST	HG002.FC1.L1	XY	NA	intervals/reportable.bed
EOF

"$REPOSITORY_ROOT/run.sh" \
    --config "$TEST_ROOT/fixture/clinical.conf" \
    --samples "$TEST_ROOT/fixture/samples.tsv" >/dev/null

QC_DIR="$TEST_ROOT/fixture/runs/RUN_001/qc"
[[ -s "$QC_DIR/multiqc/multiqc_report.html" ]]
[[ "$(find "$QC_DIR" -type f -name '*_fastqc.html' | wc -l)" -eq 2 ]]
[[ "$(find "$QC_DIR" -type f -name '*_fastqc.zip' | wc -l)" -eq 2 ]]
grep -Fq $'HG002\t1\t3\t50000\tREVIEW' "$QC_DIR/qc_status.tsv"
grep -Fq $'HG002\t' "$QC_DIR/final_fastq.tsv"
(cd "$QC_DIR" && sha256sum --check --quiet output_checksums.sha256)

printf 'PASS: HG002 QC smoke test\n'
