#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly ENV_DIR="$REPOSITORY_ROOT/envs"
# shellcheck source=envs/lib.sh
source "$ENV_DIR/lib.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; return 1; }

main() {
    local environment
    local require_archives="${1:-}"

    [[ -x "$ENV_DIR/build.sh" ]] || fail 'build.sh is not executable'
    [[ -x "$ENV_DIR/validate.sh" ]] || fail 'validate.sh is not executable'
    [[ -x "$ENV_DIR/activate.sh" ]] || fail 'activate.sh is not executable'
    [[ -s "$ENV_DIR/environment_validation_report.txt" ]] ||
        fail 'validation report is missing'
    grep -Fqx 'overall: PASS' "$ENV_DIR/environment_validation_report.txt" ||
        fail 'validation report is not successful'

    for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
        [[ -d "$ENV_DIR/$environment/conda-meta" ]] ||
            fail "environment does not activate: $environment"
        [[ -s "$ENV_DIR/$environment.lock" ]] ||
            fail "missing explicit lock: $environment.lock"
        [[ -s "$ENV_DIR/$environment.yml" ]] ||
            fail "missing resolved YAML: $environment.yml"
        "$ENV_DIR/activate.sh" "$environment" true ||
            fail "automatic activation failed: $environment"
        if [[ "$require_archives" == '--require-archives' ]]; then
            [[ -s "$ENV_DIR/$environment.tar.gz" ]] ||
                fail "missing portable archive: $environment.tar.gz"
        fi
    done
    printf 'PASS: Conda environment system smoke test\n'
}

main "$@"
