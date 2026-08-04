#!/usr/bin/env bash
# Execute one command in a ClinicalSuite environment without changing the caller.

set -Eeuo pipefail

usage() {
    printf 'Usage: %s ENVIRONMENT_PREFIX -- COMMAND [ARG ...]\n' "${0##*/}"
}

(( $# >= 3 )) || { usage >&2; exit 64; }
prefix="$1"
shift
[[ "$1" == -- ]] || { usage >&2; exit 64; }
shift
[[ -d "$prefix" && -x "$prefix/bin" ]] || {
    printf 'ERROR: invalid Conda environment prefix: %s\n' "$prefix" >&2
    exit 69
}

export CONDA_PREFIX="$prefix"
export CONDA_DEFAULT_ENV="${prefix##*/}"
export CONDA_SHLVL=1
export PATH="$prefix/bin:/usr/bin:/bin"
unset JAVA_HOME PYTHONHOME PYTHONPATH
exec "$@"
