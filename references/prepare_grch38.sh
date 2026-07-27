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
readonly ALIGNMENT_IMAGE="$REPOSITORY_ROOT/containers/alignment.sif"
readonly APPTAINER_BIN="${APPTAINER_BIN:-/usr/bin/apptainer}"

readonly REFERENCE_VERSION='Broad-GATK-hg38-v0-GRCh38'
readonly FASTA_NAME='Homo_sapiens_assembly38.fasta'
readonly FASTA_GENERATION='1575676516681666'
readonly FASTA_SIZE='3249912778'
readonly FASTA_MD5='7ff134953dcca8c8997453bbb80b6b5e'
readonly FASTA_URL="https://storage.googleapis.com/download/storage/v1/b/gcp-public-data--broad-references/o/hg38%2Fv0%2F${FASTA_NAME}?alt=media&generation=${FASTA_GENERATION}"

readonly ALT_SOURCE_NAME='Homo_sapiens_assembly38.fasta.64.alt'
readonly ALT_NAME="${FASTA_NAME}.alt"
readonly ALT_GENERATION='1575676516489805'
readonly ALT_SIZE='487553'
readonly ALT_MD5='b07e65aa4425bc365141756f5c98328c'
readonly ALT_URL="https://storage.googleapis.com/download/storage/v1/b/gcp-public-data--broad-references/o/hg38%2Fv0%2F${ALT_SOURCE_NAME}?alt=media&generation=${ALT_GENERATION}"

readonly REGIONS_NAME='GCA_000001405.15_GRCh38_assembly_regions.txt'
readonly REGIONS_SIZE='25524'
readonly REGIONS_SHA256='6b91d2c7961a322936db8fd09b7fb4a9143a590882f28c0a628a4ef26897f6c7'
readonly REGIONS_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/${REGIONS_NAME}"
readonly MIN_BWA_INDEX_MEMORY_BYTES='96000000000'

###############################################################################
# HELPERS
###############################################################################

usage() {
    cat <<EOF
Usage: ${0##*/} [--output-dir DIR]

Download the locked Broad GATK GRCh38 FASTA and ALT metadata, generate Samtools,
Picard, and BWA-MEM2 indexes with the validated ClinicalSuite alignment image,
and write checksums plus provenance. Annotation databases and known-sites VCFs
are never downloaded. Local BWA-MEM2 index generation requires at least 96 GB
of physical RAM.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

download_locked_md5() {
    local url="$1"
    local destination="$2"
    local expected_size="$3"
    local expected_md5="$4"
    local partial="${destination}.part"
    local actual_size actual_md5

    if [[ ! -f "$destination" ]]; then
        printf 'DOWNLOAD: %s\n' "$url"
        curl --fail --location --retry 5 --retry-all-errors \
            --continue-at - --output "$partial" "$url"
        mv -- "$partial" "$destination"
    fi

    actual_size="$(stat -c '%s' "$destination")"
    [[ "$actual_size" == "$expected_size" ]] ||
        die "size mismatch for $destination: expected $expected_size, found $actual_size"
    actual_md5="$(md5sum "$destination" | awk '{print $1}')"
    [[ "$actual_md5" == "$expected_md5" ]] ||
        die "source MD5 mismatch for $destination"
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

run_alignment_container() {
    local reference_dir="$1"
    shift

    "$APPTAINER_BIN" exec --cleanenv --containall --no-home --pwd / \
        --net --network none \
        --bind "$reference_dir:/reference:rw" \
        "$ALIGNMENT_IMAGE" "$@"
}

write_par_intervals() {
    local regions_file="$1"
    local destination="$2"
    local temporary="${destination}.tmp.$$"

    awk -F '\t' '
        BEGIN {
            OFS = "\t"
            print "#assembly=GRCh38"
            print "#source=GCA_000001405.15_GRCh38_assembly_regions.txt"
            print "#coordinates=0-based-half-open"
        }
        $5 == "PAR" {
            sub(/\r$/, "", $8)
            print "chr" $2, $3 - 1, $4, $1
        }
    ' "$regions_file" >"$temporary"
    [[ "$(awk '!/^#/ {count++} END {print count + 0}' "$temporary")" -eq 4 ]] ||
        die 'expected four GRCh38 pseudoautosomal intervals'
    mv -- "$temporary" "$destination"
}

write_download_provenance() {
    local output_dir="$1"
    local destination="$output_dir/source_downloads.tsv"
    local temporary="${destination}.tmp.$$"
    local fasta_sha alt_sha regions_sha

    fasta_sha="$(sha256sum "$output_dir/$FASTA_NAME" | awk '{print $1}')"
    alt_sha="$(sha256sum "$output_dir/$ALT_SOURCE_NAME" | awk '{print $1}')"
    regions_sha="$(sha256sum "$output_dir/$REGIONS_NAME" | awk '{print $1}')"
    {
        printf 'artifact\tsource\tgeneration_or_version\tsize\tsource_digest\tlocal_sha256\n'
        printf '%s\t%s\t%s\t%s\tmd5:%s\t%s\n' \
            "$FASTA_NAME" "$FASTA_URL" "$FASTA_GENERATION" "$FASTA_SIZE" \
            "$FASTA_MD5" "$fasta_sha"
        printf '%s\t%s\t%s\t%s\tmd5:%s\t%s\n' \
            "$ALT_SOURCE_NAME" "$ALT_URL" "$ALT_GENERATION" "$ALT_SIZE" \
            "$ALT_MD5" "$alt_sha"
        printf '%s\t%s\tGCA_000001405.15\t%s\tsha256:%s\t%s\n' \
            "$REGIONS_NAME" "$REGIONS_URL" "$REGIONS_SIZE" \
            "$REGIONS_SHA256" "$regions_sha"
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
    local fasta_sha alt_sha regions_sha fai_sha dict_sha par_sha
    local checksum_temporary="$output_dir/.checksums.sha256.tmp.$$"
    local provenance_temporary="$output_dir/.source_provenance.tsv.tmp.$$"
    local manifest_temporary="$output_dir/.reference_manifest.tsv.tmp.$$"
    local complete_temporary="$output_dir/.complete.tmp.$$"

    fasta_sha="$(sha256sum "$output_dir/$FASTA_NAME" | awk '{print $1}')"
    alt_sha="$(sha256sum "$output_dir/bwa-mem2/$ALT_NAME" | awk '{print $1}')"
    regions_sha="$(sha256sum "$output_dir/$REGIONS_NAME" | awk '{print $1}')"
    fai_sha="$(sha256sum "$output_dir/${FASTA_NAME}.fai" | awk '{print $1}')"
    dict_sha="$(sha256sum "$output_dir/Homo_sapiens_assembly38.dict" | awk '{print $1}')"
    par_sha="$(sha256sum "$output_dir/GRCh38_PAR.bed" | awk '{print $1}')"

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
        printf 'artifact\tsource\tversion_or_generation\tsource_size\tsource_digest\tlocal_sha256\n'
        printf '%s\t%s\t%s\t%s\tmd5:%s\t%s\n' \
            "$FASTA_NAME" "$FASTA_URL" "$FASTA_GENERATION" "$FASTA_SIZE" \
            "$FASTA_MD5" "$fasta_sha"
        printf 'bwa-mem2/%s\t%s\t%s\t%s\tmd5:%s\t%s\n' \
            "$ALT_NAME" "$ALT_URL" "$ALT_GENERATION" "$ALT_SIZE" \
            "$ALT_MD5" "$alt_sha"
        printf '%s\t%s\tGCA_000001405.15\t%s\tsha256:%s\t%s\n' \
            "$REGIONS_NAME" "$REGIONS_URL" "$REGIONS_SIZE" \
            "$REGIONS_SHA256" "$regions_sha"
        printf '%s.fai\tgenerated:Samtools-1.24\t%s\t-\t-\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fai_sha"
        printf 'Homo_sapiens_assembly38.dict\tgenerated:Picard-3.4.0\t%s\t-\t-\t%s\n' \
            "$REFERENCE_VERSION" "$dict_sha"
        printf 'bwa-mem2/\tgenerated:BWA-MEM2-2.3-release-asset\t%s\t-\t-\tsee-checksums.sha256\n' \
            "$REFERENCE_VERSION"
        printf 'GRCh38_PAR.bed\tderived:%s\tGCA_000001405.15\t-\t-\t%s\n' \
            "$REGIONS_NAME" "$par_sha"
    } >"$provenance_temporary"

    {
        printf 'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\n'
        printf 'GRCH38_FASTA\t%s\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fasta_sha"
        printf 'GRCH38_FASTA_FAI\t%s.fai\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$FASTA_NAME" "$REFERENCE_VERSION" "$fai_sha"
        printf 'GRCH38_SEQUENCE_DICTIONARY\tHomo_sapiens_assembly38.dict\tFILE\tMANDATORY\tGRCh38\t%s\t%s\n' \
            "$REFERENCE_VERSION" "$dict_sha"
        printf 'BWA_MEM2_INDEX\tbwa-mem2\tDIRECTORY\tMANDATORY\tGRCh38\tBWA-MEM2-2.3\t-\n'
        printf 'GRCH38_PAR_INTERVALS\tGRCh38_PAR.bed\tFILE\tMANDATORY\tGRCh38\tGCA_000001405.15\t%s\n' \
            "$par_sha"
        printf 'GRCH38_ASSEMBLY_REGIONS\t%s\tFILE\tOPTIONAL\tGRCh38\tGCA_000001405.15\t%s\n' \
            "$REGIONS_NAME" "$regions_sha"
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
    (cd -- "$output_dir" && sha256sum --check --quiet checksums.sha256)
}

###############################################################################
# MAIN
###############################################################################

main() {
    local output_dir="$DEFAULT_OUTPUT_DIR"
    local fasta_path alt_source_path regions_path bwa_temporary

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
    require_command md5sum
    require_command sha256sum
    require_command stat
    [[ -x "$APPTAINER_BIN" ]] || die "Apptainer is unavailable: $APPTAINER_BIN"
    [[ -s "$ALIGNMENT_IMAGE" ]] || die "alignment image is unavailable: $ALIGNMENT_IMAGE"

    mkdir -p -- "$output_dir"
    if verify_complete_bundle "$output_dir"; then
        printf 'REFERENCE READY: %s\n' "$output_dir"
        return 0
    fi

    fasta_path="$output_dir/$FASTA_NAME"
    alt_source_path="$output_dir/$ALT_SOURCE_NAME"
    regions_path="$output_dir/$REGIONS_NAME"

    download_locked_md5 "$FASTA_URL" "$fasta_path" "$FASTA_SIZE" "$FASTA_MD5"
    download_locked_md5 "$ALT_URL" "$alt_source_path" "$ALT_SIZE" "$ALT_MD5"
    download_locked_sha256 \
        "$REGIONS_URL" "$regions_path" "$REGIONS_SIZE" "$REGIONS_SHA256"

    write_download_provenance "$output_dir"

    if [[ ! -s "$output_dir/${FASTA_NAME}.fai" ]]; then
        printf 'INDEX: Samtools FASTA index\n'
        run_alignment_container "$output_dir" \
            samtools faidx -o "/reference/.${FASTA_NAME}.fai.tmp" \
            "/reference/$FASTA_NAME"
        mv -- "$output_dir/.${FASTA_NAME}.fai.tmp" "$output_dir/${FASTA_NAME}.fai"
    else
        printf 'REUSE: Samtools FASTA index\n'
    fi

    if [[ ! -s "$output_dir/Homo_sapiens_assembly38.dict" ]]; then
        printf 'INDEX: Picard sequence dictionary\n'
        run_alignment_container "$output_dir" \
            picard CreateSequenceDictionary \
            "R=/reference/$FASTA_NAME" \
            'O=/reference/.Homo_sapiens_assembly38.dict.tmp'
        mv -- "$output_dir/.Homo_sapiens_assembly38.dict.tmp" \
            "$output_dir/Homo_sapiens_assembly38.dict"
    else
        printf 'REUSE: Picard sequence dictionary\n'
    fi

    write_par_intervals "$regions_path" "$output_dir/GRCh38_PAR.bed"

    printf 'INDEX: BWA-MEM2\n'
    require_bwa_index_memory
    bwa_temporary="$output_dir/.bwa-mem2.tmp.$$"
    mkdir -p -- "$bwa_temporary"
    cp -- "$alt_source_path" "$bwa_temporary/$ALT_NAME"
    run_alignment_container "$output_dir" \
        bwa-mem2 index \
        -p "/reference/${bwa_temporary##"$output_dir/"}/${FASTA_NAME}" \
        "/reference/$FASTA_NAME"
    [[ ! -e "$output_dir/bwa-mem2" ]] ||
        die "refusing to replace existing incomplete BWA-MEM2 index directory"
    mv -- "$bwa_temporary" "$output_dir/bwa-mem2"
    rm -f -- "$alt_source_path"

    write_metadata "$output_dir"
    find "$output_dir" -type f -exec chmod a-w -- {} +

    verify_complete_bundle "$output_dir" ||
        die 'final reference checksum verification failed'
    printf 'REFERENCE READY: %s\n' "$output_dir"
}

main "$@"
