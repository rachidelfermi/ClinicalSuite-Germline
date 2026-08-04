#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly VALIDATOR="$REPOSITORY_ROOT/config/validate.sh"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

mkdir -p "$TEST_ROOT"/{runs,references,databases,envs,profiles,scratch,data,intervals}
printf '@r1\nA\n+\n!\n' >"$TEST_ROOT/data/R1.fastq.gz"
printf '@r2\nT\n+\n!\n' >"$TEST_ROOT/data/R2.fastq.gz"
printf 'chr1\t0\t1\n' >"$TEST_ROOT/intervals/reportable.bed"
cat >"$TEST_ROOT/clinical.conf" <<'EOF'
RUN_ID=SMOKE_001
RUN_ROOT=runs
REFERENCE_DIR=references
DATABASE_DIR=databases
ENV_DIR=envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=wgs-v1.0
SCRATCH_DIR=scratch
MAMBA_BIN=/bin/true
THREADS=4
EOF
cat >"$TEST_ROOT/samples.tsv" <<'EOF'
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
SMOKE	WGS	GENEMIND	data/R1.fastq.gz	data/R2.fastq.gz	LIB1	FLOWCELL.L1	CENTER1	SMOKE.FLOWCELL.L1	UNKNOWN	NA	intervals/reportable.bed
EOF

output="$($VALIDATOR --config "$TEST_ROOT/clinical.conf" --samples "$TEST_ROOT/samples.tsv")"
resolved="$TEST_ROOT/runs/SMOKE_001/resolved_config"
[[ "$output" == *"Configuration validation passed."* ]] || fail 'success was not reported'
[[ -f "$resolved/clinical.conf" && -f "$resolved/samples.tsv" ]] || \
    fail 'resolved configuration files were not created'
[[ "$(stat -c '%a' "$resolved/clinical.conf")" == 444 ]] || fail 'clinical.conf is not read-only'
[[ "$(stat -c '%a' "$resolved/samples.tsv")" == 444 ]] || fail 'samples.tsv is not read-only'
[[ "$(stat -c '%a' "$resolved")" == 555 ]] || fail 'resolved_config directory is not read-only'
grep -Fqx "RUN_ROOT=$TEST_ROOT/runs" "$resolved/clinical.conf" || fail 'RUN_ROOT is not absolute'
grep -Fq "$TEST_ROOT/data/R1.fastq.gz" "$resolved/samples.tsv" || fail 'FASTQ path is not absolute'

set +e
$VALIDATOR --config "$TEST_ROOT/clinical.conf" --samples "$TEST_ROOT/samples.tsv" >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 2 ]] || fail 'existing immutable configuration was overwritten'

printf 'PASS: configuration system smoke test\n'
