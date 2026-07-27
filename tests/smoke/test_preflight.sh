#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR
REPOSITORY_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly REPOSITORY_ROOT
# shellcheck source=tests/helpers/preflight_fixture.sh
source "$REPOSITORY_ROOT/tests/helpers/preflight_fixture.sh"

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

preflight_fixture_create "$TEST_ROOT/fixture" WES
sed -i "s|^CONTAINER_DIR=.*|CONTAINER_DIR=$REPOSITORY_ROOT/containers|" \
    "$TEST_ROOT/fixture/clinical.conf"
sed -i 's|^APPTAINER_BIN=.*|APPTAINER_BIN=/usr/bin/apptainer|' \
    "$TEST_ROOT/fixture/clinical.conf"

"$REPOSITORY_ROOT/bin/preflight.sh" \
    --config "$TEST_ROOT/fixture/clinical.conf" \
    --samples "$TEST_ROOT/fixture/samples.tsv" \
    --output-dir "$TEST_ROOT/fixture/preflight-output" >/dev/null

jq -e '.status == "PASS" and .error_count == 0 and
    .execution_module == 13 and .execution_stage == "VARIANT_FILTERING" and
    .information_count > 0' \
    "$TEST_ROOT/fixture/preflight-output/preflight.json" >/dev/null
grep -Fq 'Capture intervals available' \
    "$TEST_ROOT/fixture/preflight-output/preflight_report.txt"
grep -Fq 'DEEPVARIANT_MODEL_WES' \
    "$TEST_ROOT/fixture/preflight-output/preflight_report.txt"
grep -Fq 'Future resource declared and available; content validation begins at Module 14: VEP_CACHE' \
    "$TEST_ROOT/fixture/preflight-output/preflight_report.txt"

printf 'PASS: preflight real-container smoke test\n'
