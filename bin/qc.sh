#!/usr/bin/env bash
# ClinicalSuite V2 Module 6: conservative paired-end FASTQ quality control.

set -Eeuo pipefail

QC_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly QC_SCRIPT_DIR
QC_REPOSITORY_ROOT="$(cd -- "$QC_SCRIPT_DIR/.." && pwd -P)"
readonly QC_REPOSITORY_ROOT
# shellcheck source=config/parser.sh
source "$QC_REPOSITORY_ROOT/config/parser.sh"
# shellcheck source=bin/common.sh
source "$QC_SCRIPT_DIR/common.sh"

readonly QC_MODULE_VERSION='1.0.0'
readonly QC_EX_USAGE=64
readonly QC_EX_UNAVAILABLE=69
readonly -a QC_PROFILE_KEYS=(
    PROFILE_ID
    PROFILE_VERSION
    SUPPORTED_ASSAYS
    SUPPORTED_PLATFORMS
    FASTP_MODE
    FASTQC_FAIL_POLICY
    FASTQC_WARNING_POLICY
    MIN_READ_PAIRS
)
declare -gA QC_PROFILE=()
declare -ga QC_PROFILE_ERRORS=()
declare -g QC_BEFORE_READS=0
declare -g QC_AFTER_READS=0
declare -g QC_RESULT=''

qc_usage() {
    cat <<'EOF'
Usage: bin/qc.sh --config FILE --samples FILE [OPTIONS]

Run ClinicalSuite Module 6 with the validated qc.sif image.

Options:
  --config FILE       validated clinical.conf
  --samples FILE      validated samples.tsv
  --output-dir DIR    override RUN_DIR/qc
  --quiet             suppress routine terminal messages
  --verbose           enable debug logging
  -h, --help          show this help
EOF
}

qc_profile_key_allowed() {
    local requested="$1" key

    for key in "${QC_PROFILE_KEYS[@]}"; do
        [[ "$requested" == "$key" ]] && return 0
    done
    return 1
}

qc_profile_add_error() {
    QC_PROFILE_ERRORS+=("$1")
}

qc_list_contains() {
    local list="$1" requested="$2" item
    local -a items=()

    IFS=',' read -r -a items <<<"$list"
    for item in "${items[@]}"; do
        [[ "$item" == "$requested" ]] && return 0
    done
    return 1
}

qc_load_profile() {
    local profile_file="$1"
    local line key value line_number=0

    QC_PROFILE=()
    QC_PROFILE_ERRORS=()
    if [[ ! -f "$profile_file" || ! -r "$profile_file" ]]; then
        qc_profile_add_error "profile is missing or unreadable: $profile_file"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" != *=* ]]; then
            qc_profile_add_error "line $line_number is not KEY=VALUE"
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        if ! qc_profile_key_allowed "$key"; then
            qc_profile_add_error "unknown profile key at line $line_number: $key"
            continue
        fi
        if [[ -v "QC_PROFILE[$key]" ]]; then
            qc_profile_add_error "duplicate profile key at line $line_number: $key"
            continue
        fi
        [[ -n "$value" ]] || qc_profile_add_error "empty profile value: $key"
        QC_PROFILE["$key"]="$value"
    done <"$profile_file"

    for key in "${QC_PROFILE_KEYS[@]}"; do
        [[ -v "QC_PROFILE[$key]" ]] || qc_profile_add_error "missing profile key: $key"
    done
    (( ${#QC_PROFILE_ERRORS[@]} == 0 )) || return 1

    [[ "${QC_PROFILE[PROFILE_ID]}" == "$ASSAY_PROFILE" ]] ||
        qc_profile_add_error 'PROFILE_ID does not match ASSAY_PROFILE'
    [[ "${QC_PROFILE[PROFILE_VERSION]}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
        qc_profile_add_error 'PROFILE_VERSION is malformed'
    [[ "${QC_PROFILE[SUPPORTED_ASSAYS]}" =~ ^(WGS|WES)(,(WGS|WES))*$ ]] ||
        qc_profile_add_error 'SUPPORTED_ASSAYS is malformed'
    [[ "${QC_PROFILE[SUPPORTED_PLATFORMS]}" =~ ^(ILLUMINA|GENEMIND)(,(ILLUMINA|GENEMIND))*$ ]] ||
        qc_profile_add_error 'SUPPORTED_PLATFORMS is malformed'
    [[ "${QC_PROFILE[FASTP_MODE]}" == PASS_THROUGH ]] ||
        qc_profile_add_error 'only FASTP_MODE=PASS_THROUGH is currently validated'
    [[ "${QC_PROFILE[FASTQC_FAIL_POLICY]}" == BLOCK ||
        "${QC_PROFILE[FASTQC_FAIL_POLICY]}" == REVIEW ]] ||
        qc_profile_add_error 'FASTQC_FAIL_POLICY must be BLOCK or REVIEW'
    [[ "${QC_PROFILE[FASTQC_WARNING_POLICY]}" == BLOCK ||
        "${QC_PROFILE[FASTQC_WARNING_POLICY]}" == REVIEW ]] ||
        qc_profile_add_error 'FASTQC_WARNING_POLICY must be BLOCK or REVIEW'
    [[ "${QC_PROFILE[MIN_READ_PAIRS]}" =~ ^[0-9]+$ ]] ||
        qc_profile_add_error 'MIN_READ_PAIRS must be a non-negative integer'

    (( ${#QC_PROFILE_ERRORS[@]} == 0 ))
}

qc_validate_profile_samples() {
    local sample_id assay platform

    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        assay="${CLINICAL_SAMPLES[$sample_id.assay]}"
        platform="${CLINICAL_SAMPLES[$sample_id.platform]}"
        qc_list_contains "${QC_PROFILE[SUPPORTED_ASSAYS]}" "$assay" ||
            qc_profile_add_error "$sample_id assay is not supported by the profile: $assay"
        qc_list_contains "${QC_PROFILE[SUPPORTED_PLATFORMS]}" "$platform" ||
            qc_profile_add_error "$sample_id platform is not supported by the profile: $platform"
    done
    (( ${#QC_PROFILE_ERRORS[@]} == 0 ))
}

qc_print_profile_errors() {
    local error

    printf 'QC assay-profile validation failed.\n' >&2
    for error in "${QC_PROFILE_ERRORS[@]}"; do
        printf '  - %s\n' "$error" >&2
    done
}

qc_fastp_read_counts() {
    local json_file="$1" counts

    counts="$(
        awk '
            /"before_filtering"[[:space:]]*:/ { section = "before" }
            /"after_filtering"[[:space:]]*:/ { section = "after" }
            section != "" && /"total_reads"[[:space:]]*:/ {
                value = $0
                sub(/^.*"total_reads"[[:space:]]*:[[:space:]]*/, "", value)
                sub(/[^0-9].*$/, "", value)
                if (section == "before" && before == "") before = value
                if (section == "after" && after == "") after = value
            }
            END {
                if (before == "" || after == "") exit 1
                print before, after
            }
        ' "$json_file"
    )" || return 1
    read -r QC_BEFORE_READS QC_AFTER_READS <<<"$counts"
    [[ "$QC_BEFORE_READS" =~ ^[0-9]+$ && "$QC_AFTER_READS" =~ ^[0-9]+$ ]]
}

qc_fastqc_counts() {
    local multiqc_fastqc="$1" sample_id="$2"

    awk -F '\t' -v r1="${sample_id}_R1" -v r2="${sample_id}_R2" '
        NR == 1 { next }
        $1 == r1 || $1 == r2 {
            seen++
            for (column = 13; column <= NF; column++) {
                if ($column == "fail") failures++
                if ($column == "warn") warnings++
            }
        }
        END {
            if (seen != 2) exit 1
            print failures + 0, warnings + 0
        }
    ' "$multiqc_fastqc"
}

qc_decide_sample() {
    local failure_count="$1" warning_count="$2" read_pairs="$3"
    local decision=PASS

    if (( read_pairs < 10#${QC_PROFILE[MIN_READ_PAIRS]} )); then
        decision=BLOCK
    fi
    if (( failure_count > 0 )); then
        if [[ "${QC_PROFILE[FASTQC_FAIL_POLICY]}" == BLOCK ]]; then
            decision=BLOCK
        elif [[ "$decision" == PASS ]]; then
            decision=REVIEW
        fi
    fi
    if (( warning_count > 0 )); then
        if [[ "${QC_PROFILE[FASTQC_WARNING_POLICY]}" == BLOCK ]]; then
            decision=BLOCK
        elif [[ "$decision" == PASS ]]; then
            decision=REVIEW
        fi
    fi
    QC_RESULT="$decision"
}

qc_configuration_signature() {
    local profile_file="$1" image="$2"
    local sample_id field

    {
        printf 'module_version\t%s\n' "$QC_MODULE_VERSION"
        printf 'module_script\t%s\n' "$(sha256sum "$QC_SCRIPT_DIR/qc.sh" | awk '{print $1}')"
        printf 'common_library\t%s\n' "$(sha256sum "$QC_SCRIPT_DIR/common.sh" | awk '{print $1}')"
        printf 'config_parser\t%s\n' "$(sha256sum "$QC_REPOSITORY_ROOT/config/parser.sh" | awk '{print $1}')"
        printf 'config\t%s\n' "$(sha256sum "$CLINICAL_CONFIG_SOURCE" | awk '{print $1}')"
        printf 'samples\t%s\n' "$(sha256sum "$CLINICAL_SAMPLES_SOURCE" | awk '{print $1}')"
        printf 'profile\t%s\n' "$(sha256sum "$profile_file" | awk '{print $1}')"
        printf 'container\t%s\n' "$(sha256sum "$image" | awk '{print $1}')"
        for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
            for field in fastq_r1 fastq_r2; do
                printf '%s.%s\t%s\n' "$sample_id" "$field" \
                    "$(sha256sum "${CLINICAL_SAMPLES[$sample_id.$field]}" | awk '{print $1}')"
            done
        done
    } | sha256sum | awk '{print $1}'
}

qc_write_command_manifest() {
    local destination="$1" threads="$2"

    {
        printf 'step\tcommand_contract\n'
        printf 'raw_fastqc\tfastqc --threads %s --quiet --outdir OUTPUT SAMPLE_R1 SAMPLE_R2\n' \
            "$threads"
        printf '%s\t%s\n' fastp_report \
            'fastp --in1 SAMPLE_R1 --in2 SAMPLE_R2 --stdout --disable_adapter_trimming --disable_trim_poly_g --disable_quality_filtering --disable_length_filtering --thread THREADS --json JSON --html HTML'
        printf 'aggregate\tmultiqc --force --filename multiqc_report.html --outdir OUTPUT INPUT\n'
    } >"$destination"
}

qc_run_sample() {
    local work_dir="$1" image="$2" sample_id="$3" threads="$4"
    local sample_dir="$work_dir/samples/$sample_id"
    local r1="${CLINICAL_SAMPLES[$sample_id.fastq_r1]}"
    local r2="${CLINICAL_SAMPLES[$sample_id.fastq_r2]}"
    local fastp_threads="$threads"

    (( fastp_threads <= 16 )) || fastp_threads=16
    create_directory "$sample_dir/raw_fastqc"
    create_directory "$sample_dir/fastp"
    create_directory "$sample_dir/final"
    create_directory "$sample_dir/logs"

    report_progress 1 3 "$sample_id raw FastQC"
    run_container --apptainer "$APPTAINER_BIN" \
        --bind-ro "$r1" "/inputs/${sample_id}_R1.fastq.gz" \
        --bind-ro "$r2" "/inputs/${sample_id}_R2.fastq.gz" \
        --bind-rw "$sample_dir/raw_fastqc" /output \
        "$image" -- \
        fastqc --threads "$threads" --quiet --outdir /output \
        "/inputs/${sample_id}_R1.fastq.gz" "/inputs/${sample_id}_R2.fastq.gz" \
        >"$sample_dir/logs/fastqc.stdout" 2>"$sample_dir/logs/fastqc.stderr"

    [[ -s "$sample_dir/raw_fastqc/${sample_id}_R1_fastqc.html" &&
        -s "$sample_dir/raw_fastqc/${sample_id}_R1_fastqc.zip" &&
        -s "$sample_dir/raw_fastqc/${sample_id}_R2_fastqc.html" &&
        -s "$sample_dir/raw_fastqc/${sample_id}_R2_fastqc.zip" ]] ||
        die "$sample_id FastQC did not produce the required reports"

    report_progress 2 3 "$sample_id fastp pass-through report"
    # The contained shell, not this orchestrator, expands its parameters.
    # shellcheck disable=SC2016
    run_container --apptainer "$APPTAINER_BIN" \
        --bind-ro "$r1" "/inputs/${sample_id}_R1.fastq.gz" \
        --bind-ro "$r2" "/inputs/${sample_id}_R2.fastq.gz" \
        --bind-rw "$sample_dir/fastp" /output \
        "$image" -- \
        sh -c '
            exec fastp \
                --in1 "$1" \
                --in2 "$2" \
                --stdout \
                --disable_adapter_trimming \
                --disable_trim_poly_g \
                --disable_quality_filtering \
                --disable_length_filtering \
                --thread "$3" \
                --json "$4" \
                --html "$5" \
                >/dev/null
        ' sh \
        "/inputs/${sample_id}_R1.fastq.gz" \
        "/inputs/${sample_id}_R2.fastq.gz" \
        "$fastp_threads" \
        "/output/${sample_id}.fastp.json" \
        "/output/${sample_id}.fastp.html" \
        >"$sample_dir/logs/fastp.stdout" 2>"$sample_dir/logs/fastp.stderr"

    qc_fastp_read_counts "$sample_dir/fastp/${sample_id}.fastp.json" ||
        die "$sample_id fastp JSON does not contain valid read counts"
    [[ "$QC_BEFORE_READS" -eq "$QC_AFTER_READS" &&
        $((QC_BEFORE_READS % 2)) -eq 0 ]] ||
        die "$sample_id fastp pass-through changed or unpaired reads"

    ln -s -- "$r1" "$sample_dir/final/${r1##*/}"
    ln -s -- "$r2" "$sample_dir/final/${r2##*/}"
    check_fastq "$sample_dir/final/${r1##*/}" ||
        die "$sample_id final R1 link is invalid"
    check_fastq "$sample_dir/final/${r2##*/}" ||
        die "$sample_id final R2 link is invalid"
    report_progress 3 3 "$sample_id immutable pass-through links"
}

qc_write_results() {
    local work_dir="$1" image="$2" profile_file="$3" signature="$4" runtime="$5"
    local status_file="$work_dir/qc_status.tsv"
    local final_manifest="$work_dir/final_fastq.tsv"
    local provenance="$work_dir/provenance.tsv"
    local sample_id counts failures warnings pairs decision
    local r1 r2 module_status=PASS
    local pipeline_version container_sha profile_sha

    printf 'sample_id\tfastqc_failures\tfastqc_warnings\tread_pairs\tdecision\n' >"$status_file"
    printf 'sample_id\tfastq_r1\tfastq_r2\tsha256_r1\tsha256_r2\tmode\n' >"$final_manifest"
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        counts="$(qc_fastqc_counts \
            "$work_dir/multiqc/multiqc_report_data/multiqc_fastqc.txt" "$sample_id")" ||
            die "MultiQC did not retain both FastQC reports for $sample_id"
        read -r failures warnings <<<"$counts"
        qc_fastp_read_counts "$work_dir/samples/$sample_id/fastp/${sample_id}.fastp.json" ||
            die "cannot read final fastp counts for $sample_id"
        pairs=$((QC_BEFORE_READS / 2))
        qc_decide_sample "$failures" "$warnings" "$pairs"
        decision="$QC_RESULT"
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$sample_id" "$failures" "$warnings" "$pairs" "$decision" >>"$status_file"
        if [[ "$decision" == BLOCK ]]; then
            module_status=BLOCK
        elif [[ "$decision" == REVIEW && "$module_status" == PASS ]]; then
            module_status=REVIEW
        fi

        r1="${CLINICAL_SAMPLES[$sample_id.fastq_r1]}"
        r2="${CLINICAL_SAMPLES[$sample_id.fastq_r2]}"
        printf '%s\t%s\t%s\t%s\t%s\tPASS_THROUGH\n' \
            "$sample_id" \
            "samples/$sample_id/final/${r1##*/}" \
            "samples/$sample_id/final/${r2##*/}" \
            "$(sha256sum "$r1" | awk '{print $1}')" \
            "$(sha256sum "$r2" | awk '{print $1}')" >>"$final_manifest"
    done

    pipeline_version="$(get_pipeline_version "$QC_REPOSITORY_ROOT/VERSION")"
    container_sha="$(sha256sum "$image" | awk '{print $1}')"
    profile_sha="$(sha256sum "$profile_file" | awk '{print $1}')"
    {
        printf 'key\tvalue\n'
        printf 'module\t01_qc\n'
        printf 'module_version\t%s\n' "$QC_MODULE_VERSION"
        printf 'pipeline_version\t%s\n' "$pipeline_version"
        printf 'run_id\t%s\n' "$RUN_ID"
        printf 'status\t%s\n' "$module_status"
        printf 'signature\t%s\n' "$signature"
        printf 'container\t%s\n' "$image"
        printf 'container_sha256\t%s\n' "$container_sha"
        printf 'profile\t%s\n' "$profile_file"
        printf 'profile_sha256\t%s\n' "$profile_sha"
        printf 'fastqc_version\t0.12.1\n'
        printf 'fastp_version\t1.3.6\n'
        printf 'multiqc_version\t1.35\n'
        printf 'fastp_mode\tPASS_THROUGH\n'
        printf 'reads_modified\tfalse\n'
        printf 'runtime_seconds\t%s\n' "$runtime"
        printf 'completed_at\t%s\n' "$(common__timestamp)"
    } >"$provenance"

    log_success "Module 6 calculations complete: status=$module_status"
    (
        cd -- "$work_dir"
        find . -type f ! -name output_checksums.sha256 ! -name .complete \
            -printf '%P\n' |
            LC_ALL=C sort |
            while IFS= read -r path; do sha256sum "$path"; done
    ) >"$work_dir/output_checksums.sha256"
    create_complete_marker "$work_dir/.complete" "$signature" "$provenance"
    printf '%s\n' "$module_status"
}

qc_existing_status() {
    local output_dir="$1"
    awk -F '\t' '$1 == "status" {print $2; found=1} END {if (!found) exit 1}' \
        "$output_dir/provenance.tsv"
}

qc_main() {
    local config_file='' samples_file='' output_override=''
    local quiet=0 verbose=0 profile_file image output_dir output_parent work_dir
    local signature status runtime threads sample_id

    while (( $# > 0 )); do
        case "$1" in
            --config)
                (( $# >= 2 )) || { printf 'ERROR: --config requires a value\n' >&2; return "$QC_EX_USAGE"; }
                config_file="$2"; shift 2
                ;;
            --samples)
                (( $# >= 2 )) || { printf 'ERROR: --samples requires a value\n' >&2; return "$QC_EX_USAGE"; }
                samples_file="$2"; shift 2
                ;;
            --output-dir)
                (( $# >= 2 )) || { printf 'ERROR: --output-dir requires a value\n' >&2; return "$QC_EX_USAGE"; }
                output_override="$2"; shift 2
                ;;
            --quiet) quiet=1; shift ;;
            --verbose) verbose=1; shift ;;
            -h|--help) qc_usage; return 0 ;;
            *) printf 'ERROR: unknown QC argument: %s\n' "$1" >&2; return "$QC_EX_USAGE" ;;
        esac
    done
    [[ -n "$config_file" && -n "$samples_file" ]] || {
        printf 'ERROR: --config and --samples are required\n' >&2
        return "$QC_EX_USAGE"
    }
    if ! clinical_validate "$config_file" "$samples_file"; then
        clinical_print_errors >&2
        return "$QC_EX_UNAVAILABLE"
    fi

    profile_file="$ASSAY_PROFILE_DIR/$ASSAY_PROFILE/qc.conf"
    if ! qc_load_profile "$profile_file" || ! qc_validate_profile_samples; then
        qc_print_profile_errors
        return "$QC_EX_UNAVAILABLE"
    fi
    image="$CONTAINER_DIR/qc.sif"
    [[ -s "$image" ]] || { printf 'ERROR: missing qc.sif: %s\n' "$image" >&2; return "$QC_EX_UNAVAILABLE"; }

    if [[ -n "$output_override" ]]; then
        [[ "$output_override" == /* ]] || output_override="$(pwd -P)/$output_override"
        output_dir="$output_override"
    else
        output_dir="$RUN_DIR/qc"
    fi
    output_parent="${output_dir%/*}"
    create_directory "$output_parent"
    signature="$(qc_configuration_signature "$profile_file" "$image")"

    if [[ -d "$output_dir" ]]; then
        if check_complete_marker "$output_dir/.complete" "$signature"; then
            if ! (
                cd -- "$output_dir"
                sha256sum --check --quiet output_checksums.sha256
            ); then
                printf 'ERROR: completed QC output failed checksum verification: %s\n' \
                    "$output_dir" >&2
                return "$QC_EX_UNAVAILABLE"
            fi
            status="$(qc_existing_status "$output_dir")" ||
                die 'completed QC directory has no status'
            log_success "QC checkpoint matches; status=$status"
            [[ "$status" != BLOCK ]] || return "$QC_EX_UNAVAILABLE"
            return 0
        fi
        printf 'ERROR: existing QC output does not match this run: %s\n' "$output_dir" >&2
        return "$QC_EX_UNAVAILABLE"
    fi

    work_dir="$(mktemp -d "$output_parent/.qc.tmp.XXXXXX")"
    register_cleanup "$work_dir"
    setup_cleanup_traps
    create_directory "$work_dir/logs"
    common_init qc "$work_dir/logs/qc.log" "$quiet" "$verbose"
    start_timer module6
    # THREADS exists only after Module 2 validation succeeds.
    # shellcheck disable=SC2153
    threads="$THREADS"
    qc_write_command_manifest "$work_dir/commands.tsv" "$threads"
    report_environment "$work_dir/environment.tsv"

    log_info "starting Module 6 for ${#CLINICAL_SAMPLE_IDS[@]} sample(s)"
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        qc_run_sample "$work_dir" "$image" "$sample_id" "$threads"
    done

    create_directory "$work_dir/multiqc"
    run_container --apptainer "$APPTAINER_BIN" \
        --bind-ro "$work_dir/samples" /input \
        --bind-rw "$work_dir/multiqc" /output \
        "$image" -- \
        multiqc --force --filename multiqc_report.html --outdir /output /input \
        >"$work_dir/logs/multiqc.stdout" 2>"$work_dir/logs/multiqc.stderr"
    if [[ ! -s "$work_dir/multiqc/multiqc_report.html" ||
        ! -s "$work_dir/multiqc/multiqc_report_data/multiqc_fastqc.txt" ]]; then
        if [[ "${QC_KEEP_FAILED_WORKDIR:-0}" == 1 ]]; then
            common__unregister_cleanup "$work_dir"
            printf 'Preserved QC work directory: %s\n' "$work_dir" >&2
        fi
        die 'MultiQC did not produce the required aggregate outputs'
    fi

    runtime="$(stop_timer module6)"
    status="$(qc_write_results \
        "$work_dir" "$image" "$profile_file" "$signature" "$runtime")"
    if ! mv -- "$work_dir" "$output_dir"; then
        die "cannot publish QC output: $output_dir"
    fi
    common__unregister_cleanup "$work_dir"
    CLINICAL_LOG_FILE="$output_dir/logs/qc.log"
    find "$output_dir" -type f -exec chmod 0440 -- {} +
    find "$output_dir" -type d -exec chmod 0550 -- {} +
    [[ "$status" != BLOCK ]] || return "$QC_EX_UNAVAILABLE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    qc_main "$@"
fi
