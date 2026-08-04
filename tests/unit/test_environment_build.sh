#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly BUILD_SCRIPT="$REPOSITORY_ROOT/envs/build.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; return 1; }

main() {
    local environment
    local -a environments=(
        qc alignment variant deepvariant octopus annotation report
    )

    bash -n "$REPOSITORY_ROOT"/envs/{build,validate,activate,lib}.sh
    [[ -x "$BUILD_SCRIPT" ]] || fail 'environment build script is not executable'
    grep -Fq '"$MAMBA_BIN" create' "$BUILD_SCRIPT" ||
        fail 'build script does not create environments with Mamba'
    grep -Fq '"$MAMBA_BIN" install' "$BUILD_SCRIPT" ||
        fail 'build script cannot repair environments with Mamba'
    ! grep -Eq '(^|[[:space:]])conda[[:space:]]+(create|install)' "$BUILD_SCRIPT" ||
        fail 'forbidden conda create/install command is present'
    grep -Fq '"$CONDA_PACK_BIN"' "$BUILD_SCRIPT" ||
        fail 'validated environments are not packed with conda-pack'

    for environment in "${environments[@]}"; do
        [[ -s "$REPOSITORY_ROOT/envs/$environment.yml" ]] ||
            fail "missing pinned specification: $environment.yml"
        grep -Eq '^  - [A-Za-z0-9_.-]+=[^=[:space:]]+' \
            "$REPOSITORY_ROOT/envs/$environment.yml" ||
            fail "unpinned environment specification: $environment.yml"
    done
    printf 'PASS: Conda environment build interface unit tests\n'
}

main "$@"
