#!/usr/bin/env bash
# Validate and publish a ClinicalSuite release with portable Conda runtimes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly ENV_DIR="$SCRIPT_DIR/envs"
readonly RELEASE_ROOT="$SCRIPT_DIR/.release"
# shellcheck source=envs/lib.sh
source "$ENV_DIR/lib.sh"

die() { printf 'ERROR: %s\n' "$1" >&2; return 1; }

print_usage() {
    cat <<'EOF'
Usage: ./release.sh [OPTIONS] [TAG]

Validate the repository and Conda environments, generate release metadata,
create an annotated tag, push it, and publish the GitHub Release. TAG defaults
to v<VERSION>.

Options:
  --dry-run       Run gates and generate metadata without publishing.
  --list-assets   Print the release-asset allowlist and exit.
  -h, --help      Show this help.

Installed prefixes are never committed. Validated conda-pack archives are
portable release assets.
EOF
}

list_asset_sources() {
    local environment
    printf '%s\n' Architecture.md CHANGELOG.md MANIFEST.json RELEASE.md \
        envs/archive_checksums.sha256 envs/environment_validation_report.txt \
        envs/build.sh envs/activate.sh envs/validate.sh envs/lib.sh envs/README.md
    for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
        printf 'envs/%s.yml\nenvs/%s.lock\nenvs/%s.tar.gz\n' \
            "$environment" "$environment" "$environment"
    done
}

require_commands() {
    local command_name
    for command_name in git gh jq sha256sum; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "required release command is unavailable: $command_name"
    done
    [[ -x "${MAMBA_BIN:-}" ]] || die 'MAMBA_BIN must identify Mamba'
    [[ -x "${CONDA_PACK_BIN:-}" ]] || die 'CONDA_PACK_BIN must identify conda-pack'
}

verify_clean_repository() {
    [[ -z "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=all)" ]] ||
        die 'repository must be clean before a release'
    [[ -z "$(git -C "$SCRIPT_DIR" ls-files -- 'envs/*.tar.gz')" ]] ||
        die 'portable environment archives must not be committed to Git'
}

verify_runtime_assets() {
    local environment
    for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
        [[ -s "$ENV_DIR/$environment.yml" ]] || die "missing $environment.yml"
        [[ -s "$ENV_DIR/$environment.lock" ]] || die "missing $environment.lock"
        [[ -s "$ENV_DIR/$environment.tar.gz" ]] || die "missing $environment.tar.gz"
    done
    (cd -- "$ENV_DIR" && sha256sum --check archive_checksums.sha256) ||
        die 'portable environment archive checksum verification failed'
    grep -Fqx 'overall: PASS' "$ENV_DIR/environment_validation_report.txt" ||
        die 'environment validation report is not successful'
}

run_all_tests() {
    local test_script
    while IFS= read -r test_script; do
        printf 'TEST: %s\n' "${test_script#"$SCRIPT_DIR/"}"
        "$test_script"
    done < <(find "$SCRIPT_DIR/tests/unit" "$SCRIPT_DIR/tests/integration" \
        "$SCRIPT_DIR/tests/smoke" -maxdepth 1 -type f -name 'test_*.sh' -print | sort)
}

generate_metadata() {
    local tag="$1" output_dir="$2" commit="$3" environment
    local files_json archives_json

    files_json="$({
        while IFS= read -r path; do
            [[ "$path" == MANIFEST.json || "$path" == RELEASE.md || "$path" == *.tar.gz ]] && continue
            jq -cn --arg path "$path" \
                --arg sha256 "$(sha256sum "$SCRIPT_DIR/$path" | awk '{print $1}')" \
                '{path:$path,sha256:$sha256}'
        done < <(list_asset_sources)
    } | jq -s '.')"
    archives_json="$({
        for environment in "${CLINICAL_ENVIRONMENTS[@]}"; do
            jq -cn --arg name "$environment.tar.gz" \
                --arg sha256 "$(sha256sum "$ENV_DIR/$environment.tar.gz" | awk '{print $1}')" \
                '{name:$name,sha256:$sha256}'
        done
    } | jq -s '.')"
    jq -n --arg project ClinicalSuite --arg version "${tag#v}" --arg tag "$tag" \
        --arg commit "$commit" --arg build './envs/build.sh' \
        --argjson files "$files_json" --argjson archives "$archives_json" \
        '{schema_version:"2.0",project:$project,version:$version,tag:$tag,
          git:{commit:$commit},runtime:{type:"conda",installer:"mamba",
          build_command:$build,validation:"PASS"},files:$files,
          portable_environment_archives:$archives}' >"$output_dir/MANIFEST.json"
    {
        printf '# ClinicalSuite %s\n\n' "${tag#v}"
        printf 'Commit: `%s`\n\n' "$commit"
        printf 'This release uses pinned Mamba-built Conda environments. '
        printf 'Every archive was created by conda-pack only after validation.\n\n'
        printf 'See `MANIFEST.json`, `envs/archive_checksums.sha256`, and '
        printf '`envs/environment_validation_report.txt` for traceability.\n'
    } >"$output_dir/RELEASE.md"
}

publish_release() {
    local tag="$1" output_dir="$2" commit="$3" path
    local -a assets=()
    while IFS= read -r path; do
        case "$path" in
            MANIFEST.json) assets+=("$output_dir/MANIFEST.json") ;;
            RELEASE.md) assets+=("$output_dir/RELEASE.md") ;;
            *) assets+=("$SCRIPT_DIR/$path") ;;
        esac
    done < <(list_asset_sources)
    git -C "$SCRIPT_DIR" tag -a "$tag" "$commit" -m "ClinicalSuite ${tag#v}"
    git -C "$SCRIPT_DIR" push origin "refs/tags/$tag"
    gh release create "$tag" "${assets[@]}" --verify-tag \
        --title "ClinicalSuite ${tag#v}" --notes-file "$output_dir/RELEASE.md"
}

main() {
    local dry_run=false tag='' version commit output_dir argument
    while (( $# > 0 )); do
        argument="$1"; shift
        case "$argument" in
            -h|--help) print_usage; return 0 ;;
            --dry-run) dry_run=true ;;
            --list-assets) list_asset_sources; return 0 ;;
            -*) die "unknown option: $argument" ;;
            *) [[ -z "$tag" ]] || die 'only one tag may be supplied'; tag="$argument" ;;
        esac
    done
    version="$(<"$SCRIPT_DIR/VERSION")"
    [[ -n "$tag" ]] || tag="v$version"
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] ||
        die "invalid release tag: $tag"
    require_commands
    verify_clean_repository
    MAMBA_BIN="$MAMBA_BIN" "$ENV_DIR/validate.sh"
    verify_runtime_assets
    run_all_tests
    verify_clean_repository
    commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
    output_dir="$RELEASE_ROOT/$tag"
    rm -rf -- "$output_dir"; mkdir -p -- "$output_dir"
    generate_metadata "$tag" "$output_dir" "$commit"
    [[ "$dry_run" == true ]] || publish_release "$tag" "$output_dir" "$commit"
    printf 'PASS: release gates completed for %s\n' "$tag"
}

main "$@"
