#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=bin/common.sh
source "$REPOSITORY_ROOT/bin/common.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT
CLINICAL_COLOR=never
work_directory=''

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

common_init module-3-smoke "$TEST_ROOT/module.log" 0 1
register_cleanup "$TEST_ROOT"
setup_cleanup_traps
create_temp_directory work_directory "$TEST_ROOT" work
printf 'smoke-output\n' | atomic_write "$work_directory/output.txt"
digest="$(calculate_checksum "$work_directory/output.txt")"
create_complete_marker "$work_directory/module.complete" "$digest"
check_complete_marker "$work_directory/module.complete" "$digest"
run_command --stdout "$work_directory/version.txt" -- bash --version
grep -Fq 'GNU bash' "$work_directory/version.txt" || fail 'run_command smoke output is wrong'

environment_output="$(run_environment \
    "$REPOSITORY_ROOT/envs/report" -- python --version)"
[[ "$environment_output" == 'Python 3.12.12' ]] ||
    fail "unexpected report environment output: $environment_output"
declare -ga CLINICAL_CONFIG_KEYS=(MAMBA_BIN)
declare -gA CLINICAL_CONFIG=(
    [MAMBA_BIN]="${MAMBA_BIN:-/home/bio/anaconda3/envs/mamba/bin/mamba}"
)
report_environment "$work_directory/environment.txt"
grep -Fq 'mamba_version=' "$work_directory/environment.txt" ||
    fail 'environment report is incomplete'
report_progress 1 1 'Common library smoke test'

printf 'PASS: common Bash library smoke test\n'
