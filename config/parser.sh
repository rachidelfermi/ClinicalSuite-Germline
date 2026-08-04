#!/usr/bin/env bash
# Sourceable ClinicalSuite V2 configuration and sample-manifest parser.
# This file intentionally does not change the caller's shell options.

if [[ "${CLINICAL_CONFIG_PARSER_LOADED:-0}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly CLINICAL_CONFIG_PARSER_LOADED=1

###############################################################################
# PUBLIC SCHEMA
###############################################################################

readonly -a CLINICAL_CONFIG_KEYS=(
    RUN_ID
    RUN_ROOT
    REFERENCE_DIR
    DATABASE_DIR
    ENV_DIR
    ASSAY_PROFILE_DIR
    ASSAY_PROFILE
    SCRATCH_DIR
    MAMBA_BIN
    REFERENCE_BUILD
    THREADS
    MEMORY_GB
    CALLER_CONCURRENCY
    TIMEZONE
    LOCALE
    FILE_UMASK
    MIN_RUN_FREE_GB
    MIN_SCRATCH_FREE_GB
    DISK_SPACE_POLICY
)

readonly -a CLINICAL_REQUIRED_CONFIG_KEYS=(
    RUN_ID
    RUN_ROOT
    REFERENCE_DIR
    DATABASE_DIR
    ENV_DIR
    ASSAY_PROFILE_DIR
    ASSAY_PROFILE
    SCRATCH_DIR
    MAMBA_BIN
)

readonly -a CLINICAL_SAMPLE_COLUMNS=(
    sample_id
    assay
    platform
    fastq_r1
    fastq_r2
    library_id
    platform_unit
    sequencing_center
    read_group_id
    expected_chromosome_complement
    capture_intervals
    reportable_intervals
)

declare -gA CLINICAL_CONFIG=()
declare -gA CLINICAL_SAMPLES=()
declare -ga CLINICAL_SAMPLE_IDS=()
declare -gA CLINICAL_ERROR_TEXT=()
declare -ga CLINICAL_ERROR_ORDER=()
declare -g CLINICAL_CONFIG_SOURCE=''
declare -g CLINICAL_SAMPLES_SOURCE=''
declare -g CLINICAL_RESOLVED_CONFIG_DIR=''
declare -g CLINICAL_RESULT=''

###############################################################################
# ERROR AGGREGATION
###############################################################################

clinical_reset_errors() {
    CLINICAL_ERROR_TEXT=()
    CLINICAL_ERROR_ORDER=()
}

clinical_add_error() {
    local category="$1"
    local detail="$2"

    if [[ ! -v "CLINICAL_ERROR_TEXT[$category]" ]]; then
        CLINICAL_ERROR_ORDER+=("$category")
        CLINICAL_ERROR_TEXT["$category"]=''
    fi
    CLINICAL_ERROR_TEXT["$category"]+="  - $detail"$'\n'
}

clinical_has_errors() {
    (( ${#CLINICAL_ERROR_ORDER[@]} > 0 ))
}

clinical_print_errors() {
    local category

    printf 'Configuration validation failed.\n'
    for category in "${CLINICAL_ERROR_ORDER[@]}"; do
        printf '\n%s:\n' "$category"
        printf '%s' "${CLINICAL_ERROR_TEXT[$category]}"
    done
}

###############################################################################
# STRING AND PATH HELPERS
###############################################################################

clinical_trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    CLINICAL_RESULT="$value"
}

clinical_is_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

clinical_path_is_well_formed() {
    local value="$1"

    [[ -n "$value" ]] || return 1
    [[ "$value" != '~'* ]] || return 1
    [[ ! "$value" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] || return 1
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]]
}

clinical_absolute_existing_path() {
    local value="$1"
    local base_directory="$2"
    local kind="$3"
    local candidate
    local parent
    local leaf
    local resolved_parent

    clinical_path_is_well_formed "$value" || return 1
    if [[ "$value" == /* ]]; then
        candidate="$value"
    else
        candidate="$base_directory/$value"
    fi

    case "$kind" in
        directory)
            [[ -d "$candidate" ]] || return 2
            [[ -r "$candidate" && -x "$candidate" ]] || return 3
            CLINICAL_RESULT="$(cd -P -- "$candidate" 2>/dev/null && pwd -P)" || return 1
            ;;
        file|executable)
            [[ -f "$candidate" ]] || return 2
            [[ -r "$candidate" ]] || return 3
            [[ "$kind" != executable || -x "$candidate" ]] || return 3
            parent="${candidate%/*}"
            leaf="${candidate##*/}"
            [[ "$parent" != "$candidate" ]] || parent='.'
            resolved_parent="$(cd -P -- "$parent" 2>/dev/null && pwd -P)" || return 1
            CLINICAL_RESULT="$resolved_parent/$leaf"
            ;;
        *)
            return 1
            ;;
    esac
}

clinical_config_directory() {
    local source_path="$1"
    local parent="${source_path%/*}"

    [[ "$parent" != "$source_path" ]] || parent='.'
    CLINICAL_RESULT="$(cd -P -- "$parent" 2>/dev/null && pwd -P)" || return 1
}

clinical_split_tsv() {
    local remaining="$1"$'\t'
    declare -ga CLINICAL_TSV_FIELDS=()

    while [[ "$remaining" == *$'\t'* ]]; do
        CLINICAL_TSV_FIELDS+=("${remaining%%$'\t'*}")
        remaining="${remaining#*$'\t'}"
    done
}

###############################################################################
# CONFIGURATION PARSING
###############################################################################

clinical_config_key_is_allowed() {
    local requested="$1"
    local key

    for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
        [[ "$requested" == "$key" ]] && return 0
    done
    return 1
}

clinical_config_key_is_required() {
    local requested="$1"
    local key

    for key in "${CLINICAL_REQUIRED_CONFIG_KEYS[@]}"; do
        [[ "$requested" == "$key" ]] && return 0
    done
    return 1
}

clinical_apply_config_defaults() {
    [[ -v CLINICAL_CONFIG[REFERENCE_BUILD] ]] || CLINICAL_CONFIG[REFERENCE_BUILD]='GRCh38'
    [[ -v CLINICAL_CONFIG[THREADS] ]] || CLINICAL_CONFIG[THREADS]='8'
    [[ -v CLINICAL_CONFIG[MEMORY_GB] ]] || CLINICAL_CONFIG[MEMORY_GB]='32'
    [[ -v CLINICAL_CONFIG[CALLER_CONCURRENCY] ]] || CLINICAL_CONFIG[CALLER_CONCURRENCY]='3'
    [[ -v CLINICAL_CONFIG[TIMEZONE] ]] || CLINICAL_CONFIG[TIMEZONE]='UTC'
    [[ -v CLINICAL_CONFIG[LOCALE] ]] || CLINICAL_CONFIG[LOCALE]='C.UTF-8'
    [[ -v CLINICAL_CONFIG[FILE_UMASK] ]] || CLINICAL_CONFIG[FILE_UMASK]='0027'
    [[ -v CLINICAL_CONFIG[MIN_RUN_FREE_GB] ]] || CLINICAL_CONFIG[MIN_RUN_FREE_GB]='50'
    [[ -v CLINICAL_CONFIG[MIN_SCRATCH_FREE_GB] ]] || CLINICAL_CONFIG[MIN_SCRATCH_FREE_GB]='100'
    [[ -v CLINICAL_CONFIG[DISK_SPACE_POLICY] ]] || CLINICAL_CONFIG[DISK_SPACE_POLICY]='ERROR'
}

clinical_validate_integer() {
    local key="$1"
    local minimum="$2"
    local maximum="$3"
    local value="${CLINICAL_CONFIG[$key]-}"

    if [[ ! "$value" =~ ^[0-9]+$ || ${#value} -gt 6 ]]; then
        clinical_add_error 'Invalid value' "$key=$value (expected integer $minimum-$maximum)"
        return
    fi
    if (( 10#$value < minimum || 10#$value > maximum )); then
        clinical_add_error 'Invalid value' "$key=$value (expected integer $minimum-$maximum)"
    fi
}

clinical_validate_config_values() {
    local base_directory="$1"
    local key
    local value
    local status

    for key in RUN_ID ASSAY_PROFILE; do
        value="${CLINICAL_CONFIG[$key]-}"
        if [[ -n "$value" ]] && ! clinical_is_identifier "$value"; then
            clinical_add_error 'Invalid value' "$key=$value (unsafe identifier)"
        fi
    done

    for key in RUN_ROOT REFERENCE_DIR DATABASE_DIR ENV_DIR ASSAY_PROFILE_DIR SCRATCH_DIR; do
        value="${CLINICAL_CONFIG[$key]-}"
        [[ -n "$value" ]] || continue
        status=0
        clinical_absolute_existing_path "$value" "$base_directory" directory || status=$?
        case "$status" in
            0) CLINICAL_CONFIG["$key"]="$CLINICAL_RESULT" ;;
            1) clinical_add_error 'Invalid path' "$key=$value" ;;
            2) clinical_add_error 'Missing path' "$key=$value" ;;
            3) clinical_add_error 'Invalid path' "$key=$value (directory is not readable)" ;;
        esac
    done

    for key in RUN_ROOT SCRATCH_DIR; do
        value="${CLINICAL_CONFIG[$key]-}"
        [[ ! -d "$value" || -w "$value" ]] || \
            clinical_add_error 'Invalid path' "$key=$value (directory is not writable)"
    done

    value="${CLINICAL_CONFIG[MAMBA_BIN]-}"
    if [[ -n "$value" ]]; then
        status=0
        clinical_absolute_existing_path "$value" "$base_directory" executable || status=$?
        case "$status" in
            0) CLINICAL_CONFIG[MAMBA_BIN]="$CLINICAL_RESULT" ;;
            1) clinical_add_error 'Invalid path' "MAMBA_BIN=$value" ;;
            2) clinical_add_error 'Missing path' "MAMBA_BIN=$value" ;;
            3) clinical_add_error 'Invalid path' "MAMBA_BIN=$value (not executable)" ;;
        esac
    fi

    [[ "${CLINICAL_CONFIG[REFERENCE_BUILD]-}" == GRCh38 ]] || \
        clinical_add_error 'Invalid value' \
            "REFERENCE_BUILD=${CLINICAL_CONFIG[REFERENCE_BUILD]-} (expected GRCh38)"
    [[ "${CLINICAL_CONFIG[TIMEZONE]-}" == UTC ]] || \
        clinical_add_error 'Invalid value' \
            "TIMEZONE=${CLINICAL_CONFIG[TIMEZONE]-} (expected UTC)"
    [[ "${CLINICAL_CONFIG[LOCALE]-}" == C || "${CLINICAL_CONFIG[LOCALE]-}" == C.UTF-8 ]] || \
        clinical_add_error 'Invalid value' \
            "LOCALE=${CLINICAL_CONFIG[LOCALE]-} (expected C or C.UTF-8)"
    [[ "${CLINICAL_CONFIG[FILE_UMASK]-}" =~ ^0[0-7]{3}$ ]] || \
        clinical_add_error 'Invalid value' \
            "FILE_UMASK=${CLINICAL_CONFIG[FILE_UMASK]-} (expected four octal digits)"
    [[ "${CLINICAL_CONFIG[DISK_SPACE_POLICY]-}" == ERROR ||
        "${CLINICAL_CONFIG[DISK_SPACE_POLICY]-}" == WARNING ]] || \
        clinical_add_error 'Invalid value' \
            "DISK_SPACE_POLICY=${CLINICAL_CONFIG[DISK_SPACE_POLICY]-} (expected ERROR or WARNING)"

    clinical_validate_integer THREADS 1 1024
    clinical_validate_integer MEMORY_GB 1 65536
    clinical_validate_integer CALLER_CONCURRENCY 1 3
    clinical_validate_integer MIN_RUN_FREE_GB 0 999999
    clinical_validate_integer MIN_SCRATCH_FREE_GB 0 999999
}

clinical_parse_config() {
    local source_path="$1"
    local line
    local line_number=0
    local key
    local value
    local base_directory
    local required_key
    declare -A seen_keys=()

    CLINICAL_CONFIG=()
    CLINICAL_CONFIG_SOURCE="$source_path"

    if [[ ! -r "$source_path" || ! -f "$source_path" ]]; then
        clinical_add_error 'Missing configuration file' "$source_path"
        return 0
    fi

    clinical_config_directory "$source_path" || {
        clinical_add_error 'Invalid path' "configuration file: $source_path"
        return 0
    }
    base_directory="$CLINICAL_RESULT"
    # Public parser state retained for downstream provenance consumers.
    # shellcheck disable=SC2034
    CLINICAL_CONFIG_SOURCE="$base_directory/${source_path##*/}"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" != *=* ]]; then
            clinical_add_error 'Malformed configuration' "line $line_number: $line"
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"
        clinical_trim "$key"
        key="$CLINICAL_RESULT"
        clinical_trim "$value"
        value="$CLINICAL_RESULT"

        if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            clinical_add_error 'Malformed configuration' "line $line_number: invalid key '$key'"
            continue
        fi
        if [[ -v "seen_keys[$key]" ]]; then
            clinical_add_error 'Duplicate key' "$key (line $line_number)"
            continue
        fi
        seen_keys["$key"]=1
        if ! clinical_config_key_is_allowed "$key"; then
            clinical_add_error 'Unknown key' "$key (line $line_number)"
            continue
        fi
        CLINICAL_CONFIG["$key"]="$value"
    done <"$source_path"

    for required_key in "${CLINICAL_REQUIRED_CONFIG_KEYS[@]}"; do
        if [[ ! -v "CLINICAL_CONFIG[$required_key]" ]]; then
            clinical_add_error 'Missing key' "$required_key"
        elif [[ -z "${CLINICAL_CONFIG[$required_key]}" ]]; then
            clinical_add_error 'Empty mandatory value' "$required_key"
        fi
    done

    clinical_apply_config_defaults
    clinical_validate_config_values "$base_directory"
}

###############################################################################
# SAMPLE MANIFEST PARSING
###############################################################################

clinical_manifest_column_is_allowed() {
    local requested="$1"
    local column

    for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
        [[ "$requested" == "$column" ]] && return 0
    done
    return 1
}

clinical_manifest_value() {
    local column="$1"
    local index="${CLINICAL_COLUMN_INDEX[$column]-}"

    if [[ -n "$index" && "$index" =~ ^[0-9]+$ && $index -lt ${#CLINICAL_TSV_FIELDS[@]} ]]; then
        CLINICAL_RESULT="${CLINICAL_TSV_FIELDS[$index]}"
    else
        CLINICAL_RESULT=''
    fi
}

clinical_resolve_sample_file() {
    local sample_id="$1"
    local field="$2"
    local value="$3"
    local base_directory="$4"
    local category="$5"
    local status=0

    if ! clinical_path_is_well_formed "$value"; then
        clinical_add_error 'Invalid path' "$sample_id.$field=$value"
        return 0
    fi
    clinical_absolute_existing_path "$value" "$base_directory" file || status=$?
    if [[ $status -eq 0 ]]; then
        CLINICAL_SAMPLES["$sample_id.$field"]="$CLINICAL_RESULT"
    elif [[ $status -eq 2 ]]; then
        clinical_add_error "$category" "$sample_id.$field=$value"
    else
        clinical_add_error 'Invalid path' "$sample_id.$field=$value"
    fi
}

clinical_validate_sample_row() {
    local line_number="$1"
    local base_directory="$2"
    local sample_id
    local field
    local value
    local fastq_r1
    local fastq_r2
    local assay
    local platform
    local complement
    local capture
    declare -n seen_samples_ref="$3"
    declare -n seen_read_groups_ref="$4"

    clinical_manifest_value sample_id
    sample_id="$CLINICAL_RESULT"
    if [[ -z "$sample_id" ]]; then
        clinical_add_error 'Malformed sample row' "line $line_number: empty sample_id"
        sample_id="line_$line_number"
    elif ! clinical_is_identifier "$sample_id"; then
        clinical_add_error 'Invalid sample ID' "$sample_id (line $line_number)"
        # Never use untrusted text as an associative-array subscript.
        sample_id="line_$line_number"
    fi
    if [[ -v "seen_samples_ref[$sample_id]" ]]; then
        clinical_add_error 'Duplicate sample' "$sample_id (line $line_number)"
    else
        seen_samples_ref["$sample_id"]=1
        CLINICAL_SAMPLE_IDS+=("$sample_id")
    fi

    for field in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
        clinical_manifest_value "$field"
        value="$CLINICAL_RESULT"
        CLINICAL_SAMPLES["$sample_id.$field"]="$value"
        if [[ -z "$value" ]]; then
            clinical_add_error 'Malformed sample row' "line $line_number: empty $field"
        fi
    done

    clinical_manifest_value assay
    assay="$CLINICAL_RESULT"
    [[ "$assay" == WGS || "$assay" == WES ]] || \
        clinical_add_error 'Invalid assay' "$sample_id=$assay"

    clinical_manifest_value platform
    platform="$CLINICAL_RESULT"
    [[ "$platform" == ILLUMINA || "$platform" == GENEMIND ]] || \
        clinical_add_error 'Invalid platform' "$sample_id=$platform"

    for field in library_id platform_unit sequencing_center read_group_id; do
        clinical_manifest_value "$field"
        value="$CLINICAL_RESULT"
        if [[ -n "$value" ]] && ! clinical_is_identifier "$value"; then
            clinical_add_error 'Invalid read-group field' "$sample_id.$field=$value"
        fi
    done
    clinical_manifest_value read_group_id
    value="$CLINICAL_RESULT"
    if [[ -n "$value" ]] && clinical_is_identifier "$value"; then
        if [[ -v "seen_read_groups_ref[$value]" ]]; then
            clinical_add_error 'Duplicate read group' "$value (sample $sample_id)"
        else
            seen_read_groups_ref["$value"]=1
        fi
    fi

    clinical_manifest_value expected_chromosome_complement
    complement="$CLINICAL_RESULT"
    [[ "$complement" =~ ^(XX|XY|X0|XXY|XXX|XYY|OTHER|UNKNOWN|NA)$ ]] || \
        clinical_add_error 'Invalid chromosome complement' "$sample_id=$complement"

    clinical_manifest_value fastq_r1
    fastq_r1="$CLINICAL_RESULT"
    clinical_manifest_value fastq_r2
    fastq_r2="$CLINICAL_RESULT"
    [[ "$fastq_r1" =~ \.(fastq|fq)(\.gz)?$ ]] || \
        clinical_add_error 'Invalid path' "$sample_id.fastq_r1=$fastq_r1 (expected FASTQ suffix)"
    [[ "$fastq_r2" =~ \.(fastq|fq)(\.gz)?$ ]] || \
        clinical_add_error 'Invalid path' "$sample_id.fastq_r2=$fastq_r2 (expected FASTQ suffix)"
    clinical_resolve_sample_file "$sample_id" fastq_r1 "$fastq_r1" "$base_directory" 'Missing FASTQ'
    clinical_resolve_sample_file "$sample_id" fastq_r2 "$fastq_r2" "$base_directory" 'Missing FASTQ'
    if [[ -n "$fastq_r1" && "$fastq_r1" == "$fastq_r2" ]]; then
        clinical_add_error 'Invalid FASTQ pair' "$sample_id uses the same path for R1 and R2"
    fi

    clinical_manifest_value capture_intervals
    capture="$CLINICAL_RESULT"
    if [[ "$assay" == WGS ]]; then
        [[ "$capture" == NA ]] || \
            clinical_add_error 'Invalid interval' "$sample_id.capture_intervals must be NA for WGS"
    elif [[ "$assay" == WES ]]; then
        if [[ "$capture" == NA || -z "$capture" ]]; then
            clinical_add_error 'Invalid interval' "$sample_id.capture_intervals is required for WES"
        else
            [[ "$capture" =~ \.bed(\.gz)?$ ]] || \
                clinical_add_error 'Invalid path' "$sample_id.capture_intervals=$capture (expected BED suffix)"
            clinical_resolve_sample_file \
                "$sample_id" capture_intervals "$capture" "$base_directory" 'Missing interval'
        fi
    fi

    clinical_manifest_value reportable_intervals
    value="$CLINICAL_RESULT"
    [[ "$value" =~ \.bed(\.gz)?$ ]] || \
        clinical_add_error 'Invalid path' "$sample_id.reportable_intervals=$value (expected BED suffix)"
    clinical_resolve_sample_file \
        "$sample_id" reportable_intervals "$value" "$base_directory" 'Missing interval'
}

clinical_parse_samples() {
    local source_path="$1"
    local line
    local line_number=0
    local base_directory
    local column
    local index
    local header_field_count=0
    local skip_header=true
    declare -gA CLINICAL_COLUMN_INDEX=()
    declare -A seen_columns=()
    # These arrays are consumed through namerefs in clinical_validate_sample_row.
    # shellcheck disable=SC2034
    declare -A seen_samples=()
    # shellcheck disable=SC2034
    declare -A seen_read_groups=()

    CLINICAL_SAMPLES=()
    CLINICAL_SAMPLE_IDS=()
    CLINICAL_SAMPLES_SOURCE="$source_path"

    if [[ ! -r "$source_path" || ! -f "$source_path" ]]; then
        clinical_add_error 'Missing sample manifest' "$source_path"
        return 0
    fi

    clinical_config_directory "$source_path" || {
        clinical_add_error 'Invalid path' "sample manifest: $source_path"
        return 0
    }
    base_directory="$CLINICAL_RESULT"
    CLINICAL_SAMPLES_SOURCE="$base_directory/${source_path##*/}"

    if ! IFS= read -r line <"$source_path"; then
        clinical_add_error 'Malformed sample manifest' 'file is empty'
        return 0
    fi
    ((line_number += 1))
    line="${line%$'\r'}"
    clinical_split_tsv "$line"
    header_field_count="${#CLINICAL_TSV_FIELDS[@]}"
    for index in "${!CLINICAL_TSV_FIELDS[@]}"; do
        column="${CLINICAL_TSV_FIELDS[$index]}"
        if ! clinical_manifest_column_is_allowed "$column"; then
            clinical_add_error 'Unknown column' "$column"
            continue
        fi
        if [[ -v "seen_columns[$column]" ]]; then
            clinical_add_error 'Duplicate column' "$column"
            continue
        fi
        seen_columns["$column"]=1
        CLINICAL_COLUMN_INDEX["$column"]="$index"
    done
    for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
        [[ -v "CLINICAL_COLUMN_INDEX[$column]" ]] || \
            clinical_add_error 'Missing column' "$column"
    done

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        if [[ "$skip_header" == true ]]; then
            skip_header=false
            continue
        fi
        [[ -z "$line" ]] && continue
        clinical_split_tsv "$line"
        if (( ${#CLINICAL_TSV_FIELDS[@]} != header_field_count )); then
            clinical_add_error 'Malformed sample row' \
                "line $line_number: expected $header_field_count fields, found ${#CLINICAL_TSV_FIELDS[@]}"
        fi
        clinical_validate_sample_row \
            "$line_number" "$base_directory" seen_samples seen_read_groups
    done <"$source_path"

    (( ${#CLINICAL_SAMPLE_IDS[@]} > 0 )) || \
        clinical_add_error 'Malformed sample manifest' 'no sample rows'
}

###############################################################################
# PUBLIC VALIDATION, EXPORT, AND RESOLUTION
###############################################################################

clinical_export_config() {
    local key

    for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
        printf -v "$key" '%s' "${CLINICAL_CONFIG[$key]}"
        export "${key?}"
    done
    printf -v SAMPLES_TSV '%s' "$CLINICAL_SAMPLES_SOURCE"
    printf -v RUN_DIR '%s' "${CLINICAL_CONFIG[RUN_ROOT]}/${CLINICAL_CONFIG[RUN_ID]}"
    export SAMPLES_TSV RUN_DIR
}

clinical_validate() {
    local config_path="$1"
    local samples_path="$2"

    clinical_reset_errors
    clinical_parse_config "$config_path"
    clinical_parse_samples "$samples_path"
    if clinical_has_errors; then
        return 1
    fi
    clinical_export_config
    return 0
}

clinical_write_resolved() {
    local target_directory="$1"
    local config_temporary
    local samples_temporary
    local old_umask
    local key
    local sample_id
    local column
    local separator

    if [[ -L "$target_directory" ]]; then
        clinical_add_error 'Invalid path' "resolved configuration is a symbolic link: $target_directory"
        return 1
    fi
    if [[ -e "$target_directory/clinical.conf" || -e "$target_directory/samples.tsv" ]]; then
        clinical_add_error 'Immutable configuration exists' "$target_directory"
        return 1
    fi

    mkdir -p -- "$target_directory" || {
        clinical_add_error 'Invalid path' "cannot create resolved configuration: $target_directory"
        return 1
    }
    target_directory="$(cd -P -- "$target_directory" 2>/dev/null && pwd -P)" || {
        clinical_add_error 'Invalid path' "cannot resolve configuration directory: $target_directory"
        return 1
    }
    config_temporary="$target_directory/.clinical.conf.$$"
    samples_temporary="$target_directory/.samples.tsv.$$"
    old_umask="$(umask)"
    umask 077
    if ! : >"$config_temporary" || ! : >"$samples_temporary"; then
        umask "$old_umask"
        rm -f -- "$config_temporary" "$samples_temporary"
        clinical_add_error 'Invalid path' "cannot write resolved configuration: $target_directory"
        return 1
    fi
    for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
        printf '%s=%s\n' "$key" "${CLINICAL_CONFIG[$key]}" >>"$config_temporary"
    done

    separator=''
    for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
        printf '%s%s' "$separator" "$column" >>"$samples_temporary"
        separator=$'\t'
    done
    printf '\n' >>"$samples_temporary"
    for sample_id in "${CLINICAL_SAMPLE_IDS[@]}"; do
        separator=''
        for column in "${CLINICAL_SAMPLE_COLUMNS[@]}"; do
            printf '%s%s' "$separator" "${CLINICAL_SAMPLES[$sample_id.$column]}" \
                >>"$samples_temporary"
            separator=$'\t'
        done
        printf '\n' >>"$samples_temporary"
    done

    if ! chmod 0444 -- "$config_temporary" "$samples_temporary" ||
        ! mv -- "$config_temporary" "$target_directory/clinical.conf" ||
        ! mv -- "$samples_temporary" "$target_directory/samples.tsv" ||
        ! chmod 0555 -- "$target_directory"; then
        umask "$old_umask"
        rm -f -- "$config_temporary" "$samples_temporary"
        clinical_add_error 'Invalid path' "cannot finalize resolved configuration: $target_directory"
        return 1
    fi
    umask "$old_umask"
    CLINICAL_RESOLVED_CONFIG_DIR="$target_directory"
    export CLINICAL_RESOLVED_CONFIG_DIR
}
