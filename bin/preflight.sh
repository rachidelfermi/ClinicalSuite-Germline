#!/usr/bin/env bash
# ClinicalSuite V2 Module 5: aggregated validation before scientific execution.

PREFLIGHT_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PREFLIGHT_SCRIPT_DIR
PREFLIGHT_REPOSITORY_ROOT="$(cd -- "$PREFLIGHT_SCRIPT_DIR/.." && pwd -P)"
readonly PREFLIGHT_REPOSITORY_ROOT
# shellcheck source=config/parser.sh
source "$PREFLIGHT_REPOSITORY_ROOT/config/parser.sh"
# shellcheck source=bin/common.sh
source "$PREFLIGHT_SCRIPT_DIR/common.sh"
# shellcheck source=envs/lib.sh
source "$PREFLIGHT_REPOSITORY_ROOT/envs/lib.sh"

readonly PREFLIGHT_EX_USAGE=64
readonly PREFLIGHT_EX_UNAVAILABLE=69
readonly PREFLIGHT_DEFAULT_STAGE='VARIANT_FILTERING'
readonly PREFLIGHT_LOCKED_REFERENCE_BASENAME='GRCh38_full_analysis_set_plus_decoy_hla.fa'
readonly PREFLIGHT_LOCKED_REFERENCE_VERSION='GRCh38_full_analysis_set_plus_decoy_hla-20150309'
readonly -a PREFLIGHT_ENVIRONMENTS=("${CLINICAL_ENVIRONMENTS[@]}")
readonly -a PREFLIGHT_REFERENCE_IDS=(
    GRCH38_FASTA
    GRCH38_FASTA_FAI
    GRCH38_SEQUENCE_DICTIONARY
    BWA_MEM2_INDEX
    GRCH38_PAR_INTERVALS
    KNOWN_INDELS
    KNOWN_INDELS_INDEX
    MILLS_INDELS
    MILLS_INDELS_INDEX
)
readonly -a PREFLIGHT_DATABASE_IDS=(
    CLINVAR
    CLINVAR_INDEX
    DBSNP
    DBSNP_INDEX
    GNOMAD
    GNOMAD_INDEX
    VEP_CACHE
    LOFTEE
    SPLICEAI
    SPLICEAI_INDEX
    DBNSFP
)
readonly -a PREFLIGHT_OPTIONAL_DATABASE_IDS=(REVEL)

declare -ga PREFLIGHT_ERRORS=()
declare -ga PREFLIGHT_WARNINGS=()
declare -ga PREFLIGHT_INFORMATION=()
declare -ga PREFLIGHT_CHECKS=()
declare -gA PREFLIGHT_RESOURCE_PATH=()
declare -gA PREFLIGHT_RESOURCE_KIND=()
declare -gA PREFLIGHT_RESOURCE_REQUIREMENT=()
declare -gA PREFLIGHT_RESOURCE_ASSEMBLY=()
declare -gA PREFLIGHT_RESOURCE_VERSION=()
declare -gA PREFLIGHT_RESOURCE_SHA256=()
declare -gA PREFLIGHT_RESOURCE_REFERENCE_SHA256=()
declare -ga PREFLIGHT_REFERENCE_DECLARED_IDS=()
declare -ga PREFLIGHT_DATABASE_DECLARED_IDS=()
declare -g PREFLIGHT_CONFIG_VALID=false
declare -g PREFLIGHT_OUTPUT_DIR=''
declare -g PREFLIGHT_REFERENCE_CONTIG_STYLE=''
declare -g PREFLIGHT_FASTA_SHA256=''
declare -g PREFLIGHT_RESULT=''
declare -g PREFLIGHT_STAGE_NAME="$PREFLIGHT_DEFAULT_STAGE"
declare -g PREFLIGHT_STAGE_MODULE=13

preflight_reset() {
    PREFLIGHT_ERRORS=()
    PREFLIGHT_WARNINGS=()
    PREFLIGHT_INFORMATION=()
    PREFLIGHT_CHECKS=()
    PREFLIGHT_RESOURCE_PATH=()
    PREFLIGHT_RESOURCE_KIND=()
    PREFLIGHT_RESOURCE_REQUIREMENT=()
    PREFLIGHT_RESOURCE_ASSEMBLY=()
    PREFLIGHT_RESOURCE_VERSION=()
    PREFLIGHT_RESOURCE_SHA256=()
    PREFLIGHT_RESOURCE_REFERENCE_SHA256=()
    PREFLIGHT_REFERENCE_DECLARED_IDS=()
    PREFLIGHT_DATABASE_DECLARED_IDS=()
    PREFLIGHT_CONFIG_VALID=false
    PREFLIGHT_OUTPUT_DIR=''
    PREFLIGHT_REFERENCE_CONTIG_STYLE=''
    PREFLIGHT_FASTA_SHA256=''
    PREFLIGHT_STAGE_NAME="$PREFLIGHT_DEFAULT_STAGE"
    PREFLIGHT_STAGE_MODULE=13
}

preflight_error() {
    PREFLIGHT_ERRORS+=("$1")
}

preflight_warning() {
    PREFLIGHT_WARNINGS+=("$1")
}

preflight_information() {
    PREFLIGHT_INFORMATION+=("$1")
}

preflight_pass() {
    PREFLIGHT_CHECKS+=("PASS|$1|$2")
}

preflight_fail_check() {
    PREFLIGHT_CHECKS+=("FAIL|$1|$2")
    preflight_error "$2"
}

preflight_warn_check() {
    PREFLIGHT_CHECKS+=("WARN|$1|$2")
    preflight_warning "$2"
}

preflight_info_check() {
    PREFLIGHT_CHECKS+=("INFO|$1|$2")
    preflight_information "$2"
}

preflight_skip() {
    PREFLIGHT_CHECKS+=("SKIP|$1|$2")
}

preflight_print_usage() {
    cat <<'EOF'
Usage: bin/preflight.sh --config FILE --samples FILE [OPTIONS]

Validate the complete ClinicalSuite execution environment without starting any
scientific analysis.

Options:
  --config FILE       clinical.conf input
  --samples FILE      samples.tsv input
  --output-dir DIR    report directory override
  --stage STAGE       validate resources through STAGE
                      (default: VARIANT_FILTERING)
  -h, --help          show this help

Stages:
  QC, ALIGNMENT, COVERAGE, DEEPVARIANT, HAPLOTYPECALLER, OCTOPUS,
  CONSENSUS, VARIANT_FILTERING, ANNOTATION, ACMG, REPORTING
EOF
}

preflight_set_stage() {
    local requested="${1^^}"

    requested="${requested//-/_}"
    case "$requested" in
        6|QC) PREFLIGHT_STAGE_NAME=QC; PREFLIGHT_STAGE_MODULE=6 ;;
        7|ALIGNMENT) PREFLIGHT_STAGE_NAME=ALIGNMENT; PREFLIGHT_STAGE_MODULE=7 ;;
        8|COVERAGE) PREFLIGHT_STAGE_NAME=COVERAGE; PREFLIGHT_STAGE_MODULE=8 ;;
        9|DEEPVARIANT) PREFLIGHT_STAGE_NAME=DEEPVARIANT; PREFLIGHT_STAGE_MODULE=9 ;;
        10|GATK|HAPLOTYPECALLER)
            PREFLIGHT_STAGE_NAME=HAPLOTYPECALLER
            PREFLIGHT_STAGE_MODULE=10
            ;;
        11|OCTOPUS) PREFLIGHT_STAGE_NAME=OCTOPUS; PREFLIGHT_STAGE_MODULE=11 ;;
        12|CONSENSUS) PREFLIGHT_STAGE_NAME=CONSENSUS; PREFLIGHT_STAGE_MODULE=12 ;;
        13|FILTERING|VARIANT_FILTERING)
            PREFLIGHT_STAGE_NAME=VARIANT_FILTERING
            PREFLIGHT_STAGE_MODULE=13
            ;;
        14|ANNOTATION) PREFLIGHT_STAGE_NAME=ANNOTATION; PREFLIGHT_STAGE_MODULE=14 ;;
        15|ACMG) PREFLIGHT_STAGE_NAME=ACMG; PREFLIGHT_STAGE_MODULE=15 ;;
        16|REPORT|REPORTING) PREFLIGHT_STAGE_NAME=REPORTING; PREFLIGHT_STAGE_MODULE=16 ;;
        *) return 1 ;;
    esac
}

preflight_stage_label() {
    printf 'Module %s (%s)\n' "$PREFLIGHT_STAGE_MODULE" "$PREFLIGHT_STAGE_NAME"
}

preflight_environment_requirement() {
    local first_module

    first_module="$(clinical_environment_first_module "$1")" || return 1
    preflight_stage_requirement "$first_module" MANDATORY
}

preflight_resource_first_module() {
    local scope="$1" id="$2"

    if [[ "$scope" == reference ]]; then
        case "$id" in
            GRCH38_PAR_INTERVALS|DEEPVARIANT_MODEL_*) printf '9\n' ;;
            *) printf '7\n' ;;
        esac
        return
    fi
    case "$id" in
        REVEL|ACMG_*|CLINGEN*|HPO*|OMIM*|PANELAPP*|GENEREVIEWS*|DECIPHER*|\
        AUTOACMG*|INTERVAR*)
            printf '15\n'
            ;;
        *) printf '14\n' ;;
    esac
}

preflight_stage_requirement() {
    local first_module="$1"
    local eventual_requirement="${2:-MANDATORY}"

    if (( PREFLIGHT_STAGE_MODULE < first_module )); then
        PREFLIGHT_RESULT=FUTURE
    else
        PREFLIGHT_RESULT="$eventual_requirement"
    fi
}

preflight_requirement_issue() {
    local requirement="$1" category="$2" message="$3"

    case "$requirement" in
        MANDATORY) preflight_fail_check "$category" "$message" ;;
        OPTIONAL) preflight_warn_check "$category" "$message" ;;
        FUTURE) preflight_info_check "$category" "$message" ;;
        *) preflight_fail_check compatibility "Internal requirement error: $requirement" ;;
    esac
}

preflight_json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    PREFLIGHT_RESULT="$value"
}

preflight_timestamp() {
    local timestamp

    TZ=UTC printf -v timestamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    printf '%s\n' "$timestamp"
}

preflight_configuration_signature() {
    local key sample_id column

    {
        for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
            printf 'config\t%s\t%s\n' "$key" "${CLINICAL_CONFIG[$key]}"
        done
        for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
            for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
                printf 'sample\t%s\t%s\t%s\n' \
                    "$sample_id" "$column" "${CLINICAL_SAMPLES[$sample_id.$column]}"
            done
        done
    } | sha256sum | {
        local digest
        IFS=' ' read -r digest _
        printf '%s\n' "$digest"
    }
}

preflight_validate_configuration() {
    local config_file="$1"
    local samples_file="$2"
    local validation_output line

    if clinical_validate "$config_file" "$samples_file"; then
        PREFLIGHT_CONFIG_VALID=true
        preflight_pass configuration 'Configuration and sample manifest are valid'
        return 0
    fi

    validation_output="$(clinical_print_errors)"
    while IFS= read -r line; do
        [[ -n "$line" ]] && preflight_error "Configuration: $line"
    done <<<"$validation_output"
    PREFLIGHT_CHECKS+=("FAIL|configuration|Configuration or sample manifest validation failed")
    return 1
}

preflight_resolve_configuration() {
    local resolved_dir="$RUN_DIR/resolved_config"
    local original_signature resolved_signature

    if [[ ! -e "$resolved_dir/clinical.conf" && ! -e "$resolved_dir/samples.tsv" ]]; then
        if clinical_write_resolved "$resolved_dir"; then
            preflight_pass configuration "Resolved configuration created: $resolved_dir"
        else
            preflight_fail_check configuration "Cannot create resolved configuration: $resolved_dir"
            return 1
        fi
        return 0
    fi
    if [[ ! -f "$resolved_dir/clinical.conf" || ! -f "$resolved_dir/samples.tsv" ]]; then
        preflight_fail_check configuration "Resolved configuration is incomplete: $resolved_dir"
        return 1
    fi

    original_signature="$(preflight_configuration_signature)" || {
        preflight_fail_check configuration 'Cannot sign current configuration'
        return 1
    }
    if ! clinical_validate "$resolved_dir/clinical.conf" "$resolved_dir/samples.tsv"; then
        preflight_fail_check configuration "Existing resolved configuration is invalid: $resolved_dir"
        return 1
    fi
    resolved_signature="$(preflight_configuration_signature)" || {
        preflight_fail_check configuration 'Cannot sign existing resolved configuration'
        return 1
    }
    if [[ "$resolved_signature" != "$original_signature" ]]; then
        preflight_fail_check configuration \
            "Existing resolved configuration does not match requested inputs: $resolved_dir"
        clinical_validate "$1" "$2" >/dev/null 2>&1 || true
        return 1
    fi
    preflight_pass configuration "Existing resolved configuration matches requested inputs: $resolved_dir"
}

preflight_prepare_output() {
    local requested="$1"

    if [[ -n "$requested" ]]; then
        if [[ "$requested" == /* ]]; then
            PREFLIGHT_OUTPUT_DIR="$requested"
        else
            PREFLIGHT_OUTPUT_DIR="$(pwd -P)/$requested"
        fi
    elif [[ "$PREFLIGHT_CONFIG_VALID" == true ]]; then
        PREFLIGHT_OUTPUT_DIR="$RUN_DIR/preflight"
    else
        PREFLIGHT_OUTPUT_DIR="$(pwd -P)/preflight"
    fi
    if ! create_directory "$PREFLIGHT_OUTPUT_DIR" 0750 2>/dev/null; then
        printf 'ERROR: cannot create preflight report directory: %s\n' \
            "$PREFLIGHT_OUTPUT_DIR" >&2
        return 1
    fi
    common_init preflight "$PREFLIGHT_OUTPUT_DIR/preflight.log" 1 0 || return 1
}

preflight_check_runtime() {
    local command_name output
    local -a commands=(
        awk basename cat chmod cp date df dirname grep gzip head hostname id
        mkdir mktemp mv od pwd rm sed sha256sum sort stat tr
    )

    if (( BASH_VERSINFO[0] > 4 ||
        (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
        preflight_pass runtime "Bash ${BASH_VERSION} satisfies 4.4+"
    else
        preflight_fail_check runtime "Bash 4.4+ is required; found $BASH_VERSION"
    fi
    for command_name in "${commands[@]}"; do
        if require_command "$command_name" 2>/dev/null; then
            preflight_pass runtime "Required utility available: $command_name"
        else
            preflight_fail_check runtime "Required utility unavailable: $command_name"
        fi
    done
    if [[ "$PREFLIGHT_CONFIG_VALID" != true ]]; then
        preflight_skip runtime 'Mamba path check skipped because configuration is invalid'
        return
    fi
    if [[ ! -x "$MAMBA_BIN" ]]; then
        preflight_fail_check runtime "Mamba is not executable: $MAMBA_BIN"
        return
    fi
    output="$("$MAMBA_BIN" --version 2>&1)" || {
        preflight_fail_check runtime "Mamba version command failed: $MAMBA_BIN"
        return
    }
    preflight_pass runtime "Mamba available: $output"
}

preflight_check_write_access() {
    local label="$1"
    local directory="$2"
    local probe

    if [[ ! -d "$directory" || ! -w "$directory" || ! -x "$directory" ]]; then
        preflight_fail_check permissions "$label directory is not writable: $directory"
        return
    fi
    if ! probe="$(mktemp -- "$directory/.preflight-write.XXXXXX" 2>/dev/null)"; then
        preflight_fail_check permissions "$label directory cannot create files: $directory"
        return
    fi
    rm -f -- "$probe"
    preflight_pass permissions "$label directory is writable: $directory"
}

preflight_check_permissions() {
    local sample_id field path

    [[ "$PREFLIGHT_CONFIG_VALID" == true ]] || {
        preflight_skip permissions 'Permission checks skipped because configuration is invalid'
        return
    }
    preflight_check_write_access 'Run root' "$RUN_ROOT"
    preflight_check_write_access 'Scratch' "$SCRATCH_DIR"
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        for field in fastq_r1 fastq_r2; do
            path="${CLINICAL_SAMPLES[$sample_id.$field]}"
            if [[ -r "$path" ]]; then
                preflight_pass permissions "Readable input: $sample_id.$field"
            else
                preflight_fail_check permissions "Unreadable FASTQ: $sample_id.$field ($path)"
            fi
        done
    done
}

preflight_fastq_pair_key() {
    local path="$1"
    local read_number="$2"
    local name="${path##*/}"

    name="${name%.gz}"
    name="${name%.fastq}"
    name="${name%.fq}"
    if [[ "$read_number" == 1 ]]; then
        [[ "$name" =~ (^|[._-])R?1([._-]|$) ]] || return 1
        printf '%s\n' "$name" | sed -E 's/(^|[._-])R?1([._-]|$)/\1READ\2/'
    else
        [[ "$name" =~ (^|[._-])R?2([._-]|$) ]] || return 1
        printf '%s\n' "$name" | sed -E 's/(^|[._-])R?2([._-]|$)/\1READ\2/'
    fi
}

preflight_fastq_first_id() {
    local path="$1"
    local header

    if [[ "$path" == *.gz ]]; then
        IFS= read -r header < <(gzip -cd -- "$path") || return 1
    else
        IFS= read -r header <"$path" || return 1
    fi
    [[ "$header" == @* ]] || return 1
    header="${header#@}"
    header="${header%%[[:space:]]*}"
    header="${header%/1}"
    header="${header%/2}"
    printf '%s\n' "$header"
}

preflight_check_samples() {
    local sample_id r1 r2 key1 key2 id1 id2 id_key1 id_key2 assay interval

    [[ "$PREFLIGHT_CONFIG_VALID" == true ]] || {
        preflight_skip samples 'Sample checks skipped because configuration is invalid'
        return
    }
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        r1="${CLINICAL_SAMPLES[$sample_id.fastq_r1]}"
        r2="${CLINICAL_SAMPLES[$sample_id.fastq_r2]}"
        if check_fastq "$r1" 2>/dev/null; then
            preflight_pass samples "FASTQ structure valid: $sample_id R1"
        else
            preflight_fail_check samples "Unreadable or malformed FASTQ: $sample_id R1 ($r1)"
        fi
        if check_fastq "$r2" 2>/dev/null; then
            preflight_pass samples "FASTQ structure valid: $sample_id R2"
        else
            preflight_fail_check samples "Unreadable or malformed FASTQ: $sample_id R2 ($r2)"
        fi
        key1="$(preflight_fastq_pair_key "$r1" 1 2>/dev/null)" || key1=''
        key2="$(preflight_fastq_pair_key "$r2" 2 2>/dev/null)" || key2=''
        if [[ -n "$key1" && "$key1" == "$key2" ]]; then
            preflight_pass samples "FASTQ pair names match: $sample_id"
        else
            preflight_fail_check samples "FASTQ pair names do not match: $sample_id"
        fi
        id1="$(preflight_fastq_first_id "$r1" 2>/dev/null)" || id1=''
        id2="$(preflight_fastq_first_id "$r2" 2>/dev/null)" || id2=''
        id_key1="$(preflight_fastq_pair_key "$id1" 1 2>/dev/null)" || id_key1=''
        id_key2="$(preflight_fastq_pair_key "$id2" 2 2>/dev/null)" || id_key2=''
        if [[ -n "$id1" && ( "$id1" == "$id2" ||
            ( -n "$id_key1" && "$id_key1" == "$id_key2" ) ) ]]; then
            preflight_pass samples "FASTQ first-record identifiers match: $sample_id"
        else
            preflight_fail_check samples "FASTQ first-record identifiers do not match: $sample_id"
        fi

        assay="${CLINICAL_SAMPLES[$sample_id.assay]}"
        interval="${CLINICAL_SAMPLES[$sample_id.reportable_intervals]}"
        if [[ -r "$interval" && -s "$interval" ]]; then
            preflight_pass samples "Reportable intervals available: $sample_id"
        else
            preflight_fail_check samples "Missing reportable intervals: $sample_id ($interval)"
        fi
        if [[ "$assay" == WES ]]; then
            interval="${CLINICAL_SAMPLES[$sample_id.capture_intervals]}"
            if [[ -r "$interval" && -s "$interval" ]]; then
                preflight_pass samples "Capture intervals available: $sample_id"
            else
                preflight_fail_check samples "Missing WES capture intervals: $sample_id ($interval)"
            fi
        fi
    done
}

preflight_resource_key() {
    printf '%s.%s\n' "$1" "$2"
}

preflight_resolve_resource_path() {
    local root="$1"
    local declared="$2"

    clinical_path_is_well_formed "$declared" || return 1
    [[ "$declared" != '..' && "$declared" != ../* && "$declared" != */../* &&
        "$declared" != */.. ]] || return 1
    if [[ "$declared" == /* ]]; then
        PREFLIGHT_RESULT="$declared"
    else
        PREFLIGHT_RESULT="$root/$declared"
    fi
}

preflight_parse_resource_manifest() {
    local scope="$1"
    local root="$2"
    local manifest="$3"
    local expected_fields="$4"
    local expected_header="$5"
    local manifest_requirement="${6:-MANDATORY}"
    local line line_number=0 id path kind requirement assembly version checksum reference_checksum key
    local row_requirement first_module
    declare -A seen=()

    if [[ ! -r "$manifest" ]]; then
        preflight_requirement_issue "$manifest_requirement" resources \
            "Missing $scope manifest for $(preflight_stage_label): $manifest"
        return
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        [[ -n "$line" ]] || continue
        if (( line_number == 1 )); then
            [[ "$line" == "$expected_header" ]] ||
                preflight_requirement_issue "$manifest_requirement" resources \
                    "Malformed $scope manifest header: $manifest"
            continue
        fi
        clinical_split_tsv "$line"
        if (( ${#CLINICAL_TSV_FIELDS[@]} != expected_fields )); then
            preflight_requirement_issue "$manifest_requirement" resources \
                "Malformed $scope manifest row $line_number: expected $expected_fields fields"
            continue
        fi
        id="${CLINICAL_TSV_FIELDS[0]}"
        path="${CLINICAL_TSV_FIELDS[1]}"
        kind="${CLINICAL_TSV_FIELDS[2]}"
        requirement="${CLINICAL_TSV_FIELDS[3]}"
        assembly="${CLINICAL_TSV_FIELDS[4]}"
        version="${CLINICAL_TSV_FIELDS[5]}"
        checksum="${CLINICAL_TSV_FIELDS[6],,}"
        reference_checksum='-'
        (( expected_fields == 8 )) && reference_checksum="${CLINICAL_TSV_FIELDS[7],,}"
        if ! clinical_is_identifier "$id"; then
            preflight_requirement_issue "$manifest_requirement" resources \
                "Unsafe resource ID in $scope manifest line $line_number: $id"
            continue
        fi
        first_module="$(preflight_resource_first_module "$scope" "$id")"
        preflight_stage_requirement "$first_module" MANDATORY
        row_requirement="$PREFLIGHT_RESULT"
        if [[ -v "seen[$id]" ]]; then
            preflight_requirement_issue "$row_requirement" resources \
                "Duplicate resource ID in $scope manifest: $id"
            continue
        fi
        seen["$id"]=1
        [[ "$kind" == FILE || "$kind" == DIRECTORY ]] ||
            preflight_requirement_issue "$row_requirement" resources \
                "Invalid resource kind for $id: $kind"
        [[ "$requirement" == MANDATORY || "$requirement" == OPTIONAL ]] ||
            preflight_requirement_issue "$row_requirement" resources \
                "Invalid resource requirement for $id: $requirement"
        [[ -n "$version" && "$version" != latest ]] ||
            preflight_requirement_issue "$row_requirement" resources \
                "Unpinned resource version for $id: $version"
        if ! preflight_resolve_resource_path "$root" "$path"; then
            preflight_requirement_issue "$row_requirement" resources \
                "Malformed resource path for $id: $path"
            continue
        fi
        key="$(preflight_resource_key "$scope" "$id")"
        PREFLIGHT_RESOURCE_PATH["$key"]="$PREFLIGHT_RESULT"
        PREFLIGHT_RESOURCE_KIND["$key"]="$kind"
        PREFLIGHT_RESOURCE_REQUIREMENT["$key"]="$requirement"
        PREFLIGHT_RESOURCE_ASSEMBLY["$key"]="$assembly"
        PREFLIGHT_RESOURCE_VERSION["$key"]="$version"
        PREFLIGHT_RESOURCE_SHA256["$key"]="$checksum"
        PREFLIGHT_RESOURCE_REFERENCE_SHA256["$key"]="$reference_checksum"
        if [[ "$scope" == reference ]]; then
            PREFLIGHT_REFERENCE_DECLARED_IDS+=("$id")
        else
            PREFLIGHT_DATABASE_DECLARED_IDS+=("$id")
        fi
    done <"$manifest"
    if [[ "$manifest_requirement" == FUTURE ]]; then
        preflight_info_check resources \
            "Future $scope manifest inspected for $(preflight_stage_label): $manifest"
    else
        preflight_pass resources "$scope manifest parsed: $manifest"
    fi
}

preflight_check_resource_entry() {
    local scope="$1"
    local id="$2"
    local forced_requirement="${3:-}"
    local key path kind requirement assembly checksum actual first_module

    key="$(preflight_resource_key "$scope" "$id")"
    first_module="$(preflight_resource_first_module "$scope" "$id")"
    preflight_stage_requirement "$first_module" \
        "${forced_requirement:-${PREFLIGHT_RESOURCE_REQUIREMENT[$key]-MANDATORY}}"
    requirement="$PREFLIGHT_RESULT"
    if [[ ! -v "PREFLIGHT_RESOURCE_PATH[$key]" ]]; then
        preflight_requirement_issue "$requirement" resources \
            "$requirement resource not declared: $id (first required Module $first_module)"
        return
    fi
    path="${PREFLIGHT_RESOURCE_PATH[$key]}"
    kind="${PREFLIGHT_RESOURCE_KIND[$key]}"
    assembly="${PREFLIGHT_RESOURCE_ASSEMBLY[$key]}"
    checksum="${PREFLIGHT_RESOURCE_SHA256[$key]}"
    if [[ "$requirement" == FUTURE ]]; then
        if [[ "$kind" == FILE && -f "$path" && -r "$path" && -s "$path" ]] ||
            [[ "$kind" == DIRECTORY && -d "$path" && -r "$path" &&
                -n "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            preflight_info_check resources \
                "Future resource declared and available; content validation begins at Module $first_module: $id"
        else
            preflight_info_check resources \
                "FUTURE resource missing or unreadable: $id ($path; first required Module $first_module)"
        fi
        return
    fi
    if [[ "$kind" == FILE ]]; then
        if [[ ! -f "$path" || ! -r "$path" || ! -s "$path" ]]; then
            preflight_requirement_issue "$requirement" resources \
                "$requirement resource missing or unreadable: $id ($path)"
            return
        fi
        if [[ ! "$checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
            preflight_requirement_issue "$requirement" compatibility \
                "Invalid SHA-256 declaration for $requirement resource $id"
        else
            actual="$(calculate_checksum "$path" 2>/dev/null)" || actual=''
            if [[ "$actual" == "$checksum" ]]; then
                preflight_pass resources "Checksum valid: $id"
            else
                preflight_requirement_issue "$requirement" compatibility \
                    "Checksum mismatch for $requirement resource: $id ($path)"
            fi
        fi
    elif [[ "$kind" == DIRECTORY ]]; then
        if [[ ! -d "$path" || ! -r "$path" || -z "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            preflight_requirement_issue "$requirement" resources \
                "$requirement resource directory missing or empty: $id ($path)"
            return
        fi
        preflight_pass resources "Resource directory available: $id"
    fi
    if [[ "$assembly" != GRCh38 ]]; then
        preflight_requirement_issue "$requirement" compatibility \
            "Resource assembly mismatch for $requirement resource $id: $assembly"
    fi
}

preflight_require_resource_declaration() {
    local scope="$1"
    local id="$2"
    local eventual_requirement="${3:-MANDATORY}"
    local key first_module requirement

    key="$(preflight_resource_key "$scope" "$id")"
    first_module="$(preflight_resource_first_module "$scope" "$id")"
    preflight_stage_requirement "$first_module" "$eventual_requirement"
    requirement="$PREFLIGHT_RESULT"
    if [[ ! -v "PREFLIGHT_RESOURCE_PATH[$key]" ]]; then
        preflight_requirement_issue "$requirement" resources \
            "$requirement resource not declared: $id (first required Module $first_module)"
        return
    fi
    if [[ "$requirement" == MANDATORY &&
        "${PREFLIGHT_RESOURCE_REQUIREMENT[$key]}" != MANDATORY ]]; then
        preflight_fail_check compatibility \
            "Required resource is not declared MANDATORY: $id"
    fi
}

preflight_required_assays() {
    local sample_id assay
    declare -A seen=()

    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        assay="${CLINICAL_SAMPLES[$sample_id.assay]}"
        if [[ ! -v "seen[$assay]" ]]; then
            seen["$assay"]=1
            printf '%s\n' "$assay"
        fi
    done
}

preflight_check_reference_consistency() {
    local fasta_key fai_key dict_key fasta fai dictionary fasta_contig fai_contig dict_contig
    local requirement id key declared_version

    fasta_key="$(preflight_resource_key reference GRCH38_FASTA)"
    fai_key="$(preflight_resource_key reference GRCH38_FASTA_FAI)"
    dict_key="$(preflight_resource_key reference GRCH38_SEQUENCE_DICTIONARY)"
    [[ -v "PREFLIGHT_RESOURCE_PATH[$fasta_key]" &&
        -v "PREFLIGHT_RESOURCE_PATH[$fai_key]" &&
        -v "PREFLIGHT_RESOURCE_PATH[$dict_key]" ]] || return
    fasta="${PREFLIGHT_RESOURCE_PATH[$fasta_key]}"
    fai="${PREFLIGHT_RESOURCE_PATH[$fai_key]}"
    dictionary="${PREFLIGHT_RESOURCE_PATH[$dict_key]}"
    preflight_stage_requirement 7 MANDATORY
    requirement="$PREFLIGHT_RESULT"
    if [[ "${fasta##*/}" != "$PREFLIGHT_LOCKED_REFERENCE_BASENAME" ]]; then
        preflight_requirement_issue "$requirement" compatibility \
            "Unsupported GRCh38 FASTA: ${fasta##*/} (required: $PREFLIGHT_LOCKED_REFERENCE_BASENAME)"
    fi
    for id in GRCH38_FASTA GRCH38_FASTA_FAI GRCH38_SEQUENCE_DICTIONARY \
        BWA_MEM2_INDEX GRCH38_PAR_INTERVALS; do
        key="$(preflight_resource_key reference "$id")"
        [[ -v "PREFLIGHT_RESOURCE_VERSION[$key]" ]] || continue
        declared_version="${PREFLIGHT_RESOURCE_VERSION[$key]}"
        if [[ "$declared_version" != "$PREFLIGHT_LOCKED_REFERENCE_VERSION" ]]; then
            preflight_requirement_issue "$requirement" compatibility \
                "Unsupported reference version for $id: $declared_version (required: $PREFLIGHT_LOCKED_REFERENCE_VERSION)"
        fi
    done
    [[ -r "$fasta" && -r "$fai" && -r "$dictionary" ]] || return
    IFS= read -r fasta_contig <"$fasta" || fasta_contig=''
    fasta_contig="${fasta_contig#>}"
    fasta_contig="${fasta_contig%%[[:space:]]*}"
    IFS=$'\t' read -r fai_contig _ <"$fai" || fai_contig=''
    dict_contig="$(awk -F '\t' '$1=="@SQ" {for(i=1;i<=NF;i++) if($i ~ /^SN:/) {sub(/^SN:/,"",$i); print $i; exit}}' "$dictionary")"
    if [[ -n "$fasta_contig" && "$fasta_contig" == "$fai_contig" &&
        "$fasta_contig" == "$dict_contig" ]]; then
        preflight_pass compatibility "FASTA, FAI, and sequence dictionary share first contig: $fasta_contig"
        [[ "$fasta_contig" == chr* ]] && PREFLIGHT_REFERENCE_CONTIG_STYLE=chr ||
            PREFLIGHT_REFERENCE_CONTIG_STYLE=nochr
    else
        preflight_requirement_issue "$requirement" compatibility \
            "Reference indexes are inconsistent (FASTA=$fasta_contig FAI=$fai_contig dictionary=$dict_contig)"
    fi
    PREFLIGHT_FASTA_SHA256="${PREFLIGHT_RESOURCE_SHA256[$fasta_key]}"
}

preflight_check_interval_contig() {
    local label="$1"
    local path="$2"
    local first_module="${3:-8}"
    local contig=''
    local requirement

    preflight_stage_requirement "$first_module" MANDATORY
    requirement="$PREFLIGHT_RESULT"

    [[ -n "$PREFLIGHT_REFERENCE_CONTIG_STYLE" && -r "$path" ]] || return
    if [[ "$path" == *.gz ]]; then
        while IFS=$'\t' read -r contig _; do
            [[ -n "$contig" && "$contig" != \#* ]] && break
            contig=''
        done < <(gzip -cd -- "$path")
    else
        while IFS=$'\t' read -r contig _; do
            [[ -n "$contig" && "$contig" != \#* ]] && break
            contig=''
        done <"$path"
    fi
    [[ -n "$contig" ]] || {
        preflight_requirement_issue "$requirement" compatibility \
            "Interval file has no records for $requirement resource: $label ($path)"
        return
    }
    if [[ "$PREFLIGHT_REFERENCE_CONTIG_STYLE" == chr && "$contig" != chr* ]] ||
        [[ "$PREFLIGHT_REFERENCE_CONTIG_STYLE" == nochr && "$contig" == chr* ]]; then
        preflight_requirement_issue "$requirement" compatibility \
            "Interval contig naming is incompatible for $requirement resource: $label ($contig)"
    else
        preflight_pass compatibility "Interval contig naming matches reference: $label"
    fi
}

preflight_check_references_and_databases() {
    local id assay sample_id path key reference_checksum
    local reference_manifest database_manifest
    local reference_manifest_requirement database_manifest_requirement
    local resource_requirement first_module
    local reference_header=$'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256'
    local database_header=$'resource_id\tpath\tkind\trequirement\tassembly\tversion\tsha256\treference_sha256'

    [[ "$PREFLIGHT_CONFIG_VALID" == true ]] || {
        preflight_skip resources 'Reference/database checks skipped because configuration is invalid'
        return
    }
    reference_manifest="$REFERENCE_DIR/reference_manifest.tsv"
    database_manifest="$DATABASE_DIR/database_manifest.tsv"
    preflight_stage_requirement 7 MANDATORY
    reference_manifest_requirement="$PREFLIGHT_RESULT"
    preflight_stage_requirement 14 MANDATORY
    database_manifest_requirement="$PREFLIGHT_RESULT"
    preflight_parse_resource_manifest reference "$REFERENCE_DIR" \
        "$reference_manifest" 7 "$reference_header" "$reference_manifest_requirement"
    preflight_parse_resource_manifest database "$DATABASE_DIR" \
        "$database_manifest" 8 "$database_header" "$database_manifest_requirement"
    for id in "${PREFLIGHT_REFERENCE_DECLARED_IDS[@]}"; do
        preflight_check_resource_entry reference "$id"
    done
    for id in "${PREFLIGHT_REFERENCE_IDS[@]}"; do
        preflight_require_resource_declaration reference "$id"
    done
    while IFS= read -r assay; do
        preflight_require_resource_declaration reference "DEEPVARIANT_MODEL_$assay"
    done < <(preflight_required_assays)
    for id in "${PREFLIGHT_DATABASE_DECLARED_IDS[@]}"; do
        preflight_check_resource_entry database "$id"
    done
    for id in "${PREFLIGHT_DATABASE_IDS[@]}"; do
        preflight_require_resource_declaration database "$id"
    done
    for id in "${PREFLIGHT_OPTIONAL_DATABASE_IDS[@]}"; do
        preflight_require_resource_declaration database "$id" OPTIONAL
    done
    preflight_check_reference_consistency

    for id in "${PREFLIGHT_DATABASE_DECLARED_IDS[@]}"; do
        key="$(preflight_resource_key database "$id")"
        [[ -v "PREFLIGHT_RESOURCE_PATH[$key]" ]] || continue
        reference_checksum="${PREFLIGHT_RESOURCE_REFERENCE_SHA256[$key]}"
        first_module="$(preflight_resource_first_module database "$id")"
        preflight_stage_requirement "$first_module" \
            "${PREFLIGHT_RESOURCE_REQUIREMENT[$key]}"
        resource_requirement="$PREFLIGHT_RESULT"
        if [[ -n "$PREFLIGHT_FASTA_SHA256" &&
            "$reference_checksum" != "$PREFLIGHT_FASTA_SHA256" ]]; then
            preflight_requirement_issue "$resource_requirement" compatibility \
                "Database/reference checksum mismatch for $resource_requirement resource $id"
        fi
    done
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        path="${CLINICAL_SAMPLES[$sample_id.reportable_intervals]}"
        preflight_check_interval_contig "$sample_id reportable" "$path"
        if [[ "${CLINICAL_SAMPLES[$sample_id.assay]}" == WES ]]; then
            path="${CLINICAL_SAMPLES[$sample_id.capture_intervals]}"
            preflight_check_interval_contig "$sample_id capture" "$path"
        fi
    done
    key="$(preflight_resource_key reference GRCH38_PAR_INTERVALS)"
    [[ ! -v "PREFLIGHT_RESOURCE_PATH[$key]" ]] ||
        preflight_check_interval_contig GRCH38_PAR_INTERVALS \
            "${PREFLIGHT_RESOURCE_PATH[$key]}" 9
}

preflight_check_environment_command() {
    local environment="$1"
    local label="$2"
    local expected_pattern="$3"
    local expected_status="$4"
    shift 4
    local prefix="$ENV_DIR/$environment"
    local output status requirement

    preflight_environment_requirement "$environment"
    requirement="$PREFLIGHT_RESULT"
    if [[ "$requirement" == FUTURE ]]; then
        preflight_info_check environments \
            "Future environment executable check deferred until Module $(clinical_environment_first_module "$environment"): $label in $environment"
        return
    fi

    if output="$(run_environment "$prefix" -- "$@" 2>&1)"; then
        status=0
    else
        status=$?
    fi
    if (( status == expected_status )) && grep -Eq -- "$expected_pattern" <<<"$output"; then
        preflight_pass environments "$label available in $environment"
    else
        preflight_fail_check environments \
            "$label validation failed in $environment (status $status)"
    fi
}

preflight_check_environments() {
    local environment prefix lock_file yml_file requirement installed_lock
    local environments_ready=true

    [[ "$PREFLIGHT_CONFIG_VALID" == true ]] || {
        preflight_skip environments 'Conda environment checks skipped because configuration is invalid'
        return
    }
    for environment in "${PREFLIGHT_ENVIRONMENTS[@]}"; do
        prefix="$ENV_DIR/$environment"
        lock_file="$ENV_DIR/$environment.lock"
        yml_file="$ENV_DIR/$environment.yml"
        preflight_environment_requirement "$environment"
        requirement="$PREFLIGHT_RESULT"
        if [[ ! -d "$prefix/conda-meta" || ! -x "$prefix/bin" ]]; then
            preflight_requirement_issue "$requirement" environments \
                "Missing $requirement Conda environment: $prefix"
            [[ "$requirement" == FUTURE ]] || environments_ready=false
            continue
        fi
        if [[ ! -r "$lock_file" || ! -r "$yml_file" ]]; then
            preflight_requirement_issue "$requirement" environments \
                "Missing lock/YAML for $requirement environment: $environment"
            [[ "$requirement" == FUTURE ]] || environments_ready=false
            continue
        fi
        if [[ "$requirement" == FUTURE ]]; then
            preflight_info_check environments \
                "Future environment integrity validation deferred until Module $(clinical_environment_first_module "$environment"): $environment"
            continue
        fi
        installed_lock="$("$MAMBA_BIN" list --explicit --prefix "$prefix" 2>/dev/null)" || installed_lock=''
        if [[ -n "$installed_lock" && "$installed_lock" == "$(<"$lock_file")" ]]; then
            preflight_pass environments "Explicit lock matches installed environment: $environment"
        else
            preflight_requirement_issue "$requirement" environments \
                "Installed packages differ from explicit lock: $environment"
            environments_ready=false
        fi
    done

    [[ "$environments_ready" == true ]] || {
        preflight_skip environments 'Executable checks skipped because environment integrity failed'
        return
    }
    clinical_environment_each_runtime_check preflight_check_environment_command
}

preflight_check_disk_space_path() {
    local label="$1"
    local path="$2"
    local minimum_gb="$3"
    local available_kb available_gb message

    available_kb="$(df -Pk -- "$path" 2>/dev/null | awk 'NR==2 {print $4}')" || available_kb=''
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        preflight_fail_check disk "Cannot determine free space for $label: $path"
        return
    fi
    available_gb=$((available_kb / 1024 / 1024))
    message="$label free space ${available_gb}GiB; required ${minimum_gb}GiB"
    if (( available_gb < minimum_gb )); then
        if [[ "$DISK_SPACE_POLICY" == WARNING ]]; then
            preflight_warn_check disk "Low disk space: $message"
        else
            preflight_fail_check disk "Insufficient disk space: $message"
        fi
    else
        preflight_pass disk "$message"
    fi
}

preflight_check_disk_space() {
    [[ "$PREFLIGHT_CONFIG_VALID" == true ]] || {
        preflight_skip disk 'Disk-space checks skipped because configuration is invalid'
        return
    }
    preflight_check_disk_space_path 'Run root' "$RUN_ROOT" "$MIN_RUN_FREE_GB"
    preflight_check_disk_space_path 'Scratch' "$SCRATCH_DIR" "$MIN_SCRATCH_FREE_GB"
}

preflight_write_text_report() {
    local generated="$1"
    local status="$2"
    local item index=0 result category message

    {
        printf 'ClinicalSuite V2 preflight report\n'
        printf 'Generated (UTC): %s\n' "$generated"
        printf 'Execution stage: %s\n' "$(preflight_stage_label)"
        printf 'Status: %s\n' "$status"
        printf 'Errors: %s\n' "${#PREFLIGHT_ERRORS[@]}"
        printf 'Warnings: %s\n' "${#PREFLIGHT_WARNINGS[@]}"
        printf 'Information: %s\n' "${#PREFLIGHT_INFORMATION[@]}"
        printf '\nErrors\n------\n'
        if (( ${#PREFLIGHT_ERRORS[@]} == 0 )); then
            printf 'None\n'
        else
            for item in "${PREFLIGHT_ERRORS[@]}"; do
                ((index += 1))
                printf '%s. %s\n' "$index" "$item"
            done
        fi
        printf '\nWarnings\n--------\n'
        index=0
        if (( ${#PREFLIGHT_WARNINGS[@]} == 0 )); then
            printf 'None\n'
        else
            for item in "${PREFLIGHT_WARNINGS[@]}"; do
                ((index += 1))
                printf '%s. %s\n' "$index" "$item"
            done
        fi
        printf '\nInformation\n-----------\n'
        index=0
        if (( ${#PREFLIGHT_INFORMATION[@]} == 0 )); then
            printf 'None\n'
        else
            for item in "${PREFLIGHT_INFORMATION[@]}"; do
                ((index += 1))
                printf '%s. %s\n' "$index" "$item"
            done
        fi
        printf '\nChecks\n------\n'
        for item in "${PREFLIGHT_CHECKS[@]}"; do
            result="${item%%|*}"
            category="${item#*|}"
            message="${category#*|}"
            category="${category%%|*}"
            printf '[%s] %s: %s\n' "$result" "$category" "$message"
        done
    } | atomic_write "$PREFLIGHT_OUTPUT_DIR/preflight_report.txt" 0440
}

preflight_write_json_array() {
    local -n values_ref="$1"
    local item separator=''

    printf '['
    for item in "${values_ref[@]}"; do
        preflight_json_escape "$item"
        printf '%s"%s"' "$separator" "$PREFLIGHT_RESULT"
        separator=','
    done
    printf ']'
}

preflight_write_json_report() {
    local generated="$1"
    local status="$2"
    local item result category message separator=''

    {
        printf '{\n'
        printf '  "schema_version": "1.1",\n'
        printf '  "generated_at": "%s",\n' "$generated"
        printf '  "execution_stage": "%s",\n' "$PREFLIGHT_STAGE_NAME"
        printf '  "execution_module": %s,\n' "$PREFLIGHT_STAGE_MODULE"
        printf '  "status": "%s",\n' "$status"
        printf '  "error_count": %s,\n' "${#PREFLIGHT_ERRORS[@]}"
        printf '  "warning_count": %s,\n' "${#PREFLIGHT_WARNINGS[@]}"
        printf '  "information_count": %s,\n' "${#PREFLIGHT_INFORMATION[@]}"
        printf '  "errors": '
        preflight_write_json_array PREFLIGHT_ERRORS
        printf ',\n  "warnings": '
        preflight_write_json_array PREFLIGHT_WARNINGS
        printf ',\n  "information": '
        preflight_write_json_array PREFLIGHT_INFORMATION
        printf ',\n  "checks": ['
        for item in "${PREFLIGHT_CHECKS[@]}"; do
            result="${item%%|*}"
            category="${item#*|}"
            message="${category#*|}"
            category="${category%%|*}"
            preflight_json_escape "$result"
            result="$PREFLIGHT_RESULT"
            preflight_json_escape "$category"
            category="$PREFLIGHT_RESULT"
            preflight_json_escape "$message"
            message="$PREFLIGHT_RESULT"
            printf '%s\n    {"result":"%s","category":"%s","message":"%s"}' \
                "$separator" "$result" "$category" "$message"
            separator=','
        done
        (( ${#PREFLIGHT_CHECKS[@]} == 0 )) || printf '\n  '
        printf ']\n}\n'
    } | atomic_write "$PREFLIGHT_OUTPUT_DIR/preflight.json" 0440
}

preflight_write_reports() {
    local generated status

    generated="$(preflight_timestamp)"
    if (( ${#PREFLIGHT_ERRORS[@]} == 0 )); then
        status=PASS
    else
        status=FAIL
    fi
    preflight_write_text_report "$generated" "$status" || return 1
    preflight_write_json_report "$generated" "$status" || return 1
}

preflight_run() {
    local config_file="$1"
    local samples_file="$2"
    local output_override="${3:-}"
    local requested_stage="${4:-$PREFLIGHT_DEFAULT_STAGE}"

    preflight_reset
    preflight_set_stage "$requested_stage" || return "$PREFLIGHT_EX_USAGE"
    preflight_validate_configuration "$config_file" "$samples_file" || true
    preflight_prepare_output "$output_override" || return 1
    if [[ "$PREFLIGHT_CONFIG_VALID" == true ]]; then
        preflight_resolve_configuration "$config_file" "$samples_file" || true
    fi
    preflight_check_runtime
    preflight_check_permissions
    preflight_check_samples
    preflight_check_environments
    preflight_check_references_and_databases
    preflight_check_disk_space
    preflight_write_reports || return 1

    if (( ${#PREFLIGHT_ERRORS[@]} > 0 )); then
        cat -- "$PREFLIGHT_OUTPUT_DIR/preflight_report.txt" >&2
        printf '\nPreflight failed; reports: %s\n' "$PREFLIGHT_OUTPUT_DIR" >&2
        return "$PREFLIGHT_EX_UNAVAILABLE"
    fi
    printf 'Preflight passed; reports: %s\n' "$PREFLIGHT_OUTPUT_DIR"
}

preflight_main() {
    local config_file='' samples_file='' output_dir=''
    local stage="$PREFLIGHT_DEFAULT_STAGE"

    while (( $# > 0 )); do
        case "$1" in
            --config)
                (( $# >= 2 )) || { printf 'ERROR: --config requires a value\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
                config_file="$2"; shift 2
                ;;
            --samples)
                (( $# >= 2 )) || { printf 'ERROR: --samples requires a value\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
                samples_file="$2"; shift 2
                ;;
            --output-dir)
                (( $# >= 2 )) || { printf 'ERROR: --output-dir requires a value\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
                output_dir="$2"; shift 2
                ;;
            --stage)
                (( $# >= 2 )) || { printf 'ERROR: --stage requires a value\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
                stage="$2"; shift 2
                ;;
            -h|--help) preflight_print_usage; return 0 ;;
            *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; return "$PREFLIGHT_EX_USAGE" ;;
        esac
    done
    [[ -n "$config_file" ]] || { printf 'ERROR: --config is required\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
    [[ -n "$samples_file" ]] || { printf 'ERROR: --samples is required\n' >&2; return "$PREFLIGHT_EX_USAGE"; }
    if ! preflight_set_stage "$stage"; then
        printf 'ERROR: invalid --stage value: %s\n' "$stage" >&2
        return "$PREFLIGHT_EX_USAGE"
    fi
    preflight_run "$config_file" "$samples_file" "$output_dir" "$stage"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    preflight_main "$@"
fi
