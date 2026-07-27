#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=bin/qc.sh
source "$REPOSITORY_ROOT/bin/qc.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

write_profile() {
    local path="$1"

    cat >"$path" <<'EOF'
PROFILE_ID=test-wgs-v1
PROFILE_VERSION=1.0.0
SUPPORTED_ASSAYS=WGS
SUPPORTED_PLATFORMS=ILLUMINA
FASTP_MODE=PASS_THROUGH
FASTQC_FAIL_POLICY=REVIEW
FASTQC_WARNING_POLICY=REVIEW
MIN_READ_PAIRS=10
EOF
}

test_profile_parser() {
    local profile="$TEST_ROOT/qc.conf"

    ASSAY_PROFILE=test-wgs-v1
    write_profile "$profile"
    qc_load_profile "$profile" || fail 'valid QC profile was rejected'
    [[ "${QC_PROFILE[FASTP_MODE]}" == PASS_THROUGH ]] ||
        fail 'profile value was not retained'
    printf 'UNKNOWN=value\n' >>"$profile"
    assert_fails qc_load_profile "$profile"
    [[ "${QC_PROFILE_ERRORS[*]}" == *'unknown profile key'* ]] ||
        fail 'unknown profile key was not reported'
}

test_fastp_counts_and_decisions() {
    local json="$TEST_ROOT/fastp.json"

    cat >"$json" <<'EOF'
{
  "summary": {
    "before_filtering": {
      "total_reads": 200
    },
    "after_filtering": {
      "total_reads": 200
    }
  }
}
EOF
    qc_fastp_read_counts "$json" || fail 'fastp counts were not parsed'
    [[ "$QC_BEFORE_READS" -eq 200 && "$QC_AFTER_READS" -eq 200 ]] ||
        fail 'fastp counts are incorrect'

    QC_PROFILE[MIN_READ_PAIRS]=10
    QC_PROFILE[FASTQC_FAIL_POLICY]=REVIEW
    QC_PROFILE[FASTQC_WARNING_POLICY]=REVIEW
    qc_decide_sample 0 0 100
    [[ "$QC_RESULT" == PASS ]] || fail 'clean sample was not passed'
    qc_decide_sample 1 0 100
    [[ "$QC_RESULT" == REVIEW ]] || fail 'FastQC failure was not retained for review'
    QC_PROFILE[FASTQC_FAIL_POLICY]=BLOCK
    qc_decide_sample 1 0 100
    [[ "$QC_RESULT" == BLOCK ]] || fail 'blocking FastQC policy was not enforced'
    qc_decide_sample 0 0 9
    [[ "$QC_RESULT" == BLOCK ]] || fail 'minimum read-pair policy was not enforced'
}

test_fastqc_counts() {
    local table="$TEST_ROOT/multiqc_fastqc.txt" counts

    {
        printf 'Sample'
        for column in {2..12}; do printf '\tmetadata%s' "$column"; done
        printf '\tbasic\tquality\tadapter\n'
        printf 'HG002_R1'
        for column in {2..12}; do printf '\tvalue%s' "$column"; done
        printf '\tpass\twarn\tpass\n'
        printf 'HG002_R2'
        for column in {2..12}; do printf '\tvalue%s' "$column"; done
        printf '\tpass\tfail\twarn\n'
    } >"$table"
    counts="$(qc_fastqc_counts "$table" HG002)" ||
        fail 'FastQC status rows were not parsed'
    [[ "$counts" == '1 2' ]] || fail "unexpected FastQC counts: $counts"
    assert_fails qc_fastqc_counts "$table" missing
}

test_cli_contract() {
    "$REPOSITORY_ROOT/bin/qc.sh" --help >/dev/null
    local status

    set +e
    "$REPOSITORY_ROOT/bin/qc.sh" >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 64 ]] || fail "missing arguments returned $status"
}

main() {
    test_profile_parser
    test_fastp_counts_and_decisions
    test_fastqc_counts
    test_cli_contract
    printf 'PASS: QC unit tests\n'
}

main "$@"
