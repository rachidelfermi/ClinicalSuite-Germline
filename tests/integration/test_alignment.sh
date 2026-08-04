#!/usr/bin/env bash
# Real-environment integration test on a synthetic, non-biological reference.

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=bin/alignment.sh
source "$REPOSITORY_ROOT/bin/alignment.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
cleanup_test_root() {
    if [[ "${KEEP_TEST_OUTPUT:-0}" == 1 ]]; then
        printf 'Preserved integration output: %s\n' "$TEST_ROOT" >&2
        return
    fi
    chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
    rm -rf -- "$TEST_ROOT"
}
trap cleanup_test_root EXIT
common_init alignment-integration '' 1 0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fastqs() {
    local r1="$1"
    local r2="$2"
    local fasta="$3"
    local index start sequence read1 read2 quality

    sequence="$(sed -n '2p' "$fasta")"
    quality="$(printf '%100s' '' | tr ' ' I)"

    for index in $(seq 1 10); do
        start=$((index * 200))
        read1="${sequence:start:100}"
        printf '@A001:1:TEST:1:1101:%d:%d 1:N:0:1\n%s\n+\n%s\n' \
            "$((1000 + index))" "$((2000 + index))" "$read1" "$quality"
    done | gzip -n >"$r1"
    for index in $(seq 1 10); do
        start=$((index * 200 + 200))
        read2="$(
            printf '%s' "${sequence:start:100}" |
                rev | tr ACGT TGCA
        )"
        printf '@A001:1:TEST:1:1101:%d:%d 2:N:0:1\n%s\n+\n%s\n' \
            "$((1000 + index))" "$((2000 + index))" "$read2" "$quality"
    done | gzip -n >"$r2"
}

make_vcf() {
    local destination="$1"
    local temporary="$TEST_ROOT/empty.vcf"

    {
        printf '##fileformat=VCFv4.2\n'
        printf '##contig=<ID=chr1,length=4000>\n'
        printf '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n'
    } >"$temporary"
    "$REPOSITORY_ROOT/envs/activate.sh" "$REPOSITORY_ROOT/envs/alignment" -- \
        bgzip -c "$temporary" >"$destination"
    "$REPOSITORY_ROOT/envs/activate.sh" "$REPOSITORY_ROOT/envs/alignment" -- \
        tabix -f -p vcf "$destination"
}

prepare_reference() {
    local reference_dir="$TEST_ROOT/reference"
    local fasta="$reference_dir/GRCh38_full_analysis_set_plus_decoy_hla.fa"
    local index_dir="$reference_dir/bwa"

    mkdir -p "$index_dir"
    {
        printf '>chr1\n'
        awk 'BEGIN {
            bases[0]="A"; bases[1]="C"; bases[2]="G"; bases[3]="T"
            srand(42)
            for (i=0; i<4000; i++) printf "%s", bases[int(rand()*4)]
        }'
        printf '\n'
    } >"$fasta"
    "$REPOSITORY_ROOT/envs/activate.sh" "$REPOSITORY_ROOT/envs/alignment" -- \
        samtools faidx "$fasta"
    "$REPOSITORY_ROOT/envs/activate.sh" "$REPOSITORY_ROOT/envs/alignment" -- \
        picard CreateSequenceDictionary \
        "R=$fasta" \
        "O=$reference_dir/GRCh38_full_analysis_set_plus_decoy_hla.dict"
    "$REPOSITORY_ROOT/envs/activate.sh" "$REPOSITORY_ROOT/envs/alignment" -- \
        bwa-mem2 index \
        -p "$index_dir/GRCh38_full_analysis_set_plus_decoy_hla.fa" \
        "$fasta"
    printf 'synthetic-alt\n' \
        >"$index_dir/GRCh38_full_analysis_set_plus_decoy_hla.fa.alt"

    make_vcf "$TEST_ROOT/known.vcf.gz"
    cp "$TEST_ROOT/known.vcf.gz" "$TEST_ROOT/mills.vcf.gz"
    cp "$TEST_ROOT/known.vcf.gz.tbi" "$TEST_ROOT/mills.vcf.gz.tbi"

    ALIGNMENT_REFERENCE_PATH=(
        [GRCH38_FASTA]="$fasta"
        [GRCH38_FASTA_FAI]="${fasta}.fai"
        [GRCH38_SEQUENCE_DICTIONARY]="$reference_dir/GRCh38_full_analysis_set_plus_decoy_hla.dict"
        [BWA_MEM2_INDEX]="$index_dir"
        [KNOWN_INDELS]="$TEST_ROOT/known.vcf.gz"
        [KNOWN_INDELS_INDEX]="$TEST_ROOT/known.vcf.gz.tbi"
        [MILLS_INDELS]="$TEST_ROOT/mills.vcf.gz"
        [MILLS_INDELS_INDEX]="$TEST_ROOT/mills.vcf.gz.tbi"
    )
}

main() {
    local work="$TEST_ROOT/work"
    local r1="$TEST_ROOT/R1.fastq.gz"
    local r2="$TEST_ROOT/R2.fastq.gz"
    local signature='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    local before after

    [[ -d "$REPOSITORY_ROOT/envs/alignment/conda-meta" ]] ||
        fail 'real Module 7 Conda environment is unavailable'
    mkdir -p "$work"/{checkpoints,logs,samples}
    prepare_reference
    make_fastqs "$r1" "$r2" \
        "$TEST_ROOT/reference/GRCh38_full_analysis_set_plus_decoy_hla.fa"

    MAMBA_BIN="${MAMBA_BIN:-/home/bio/anaconda3/envs/mamba/bin/mamba}"
    ENV_DIR="$REPOSITORY_ROOT/envs"
    ALIGNMENT_QC_FASTQ_R1=([SYNTHETIC]="$r1")
    ALIGNMENT_QC_FASTQ_R2=([SYNTHETIC]="$r2")
    ALIGNMENT_QC_READ_PAIRS=([SYNTHETIC]=10)
    CLINICAL_SAMPLES=(
        [SYNTHETIC.sample_id]=SYNTHETIC
        [SYNTHETIC.read_group_id]=SYNTHETIC.RG1
        [SYNTHETIC.library_id]=SYNTHETIC.LIB1
        [SYNTHETIC.platform]=ILLUMINA
        [SYNTHETIC.platform_unit]=SYNTHETIC.PU1
        [SYNTHETIC.sequencing_center]=TEST_CENTER
    )
    alignment_reference_binds
    alignment_run_sample "$work" SYNTHETIC 2 4 "$signature"

    [[ -s "$work/samples/SYNTHETIC/SYNTHETIC.analysis_ready.bam" ]] ||
        fail 'real-environment integration BAM is missing'
    [[ -s "$work/samples/SYNTHETIC/SYNTHETIC.analysis_ready.bam.bai" ]] ||
        fail 'real-environment integration BAI is missing'
    for path in \
        "$work/samples/SYNTHETIC/SYNTHETIC.sorted.bam" \
        "$work/samples/SYNTHETIC/SYNTHETIC.sorted.bam.bai" \
        "$work/samples/SYNTHETIC/SYNTHETIC.duplicates_marked.bam" \
        "$work/samples/SYNTHETIC/SYNTHETIC.duplicates_marked.bai" \
        "$work/samples/SYNTHETIC/SYNTHETIC.duplicate_metrics.txt" \
        "$work/samples/SYNTHETIC/SYNTHETIC.recal.table" \
        "$work/samples/SYNTHETIC/validation/samtools.flagstat.txt" \
        "$work/samples/SYNTHETIC/validation/samtools.stats.txt" \
        "$work/samples/SYNTHETIC/validation/samtools.idxstats.txt"; do
        [[ -s "$path" ]] || fail "required integration output is missing: $path"
    done
    [[ ! -e "$work/samples/SYNTHETIC/SYNTHETIC.analysis_ready.bai" ]] ||
        fail 'GATK created an undeclared duplicate final index'
    grep -Fq $'quickcheck_pass\ttrue' \
        "$work/samples/SYNTHETIC/validation/validation.tsv" ||
        fail 'analysis-ready validation was not recorded'
    grep -Fxq 'No errors found' \
        "$work/samples/SYNTHETIC/validation/picard_validate_summary.txt" ||
        fail 'strict Picard validation did not pass'
    grep -Fq $'final_primary_records\t20' \
        "$work/samples/SYNTHETIC/validation/validation.tsv" ||
        fail 'primary read count was not preserved'
    grep -Fq $'@RG\tID:SYNTHETIC.RG1\tSM:SYNTHETIC' \
        "$work/samples/SYNTHETIC/validation/header.sam" ||
        fail 'validated read group is missing from the final BAM'
    [[ "$(find "$work/checkpoints" -name 'SYNTHETIC.*.complete' | wc -l)" -eq 7 ]] ||
        fail 'not all seven execution checkpoints were created'
    before="$(stat -c '%Y' \
        "$work/checkpoints/SYNTHETIC.07_validate.complete")"
    sleep 1
    alignment_run_sample "$work" SYNTHETIC 2 4 "$signature"
    after="$(stat -c '%Y' \
        "$work/checkpoints/SYNTHETIC.07_validate.complete")"
    [[ "$before" == "$after" ]] ||
        fail 'completed step was rerun instead of resumed'
    printf 'PASS: real-environment alignment integration test\n'
}

main "$@"
