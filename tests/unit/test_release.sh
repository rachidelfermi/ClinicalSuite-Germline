#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
readonly RELEASE_SCRIPT="$REPOSITORY_ROOT/release.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

main() {
    local assets

    "$RELEASE_SCRIPT" --help >/dev/null
    assets="$("$RELEASE_SCRIPT" --list-assets)"

    grep -Fxq Architecture.md <<<"$assets" || fail 'Architecture.md is absent'
    grep -Fxq CHANGELOG.md <<<"$assets" || fail 'CHANGELOG.md is absent'
    grep -Fxq MANIFEST.json <<<"$assets" || fail 'MANIFEST.json is absent'
    grep -Fxq RELEASE.md <<<"$assets" || fail 'RELEASE.md is absent'
    grep -Fxq envs/archive_checksums.sha256 <<<"$assets" ||
        fail 'archive checksums are absent'
    grep -Fxq envs/environment_validation_report.txt <<<"$assets" ||
        fail 'validation report is absent'
    grep -Fxq envs/build.sh <<<"$assets" || fail 'build.sh is absent'
    grep -Fxq envs/README.md <<<"$assets" || fail 'environment README is absent'
    [[ "$(grep -Ec '^envs/[^/]+\.lock$' <<<"$assets")" -eq 7 ]] ||
        fail 'the seven explicit locks are not allowlisted'
    [[ "$(grep -Ec '^envs/[^/]+\.yml$' <<<"$assets")" -eq 7 ]] ||
        fail 'the seven YAML exports are not allowlisted'
    [[ "$(grep -Ec '^envs/[^/]+\.tar\.gz$' <<<"$assets")" -eq 7 ]] ||
        fail 'the seven portable archives are not allowlisted'
    [[ -z "$(git -C "$REPOSITORY_ROOT" ls-files -- 'envs/*.tar.gz')" ]] ||
        fail 'a portable archive is tracked by Git'

    printf 'PASS: Conda runtime release interface unit tests\n'
}

main "$@"
