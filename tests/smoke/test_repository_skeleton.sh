#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT

###############################################################################
# EXPECTED REPOSITORY CONTRACT
###############################################################################

readonly -a REQUIRED_DIRECTORIES=(
    bin
    config
    config/schemas
    containers
    containers/definitions
    databases
    docs
    references
    tests
    tests/integration
    tests/smoke
    tests/unit
    validation
    validation/expected
    validation/fixtures
    validation/scripts
)

readonly -a REQUIRED_FILES=(
    .gitignore
    Architecture.md
    CHANGELOG.md
    README.md
    VERSION
    run.sh
    containers/README.md
    databases/README.md
    docs/implementation-status.md
    docs/scientific-decisions.md
    docs/validation-plan.md
    references/README.md
    tests/unit/test_run_interface.sh
)

###############################################################################
# TEST HELPERS
###############################################################################

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

###############################################################################
# STRUCTURE TESTS
###############################################################################

test_required_directories() {
    local relative_path

    for relative_path in "${REQUIRED_DIRECTORIES[@]}"; do
        [[ -d "$REPOSITORY_ROOT/$relative_path" ]] || \
            fail "missing directory: $relative_path"
    done
}

test_required_files() {
    local relative_path

    for relative_path in "${REQUIRED_FILES[@]}"; do
        [[ -f "$REPOSITORY_ROOT/$relative_path" ]] || \
            fail "missing file: $relative_path"
    done

    [[ -x "$REPOSITORY_ROOT/run.sh" ]] || fail 'run.sh is not executable'
    [[ -x "$REPOSITORY_ROOT/tests/unit/test_run_interface.sh" ]] || \
        fail 'unit test is not executable'
}

###############################################################################
# ENTRY-POINT TESTS
###############################################################################

test_help() {
    local output

    output="$("$REPOSITORY_ROOT/run.sh" --help)"
    [[ "$output" == *'--preflight-only'* ]] || \
        fail 'run.sh --help did not expose the current preflight interface'
}

test_missing_inputs_exit() {
    local output
    local status

    set +e
    output="$("$REPOSITORY_ROOT/run.sh" 2>&1)"
    status=$?
    set -e

    [[ $status -eq 69 ]] || fail "run.sh returned $status instead of 69"
    [[ "$output" == *'ClinicalSuite V2 requires validated configuration and sample inputs.'* ]] || \
        fail 'run.sh did not provide a clear missing-input message'
}

###############################################################################
# MAIN
###############################################################################

main() {
    test_required_directories
    test_required_files
    test_help
    test_missing_inputs_exit
    printf 'PASS: repository skeleton smoke test\n'
}

main "$@"
