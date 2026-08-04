#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# LOCKED INPUTS
###############################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/GRCh38"
readonly ALIGNMENT_ENVIRONMENT="${ENV_DIR:-$REPOSITORY_ROOT/envs}/alignment"
readonly ENV_ACTIVATE="$REPOSITORY_ROOT/envs/activate.sh"

# This is the only reference identity accepted by ClinicalSuite V2.
readonly REFERENCE_VERSION='GRCh38_full_analysis_set_plus_decoy_hla-20150309'
readonly SOURCE_ROOT='https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome'
readonly FASTA_NAME='GRCh38_full_analysis_set_plus_decoy_hla.fa'
readonly FASTA_SIZE='3263683042'
readonly FASTA_SHA256='3b103f4742abfd54938fb0333e19ad067635c8eb86f1dbf0ce44b165c4292b50'
readonly FASTA_URL="$SOURCE_ROOT/$FASTA_NAME"
readonly ALT_NAME="${FASTA_NAME}.alt"
readonly ALT_SIZE='487553'
readonly ALT_SHA256='d9254da07b8030e26129dc29d9d02b9c30a360b233a367ce041691c00407d510'
readonly ALT_URL="$SOURCE_ROOT/$ALT_NAME"
readonly SOURCE_README_NAME='README.20150309.GRCh38_full_analysis_set_plus_decoy_hla'
readonly SOURCE_README_SIZE='1973'
readonly SOURCE_README_SHA256='f8662c7ff1b9abdf986eca668559d38a509d4b65cc553b0fa2ee64fe3d217ea1'
readonly SOURCE_README_URL="$SOURCE_ROOT/$SOURCE_README_NAME"
readonly REGIONS_NAME='20150713_location_of_centromeres_and_other_regions.txt'
readonly REGIONS_SIZE='1300'
readonly REGIONS_SHA256='998b492d65a60cc557735d90c9215bf934289f8040e4583bd4df8aa4c073c881'
readonly REGIONS_URL="$SOURCE_ROOT/$REGIONS_NAME"
readonly DICTIONARY_NAME='GRCh38_full_analysis_set_plus_decoy_hla.dict'
readonly PAR_NAME='GRCh38_full_analysis_set_plus_decoy_hla_PAR.bed'
readonly MIN_BWA_INDEX_MEMORY_BYTES='96000000000'

###############################################################################
# HELPERS
###############################################################################

usage() {
    cat <<EOF
Usage: ${0##*/} [--output-dir DIR]

Download the locked Broad GRCh38 Full Analysis Set + Decoy + HLA FASTA and its
official companion metadata. Generate Samtools, Picard, and BWA-MEM2 indexes
with the validated ClinicalSuite alignment image and write checksums plus
provenance. No other GRCh38 FASTA is supported. Annotation databases and
known-sites VCFs are never downloaded.

Local BWA-MEM2 index generation requires at least 96 GB of physical RAM.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command is unavailable: $1"
}

download_locked_sha256() {
    local url="$1"
    local destination="$2"
    local expected_size="$3"
    local expected_sha256="$4"
    local partial="${destination}.part"
    local actual_size actual_sha256

    if [[ ! -f "$destination" ]]; then
        printf 'DOWNLOAD: %s\n' "$url"
        curl --fail --location --retry 5 --retry-all-errors \
            --continue-at - --output "$partial" "$url"
        mv -- "$partial" "$destination"
    fi

    actual_size="$(stat -c '%s' "$destination")"
    [[ "$actual_size" == "$expected_size" ]] ||
        die "size mismatch for $destination: expected $expected_size, found $actual_size"
    actual_sha256="$(sha256sum "$destination" | awk '{print $1}')"
    [[ "$actual_sha256" == "$expected_sha256" ]] ||
        die "source SHA-256 mismatch for $destination"
}

run_alignment_environment() {
    local reference_dir="$1"
    shift
    local argument
    local -a command=()

    for argument in "$@"; do
        command+=("${argument//\/reference/"$reference_dir"}")
    done
    "$ENV_ACTIVATE" "$ALIGNMENT_ENVIRONMENT" -- "${command[@]}"
}

validate_locked_fasta() {
    local fasta="$1"
    local fai="$2"
    local contig_count

    contig_count="$(wc -l <"$fai")"
    [[ "$contig_count" -eq 3366 ]] ||
        die "locked FASTA index must contain 3366 contigs; found $contig_count"
    awk -F '\t' '
        $1 == "chr1" {chr1 = 1}
        $1 == "chrM" {chrM = 1}
        $1 ~ /_decoy$/ {decoy = 1}
        $1 ~ /^HLA-/ {hla = 1}
        END {exit !(chr1 && chrM && decoy && hla)}
    ' "$fai" ||
        die "FASTA does not contain the locked chr, decoy, and HLA contig classes"
    [[ "$(sha256sum "$fasta" | awk '{print $1}')" == "$FASTA_SHA256" ]] ||
        die 'locked FASTA checksum changed after indexing'
}

write_par_intervals() {
    local destination="$1"
    local temporary="${destination}.tmp.$$"

    # GRCh38 PAR coordinates are rendered as 0-based, half-open intervals.
    # The Y coordinates are also recorded by the official companion regions
    # file. X and Y rows are both emitted because callers require both copies.
    {
        printf '#assembly=GRCh38\n'
        printf '#reference=%s\n' "$REFERENCE_VERSION"
        printf '#coordinates=0-based-half-open\n'
        printf '#source=GRC GRCh38 pseudoautosomal regions; 1000 Genomes companion regions metadata\n'
        printf 'chrX\t10000\t2781479\tPAR1\n'
        printf 'chrY\t10000\t2781479\tPAR1\n'
        printf 'chrX\t155701382\t156030895\tPAR2\n'
        printf 'chrY\t56887902\t57217415\tPAR2\n'
    } >"$temporary"
    mv -- "$temporary" "$destination"
}

write_download_provenance() {
    local output_dir="$1"
    local destination="$output_dir/source_downloads.tsv"
    local temporary="${destination}.tmp.$$"
    local artifact source size expected_sha local_sha

    {
        printf 'artifact\tsource\tversion\tsize\tsource_sha256\tlocal_sha256\n'
        while IFS=$'\t' read -r artifact source size expected_sha; do
            local_sha="$(sha256sum "$output_dir/$artifact" | awk '{print $1}')"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$artifact" "$source" "$REFERENCE_VERSION" "$size" \
                "$expected_sha" "$local_sha"
        done <<EOF
$FASTA_NAME	$FASTA_URL	$FASTA_SIZE	$FASTA_SHA256
$ALT_NAME	$ALT_URL	$ALT_SIZE	$ALT_SHA256
$SOURCE_README_NAME	$SOURCE_README_URL	$SOURCE_README_SIZE	$SOURCE_README_SHA256
$REGIONS_NAME	$REGIONS_URL	$REGIONS_SIZE	$REGIONS_SHA256
EOF
    } >"$temporary"
    chmod 0444 -- "$temporary"
    mv -- "$temporary" "$destination"
}

require_bwa_index_memory() {
    local available

    available="$(
        awk '/^MemTotal:/ {print $2 * 1024; found=1} END {if (!found) exit 1}' \
            /proc/meminfo
    )" || die 'cannot determine physical memory for BWA-MEM2 indexing'
    awk -v available="$available" -v required="$MIN_BWA_INDEX_MEMORY_BYTES" \
        'BEGIN {exit !(available >= required)}' ||
        die "BWA-MEM2 indexing requires at least 96 GB RAM; this host has $((available / 1000000000)) GB. Completed downloads and indexes were preserved."
}

write_metadata() {
    local output_dir="$1"
    local fasta_sha alt_sha regions_sha readme_sha fai_sha dict_sha par_sha
    local checksum_temporary="$output_dir/.checksums.sha256.tmp.$$"
    local provenance_temporary="$output_dir/.source_provenance.tsv.tmp.$$"
    local manifest_temporary="$output_dir/.reference_manifest.tsv.tmp.$$"
    local complete_temporary="$output_dir/.complete.tmp.$$"

    fasta_sha="$(sha256sum "$output_dir/$FASTA_NAME" | awk '{print $1}')"
    alt_sha="$(sha256sum "$output_dir/bwa-mem2/$ALT_NAME" | awk '{print $1}')"
    regions_sha="$(sha256sum "$output_dir/$REGIONS_NAME" | awk '{print $1}')"
    readme_sha="$(sha256sum "$output_dir/$SOURCE_README_NAME" | awk '{print $1}')"
    fai_sha="$(sha256sum "$output_dir/${FASTA_NAME}.fai" | awk '{print $1}')"
    dict_sha="$(sha256sum "$output_dir/$DICTIONARY_NAME" | awk '{print $1}')"
    par_sha="$(sha256sum "$output_dir/$PAR_NAME" | awk '{print $1}')"

    (
        cd -- "$output_dir"
        find . -type f \
            ! -name 'checksums.sha256' \
            ! -name 'source_provenance.tsv' \
            ! -name 'reference_manifest.tsv' \
            ! -name '.complete' \
            -printf '%P\n' |
            LC_ALL=C sort |
            while IFS= read -r path; do
                sha256sum "$path"
            done
    ) >"$checksum_temporary"

    {
        printf 'artifact\tsource\tversion\tsource_size\tsource_sha256\tlocal_sha256\n'
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$FASTA_NAME" "$FASTA_URL" "$REFERENCE_VERSION" "$FASTA_SIZE" \
            "$FASTA_SHA256" "$fasta_sha"
        printf 'bwa-mem2/%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$ALT_NAME" "$ALT_URL" "$REFERENCE_VERSION" "$ALT_SIZE" \
            "$ALT_SHA256" "$alt_sha"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$SOURCE_README_NAME" "$SOURCE_README_URL" "$REFERENCE_VERSION" \
            "$SOURCE_README_SIZE" "$SOURCE_README_SHA256" "$readme_sha"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$REGIONS_NAME" "$REGIONS_URL" "$REFERENCE_VERSION" "$REGIONS_SIZE" \
            "$REGIONS_SHA256" "$regions_sha"
        printf '%s.fai\tgenerated:Samtools-1.24\t%s\t-\t-\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fai_sha"
        printf '%s\tgenerated:Picard-3.4.0\t%s\t-\t-\t%s\n' \
            "$DICTIONARY_NAME" "$REFERENCE_VERSION" "$dict_sha"
        printf 'bwa-mem2/\tgenerated:BWA-MEM2-2.3\t%s\t-\t-\tsee-checksums.sha256\n' \
            "$REFERENCE_VERSION"
        printf '%s\tderived:GRC-GRCh38-PAR\t%s\t-\t-\t%s\n' \
            "$PAR_NAME" "$REFERENCE_VERSION" "$par_sha"
    } >"$provenance_temporary"

    {
        printf 'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\n'
        printf 'GRCH38_FASTA\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fasta_sha"
        printf 'GRCH38_FASTA_FAI\t%s.fai\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fai_sha"
        printf 'GRCH38_SEQUENCE_DICTIONARY\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$DICTIONARY_NAME" "$REFERENCE_VERSION" "$dict_sha"
        printf 'BWA_MEM2_INDEX\tbwa-mem2\tDIRECTORY\tMANDATORY\tGRCh38\t%s\t-\n' \
            "$REFERENCE_VERSION"
        printf 'GRCH38_PAR_INTERVALS\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$PAR_NAME" "$REFERENCE_VERSION" "$par_sha"
        printf 'GRCH38_REGIONS_METADATA\t%s\tFILE\tOPTIONAL\tGRCh38\t%s\t%s\n' \
            "$REGIONS_NAME" "$REFERENCE_VERSION" "$regions_sha"
    } >"$manifest_temporary"

    {
        printf 'format=ClinicalSuite-reference-v1\n'
        printf 'bundle=%s\n' "$REFERENCE_VERSION"
        printf 'fasta_sha256=%s\n' "$fasta_sha"
        printf 'completed_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } >"$complete_temporary"

    chmod 0444 -- "$checksum_temporary" "$provenance_temporary" \
        "$manifest_temporary" "$complete_temporary"
    mv -- "$checksum_temporary" "$output_dir/checksums.sha256"
    mv -- "$provenance_temporary" "$output_dir/source_provenance.tsv"
    mv -- "$manifest_temporary" "$output_dir/reference_manifest.tsv"
    mv -- "$complete_temporary" "$output_dir/.complete"
}

verify_complete_bundle() {
    local output_dir="$1"

    [[ -f "$output_dir/.complete" && -f "$output_dir/checksums.sha256" ]] ||
        return 1
    grep -Fxq "bundle=$REFERENCE_VERSION" "$output_dir/.complete" || return 1
    (cd -- "$output_dir" && sha256sum --check --quiet checksums.sha256)
}

###############################################################################
# MAIN
###############################################################################

main() {
    local output_dir="$DEFAULT_OUTPUT_DIR"
    local fasta_path alt_path regions_path source_readme_path bwa_temporary

    while (( $# > 0 )); do
        case "$1" in
            --output-dir)
                (( $# >= 2 )) || die '--output-dir requires a value'
                output_dir="$2"
                shift 2
                ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done

    [[ "$output_dir" == /* ]] || output_dir="$(pwd -P)/$output_dir"
    require_command curl
    require_command sha256sum
    require_command stat
    [[ -x "$ENV_ACTIVATE" ]] ||
        die "environment launcher is unavailable: $ENV_ACTIVATE"
    [[ -d "$ALIGNMENT_ENVIRONMENT/conda-meta" ]] ||
        die "alignment environment is unavailable: $ALIGNMENT_ENVIRONMENT"

    mkdir -p -- "$output_dir"
    if verify_complete_bundle "$output_dir"; then
        printf 'REFERENCE READY: %s\n' "$output_dir"
        return 0
    fi

    fasta_path="$output_dir/$FASTA_NAME"
    alt_path="$output_dir/$ALT_NAME"
    regions_path="$output_dir/$REGIONS_NAME"
    source_readme_path="$output_dir/$SOURCE_README_NAME"

    download_locked_sha256 "$FASTA_URL" "$fasta_path" "$FASTA_SIZE" "$FASTA_SHA256"
    download_locked_sha256 "$ALT_URL" "$alt_path" "$ALT_SIZE" "$ALT_SHA256"
    download_locked_sha256 \
        "$SOURCE_README_URL" "$source_readme_path" \
        "$SOURCE_README_SIZE" "$SOURCE_README_SHA256"
    download_locked_sha256 \
        "$REGIONS_URL" "$regions_path" "$REGIONS_SIZE" "$REGIONS_SHA256"
    write_download_provenance "$output_dir"

    if [[ ! -s "$output_dir/${FASTA_NAME}.fai" ]]; then
        printf 'INDEX: Samtools FASTA index\n'
        run_alignment_environment "$output_dir" \
            samtools faidx -o "/reference/.${FASTA_NAME}.fai.tmp" \
            "/reference/$FASTA_NAME"
        mv -- "$output_dir/.${FASTA_NAME}.fai.tmp" \
            "$output_dir/${FASTA_NAME}.fai"
    else
        printf 'REUSE: Samtools FASTA index\n'
    fi
    validate_locked_fasta "$fasta_path" "$output_dir/${FASTA_NAME}.fai"

    if [[ ! -s "$output_dir/$DICTIONARY_NAME" ]]; then
        printf 'INDEX: Picard sequence dictionary\n'
        run_alignment_environment "$output_dir" \
            picard CreateSequenceDictionary \
            "R=/reference/$FASTA_NAME" \
            "O=/reference/.${DICTIONARY_NAME}.tmp"
        mv -- "$output_dir/.${DICTIONARY_NAME}.tmp" \
            "$output_dir/$DICTIONARY_NAME"
    else
        printf 'REUSE: Picard sequence dictionary\n'
    fi

    write_par_intervals "$output_dir/$PAR_NAME"

    printf 'INDEX: BWA-MEM2\n'
    require_bwa_index_memory
    bwa_temporary="$output_dir/.bwa-mem2.tmp.$$"
    mkdir -p -- "$bwa_temporary"
    cp -- "$alt_path" "$bwa_temporary/$ALT_NAME"
    run_alignment_environment "$output_dir" \
        bwa-mem2 index \
        -p "/reference/${bwa_temporary##"$output_dir/"}/${FASTA_NAME}" \
        "/reference/$FASTA_NAME"
    [[ ! -e "$output_dir/bwa-mem2" ]] ||
        die "refusing to replace existing incomplete BWA-MEM2 index directory"
    mv -- "$bwa_temporary" "$output_dir/bwa-mem2"

    write_metadata "$output_dir"
    find "$output_dir" -type f -exec chmod a-w -- {} +
    verify_complete_bundle "$output_dir" ||
        die 'final reference checksum verification failed'
    printf 'REFERENCE READY: %s\n' "$output_dir"
}

main "$@"
