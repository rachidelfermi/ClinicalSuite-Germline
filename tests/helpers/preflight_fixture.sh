#!/usr/bin/env bash
# Synthetic, non-biological Module 5 fixture builder.

preflight_fixture_checksum() {
    local output

    output="$(sha256sum -- "$1")"
    printf '%s\n' "${output%% *}"
}

preflight_fixture_write_mock_mamba() {
    local target="$1"

    cat >"$target" <<'EOF'
#!/usr/bin/env bash
set -u
if [[ "${1:-}" == --version ]]; then
    printf '2.1.1\n'
    exit 0
fi
if [[ "${1:-}" == list && "${2:-}" == --explicit && "${3:-}" == --prefix ]]; then
    prefix="${4:?}"
    cat "${prefix%/*}/${prefix##*/}.lock"
    exit 0
fi
exit 2
EOF
    chmod +x "$target"
}

preflight_fixture_write_mock_tool() {
    local target="$1"

    cat >"$target" <<'EOF'
#!/usr/bin/env bash
command_name="${0##*/}"
case "$command_name" in
    fastqc) printf 'FastQC v0.12.1\n' ;;
    fastp) printf 'fastp 1.3.6\n' ;;
    multiqc) printf 'multiqc, version 1.35\n' ;;
    bwa-mem2) printf '2.2.1\n' ;;
    samtools) printf 'samtools 1.24\n' ;;
    mosdepth) printf 'mosdepth 0.3.14\n' ;;
    gatk) printf 'The Genome Analysis Toolkit (GATK) v4.6.2.0\n' ;;
    bcftools) printf 'bcftools 1.24\n' ;;
    htsfile) printf 'htsfile (htslib) 1.24\n' ;;
    octopus) printf 'octopus version 0.7.4\n' ;;
    picard) printf 'Version:3.4.0\n'; exit 1 ;;
    run_deepvariant) printf 'Runs all 3 steps\n'; exit 1 ;;
    vep) printf 'ensembl-vep : 116.0\n' ;;
    python)
        if [[ "$*" == *'import jinja2'* ]]; then
            printf 'imports-ok\n'
        else
            printf 'Python 3.12.12\n'
        fi
        ;;
    sh) printf 'available\n' ;;
    *) printf 'unknown mock command: %s\n' "$command_name" >&2; exit 127 ;;
esac
EOF
    chmod +x "$target"
}

preflight_fixture_add_reference_file() {
    local manifest="$1" root="$2" id="$3" relative="$4" version="$5"
    local checksum

    checksum="$(preflight_fixture_checksum "$root/$relative")"
    printf '%s\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
        "$id" "$relative" "$version" "$checksum" >>"$manifest"
}

preflight_fixture_add_database_file() {
    local manifest="$1" root="$2" id="$3" relative="$4" version="$5" reference_checksum="$6"
    local checksum

    checksum="$(preflight_fixture_checksum "$root/$relative")"
    printf '%s\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\t%s\n' \
        "$id" "$relative" "$version" "$checksum" "$reference_checksum" >>"$manifest"
}

preflight_fixture_create() {
    local root="$1"
    local assay="${2:-WGS}"
    local reference_manifest database_manifest fasta_checksum environment tool
    local capture_value='NA'
    local reference_name='GRCh38_full_analysis_set_plus_decoy_hla.fa'
    local reference_version='GRCh38_full_analysis_set_plus_decoy_hla-20150309'

    mkdir -p "$root"/{runs,references,databases,envs,profiles,scratch,data,intervals}
    mkdir -p "$root/references"/{bwa,models/wgs,models/wes}
    mkdir -p "$root/databases"/{vep_cache,loftee}

    printf '@sample_R1\nACGT\n+\n!!!!\n' | gzip -c >"$root/data/sample_R1.fastq.gz"
    printf '@sample_R2\nTGCA\n+\n!!!!\n' | gzip -c >"$root/data/sample_R2.fastq.gz"
    printf 'chr1\t0\t4\n' >"$root/intervals/reportable.bed"
    printf 'chr1\t0\t4\n' >"$root/intervals/capture.bed"

    printf '>chr1\nACGT\n' >"$root/references/$reference_name"
    printf 'chr1\t4\t6\t4\t5\n' >"$root/references/${reference_name}.fai"
    printf '@HD\tVN:1.6\n@SQ\tSN:chr1\tLN:4\n' \
        >"$root/references/GRCh38_full_analysis_set_plus_decoy_hla.dict"
    printf 'index\n' >"$root/references/bwa/index.0123"
    printf 'chr1\t0\t4\n' \
        >"$root/references/GRCh38_full_analysis_set_plus_decoy_hla_PAR.bed"
    printf 'known\n' >"$root/references/known_indels.vcf.gz"
    printf 'index\n' >"$root/references/known_indels.vcf.gz.tbi"
    printf 'mills\n' >"$root/references/mills.vcf.gz"
    printf 'index\n' >"$root/references/mills.vcf.gz.tbi"
    printf 'model\n' >"$root/references/models/wgs/model.ckpt"
    printf 'model\n' >"$root/references/models/wes/model.ckpt"

    reference_manifest="$root/references/reference_manifest.tsv"
    printf 'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\n' >"$reference_manifest"
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        GRCH38_FASTA "$reference_name" "$reference_version"
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        GRCH38_FASTA_FAI "${reference_name}.fai" "$reference_version"
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        GRCH38_SEQUENCE_DICTIONARY \
        GRCh38_full_analysis_set_plus_decoy_hla.dict "$reference_version"
    printf 'BWA_MEM2_INDEX\tbwa\tDIRECTORY\tMANDATORY\tGRCh38\t%s\t-\n' \
        "$reference_version" >>"$reference_manifest"
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        GRCH38_PAR_INTERVALS \
        GRCh38_full_analysis_set_plus_decoy_hla_PAR.bed "$reference_version"
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        KNOWN_INDELS known_indels.vcf.gz test-v1
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        KNOWN_INDELS_INDEX known_indels.vcf.gz.tbi test-v1
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        MILLS_INDELS mills.vcf.gz test-v1
    preflight_fixture_add_reference_file "$reference_manifest" "$root/references" \
        MILLS_INDELS_INDEX mills.vcf.gz.tbi test-v1
    printf 'DEEPVARIANT_MODEL_WGS\tmodels/wgs\tDIRECTORY\tMANDATORY\tGRCh38\t1.10.0\t-\n' \
        >>"$reference_manifest"
    printf 'DEEPVARIANT_MODEL_WES\tmodels/wes\tDIRECTORY\tMANDATORY\tGRCh38\t1.10.0\t-\n' \
        >>"$reference_manifest"
    fasta_checksum="$(
        preflight_fixture_checksum "$root/references/$reference_name"
    )"

    printf 'clinvar\n' >"$root/databases/clinvar.vcf.gz"
    printf 'index\n' >"$root/databases/clinvar.vcf.gz.tbi"
    printf 'dbsnp\n' >"$root/databases/dbsnp.vcf.gz"
    printf 'index\n' >"$root/databases/dbsnp.vcf.gz.tbi"
    printf 'gnomad\n' >"$root/databases/gnomad.vcf.gz"
    printf 'index\n' >"$root/databases/gnomad.vcf.gz.tbi"
    printf 'spliceai\n' >"$root/databases/spliceai.vcf.gz"
    printf 'index\n' >"$root/databases/spliceai.vcf.gz.tbi"
    printf 'dbnsfp\n' >"$root/databases/dbnsfp.gz"
    printf 'cache\n' >"$root/databases/vep_cache/cache.dat"
    printf 'plugin\n' >"$root/databases/loftee/loftee.pl"

    database_manifest="$root/databases/database_manifest.tsv"
    printf 'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\treference_sha256\n' \
        >"$database_manifest"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        CLINVAR clinvar.vcf.gz test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        CLINVAR_INDEX clinvar.vcf.gz.tbi test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        DBSNP dbsnp.vcf.gz test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        DBSNP_INDEX dbsnp.vcf.gz.tbi test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        GNOMAD gnomad.vcf.gz test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        GNOMAD_INDEX gnomad.vcf.gz.tbi test-v1 "$fasta_checksum"
    printf 'VEP_CACHE\tvep_cache\tDIRECTORY\tMANDATORY\tGRCh38\t116\t-\t%s\n' \
        "$fasta_checksum" >>"$database_manifest"
    printf 'LOFTEE\tloftee\tDIRECTORY\tMANDATORY\tGRCh38\ttest-v1\t-\t%s\n' \
        "$fasta_checksum" >>"$database_manifest"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        SPLICEAI spliceai.vcf.gz test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        SPLICEAI_INDEX spliceai.vcf.gz.tbi test-v1 "$fasta_checksum"
    preflight_fixture_add_database_file "$database_manifest" "$root/databases" \
        DBNSFP dbnsfp.gz test-v1 "$fasta_checksum"

    preflight_fixture_write_mock_mamba "$root/mamba"
    for environment in qc alignment variant deepvariant octopus annotation report; do
        mkdir -p "$root/envs/$environment"/{bin,conda-meta}
        printf '@EXPLICIT\nhttps://example.invalid/%s-1.0-0.conda\n' "$environment" \
            >"$root/envs/$environment.lock"
        printf 'name: %s\ndependencies:\n  - mock=1.0\n' "$environment" \
            >"$root/envs/$environment.yml"
    done
    preflight_fixture_write_mock_tool "$root/envs/mock-tool"
    for tool in fastqc fastp multiqc bwa-mem2 samtools picard mosdepth gatk \
        bcftools htsfile octopus run_deepvariant vep python; do
        for environment in qc alignment variant deepvariant octopus annotation report; do
            ln -s "$root/envs/mock-tool" "$root/envs/$environment/bin/$tool"
        done
    done

    if [[ "$assay" == WES ]]; then
        capture_value='intervals/capture.bed'
    fi
    cat >"$root/clinical.conf" <<EOF
RUN_ID=RUN_001
RUN_ROOT=runs
REFERENCE_DIR=references
DATABASE_DIR=databases
ENV_DIR=envs
ASSAY_PROFILE_DIR=profiles
ASSAY_PROFILE=test-${assay,,}-v1
SCRATCH_DIR=scratch
MAMBA_BIN=mamba
MIN_RUN_FREE_GB=0
MIN_SCRATCH_FREE_GB=0
DISK_SPACE_POLICY=ERROR
EOF
    cat >"$root/samples.tsv" <<EOF
sample_id	assay	platform	fastq_r1	fastq_r2	library_id	platform_unit	sequencing_center	read_group_id	expected_chromosome_complement	capture_intervals	reportable_intervals
SAMPLE_001	$assay	ILLUMINA	data/sample_R1.fastq.gz	data/sample_R2.fastq.gz	LIB001	FC01.L1	CENTER1	SAMPLE_001.FC01.L1	UNKNOWN	$capture_value	intervals/reportable.bed
EOF
}
