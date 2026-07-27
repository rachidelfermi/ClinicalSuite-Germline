# Module 5 preflight validation

Module 5 is validation-only. It downloads nothing, rebuilds no container, and
starts no scientific workflow.

## Validation commands

```bash
find . -type f -name '*.sh' -print0 | sort -z | xargs -0 bash -n
shellcheck -x -P "$PWD" bin/preflight.sh run.sh \
  tests/helpers/preflight_fixture.sh tests/unit/test_preflight.sh \
  tests/integration/test_preflight.sh tests/smoke/test_preflight.sh
bash tests/unit/test_preflight.sh
bash tests/integration/test_preflight.sh
bash tests/smoke/test_preflight.sh
bash tests/unit/test_configuration.sh
bash tests/smoke/test_configuration_system.sh
bash tests/unit/test_common.sh
bash tests/integration/test_configuration_common.sh
bash tests/smoke/test_common_library.sh
bash tests/unit/test_run_interface.sh
bash tests/unit/test_container_build.sh
bash tests/smoke/test_repository_skeleton.sh
bash tests/smoke/test_container_system.sh
git diff --check
```

ShellCheck is unpacked temporarily because it is not installed system-wide.
The real-container smoke test validates the Module 13 container set with
networking disabled and a synthetic WES fixture. Future annotation/report
container checks are recorded as informational and deferred.

## Result

Initially validated on 2026-07-23 and stage-aware behavior revalidated on
2026-07-27. Repository-wide Bash syntax, Module 5 ShellCheck,
preflight unit/integration/real-container smoke tests, regression tests, JSON
parsing, and `git diff --check` passed.

Boundary fixtures prove that annotation databases and `annotation.sif` do not
block Module 13, become mandatory at Module 14, and a declared mandatory
`ACMG_RULES` resource changes from informational at Module 14 to fatal at Module
15. The working tree was intentionally left uncommitted.
