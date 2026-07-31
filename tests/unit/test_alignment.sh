#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=bin/alignment.sh
source "$REPOSITORY_ROOT/bin/alignment.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT
common_init alignment-unit '' 1 0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_fails() {
    if ( "$@" ) >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

write_reference_fixture() {
    local root="$1"
    local fasta="$root/GRCh38_full_analysis_set_plus_decoy_hla.fa"
    local fasta_sha suffix file

    mkdir -p "$root/bwa"
    printf '>chr1\nACGTACGT\n' >"$fasta"
    printf 'chr1\t8\t6\t8\t9\n' >"${fasta}.fai"
    printf '@HD\tVN:1.6\n@SQ\tSN:chr1\tLN:8\n' \
        >"$root/GRCh38_full_analysis_set_plus_decoy_hla.dict"
    for suffix in "${ALIGNMENT_BWA_INDEX_SUFFIXES[@]}"; do
        printf 'index-%s\n' "$suffix" \
            >"$root/bwa/GRCh38_full_analysis_set_plus_decoy_hla.fa$suffix"
    done
    (
        cd -- "$root"
        sha256sum bwa/GRCh38_full_analysis_set_plus_decoy_hla.fa.*
    ) >"$root/checksums.sha256"
    for file in known.vcf.gz known.vcf.gz.tbi \
        mills.vcf.gz mills.vcf.gz.tbi; do
        printf '%s\n' "$file" >"$root/$file"
    done
    fasta_sha="$(calculate_checksum "$fasta")"
    {
        printf 'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\n'
        printf 'GRCH38_FASTA\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "${fasta##*/}" "$ALIGNMENT_LOCKED_REFERENCE_VERSION" "$fasta_sha"
        printf 'GRCH38_FASTA_FAI\t%s.fai\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "${fasta##*/}" "$ALIGNMENT_LOCKED_REFERENCE_VERSION" \
            "$(calculate_checksum "${fasta}.fai")"
        printf 'GRCH38_SEQUENCE_DICTIONARY\tGRCh38_full_analysis_set_plus_decoy_hla.dict\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$ALIGNMENT_LOCKED_REFERENCE_VERSION" \
            "$(calculate_checksum "$root/GRCh38_full_analysis_set_plus_decoy_hla.dict")"
        printf 'BWA_MEM2_INDEX\tbwa\tDIRECTORY\tMANDATORY\tGRCh38\t%s\t-\n' \
            "$ALIGNMENT_LOCKED_REFERENCE_VERSION"
        printf 'KNOWN_INDELS\tknown.vcf.gz\tFILE\tMANDATORY\tGRCh38\tknown-test\t%s\n' \
            "$(calculate_checksum "$root/known.vcf.gz")"
        printf 'KNOWN_INDELS_INDEX\tknown.vcf.gz.tbi\tFILE\tMANDATORY\tGRCh38\tknown-test\t%s\n' \
            "$(calculate_checksum "$root/known.vcf.gz.tbi")"
        printf 'MILLS_INDELS\tmills.vcf.gz\tFILE\tMANDATORY\tGRCh38\tmills-test\t%s\n' \
            "$(calculate_checksum "$root/mills.vcf.gz")"
        printf 'MILLS_INDELS_INDEX\tmills.vcf.gz.tbi\tFILE\tMANDATORY\tGRCh38\tmills-test\t%s\n' \
            "$(calculate_checksum "$root/mills.vcf.gz.tbi")"
    } >"$root/reference_manifest.tsv"
    printf '%s\n' "$fasta_sha"
}

write_qc_fixture() {
    local root="$1"
    local r1="$root/samples/S1/final/S1_R1.fastq.gz"
    local r2="$root/samples/S1/final/S1_R2.fastq.gz"

    mkdir -p "${r1%/*}"
    printf '@r/1\nACGT\n+\nIIII\n' | gzip -n >"$r1"
    printf '@r/2\nTGCA\n+\nIIII\n' | gzip -n >"$r2"
    printf 'sample_id\tfastq_r1\tfastq_r2\tsha256_r1\tsha256_r2\tmode\n' \
        >"$root/final_fastq.tsv"
    printf 'S1\tsamples/S1/final/S1_R1.fastq.gz\tsamples/S1/final/S1_R2.fastq.gz\t%s\t%s\tPASS_THROUGH\n' \
        "$(calculate_checksum "$r1")" "$(calculate_checksum "$r2")" \
        >>"$root/final_fastq.tsv"
    printf 'sample_id\tfastqc_failures\tfastqc_warnings\tread_pairs\tdecision\n' \
        >"$root/qc_status.tsv"
    printf 'S1\t0\t0\t1\tPASS\n' >>"$root/qc_status.tsv"
    printf 'key\tvalue\nstatus\tPASS\n' >"$root/provenance.tsv"
    (
        cd -- "$root"
        sha256sum final_fastq.tsv provenance.tsv qc_status.tsv \
            samples/S1/final/S1_R1.fastq.gz samples/S1/final/S1_R2.fastq.gz
    ) >"$root/output_checksums.sha256"
    printf 'checkpoint\n' >"$root/.complete"
}

test_read_group() {
    CLINICAL_SAMPLES=(
        [S1.sample_id]=S1
        [S1.read_group_id]=FLOWCELL.1
        [S1.library_id]=LIB1
        [S1.platform]=ILLUMINA
        [S1.platform_unit]=FLOWCELL.L1
        [S1.sequencing_center]=CENTER
    )
    local value
    value="$(alignment_sample_read_group S1)"
    [[ "$value" == '@RG\tID:FLOWCELL.1\tSM:S1\tLB:LIB1\tPL:ILLUMINA\tPU:FLOWCELL.L1\tCN:CENTER' ]] ||
        fail 'read group is not exact'
}

test_manifest_and_reference_validation() {
    local root="$TEST_ROOT/reference"
    local fasta_sha

    fasta_sha="$(write_reference_fixture "$root")"
    REFERENCE_DIR="$root"
    alignment_reset_state
    alignment_parse_reference_manifest "$root/reference_manifest.tsv"
    alignment_validate_reference_resources "$fasta_sha"
    [[ "${ALIGNMENT_REFERENCE_VERSION[KNOWN_INDELS]}" == known-test ]] ||
        fail 'BQSR resource version was not retained'
    assert_fails alignment_resolve_manifest_path ../escape
    printf 'corruption\n' >>"$root/known.vcf.gz"
    assert_fails alignment_validate_reference_resources "$fasta_sha"
    printf 'known.vcf.gz\n' >"$root/known.vcf.gz"
    rm "$root/bwa/GRCh38_full_analysis_set_plus_decoy_hla.fa.alt"
    assert_fails alignment_validate_reference_resources "$fasta_sha"
    printf 'index-.alt\n' \
        >"$root/bwa/GRCh38_full_analysis_set_plus_decoy_hla.fa.alt"

    cp "$root/reference_manifest.tsv" "$root/duplicate.tsv"
    tail -n 1 "$root/reference_manifest.tsv" >>"$root/duplicate.tsv"
    assert_fails alignment_parse_reference_manifest "$root/duplicate.tsv"
}

test_qc_handoff() {
    local root="$TEST_ROOT/qc"
    local unsafe_root="$TEST_ROOT/qc-unsafe"

    write_qc_fixture "$root"
    CLINICAL_SAMPLE_IDS=(S1)
    CLINICAL_SAMPLES=([S1.sample_id]=S1)
    alignment_reset_state
    alignment_load_qc_handoff "$root"
    [[ "${ALIGNMENT_QC_READ_PAIRS[S1]}" == 1 ]] ||
        fail 'QC read-pair count was not loaded'
    chmod u+w "$root/qc_status.tsv" "$root/output_checksums.sha256"
    printf 'corrupt\n' >>"$root/qc_status.tsv"
    assert_fails alignment_load_qc_handoff "$root"

    write_qc_fixture "$unsafe_root"
    cp "$unsafe_root/samples/S1/final/S1_R1.fastq.gz" \
        "$TEST_ROOT/escape_R1.fastq.gz"
    sed -i \
        's#samples/S1/final/S1_R1.fastq.gz#../escape_R1.fastq.gz#' \
        "$unsafe_root/final_fastq.tsv"
    (
        cd -- "$unsafe_root"
        sha256sum final_fastq.tsv provenance.tsv qc_status.tsv \
            samples/S1/final/S1_R1.fastq.gz samples/S1/final/S1_R2.fastq.gz
    ) >"$unsafe_root/output_checksums.sha256"
    assert_fails alignment_load_qc_handoff "$unsafe_root"
}

test_step_checkpoint() {
    local root="$TEST_ROOT/checkpoint"
    local signature

    mkdir -p "$root/checkpoints" "$root/samples/S1"
    printf 'output\n' >"$root/samples/S1/result.txt"
    signature="$(alignment_step_signature \
        0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
        S1 01_test)"
    alignment_record_step "$root" S1 01_test "$signature" \
        samples/S1/result.txt
    alignment_step_is_complete "$root" S1 01_test "$signature" ||
        fail 'valid step checkpoint was rejected'
    printf 'corruption\n' >>"$root/samples/S1/result.txt"
    if { alignment_step_is_complete "$root" S1 01_test "$signature"; } \
        >/dev/null 2>&1; then
        fail 'corrupted step output passed its checkpoint'
    fi
}

main() {
    test_read_group
    test_manifest_and_reference_validation
    test_qc_handoff
    test_step_checkpoint
    printf 'PASS: independent alignment unit tests\n'
}

main "$@"
