# Module 3 common Bash library validation

Module 3 provides shared operational infrastructure only. It performs no
bioinformatics workflow and defines no scientific parameter.

## Contract

- Source-safe under Bash 4.4+ without changing caller shell options.
- Timestamped module logging with optional ANSI terminal color and plain files.
- Informative precondition failures, fatal errors, registered cleanup, and
  `EXIT`/`SIGINT`/`SIGTERM` traps.
- Atomic sibling writes, no-clobber copy/move helpers, and signed completion
  markers with optional embedded provenance.
- Quoted command logging, stdout/stderr capture, timing, retries, and exact exit
  propagation.
- Isolated Conda-prefix execution with explicit logical-to-host path mappings.
- Structural FASTQ/BAM/VCF/index/checksum validation only.
- Tool/environment/pipeline versions, host provenance, progress, and timers.
- Direct access to Module 2's validated allowlist and associative array without
  duplicating configuration parsing.

## Validation commands

```bash
find . -type f -name '*.sh' -print0 | sort -z | xargs -0 bash -n
shellcheck -x -P "$PWD" bin/common.sh tests/unit/test_common.sh \
  tests/integration/test_configuration_common.sh \
  tests/smoke/test_common_library.sh
bash tests/unit/test_common.sh
bash tests/integration/test_configuration_common.sh
bash tests/smoke/test_common_library.sh
bash tests/unit/test_configuration.sh
bash tests/smoke/test_configuration_system.sh
bash tests/unit/test_run_interface.sh
bash tests/unit/test_environment_build.sh
bash tests/smoke/test_repository_skeleton.sh
bash tests/smoke/test_environment_system.sh
git diff --check
```

ShellCheck 0.8.0 is unpacked in a temporary directory because it is not installed
system-wide. The smoke test executes `python --version` inside the approved
the `report` prefix through `run_environment`; no scientific data or workflow is used.

## Result

Validated on 2026-07-22. Repository-wide Bash syntax, Module 3 ShellCheck, all
Module 3 unit/integration/smoke tests, Module 1/2/4 regression tests, and
`git diff --check` passed. The working tree was intentionally left uncommitted.
