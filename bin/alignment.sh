#!/usr/bin/env bash
# ClinicalSuite V2 Module 7: alignment and analysis-ready BAM preparation.

set -Eeuo pipefail

ALIGNMENT_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ALIGNMENT_SCRIPT_DIR
ALIGNMENT_REPOSITORY_ROOT="$(cd -- "$ALIGNMENT_SCRIPT_DIR/.." && pwd -P)"
readonly ALIGNMENT_REPOSITORY_ROOT
# shellcheck source=config/parser.sh
source "$ALIGNMENT_REPOSITORY_ROOT/config/parser.sh"
# shellcheck source=bin/common.sh
source "$ALIGNMENT_SCRIPT_DIR/common.sh"

readonly ALIGNMENT_MODULE_VERSION='2.0.0'
readonly ALIGNMENT_EX_USAGE=64
readonly ALIGNMENT_EX_UNAVAILABLE=69
readonly ALIGNMENT_LOCKED_REFERENCE_BASENAME='GRCh38_full_analysis_set_plus_decoy_hla.fa'
readonly ALIGNMENT_LOCKED_REFERENCE_VERSION='GRCh38_full_analysis_set_plus_decoy_hla-20150309'
readonly ALIGNMENT_LOCKED_FASTA_SHA256='3b103f4742abfd54938fb0333e19ad067635c8eb86f1dbf0ce44b165c4292b50'
readonly -a ALIGNMENT_REQUIRED_REFERENCE_IDS=(
    GRCH38_FASTA
    GRCH38_FASTA_FAI
    GRCH38_SEQUENCE_DICTIONARY
    BWA_MEM2_INDEX
    KNOWN_INDELS
    KNOWN_INDELS_INDEX
    MILLS_INDELS
    MILLS_INDELS_INDEX
)
readonly -a ALIGNMENT_CORE_REFERENCE_IDS=(
    GRCH38_FASTA
    GRCH38_FASTA_FAI
    GRCH38_SEQUENCE_DICTIONARY
    BWA_MEM2_INDEX
)
readonly -a ALIGNMENT_BWA_INDEX_SUFFIXES=(
    .0123
    .amb
    .ann
    .bwt.2bit.64
    .pac
    .alt
)

declare -gA ALIGNMENT_REFERENCE_PATH=()
declare -gA ALIGNMENT_REFERENCE_KIND=()
declare -gA ALIGNMENT_REFERENCE_VERSION=()
declare -gA ALIGNMENT_REFERENCE_CHECKSUM=()
declare -gA ALIGNMENT_QC_FASTQ_R1=()
declare -gA ALIGNMENT_QC_FASTQ_R2=()
declare -gA ALIGNMENT_QC_FASTQ_SHA256_R1=()
declare -gA ALIGNMENT_QC_FASTQ_SHA256_R2=()
declare -gA ALIGNMENT_QC_READ_PAIRS=()
declare -gA ALIGNMENT_QC_DECISION=()

alignment_usage() {
    cat <<'EOF'
Usage: bin/alignment.sh --config FILE --samples FILE [OPTIONS]

Run ClinicalSuite Module 7 with validated QC handoff files and the locked
alignment/GATK containers.

Options:
  --config FILE       validated clinical.conf
  --samples FILE      validated samples.tsv
  --qc-dir DIR        Module 6 output (default: RUN_DIR/qc)
  --output-dir DIR    output override (default: RUN_DIR/alignment)
  --quiet             suppress routine terminal messages
  --verbose           enable debug logging
  -h, --help          show this help
EOF
}

alignment_reset_state() {
    ALIGNMENT_REFERENCE_PATH=()
    ALIGNMENT_REFERENCE_KIND=()
    ALIGNMENT_REFERENCE_VERSION=()
    ALIGNMENT_REFERENCE_CHECKSUM=()
    ALIGNMENT_QC_FASTQ_R1=()
    ALIGNMENT_QC_FASTQ_R2=()
    ALIGNMENT_QC_FASTQ_SHA256_R1=()
    ALIGNMENT_QC_FASTQ_SHA256_R2=()
    ALIGNMENT_QC_READ_PAIRS=()
    ALIGNMENT_QC_DECISION=()
}

alignment_array_contains() {
    local requested="$1"
    shift
    local value

    for value in "$@"; do
        [[ "$value" == "$requested" ]] && return 0
    done
    return 1
}

alignment_sample_read_group() {
    local sample_id="$1"

    # BWA expects escaped tab sequences. Passing literal tabs corrupts its @PG
    # CL field and produces a BAM header that HTSJDK cannot parse.
    printf '@RG\\tID:%s\\tSM:%s\\tLB:%s\\tPL:%s\\tPU:%s\\tCN:%s' \
        "${CLINICAL_SAMPLES[$sample_id.read_group_id]}" \
        "${CLINICAL_SAMPLES[$sample_id.sample_id]}" \
        "${CLINICAL_SAMPLES[$sample_id.library_id]}" \
        "${CLINICAL_SAMPLES[$sample_id.platform]}" \
        "${CLINICAL_SAMPLES[$sample_id.platform_unit]}" \
        "${CLINICAL_SAMPLES[$sample_id.sequencing_center]}"
}

alignment_resolve_manifest_path() {
    local declared="$1"

    clinical_path_is_well_formed "$declared" || return 1
    [[ "$declared" != '..' && "$declared" != ../* && "$declared" != */../* &&
        "$declared" != */.. ]] || return 1
    if [[ "$declared" == /* ]]; then
        printf '%s\n' "$declared"
    elif [[ "$declared" == . ]]; then
        # Keep the project-generated index colocated with its locked FASTA
        # without leaving a literal /./ segment that would break inventory keys.
        printf '%s\n' "$REFERENCE_DIR"
    else
        printf '%s\n' "$REFERENCE_DIR/$declared"
    fi
}

alignment_parse_reference_manifest() {
    local manifest="$1"
    local line line_number=0 id path kind requirement assembly version checksum
    local host_path expected_kind
    declare -A seen=()

    [[ -r "$manifest" ]] ||
        die "Reference manifest is missing or unreadable: $manifest" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        [[ -n "$line" ]] || continue
        if (( line_number == 1 )); then
            [[ "$line" == $'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256' ]] ||
                die "Malformed reference manifest header: $manifest" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            continue
        fi
        clinical_split_tsv "$line"
        (( ${#CLINICAL_TSV_FIELDS[@]} == 7 )) ||
            die "Malformed reference manifest row $line_number: expected 7 fields" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        id="${CLINICAL_TSV_FIELDS[0]}"
        alignment_array_contains "$id" "${ALIGNMENT_REQUIRED_REFERENCE_IDS[@]}" ||
            continue
        [[ ! -v "seen[$id]" ]] ||
            die "Duplicate reference manifest resource: $id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        seen["$id"]=1
        path="${CLINICAL_TSV_FIELDS[1]}"
        kind="${CLINICAL_TSV_FIELDS[2]}"
        requirement="${CLINICAL_TSV_FIELDS[3]}"
        assembly="${CLINICAL_TSV_FIELDS[4]}"
        version="${CLINICAL_TSV_FIELDS[5]}"
        checksum="${CLINICAL_TSV_FIELDS[6],,}"
        expected_kind=FILE
        [[ "$id" != BWA_MEM2_INDEX ]] || expected_kind=DIRECTORY

        [[ "$kind" == "$expected_kind" ]] ||
            die "Invalid resource kind for $id: $kind (expected $expected_kind)" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ "$requirement" == MANDATORY ]] ||
            die "Module 7 resource must be MANDATORY: $id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ "$assembly" == GRCh38 ]] ||
            die "Unsupported reference assembly for $id: $assembly" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ -n "$version" && "$version" != latest ]] ||
            die "Unpinned reference version for $id: $version" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        if alignment_array_contains "$id" "${ALIGNMENT_CORE_REFERENCE_IDS[@]}"; then
            [[ "$version" == "$ALIGNMENT_LOCKED_REFERENCE_VERSION" ]] ||
                die "Unsupported locked-reference version for $id: $version" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
        fi
        host_path="$(alignment_resolve_manifest_path "$path")" ||
            die "Unsafe reference path for $id: $path" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        ALIGNMENT_REFERENCE_PATH["$id"]="$host_path"
        ALIGNMENT_REFERENCE_KIND["$id"]="$kind"
        ALIGNMENT_REFERENCE_VERSION["$id"]="$version"
        ALIGNMENT_REFERENCE_CHECKSUM["$id"]="$checksum"
    done <"$manifest"

    for id in "${ALIGNMENT_REQUIRED_REFERENCE_IDS[@]}"; do
        [[ -v "seen[$id]" ]] ||
            die "Reference manifest does not declare Module 7 resource: $id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
    done
}

alignment_validate_reference_resources() {
    local expected_fasta_sha="$1"
    local id path kind expected actual fasta fai dictionary
    local fasta_contig fai_contig dict_contig suffix index_file contig_count
    local checksum_inventory relative_index

    for id in "${ALIGNMENT_REQUIRED_REFERENCE_IDS[@]}"; do
        path="${ALIGNMENT_REFERENCE_PATH[$id]}"
        kind="${ALIGNMENT_REFERENCE_KIND[$id]}"
        if [[ "$kind" == FILE ]]; then
            [[ -f "$path" && -r "$path" && -s "$path" ]] ||
                die "Required reference file is missing or unreadable: $id ($path)" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            expected="${ALIGNMENT_REFERENCE_CHECKSUM[$id]}"
            [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] ||
                die "Invalid reference SHA-256 declaration: $id" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            actual="$(calculate_checksum "$path")" ||
                die "Cannot calculate reference checksum: $id" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            [[ "$actual" == "$expected" ]] ||
                die "Reference checksum mismatch: $id ($path)" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
        else
            [[ -d "$path" && -r "$path" && -x "$path" ]] ||
                die "BWA-MEM2 index directory is missing or unreadable: $path" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
        fi
    done

    fasta="${ALIGNMENT_REFERENCE_PATH[GRCH38_FASTA]}"
    fai="${ALIGNMENT_REFERENCE_PATH[GRCH38_FASTA_FAI]}"
    dictionary="${ALIGNMENT_REFERENCE_PATH[GRCH38_SEQUENCE_DICTIONARY]}"
    [[ "${fasta##*/}" == "$ALIGNMENT_LOCKED_REFERENCE_BASENAME" ]] ||
        die "Unsupported FASTA basename: ${fasta##*/}" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    [[ "${ALIGNMENT_REFERENCE_CHECKSUM[GRCH38_FASTA]}" == "$expected_fasta_sha" ]] ||
        die 'The manifest FASTA checksum is not the locked ClinicalSuite checksum' \
            "$ALIGNMENT_EX_UNAVAILABLE"

    IFS= read -r fasta_contig <"$fasta" || fasta_contig=''
    fasta_contig="${fasta_contig#>}"
    fasta_contig="${fasta_contig%%[[:space:]]*}"
    IFS=$'\t' read -r fai_contig _ <"$fai" || fai_contig=''
    dict_contig="$(
        awk -F '\t' '$1=="@SQ" {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^SN:/) {sub(/^SN:/, "", $i); print $i; exit}
            }
        }' "$dictionary"
    )"
    [[ -n "$fasta_contig" && "$fasta_contig" == "$fai_contig" &&
        "$fasta_contig" == "$dict_contig" ]] ||
        die "FASTA/FAI/dictionary first-contig mismatch: $fasta_contig/$fai_contig/$dict_contig" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    contig_count="$(wc -l <"$fai")"
    if [[ "$expected_fasta_sha" == "$ALIGNMENT_LOCKED_FASTA_SHA256" ]]; then
        [[ "$contig_count" -eq 3366 ]] ||
            die "Locked FASTA index must contain 3366 contigs; found $contig_count" \
                "$ALIGNMENT_EX_UNAVAILABLE"
    fi

    checksum_inventory="$REFERENCE_DIR/checksums.sha256"
    [[ -r "$checksum_inventory" ]] ||
        die "Reference checksum inventory is missing: $checksum_inventory" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    for suffix in "${ALIGNMENT_BWA_INDEX_SUFFIXES[@]}"; do
        index_file="${ALIGNMENT_REFERENCE_PATH[BWA_MEM2_INDEX]}/$ALIGNMENT_LOCKED_REFERENCE_BASENAME$suffix"
        [[ -f "$index_file" && -r "$index_file" && -s "$index_file" ]] ||
            die "Required BWA-MEM2 index component is missing: $index_file" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ "$index_file" == "$REFERENCE_DIR/"* ]] ||
            die "BWA-MEM2 index is outside REFERENCE_DIR: $index_file" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        relative_index="${index_file#"$REFERENCE_DIR/"}"
        expected="$(
            awk -v path="$relative_index" '$2 == path {print $1}' \
                "$checksum_inventory"
        )"
        [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] ||
            die "Missing or duplicate BWA-MEM2 checksum: $relative_index" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        actual="$(calculate_checksum "$index_file")" ||
            die "Cannot calculate BWA-MEM2 checksum: $relative_index" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ "$actual" == "${expected,,}" ]] ||
            die "BWA-MEM2 index checksum mismatch: $relative_index" \
                "$ALIGNMENT_EX_UNAVAILABLE"
    done
}

alignment_load_qc_handoff() {
    local qc_dir="$1"
    local final_manifest="$qc_dir/final_fastq.tsv"
    local status_manifest="$qc_dir/qc_status.tsv"
    local line line_number sample_id relative_r1 relative_r2 sha_r1 sha_r2 mode
    local failures warnings pairs decision path_r1 path_r2 actual
    declare -A final_seen=()
    declare -A status_seen=()

    [[ -r "$qc_dir/.complete" && -r "$qc_dir/output_checksums.sha256" &&
        -r "$qc_dir/provenance.tsv" ]] ||
        die "Module 6 checkpoint is incomplete: $qc_dir" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    (
        cd -- "$qc_dir"
        sha256sum --check --quiet output_checksums.sha256
    ) || die "Module 6 output checksum verification failed: $qc_dir" \
        "$ALIGNMENT_EX_UNAVAILABLE"

    [[ -r "$final_manifest" && -r "$status_manifest" ]] ||
        die "Module 6 handoff manifests are missing: $qc_dir" \
            "$ALIGNMENT_EX_UNAVAILABLE"
    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        if (( line_number == 1 )); then
            [[ "$line" == $'sample_id\tfastq_r1\tfastq_r2\tsha256_r1\tsha256_r2\tmode' ]] ||
                die "Malformed Module 6 final FASTQ header: $final_manifest" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            continue
        fi
        clinical_split_tsv "$line"
        (( ${#CLINICAL_TSV_FIELDS[@]} == 6 )) ||
            die "Malformed Module 6 final FASTQ row $line_number" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        sample_id="${CLINICAL_TSV_FIELDS[0]}"
        relative_r1="${CLINICAL_TSV_FIELDS[1]}"
        relative_r2="${CLINICAL_TSV_FIELDS[2]}"
        sha_r1="${CLINICAL_TSV_FIELDS[3],,}"
        sha_r2="${CLINICAL_TSV_FIELDS[4],,}"
        mode="${CLINICAL_TSV_FIELDS[5]}"
        [[ -v "CLINICAL_SAMPLES[$sample_id.sample_id]" ]] ||
            die "QC handoff contains an unknown sample: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ ! -v "final_seen[$sample_id]" ]] ||
            die "QC handoff contains a duplicate sample: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        final_seen["$sample_id"]=1
        [[ "$mode" == PASS_THROUGH ]] ||
            die "Unsupported Module 6 FASTQ mode for $sample_id: $mode" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        if ! clinical_path_is_well_formed "$relative_r1" ||
            ! clinical_path_is_well_formed "$relative_r2"; then
            die "Malformed QC FASTQ path for sample: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        fi
        [[ "$relative_r1" != /* && "$relative_r2" != /* &&
            "$relative_r1" != '..' && "$relative_r2" != '..' &&
            "$relative_r1" != ../* && "$relative_r2" != ../* &&
            "$relative_r1" != *'/../'* && "$relative_r2" != *'/../'* &&
            "$relative_r1" != */.. && "$relative_r2" != */.. ]] ||
            die "QC FASTQ paths must remain inside the QC output: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        path_r1="$qc_dir/$relative_r1"
        path_r2="$qc_dir/$relative_r2"
        if ! check_fastq "$path_r1" || ! check_fastq "$path_r2"; then
            die "QC handoff FASTQ validation failed: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        fi
        [[ "$sha_r1" =~ ^[[:xdigit:]]{64}$ &&
            "$sha_r2" =~ ^[[:xdigit:]]{64}$ ]] ||
            die "QC handoff checksum is malformed: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        actual="$(calculate_checksum "$path_r1")"
        [[ "$actual" == "$sha_r1" ]] ||
            die "QC R1 checksum mismatch: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        actual="$(calculate_checksum "$path_r2")"
        [[ "$actual" == "$sha_r2" ]] ||
            die "QC R2 checksum mismatch: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        ALIGNMENT_QC_FASTQ_R1["$sample_id"]="$path_r1"
        ALIGNMENT_QC_FASTQ_R2["$sample_id"]="$path_r2"
        ALIGNMENT_QC_FASTQ_SHA256_R1["$sample_id"]="$sha_r1"
        ALIGNMENT_QC_FASTQ_SHA256_R2["$sample_id"]="$sha_r2"
    done <"$final_manifest"

    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        if (( line_number == 1 )); then
            [[ "$line" == $'sample_id\tfastqc_failures\tfastqc_warnings\tread_pairs\tdecision' ]] ||
                die "Malformed Module 6 status header: $status_manifest" \
                    "$ALIGNMENT_EX_UNAVAILABLE"
            continue
        fi
        IFS=$'\t' read -r sample_id failures warnings pairs decision extra <<<"$line"
        [[ -n "$sample_id" && -z "${extra:-}" &&
            "$failures" =~ ^[0-9]+$ && "$warnings" =~ ^[0-9]+$ &&
            "$pairs" =~ ^[1-9][0-9]*$ &&
            "$decision" =~ ^(PASS|REVIEW|BLOCK)$ ]] ||
            die "Malformed Module 6 status row $line_number" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ ! -v "status_seen[$sample_id]" ]] ||
            die "Duplicate Module 6 status sample: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        status_seen["$sample_id"]=1
        [[ "$decision" != BLOCK ]] ||
            die "Module 6 blocked sample cannot enter Module 7: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
        [[ "$decision" != REVIEW ]] ||
            log_warning "Module 6 review status propagated for sample: $sample_id"
        ALIGNMENT_QC_READ_PAIRS["$sample_id"]="$pairs"
        ALIGNMENT_QC_DECISION["$sample_id"]="$decision"
    done <"$status_manifest"

    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        [[ -v "final_seen[$sample_id]" && -v "status_seen[$sample_id]" ]] ||
            die "Module 6 handoff omits configured sample: $sample_id" \
                "$ALIGNMENT_EX_UNAVAILABLE"
    done
}

alignment_bwa_component_paths() {
    local suffix

    for suffix in "${ALIGNMENT_BWA_INDEX_SUFFIXES[@]}"; do
        printf '%s/%s%s\n' \
            "${ALIGNMENT_REFERENCE_PATH[BWA_MEM2_INDEX]}" \
            "$ALIGNMENT_LOCKED_REFERENCE_BASENAME" "$suffix"
    done
}

alignment_configuration_signature() {
    local qc_dir="$1"
    local sample_id id path relative_path

    {
        printf 'module_version\t%s\n' "$ALIGNMENT_MODULE_VERSION"
        printf 'module_script\t%s\n' \
            "$(calculate_checksum "$ALIGNMENT_SCRIPT_DIR/alignment.sh")"
        printf 'common_library\t%s\n' \
            "$(calculate_checksum "$ALIGNMENT_SCRIPT_DIR/common.sh")"
        printf 'config\t%s\n' "$(calculate_checksum "$CLINICAL_CONFIG_SOURCE")"
        printf 'samples\t%s\n' "$(calculate_checksum "$CLINICAL_SAMPLES_SOURCE")"
        printf 'qc_complete\t%s\n' "$(calculate_checksum "$qc_dir/.complete")"
        printf 'qc_outputs\t%s\n' \
            "$(calculate_checksum "$qc_dir/output_checksums.sha256")"
        printf 'alignment_container\t%s\n' \
            "$(calculate_checksum "$CONTAINER_DIR/alignment.sif")"
        printf 'gatk_container\t%s\n' \
            "$(calculate_checksum "$CONTAINER_DIR/gatk.sif")"
        for id in "${ALIGNMENT_REQUIRED_REFERENCE_IDS[@]}"; do
            printf 'reference_version.%s\t%s\n' "$id" \
                "${ALIGNMENT_REFERENCE_VERSION[$id]}"
            if [[ "${ALIGNMENT_REFERENCE_KIND[$id]}" == FILE ]]; then
                printf 'reference.%s\t%s\n' "$id" \
                    "${ALIGNMENT_REFERENCE_CHECKSUM[$id]}"
            fi
        done
        while IFS= read -r path; do
            relative_path="${path#"$REFERENCE_DIR/"}"
            printf 'bwa_index.%s\t%s\n' "${path##*/}" \
                "$(awk -v item="$relative_path" '$2 == item {print $1}' \
                    "$REFERENCE_DIR/checksums.sha256")"
        done < <(alignment_bwa_component_paths)
        for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
            printf '%s.qc_decision\t%s\n' "$sample_id" \
                "${ALIGNMENT_QC_DECISION[$sample_id]}"
            printf '%s.fastq_r1\t%s\n' "$sample_id" \
                "${ALIGNMENT_QC_FASTQ_SHA256_R1[$sample_id]}"
            printf '%s.fastq_r2\t%s\n' "$sample_id" \
                "${ALIGNMENT_QC_FASTQ_SHA256_R2[$sample_id]}"
        done
    } | sha256sum | awk '{print $1}'
}

alignment_step_signature() {
    local run_signature="$1"
    local sample_id="$2"
    local step="$3"

    printf '%s\t%s\t%s\n' "$run_signature" "$sample_id" "$step" |
        sha256sum | awk '{print $1}'
}

alignment_step_is_complete() {
    local work_dir="$1"
    local sample_id="$2"
    local step="$3"
    local step_signature="$4"
    local marker="$work_dir/checkpoints/$sample_id.$step.complete"
    local checksums="$work_dir/checkpoints/$sample_id.$step.sha256"

    [[ -r "$marker" && -r "$checksums" ]] || return 1
    check_complete_marker "$marker" "$step_signature" || return 1
    (cd -- "$work_dir" && sha256sum --check --quiet "${checksums#"$work_dir/"}")
}

alignment_record_step() {
    local work_dir="$1"
    local sample_id="$2"
    local step="$3"
    local step_signature="$4"
    shift 4
    local checksums="$work_dir/checkpoints/$sample_id.$step.sha256"
    local marker="$work_dir/checkpoints/$sample_id.$step.complete"
    local relative

    (
        cd -- "$work_dir"
        for relative in "$@"; do
            [[ -e "$relative" ]] ||
                die "Cannot checkpoint missing step output: $relative"
            sha256sum "$relative"
        done
    ) >"$checksums"
    create_complete_marker "$marker" "$step_signature" "$checksums"
}

alignment_write_command_manifest() {
    local destination="$1"

    {
        printf 'step\tcommand_contract\n'
        printf '%s\t%s\n' align_sort \
            'bwa-mem2 mem -K 100000000 -Y -t THREADS -R READ_GROUP BWA_PREFIX R1 R2 | samtools view -@ THREADS -u - | samtools sort -@ THREADS -m MEMORY -T TMP -o SORTED_BAM -'
        printf '%s\t%s\n' sorted_index \
            'samtools index -@ THREADS SORTED_BAM'
        printf '%s\t%s\n' mark_duplicates \
            'picard MarkDuplicates INPUT=SORTED_BAM OUTPUT=DEDUP_BAM METRICS_FILE=METRICS REMOVE_DUPLICATES=false ASSUME_SORT_ORDER=coordinate VALIDATION_STRINGENCY=STRICT CREATE_INDEX=true'
        printf '%s\t%s\n' base_recalibrator \
            'gatk BaseRecalibrator -R FASTA -I DEDUP_BAM --known-sites KNOWN_INDELS --known-sites MILLS -O RECAL_TABLE'
        printf '%s\t%s\n' apply_bqsr \
            'gatk ApplyBQSR -R FASTA -I DEDUP_BAM --bqsr-recal-file RECAL_TABLE --create-output-bam-index false -O FINAL_BAM'
        printf '%s\t%s\n' final_index \
            'samtools index -@ THREADS FINAL_BAM'
        printf '%s\t%s\n' validate \
            'samtools quickcheck/flagstat/stats/idxstats + Picard ValidateSamFile + read-group/read-count/duplicate/BQSR checks'
    } >"$destination"
}

alignment_write_tool_versions() {
    local destination="$1"
    local alignment_sha gatk_sha

    alignment_sha="$(calculate_checksum "$CONTAINER_DIR/alignment.sif")"
    gatk_sha="$(calculate_checksum "$CONTAINER_DIR/gatk.sif")"
    {
        printf 'component\tversion\tcontainer\tcontainer_sha256\n'
        printf 'BWA-MEM2\t2.3-release-asset (embedded string 2.2.1)\talignment.sif\t%s\n' \
            "$alignment_sha"
        printf 'Samtools/HTSlib\t1.24\talignment.sif\t%s\n' "$alignment_sha"
        printf 'Picard\t3.4.0\talignment.sif\t%s\n' "$alignment_sha"
        printf 'GATK\t4.6.2.0\tgatk.sif\t%s\n' "$gatk_sha"
        printf 'Apptainer\t%s\thost\t-\n' \
            "$("$APPTAINER_BIN" --version | head -n 1)"
    } >"$destination"
}

alignment_reference_binds() {
    declare -ga ALIGNMENT_GATK_BINDS=(
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[GRCH38_FASTA]}" /reference/ref.fa
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[GRCH38_FASTA_FAI]}" /reference/ref.fa.fai
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[GRCH38_SEQUENCE_DICTIONARY]}" /reference/ref.dict
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[KNOWN_INDELS]}" /known/known_indels.vcf.gz
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[KNOWN_INDELS_INDEX]}" /known/known_indels.vcf.gz.tbi
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[MILLS_INDELS]}" /known/mills.vcf.gz
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[MILLS_INDELS_INDEX]}" /known/mills.vcf.gz.tbi
    )
}

alignment_remove_sample_outputs() {
    local sample_dir="$1"
    shift
    local relative

    for relative in "$@"; do
        rm -f -- "$sample_dir/$relative"
    done
}

alignment_validate_sample_outputs() {
    local sample_dir="$1"
    local sample_id="$2"
    local threads="$3"
    local expected_records="$4"
    local read_group_id="${CLINICAL_SAMPLES[$sample_id.read_group_id]}"
    local command

    create_directory "$sample_dir/validation"
    # All values interpolated below are validated integers or safe identifiers.
    command="set -euo pipefail
samtools quickcheck -v /work/${sample_id}.analysis_ready.bam
samtools flagstat -@ $threads /work/${sample_id}.analysis_ready.bam > /work/validation/samtools.flagstat.txt
samtools stats -@ $threads /work/${sample_id}.analysis_ready.bam > /work/validation/samtools.stats.txt
samtools idxstats /work/${sample_id}.analysis_ready.bam > /work/validation/samtools.idxstats.txt
samtools view -H /work/${sample_id}.analysis_ready.bam > /work/validation/header.sam
picard ValidateSamFile \
  I=/work/${sample_id}.analysis_ready.bam \
  R=/reference/ref.fa \
  MODE=SUMMARY \
  O=/work/validation/picard_validate_summary.txt \
  VALIDATE_INDEX=true \
  IGNORE_WARNINGS=false \
  VALIDATION_STRINGENCY=STRICT
grep -q $'@HD\\t.*SO:coordinate' /work/validation/header.sam
grep -q $'@RG\\t.*ID:${read_group_id}\\t' /work/validation/header.sam
grep -q '^#:GATKReport' /work/${sample_id}.recal.table
awk -F '\\t' '
  /^LIBRARY[[:space:]]/ {header=1; next}
  header && NF > 1 {data=1; exit}
  END {exit !(header && data)}
' /work/${sample_id}.duplicate_metrics.txt
primary=\$(samtools view -c -F 2304 /work/${sample_id}.analysis_ready.bam)
rg_records=\$(samtools view -c -F 2304 -r '${read_group_id}' /work/${sample_id}.analysis_ready.bam)
duplicates=\$(samtools view -c -f 1024 -F 2304 /work/${sample_id}.analysis_ready.bam)
dedup_primary=\$(samtools view -c -F 2304 /work/${sample_id}.duplicates_marked.bam)
dedup_duplicates=\$(samtools view -c -f 1024 -F 2304 /work/${sample_id}.duplicates_marked.bam)
test \"\$primary\" -eq $expected_records
test \"\$rg_records\" -eq \"\$primary\"
test \"\$dedup_primary\" -eq \"\$primary\"
test \"\$dedup_duplicates\" -eq \"\$duplicates\"
{
  printf 'metric\\tvalue\\n'
  printf 'expected_primary_records\\t%s\\n' '$expected_records'
  printf 'final_primary_records\\t%s\\n' \"\$primary\"
  printf 'read_group_primary_records\\t%s\\n' \"\$rg_records\"
  printf 'duplicate_primary_records\\t%s\\n' \"\$duplicates\"
  printf 'coordinate_sorted\\ttrue\\n'
  printf 'quickcheck_pass\\ttrue\\n'
  printf 'picard_validate_pass\\ttrue\\n'
  printf 'bqsr_table_valid\\ttrue\\n'
} > /work/validation/validation.tsv"

    run_container --apptainer "$APPTAINER_BIN" \
        --bind-rw "$sample_dir" /work \
        "${ALIGNMENT_GATK_BINDS[@]}" \
        "$CONTAINER_DIR/alignment.sif" -- \
        bash -c "$command" \
        >"$sample_dir/logs/validation.stdout" \
        2>"$sample_dir/logs/validation.stderr"
}

alignment_run_sample() {
    local work_dir="$1"
    local sample_id="$2"
    local threads="$3"
    local memory_gb="$4"
    local run_signature="$5"
    local sample_dir="$work_dir/samples/$sample_id"
    local r1="${ALIGNMENT_QC_FASTQ_R1[$sample_id]}"
    local r2="${ALIGNMENT_QC_FASTQ_R2[$sample_id]}"
    local read_group quoted_rg step step_signature command
    local sort_memory_mb heap_gb expected_records
    local bwa_prefix="/bwa/$ALIGNMENT_LOCKED_REFERENCE_BASENAME"
    local -a bwa_binds=()

    create_directory "$sample_dir"
    create_directory "$sample_dir/logs"
    create_directory "$sample_dir/tmp"
    read_group="$(alignment_sample_read_group "$sample_id")"
    printf -v quoted_rg '%q' "$read_group"
    sort_memory_mb=$((memory_gb * 768 / (threads + 1)))
    (( sort_memory_mb >= 256 )) || sort_memory_mb=256
    heap_gb=$((memory_gb * 3 / 4))
    (( heap_gb >= 1 )) || heap_gb=1
    expected_records=$((ALIGNMENT_QC_READ_PAIRS[$sample_id] * 2))
    bwa_binds=(
        --bind-ro "$r1" /inputs/R1.fastq.gz
        --bind-ro "$r2" /inputs/R2.fastq.gz
        --bind-ro "${ALIGNMENT_REFERENCE_PATH[BWA_MEM2_INDEX]}" /bwa
        --bind-rw "$sample_dir" /work
    )

    step=01_align_sort
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse alignment/sort checkpoint"
    else
        report_progress 1 7 "$sample_id BWA-MEM2 alignment and coordinate sort"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.sorted.bam" logs/align_sort.stdout logs/align_sort.stderr
        command="set -euo pipefail
bwa-mem2 mem -K 100000000 -Y -t $threads -R $quoted_rg \
  '$bwa_prefix' /inputs/R1.fastq.gz /inputs/R2.fastq.gz |
  samtools view -@ $threads -u - |
  samtools sort -@ $threads -m ${sort_memory_mb}M \
    -T /work/tmp/${sample_id}.sort \
    -o /work/${sample_id}.sorted.bam -"
        run_container --apptainer "$APPTAINER_BIN" \
            "${bwa_binds[@]}" \
            "$CONTAINER_DIR/alignment.sif" -- \
            bash -c "$command" \
            >"$sample_dir/logs/align_sort.stdout" \
            2>"$sample_dir/logs/align_sort.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.sorted.bam"
    fi

    step=02_sorted_index
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse sorted-BAM index checkpoint"
    else
        report_progress 2 7 "$sample_id sorted BAM index"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.sorted.bam.bai" logs/sorted_index.stdout \
            logs/sorted_index.stderr
        run_container --apptainer "$APPTAINER_BIN" \
            --bind-rw "$sample_dir" /work \
            "$CONTAINER_DIR/alignment.sif" -- \
            samtools index -@ "$threads" \
            "/work/${sample_id}.sorted.bam" \
            >"$sample_dir/logs/sorted_index.stdout" \
            2>"$sample_dir/logs/sorted_index.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.sorted.bam.bai"
    fi

    step=03_mark_duplicates
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse duplicate-marking checkpoint"
    else
        report_progress 3 7 "$sample_id Picard MarkDuplicates"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.duplicates_marked.bam" \
            "${sample_id}.duplicates_marked.bai" \
            "${sample_id}.duplicate_metrics.txt" logs/mark_duplicates.stdout \
            logs/mark_duplicates.stderr
        run_container --apptainer "$APPTAINER_BIN" \
            --bind-rw "$sample_dir" /work \
            "$CONTAINER_DIR/alignment.sif" -- \
            env "PICARD_JAVA_OPTIONS=-Xmx${heap_gb}g -Djava.io.tmpdir=/work/tmp" \
            picard MarkDuplicates \
            "INPUT=/work/${sample_id}.sorted.bam" \
            "OUTPUT=/work/${sample_id}.duplicates_marked.bam" \
            "METRICS_FILE=/work/${sample_id}.duplicate_metrics.txt" \
            REMOVE_DUPLICATES=false \
            ASSUME_SORT_ORDER=coordinate \
            VALIDATION_STRINGENCY=STRICT \
            CREATE_INDEX=true \
            >"$sample_dir/logs/mark_duplicates.stdout" \
            2>"$sample_dir/logs/mark_duplicates.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.duplicates_marked.bam" \
            "samples/$sample_id/${sample_id}.duplicates_marked.bai" \
            "samples/$sample_id/${sample_id}.duplicate_metrics.txt"
    fi

    step=04_base_recalibrator
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse BaseRecalibrator checkpoint"
    else
        report_progress 4 7 "$sample_id GATK BaseRecalibrator"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.recal.table" logs/base_recalibrator.stdout \
            logs/base_recalibrator.stderr
        run_container --apptainer "$APPTAINER_BIN" \
            --bind-rw "$sample_dir" /work \
            "${ALIGNMENT_GATK_BINDS[@]}" \
            "$CONTAINER_DIR/gatk.sif" -- \
            gatk --java-options \
            "-Xmx${heap_gb}g -Djava.io.tmpdir=/work/tmp" \
            BaseRecalibrator \
            -R /reference/ref.fa \
            -I "/work/${sample_id}.duplicates_marked.bam" \
            --known-sites /known/known_indels.vcf.gz \
            --known-sites /known/mills.vcf.gz \
            -O "/work/${sample_id}.recal.table" \
            >"$sample_dir/logs/base_recalibrator.stdout" \
            2>"$sample_dir/logs/base_recalibrator.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.recal.table"
    fi

    step=05_apply_bqsr
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse ApplyBQSR checkpoint"
    else
        report_progress 5 7 "$sample_id GATK ApplyBQSR"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.analysis_ready.bam" logs/apply_bqsr.stdout \
            logs/apply_bqsr.stderr
        run_container --apptainer "$APPTAINER_BIN" \
            --bind-rw "$sample_dir" /work \
            "${ALIGNMENT_GATK_BINDS[@]}" \
            "$CONTAINER_DIR/gatk.sif" -- \
            gatk --java-options \
            "-Xmx${heap_gb}g -Djava.io.tmpdir=/work/tmp" \
            ApplyBQSR \
            -R /reference/ref.fa \
            -I "/work/${sample_id}.duplicates_marked.bam" \
            --bqsr-recal-file "/work/${sample_id}.recal.table" \
            --create-output-bam-index false \
            -O "/work/${sample_id}.analysis_ready.bam" \
            >"$sample_dir/logs/apply_bqsr.stdout" \
            2>"$sample_dir/logs/apply_bqsr.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.analysis_ready.bam"
    fi

    step=06_final_index
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse final-BAM index checkpoint"
    else
        report_progress 6 7 "$sample_id final BAM index"
        alignment_remove_sample_outputs "$sample_dir" \
            "${sample_id}.analysis_ready.bam.bai" logs/final_index.stdout \
            logs/final_index.stderr
        run_container --apptainer "$APPTAINER_BIN" \
            --bind-rw "$sample_dir" /work \
            "$CONTAINER_DIR/alignment.sif" -- \
            samtools index -@ "$threads" \
            "/work/${sample_id}.analysis_ready.bam" \
            >"$sample_dir/logs/final_index.stdout" \
            2>"$sample_dir/logs/final_index.stderr"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/${sample_id}.analysis_ready.bam.bai"
    fi

    step=07_validate
    step_signature="$(alignment_step_signature "$run_signature" "$sample_id" "$step")"
    if alignment_step_is_complete "$work_dir" "$sample_id" "$step" "$step_signature"; then
        log_info "$sample_id: reuse analysis-ready BAM validation checkpoint"
    else
        report_progress 7 7 "$sample_id analysis-ready BAM validation"
        rm -rf -- "$sample_dir/validation"
        alignment_remove_sample_outputs "$sample_dir" \
            logs/validation.stdout logs/validation.stderr
        alignment_validate_sample_outputs \
            "$sample_dir" "$sample_id" "$threads" "$expected_records"
        alignment_record_step "$work_dir" "$sample_id" "$step" "$step_signature" \
            "samples/$sample_id/validation/samtools.flagstat.txt" \
            "samples/$sample_id/validation/samtools.stats.txt" \
            "samples/$sample_id/validation/samtools.idxstats.txt" \
            "samples/$sample_id/validation/header.sam" \
            "samples/$sample_id/validation/picard_validate_summary.txt" \
            "samples/$sample_id/validation/validation.tsv"
    fi
}

alignment_write_provenance() {
    local work_dir="$1"
    local signature="$2"
    local runtime="$3"
    local qc_dir="$4"
    local provenance="$work_dir/provenance.tsv"

    {
        printf 'key\tvalue\n'
        printf 'module\t02_alignment\n'
        printf 'module_version\t%s\n' "$ALIGNMENT_MODULE_VERSION"
        printf 'pipeline_version\t%s\n' \
            "$(get_pipeline_version "$ALIGNMENT_REPOSITORY_ROOT/VERSION")"
        printf 'run_id\t%s\n' "$RUN_ID"
        printf 'status\tPASS\n'
        printf 'signature\t%s\n' "$signature"
        printf 'qc_directory\t%s\n' "$qc_dir"
        printf 'reference_name\t%s\n' "$ALIGNMENT_LOCKED_REFERENCE_BASENAME"
        printf 'reference_version\t%s\n' "$ALIGNMENT_LOCKED_REFERENCE_VERSION"
        printf 'reference_sha256\t%s\n' "$ALIGNMENT_LOCKED_FASTA_SHA256"
        printf 'reference_manifest\t%s\n' \
            "$REFERENCE_DIR/reference_manifest.tsv"
        printf 'alignment_container_sha256\t%s\n' \
            "$(calculate_checksum "$CONTAINER_DIR/alignment.sif")"
        printf 'gatk_container_sha256\t%s\n' \
            "$(calculate_checksum "$CONTAINER_DIR/gatk.sif")"
        printf 'bwa_input_batch_size\t100000000\n'
        printf 'duplicates_removed\tfalse\n'
        printf 'bqsr_known_sites\tKNOWN_INDELS,MILLS_INDELS\n'
        printf 'runtime_seconds\t%s\n' "$runtime"
        printf 'completed_at\t%s\n' "$(common__timestamp)"
    } >"$provenance"
}

alignment_write_results() {
    local work_dir="$1"
    local signature="$2"
    local runtime="$3"
    local qc_dir="$4"

    alignment_write_provenance "$work_dir" "$signature" "$runtime" "$qc_dir"
    (
        cd -- "$work_dir"
        find . -type f \
            ! -name output_checksums.sha256 \
            ! -name .complete \
            -printf '%P\n' |
            LC_ALL=C sort |
            while IFS= read -r path; do
                sha256sum "$path"
            done
    ) >"$work_dir/output_checksums.sha256"
    create_complete_marker \
        "$work_dir/.complete" "$signature" "$work_dir/provenance.tsv"
}

alignment_main() {
    local config_file='' samples_file='' qc_override='' output_override=''
    local quiet=0 verbose=0 qc_dir output_dir output_parent output_name work_dir
    local signature runtime sample_id

    while (( $# > 0 )); do
        case "$1" in
            --config)
                (( $# >= 2 )) ||
                    { printf 'ERROR: --config requires a value\n' >&2; return "$ALIGNMENT_EX_USAGE"; }
                config_file="$2"
                shift 2
                ;;
            --samples)
                (( $# >= 2 )) ||
                    { printf 'ERROR: --samples requires a value\n' >&2; return "$ALIGNMENT_EX_USAGE"; }
                samples_file="$2"
                shift 2
                ;;
            --qc-dir)
                (( $# >= 2 )) ||
                    { printf 'ERROR: --qc-dir requires a value\n' >&2; return "$ALIGNMENT_EX_USAGE"; }
                qc_override="$2"
                shift 2
                ;;
            --output-dir)
                (( $# >= 2 )) ||
                    { printf 'ERROR: --output-dir requires a value\n' >&2; return "$ALIGNMENT_EX_USAGE"; }
                output_override="$2"
                shift 2
                ;;
            --quiet) quiet=1; shift ;;
            --verbose) verbose=1; shift ;;
            -h|--help) alignment_usage; return 0 ;;
            *)
                printf 'ERROR: unknown alignment argument: %s\n' "$1" >&2
                return "$ALIGNMENT_EX_USAGE"
                ;;
        esac
    done
    [[ -n "$config_file" && -n "$samples_file" ]] ||
        { printf 'ERROR: --config and --samples are required\n' >&2; return "$ALIGNMENT_EX_USAGE"; }

    alignment_reset_state
    if ! clinical_validate "$config_file" "$samples_file"; then
        clinical_print_errors >&2
        return "$ALIGNMENT_EX_UNAVAILABLE"
    fi
    [[ -s "$CONTAINER_DIR/alignment.sif" && -s "$CONTAINER_DIR/gatk.sif" ]] ||
        { printf 'ERROR: Module 7 container image is missing\n' >&2; return "$ALIGNMENT_EX_UNAVAILABLE"; }

    qc_dir="${qc_override:-$RUN_DIR/qc}"
    output_dir="${output_override:-$RUN_DIR/alignment}"
    [[ "$qc_dir" == /* ]] || qc_dir="$(pwd -P)/$qc_dir"
    [[ "$output_dir" == /* ]] || output_dir="$(pwd -P)/$output_dir"
    output_parent="${output_dir%/*}"
    output_name="${output_dir##*/}"
    create_directory "$output_parent"

    common_init alignment '' "$quiet" "$verbose"
    alignment_parse_reference_manifest "$REFERENCE_DIR/reference_manifest.tsv"
    alignment_validate_reference_resources "$ALIGNMENT_LOCKED_FASTA_SHA256"
    alignment_load_qc_handoff "$qc_dir"
    alignment_reference_binds
    signature="$(alignment_configuration_signature "$qc_dir")"

    if [[ -d "$output_dir" ]]; then
        if check_complete_marker "$output_dir/.complete" "$signature" &&
            (cd -- "$output_dir" &&
                sha256sum --check --quiet output_checksums.sha256); then
            log_success "Module 7 checkpoint matches and all outputs verify"
            return 0
        fi
        printf 'ERROR: existing Module 7 output is incomplete or incompatible: %s\n' \
            "$output_dir" >&2
        return "$ALIGNMENT_EX_UNAVAILABLE"
    fi

    work_dir="$output_parent/.${output_name}.work"
    if [[ -e "$work_dir/run_signature.txt" ]]; then
        [[ "$(<"$work_dir/run_signature.txt")" == "$signature" ]] ||
            { printf 'ERROR: incompatible Module 7 work directory: %s\n' "$work_dir" >&2; return "$ALIGNMENT_EX_UNAVAILABLE"; }
    elif [[ -e "$work_dir" ]]; then
        printf 'ERROR: unidentifiable Module 7 work directory: %s\n' "$work_dir" >&2
        return "$ALIGNMENT_EX_UNAVAILABLE"
    else
        create_directory "$work_dir"
        printf '%s\n' "$signature" >"$work_dir/run_signature.txt"
    fi
    create_directory "$work_dir/logs"
    create_directory "$work_dir/checkpoints"
    create_directory "$work_dir/samples"
    common_init alignment "$work_dir/logs/alignment.log" "$quiet" "$verbose"
    setup_cleanup_traps
    start_timer module7
    alignment_write_command_manifest "$work_dir/commands.tsv"
    alignment_write_tool_versions "$work_dir/tool_versions.tsv"
    report_environment "$work_dir/environment.tsv"

    log_info "starting or resuming Module 7 for ${#CLINICAL_SAMPLE_IDS[@]} sample(s)"
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        # Module 2 exports these validated configuration keys.
        # shellcheck disable=SC2153
        alignment_run_sample "$work_dir" "$sample_id" "$THREADS" \
            "$MEMORY_GB" "$signature"
    done
    runtime="$(stop_timer module7)"
    alignment_write_results "$work_dir" "$signature" "$runtime" "$qc_dir"
    (
        cd -- "$work_dir"
        sha256sum --check --quiet output_checksums.sha256
    ) || die 'Final Module 7 output checksum verification failed'

    mv -- "$work_dir" "$output_dir" ||
        die "Cannot atomically publish Module 7 output: $output_dir"
    find "$output_dir" -type f -exec chmod 0440 -- {} +
    find "$output_dir" -type d -exec chmod 0550 -- {} +
    log_success "Module 7 completed: $output_dir"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    alignment_main "$@"
fi
