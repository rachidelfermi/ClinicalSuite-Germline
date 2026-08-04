#!/usr/bin/env bash
# Shared ClinicalSuite V2 runtime helpers. This library deliberately leaves the
# caller's shell options unchanged and performs no work when sourced.

if [[ "${CLINICAL_COMMON_LOADED:-0}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly CLINICAL_COMMON_LOADED=1

COMMON_LIBRARY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly COMMON_LIBRARY_DIR

declare -g CLINICAL_MODULE_NAME='ClinicalSuite'
declare -g CLINICAL_LOG_FILE=''
declare -g CLINICAL_QUIET=0
declare -g CLINICAL_VERBOSE=0
declare -g CLINICAL_COLOR='auto'
declare -ga CLINICAL_CLEANUP_PATHS=()
declare -gA CLINICAL_TIMERS=()
declare -g RUN_COMMAND_STATUS=0
declare -g RUN_COMMAND_ELAPSED_SECONDS=0
declare -g TIMER_ELAPSED_SECONDS=0

###############################################################################
# PRIVATE HELPERS
###############################################################################

common__timestamp() {
    local timestamp

    TZ=UTC printf -v timestamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    printf '%s\n' "$timestamp"
}

common__valid_boolean() {
    [[ "$1" == 0 || "$1" == 1 ]]
}

common__valid_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

common__log() {
    local level="$1"
    local color="$2"
    local terminal_policy="$3"
    shift 3
    local message="$*"
    local timestamp line
    local use_color=false

    [[ "$terminal_policy" != debug || "$CLINICAL_VERBOSE" == 1 ]] || return 0
    message="${message//$'\r'/\\r}"
    message="${message//$'\n'/\\n}"
    timestamp="$(common__timestamp)"
    line="$timestamp [$CLINICAL_MODULE_NAME] $level: $message"
    if [[ -n "$CLINICAL_LOG_FILE" ]]; then
        if ! printf '%s\n' "$line" >>"$CLINICAL_LOG_FILE"; then
            printf '%s [ClinicalSuite] ERROR: cannot write log file: %s\n' \
                "$timestamp" "$CLINICAL_LOG_FILE" >&2
            return 1
        fi
    fi

    case "$terminal_policy" in
        quiet) (( CLINICAL_QUIET == 0 )) || return 0 ;;
        debug) (( CLINICAL_VERBOSE == 1 && CLINICAL_QUIET == 0 )) || return 0 ;;
        always) ;;
        *) printf 'ClinicalSuite internal error: invalid log policy\n' >&2; return 2 ;;
    esac
    if [[ "$CLINICAL_COLOR" == always ]] ||
        [[ "$CLINICAL_COLOR" == auto && -t 2 && -z "${NO_COLOR:-}" ]]; then
        use_color=true
    fi
    if [[ "$use_color" == true ]]; then
        printf '\033[%sm%s\033[0m\n' "$color" "$line" >&2
    else
        printf '%s\n' "$line" >&2
    fi
}

common__command_string() {
    local argument quoted
    local result=''

    for argument in "$@"; do
        printf -v quoted '%q' "$argument"
        result+="${result:+ }$quoted"
    done
    printf '%s\n' "$result"
}

common__unregister_cleanup() {
    local requested="$1"
    local path
    local -a retained=()

    for path in "${CLINICAL_CLEANUP_PATHS[@]}"; do
        [[ "$path" == "$requested" ]] || retained+=("$path")
    done
    CLINICAL_CLEANUP_PATHS=("${retained[@]}")
}

common__cleanup_on_exit() {
    local status=$?

    cleanup || true
    return "$status"
}

common__handle_signal() {
    local signal="$1"
    local status="$2"

    log_warning "received $signal; cleaning temporary paths"
    cleanup || true
    trap - "$signal"
    exit "$status"
}

common__read_fastq_record() {
    local file="$1"
    local first second third fourth

    if [[ "$file" == *.gz ]]; then
        {
            IFS= read -r first || return 1
            IFS= read -r second || return 1
            IFS= read -r third || return 1
            IFS= read -r fourth || return 1
        } < <(gzip -cd -- "$file")
    else
        {
            IFS= read -r first || return 1
            IFS= read -r second || return 1
            IFS= read -r third || return 1
            IFS= read -r fourth || return 1
        } <"$file"
    fi
    [[ "$first" == @* && "$third" == +* && -n "$second" && ${#second} -eq ${#fourth} ]]
}

common__emit_environment_report() {
    local hostname_value user_value os_value='unknown'
    local cpu_value='unknown' ram_kib='unknown' mamba_value='not configured'
    local key value mamba_bin line

    hostname_value="$(hostname 2>/dev/null || printf 'unknown')"
    user_value="$(id -un 2>/dev/null || printf '%s' "${USER:-unknown}")"
    if [[ -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
            if [[ "$key" == PRETTY_NAME ]]; then
                value="${value#\"}"
                value="${value%\"}"
                os_value="$value"
                break
            fi
        done </etc/os-release
    fi
    cpu_value="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 'unknown')"
    if [[ -r /proc/meminfo ]]; then
        while read -r key value _; do
            if [[ "$key" == MemTotal: ]]; then
                ram_kib="$value"
                break
            fi
        done </proc/meminfo
    fi
    if mamba_bin="$(config_get MAMBA_BIN 2>/dev/null)"; then
        mamba_value="$("$mamba_bin" --version 2>&1 | { IFS= read -r line; printf '%s' "$line"; })"
    fi

    printf 'generated_at=%s\n' "$(common__timestamp)"
    printf 'hostname=%s\n' "$hostname_value"
    printf 'user=%s\n' "$user_value"
    printf 'operating_system=%s\n' "$os_value"
    printf 'cpu_count=%s\n' "$cpu_value"
    printf 'ram_kib=%s\n' "$ram_kib"
    printf 'mamba_version=%s\n' "$mamba_value"
}

###############################################################################
# INITIALIZATION AND LOGGING
###############################################################################

common_init() {
    local module_name="${1:-ClinicalSuite}"
    local log_file="${2:-}"
    local quiet="${3:-0}"
    local verbose="${4:-0}"
    local parent

    common__valid_identifier "$module_name" || {
        printf 'ERROR: unsafe module name: %s\n' "$module_name" >&2
        return 2
    }
    if ! common__valid_boolean "$quiet" || ! common__valid_boolean "$verbose"; then
        printf 'ERROR: quiet and verbose must be 0 or 1\n' >&2
        return 2
    fi
    if [[ -n "$log_file" ]]; then
        [[ "$log_file" == /* ]] || {
            printf 'ERROR: log path must be absolute: %s\n' "$log_file" >&2
            return 2
        }
        [[ ! -L "$log_file" ]] || {
            printf 'ERROR: log path must not be a symbolic link: %s\n' "$log_file" >&2
            return 2
        }
        parent="${log_file%/*}"
        [[ -d "$parent" && -w "$parent" ]] || {
            printf 'ERROR: log directory is not writable: %s\n' "$parent" >&2
            return 2
        }
        : >>"$log_file" || return 2
    fi
    CLINICAL_MODULE_NAME="$module_name"
    CLINICAL_LOG_FILE="$log_file"
    CLINICAL_QUIET="$quiet"
    CLINICAL_VERBOSE="$verbose"
}

log_info() { common__log INFO '36' quiet "$@"; }
log_warning() { common__log WARNING '33' always "$@"; }
log_error() { common__log ERROR '31' always "$@"; }
log_success() { common__log SUCCESS '32' quiet "$@"; }
log_debug() { common__log DEBUG '90' debug "$@"; }

###############################################################################
# ERROR HANDLING
###############################################################################

die() {
    local message="${1:-unspecified fatal error}"
    local status="${2:-1}"

    [[ "$status" =~ ^[1-9][0-9]*$ && "$status" -le 255 ]] || status=1
    log_error "$message"
    exit "$status"
}

warn() { log_warning "$@"; }

require_file() {
    local path="$1"

    [[ -f "$path" && -r "$path" ]] && return 0
    log_error "required readable file is missing: $path"
    return 1
}

require_directory() {
    local path="$1"

    [[ -d "$path" && -r "$path" && -x "$path" ]] && return 0
    log_error "required readable directory is missing: $path"
    return 1
}

require_command() {
    local command_name="$1"

    command -v -- "$command_name" >/dev/null 2>&1 && return 0
    log_error "required command is unavailable: $command_name"
    return 1
}

###############################################################################
# TEMPORARY PATHS AND CLEANUP
###############################################################################

register_cleanup() {
    local path="$1"

    [[ "$path" == /* && "$path" != / ]] || {
        log_error "cleanup path must be absolute and may not be root: $path"
        return 2
    }
    CLINICAL_CLEANUP_PATHS+=("$path")
}

create_temp_directory() {
    local output_variable="$1"
    local parent="${2:-${TMPDIR:-/tmp}}"
    local prefix="${3:-clinicalsuite}"
    local created

    [[ "$output_variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        log_error "invalid output variable name: $output_variable"
        return 2
    }
    require_directory "$parent" || return 1
    common__valid_identifier "$prefix" || {
        log_error "unsafe temporary-directory prefix: $prefix"
        return 2
    }
    created="$(mktemp -d -- "$parent/$prefix.XXXXXX")" || {
        log_error "cannot create temporary directory under: $parent"
        return 1
    }
    register_cleanup "$created" || return 1
    printf -v "$output_variable" '%s' "$created"
}

cleanup() {
    local index path status=0

    for ((index=${#CLINICAL_CLEANUP_PATHS[@]} - 1; index >= 0; index--)); do
        path="${CLINICAL_CLEANUP_PATHS[$index]}"
        [[ -e "$path" || -L "$path" ]] || continue
        if ! rm -rf -- "$path"; then
            log_error "failed to remove temporary path: $path"
            status=1
        fi
    done
    CLINICAL_CLEANUP_PATHS=()
    return "$status"
}

setup_cleanup_traps() {
    trap common__cleanup_on_exit EXIT
    trap 'common__handle_signal SIGINT 130' INT
    trap 'common__handle_signal SIGTERM 143' TERM
}

###############################################################################
# FILESYSTEM AND CHECKPOINT UTILITIES
###############################################################################

create_directory() {
    local path="$1"
    local mode="${2:-0750}"

    [[ -n "$path" && "$mode" =~ ^0?[0-7]{3}$ ]] || {
        log_error "invalid directory path or mode: $path $mode"
        return 2
    }
    if ! mkdir -p -- "$path" || ! chmod "$mode" -- "$path"; then
        log_error "cannot create directory: $path"
        return 1
    fi
}

atomic_write() {
    local target="$1"
    shift
    local mode='0640'
    local parent="${target%/*}"
    local leaf="${target##*/}"
    local temporary
    local temporary_absolute
    local writer_status=0
    local -a writer=()

    if (( $# > 0 )) && [[ "$1" =~ ^0?[0-7]{3}$ ]]; then
        mode="$1"
        shift
    fi
    if (( $# > 0 )); then
        [[ "$1" == -- ]] || { log_error "unknown atomic_write argument: $1"; return 2; }
        shift
        writer=("$@")
        (( ${#writer[@]} > 0 )) || { log_error 'atomic_write received no writer command'; return 2; }
    fi

    [[ "$parent" != "$target" ]] || parent='.'
    [[ -d "$parent" && -w "$parent" && ! -L "$target" ]] || {
        log_error "atomic-write target is unsafe or unwritable: $target"
        return 1
    }
    [[ "$mode" =~ ^0?[0-7]{3}$ ]] || {
        log_error "invalid atomic-write mode: $mode"
        return 2
    }
    temporary="$(mktemp -- "$parent/.$leaf.tmp.XXXXXX")" || {
        log_error "cannot create temporary output beside: $target"
        return 1
    }
    temporary_absolute="$(cd -P -- "$parent" && pwd -P)/${temporary##*/}"
    register_cleanup "$temporary_absolute" || return 1
    if (( ${#writer[@]} > 0 )); then
        if "${writer[@]}" >"$temporary"; then
            writer_status=0
        else
            writer_status=$?
        fi
    else
        if cat >"$temporary"; then
            writer_status=0
        else
            writer_status=$?
        fi
    fi
    if (( writer_status != 0 )); then
        rm -f -- "$temporary"
        common__unregister_cleanup "$temporary_absolute"
        log_error "atomic-write producer failed with status $writer_status: $target"
        return "$writer_status"
    fi
    if ! chmod "$mode" -- "$temporary" || ! mv -f -- "$temporary" "$target"; then
        log_error "atomic write failed: $target"
        return 1
    fi
    common__unregister_cleanup "$temporary_absolute"
}

safe_copy() {
    local source="$1"
    local target="$2"
    local source_mode

    require_file "$source" || return 1
    [[ ! -e "$target" && ! -L "$target" ]] || {
        log_error "copy target already exists: $target"
        return 1
    }
    source_mode="$(stat -c '%a' "$source")" || return 1
    atomic_write "$target" "$source_mode" <"$source"
}

safe_move() {
    local source="$1"
    local target="$2"

    require_file "$source" || return 1
    [[ ! -e "$target" && ! -L "$target" ]] || {
        log_error "move target already exists: $target"
        return 1
    }
    if ! mv -- "$source" "$target"; then
        log_error "cannot move $source to $target"
        return 1
    fi
}

create_complete_marker() {
    local marker="$1"
    local signature="$2"
    local provenance_file="${3:-}"
    local content

    [[ "$signature" =~ ^[[:xdigit:]]{64}$ ]] || {
        log_error 'checkpoint signature must be a SHA-256 digest'
        return 2
    }
    if [[ -n "$provenance_file" ]]; then
        require_file "$provenance_file" || return 1
    fi
    content="format=ClinicalSuite-complete-v1
signature=${signature,,}
completed_at=$(common__timestamp)"
    if [[ -n "$provenance_file" ]]; then
        content+=$'\nprovenance_begin\n'
        content+="$(cat -- "$provenance_file")"
        content+=$'\nprovenance_end'
    fi
    printf '%s\n' "$content" | atomic_write "$marker" 0440
}

check_complete_marker() {
    local marker="$1"
    local expected_signature="$2"
    local key value format='' signature=''
    local format_seen=false signature_seen=false

    [[ "$expected_signature" =~ ^[[:xdigit:]]{64}$ ]] || return 2
    [[ -f "$marker" && -r "$marker" ]] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            format)
                [[ "$format_seen" == false ]] || return 1
                format_seen=true
                format="$value"
                ;;
            signature)
                [[ "$signature_seen" == false ]] || return 1
                signature_seen=true
                signature="$value"
                ;;
            provenance_begin) break ;;
        esac
    done <"$marker"
    [[ "$format" == ClinicalSuite-complete-v1 && "$signature" == "${expected_signature,,}" ]]
}

###############################################################################
# COMMAND AND CONDA-ENVIRONMENT EXECUTION
###############################################################################

run_command() {
    local retries=0 retry_delay=0 timing=false stdout_file='' stderr_file=''
    local attempt=0 status=0 started elapsed capture_directory stdout_capture stderr_capture
    local cleanup_path
    local command_text
    local -a command=()

    while (( $# > 0 )); do
        case "$1" in
            --retries)
                (( $# >= 2 )) || { log_error '--retries requires a value'; return 2; }
                retries="$2"; shift 2
                ;;
            --retry-delay)
                (( $# >= 2 )) || { log_error '--retry-delay requires a value'; return 2; }
                retry_delay="$2"; shift 2
                ;;
            --timing) timing=true; shift ;;
            --stdout)
                (( $# >= 2 )) || { log_error '--stdout requires a value'; return 2; }
                stdout_file="$2"; shift 2
                ;;
            --stderr)
                (( $# >= 2 )) || { log_error '--stderr requires a value'; return 2; }
                stderr_file="$2"; shift 2
                ;;
            --) shift; command=("$@"); break ;;
            *) log_error "unknown run_command option: $1"; return 2 ;;
        esac
    done
    [[ "$retries" =~ ^[0-9]+$ && "$retry_delay" =~ ^[0-9]+$ ]] || {
        log_error 'run_command retries and delay must be non-negative integers'
        return 2
    }
    (( ${#command[@]} > 0 )) || { log_error 'run_command received no command'; return 2; }
    create_temp_directory capture_directory "${TMPDIR:-/tmp}" command-capture || return 1
    stdout_capture="$capture_directory/stdout"
    stderr_capture="$capture_directory/stderr"
    command_text="$(common__command_string "${command[@]}")"
    started=$SECONDS

    while (( attempt <= retries )); do
        ((attempt += 1))
        log_info "command attempt $attempt/$((retries + 1)): $command_text"
        if "${command[@]}" >"$stdout_capture" 2>"$stderr_capture"; then
            status=0
            break
        else
            status=$?
        fi
        if (( attempt <= retries )); then
            log_warning "command failed with status $status; retrying: $command_text"
            (( retry_delay == 0 )) || sleep "$retry_delay"
        fi
    done
    elapsed=$((SECONDS - started))
    RUN_COMMAND_STATUS="$status"
    # Public result state is consumed by callers after the function returns.
    # shellcheck disable=SC2034
    RUN_COMMAND_ELAPSED_SECONDS="$elapsed"

    if [[ -n "$stdout_file" ]]; then
        atomic_write "$stdout_file" <"$stdout_capture" || status=1
    else
        cat -- "$stdout_capture"
    fi
    if [[ -n "$stderr_file" ]]; then
        atomic_write "$stderr_file" <"$stderr_capture" || status=1
    else
        cat -- "$stderr_capture" >&2
    fi
    if [[ "$timing" == true ]]; then
        log_info "command runtime: ${elapsed}s: $command_text"
    fi
    if (( status != 0 )); then
        log_error "command failed with status $status: $command_text"
    else
        log_debug "command completed successfully: $command_text"
    fi
    cleanup_path="$capture_directory"
    rm -rf -- "$capture_directory"
    common__unregister_cleanup "$cleanup_path"
    # shellcheck disable=SC2034
    RUN_COMMAND_STATUS="$status"
    return "$status"
}

run_environment() {
    local prefix=''
    local source_path destination_path mode
    local mapping argument mapped
    local -a mappings=() environment_command=() activated_command=()

    while (( $# > 0 )); do
        case "$1" in
            --bind-ro|--bind-rw)
                (( $# >= 3 )) || { log_error "$1 requires host and logical paths"; return 2; }
                mode="${1#--bind-}"
                source_path="$2"
                destination_path="$3"
                shift 3
                [[ "$source_path" == /* && -e "$source_path" && "$destination_path" == /* &&
                    "$source_path" != *[:,]* && "$destination_path" != *[:,]* ]] || {
                    log_error "invalid environment path mapping: $source_path -> $destination_path"
                    return 2
                }
                mappings+=("$source_path" "$destination_path" "$mode")
                ;;
            --) shift; environment_command=("$@"); break ;;
            -*) log_error "unknown run_environment option: $1"; return 2 ;;
            *)
                [[ -z "$prefix" ]] || { log_error "unexpected environment argument: $1"; return 2; }
                prefix="$1"
                shift
                ;;
        esac
    done
    [[ -n "$prefix" && -d "$prefix/conda-meta" && -x "$prefix/bin" ]] || {
        log_error "Conda environment is missing or invalid: $prefix"
        return 1
    }
    (( ${#environment_command[@]} > 0 )) || {
        log_error 'run_environment received no command'
        return 2
    }

    # Module commands use stable logical paths. Translate only
    # declared mappings so the scientific command contracts remain unchanged.
    for argument in "${environment_command[@]}"; do
        mapped="$argument"
        for ((mapping=0; mapping<${#mappings[@]}; mapping+=3)); do
            source_path="${mappings[mapping]}"
            destination_path="${mappings[mapping + 1]}"
            mapped="${mapped//"$destination_path"/"$source_path"}"
        done
        activated_command+=("$mapped")
    done
    run_command -- env \
        "CONDA_PREFIX=$prefix" \
        "CONDA_DEFAULT_ENV=${prefix##*/}" \
        CONDA_SHLVL=1 \
        "PATH=$prefix/bin:/usr/bin:/bin" \
        JAVA_HOME= PYTHONHOME= PYTHONPATH= \
        "${activated_command[@]}"
}

###############################################################################
# STRUCTURAL VALIDATION
###############################################################################

check_fastq() {
    local file="$1"

    require_file "$file" || return 1
    [[ -s "$file" && "$file" =~ \.(fastq|fq)(\.gz)?$ ]] || {
        log_error "invalid FASTQ path or empty file: $file"
        return 1
    }
    if [[ "$file" == *.gz ]] && ! gzip -t -- "$file"; then
        log_error "invalid gzip stream: $file"
        return 1
    fi
    common__read_fastq_record "$file" || {
        log_error "invalid first FASTQ record: $file"
        return 1
    }
}

check_bam() {
    local file="$1"
    local samtools_command="${2:-}"
    local magic

    require_file "$file" || return 1
    [[ -s "$file" && "$file" == *.bam ]] || {
        log_error "invalid BAM path or empty file: $file"
        return 1
    }
    if [[ -n "$samtools_command" ]]; then
        require_command "$samtools_command" || return 1
        "$samtools_command" quickcheck -v -- "$file" || {
            log_error "BAM structural validation failed: $file"
            return 1
        }
    else
        gzip -t -- "$file" 2>/dev/null || {
            log_error "BAM is not a valid BGZF/gzip stream: $file"
            return 1
        }
        magic="$(gzip -cd -- "$file" 2>/dev/null | head -c 4 | od -An -t x1 | tr -d ' \n')"
        [[ "$magic" == 42414d01 ]] || {
            log_error "BAM magic bytes are invalid: $file"
            return 1
        }
    fi
}

check_vcf() {
    local file="$1"
    local line
    local found_format=false found_header=false

    require_file "$file" || return 1
    [[ -s "$file" && "$file" =~ \.vcf(\.gz)?$ ]] || {
        log_error "invalid VCF path or empty file: $file"
        return 1
    }
    if [[ "$file" == *.gz ]]; then
        gzip -t -- "$file" || { log_error "invalid gzip stream: $file"; return 1; }
        while IFS= read -r line; do
            [[ "$line" == '##fileformat=VCF'* ]] && found_format=true
            [[ "$line" == '#CHROM'$'\t'* ]] && found_header=true
        done < <(gzip -cd -- "$file")
    else
        while IFS= read -r line; do
            [[ "$line" == '##fileformat=VCF'* ]] && found_format=true
            [[ "$line" == '#CHROM'$'\t'* ]] && found_header=true
        done <"$file"
    fi
    [[ "$found_format" == true && "$found_header" == true ]] || {
        log_error "VCF headers are incomplete: $file"
        return 1
    }
}

check_index() {
    local data_file="$1"
    local index_file="$2"

    require_file "$data_file" && require_file "$index_file" || return 1
    [[ -s "$index_file" ]] || { log_error "index is empty: $index_file"; return 1; }
}

calculate_checksum() {
    local file="$1"
    local output

    require_file "$file" || return 1
    output="$(sha256sum -- "$file")" || { log_error "cannot checksum file: $file"; return 1; }
    printf '%s\n' "${output%% *}"
}

check_checksum() {
    local file="$1"
    local expected="${2,,}"
    local actual

    [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
        log_error 'expected checksum must be a SHA-256 digest'
        return 2
    }
    actual="$(calculate_checksum "$file")" || return 1
    [[ "$actual" == "$expected" ]] || {
        log_error "checksum mismatch: $file"
        return 1
    }
}

###############################################################################
# VERSION AND ENVIRONMENT REPORTING
###############################################################################

get_tool_version() {
    local output line status

    (( $# > 0 )) || { log_error 'get_tool_version received no command'; return 2; }
    if output="$("$@" 2>&1)"; then
        status=0
    else
        status=$?
    fi
    (( status == 0 )) || { log_error "version command failed with status $status"; return "$status"; }
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
            return 0
        fi
    done <<<"$output"
    log_error 'version command returned no output'
    return 1
}

get_environment_version() {
    local prefix="$1"
    shift

    (( $# > 0 )) || { log_error 'get_environment_version received no command'; return 2; }
    run_environment "$prefix" -- "$@"
}

get_pipeline_version() {
    local version_file="${1:-$COMMON_LIBRARY_DIR/../VERSION}"
    local version

    require_file "$version_file" || return 1
    IFS= read -r version <"$version_file" || true
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._-][A-Za-z0-9.-]+)?$ ]] || {
        log_error "invalid pipeline version: $version"
        return 1
    }
    printf '%s\n' "$version"
}

report_environment() {
    local output_file="${1:-}"

    if [[ -z "$output_file" ]]; then
        common__emit_environment_report
    else
        common__emit_environment_report | atomic_write "$output_file" 0440
    fi
}

###############################################################################
# PROGRESS, TIMING, AND CONFIGURATION ACCESS
###############################################################################

report_progress() {
    local current="$1"
    local total="$2"
    local label="$3"

    if [[ ! "$current" =~ ^[0-9]+$ || ! "$total" =~ ^[1-9][0-9]*$ ]] ||
        (( current < 1 || current > total )); then
        log_error "invalid progress position: $current/$total"
        return 2
    fi
    log_info "[$current/$total] $label"
}

start_timer() {
    local name="$1"

    common__valid_identifier "$name" || { log_error "invalid timer name: $name"; return 2; }
    [[ ! -v "CLINICAL_TIMERS[$name]" ]] || { log_error "timer already started: $name"; return 1; }
    CLINICAL_TIMERS["$name"]="$SECONDS"
}

stop_timer() {
    local name="$1"
    local started

    [[ -v "CLINICAL_TIMERS[$name]" ]] || { log_error "timer was not started: $name"; return 1; }
    started="${CLINICAL_TIMERS[$name]}"
    TIMER_ELAPSED_SECONDS=$((SECONDS - started))
    unset 'CLINICAL_TIMERS[$name]'
    log_info "timer $name: ${TIMER_ELAPSED_SECONDS}s"
    printf '%s\n' "$TIMER_ELAPSED_SECONDS"
}

config_get() {
    local requested="$1"
    local key allowed=false declaration

    declaration="$(declare -p CLINICAL_CONFIG 2>/dev/null)" || {
        log_error 'validated configuration is not loaded'
        return 1
    }
    [[ "$declaration" == 'declare -A '* ]] || {
        log_error 'CLINICAL_CONFIG is not an associative array'
        return 1
    }
    declaration="$(declare -p CLINICAL_CONFIG_KEYS 2>/dev/null)" || {
        log_error 'configuration allowlist is not loaded'
        return 1
    }
    [[ "$declaration" == 'declare -a '* || "$declaration" == 'declare -ar '* ]] || {
        log_error 'CLINICAL_CONFIG_KEYS is not an indexed array'
        return 1
    }
    for key in "${CLINICAL_CONFIG_KEYS[@]}"; do
        [[ "$requested" == "$key" ]] && { allowed=true; break; }
    done
    [[ "$allowed" == true ]] || { log_error "unknown configuration key: $requested"; return 2; }
    [[ -v "CLINICAL_CONFIG[$requested]" ]] || return 1
    printf '%s\n' "${CLINICAL_CONFIG[$requested]}"
}

config_require() {
    local requested="$1"
    local value

    value="$(config_get "$requested")" || return 1
    [[ -n "$value" ]] || { log_error "required configuration value is empty: $requested"; return 1; }
    printf '%s\n' "$value"
}
