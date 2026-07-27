# Incremental validation plan

Each module must complete this sequence before the next module begins:

1. design against `Architecture.md` and the scientific decision record;
2. implementation within the declared module contract;
3. Bash syntax or Python compilation checks;
4. ShellCheck or applicable static analysis;
5. focused unit tests;
6. module smoke tests, including expected failures;
7. output/file-format and provenance validation;
8. documentation and implementation-status update; and
9. a scoped project-state commit containing only that module.

A missing required validation tool is a blocker, not a passing result. Scientific
tools and containers additionally require version, model, reference compatibility,
and representative-data validation; a successful `--version` command alone is
insufficient.

## Repository skeleton

The repository skeleton is tested by:

```bash
bash -n run.sh tests/unit/test_run_interface.sh \
  tests/smoke/test_repository_skeleton.sh
shellcheck run.sh tests/unit/test_run_interface.sh \
  tests/smoke/test_repository_skeleton.sh
bash tests/unit/test_run_interface.sh
bash tests/smoke/test_repository_skeleton.sh
```

The tests confirm required paths, executable state, successful help, rejected
invalid arguments, and the clear missing-input exit used before preflight
exists. Python compilation is not applicable because this module contains no
Python source.

## Container build system

Module 4 validation is performed with:

```bash
bash -n containers/build.sh containers/validate.sh \
  tests/unit/test_container_build.sh tests/smoke/test_container_system.sh
shellcheck containers/build.sh containers/validate.sh \
  tests/unit/test_container_build.sh tests/smoke/test_container_system.sh
bash tests/unit/test_container_build.sh
bash tests/smoke/test_container_system.sh --require-images
./containers/validate.sh
(cd containers && sha256sum --check checksums.sha256)
```

The release gate checks all required executables and versions, expected CLI exit
behavior, report-library imports, SIF hashes, and the absence of embedded caller
models and annotation data. No scientific dataset or workflow is exercised in
Module 4.

## Common Bash library

Module 3 validation is performed with:

```bash
bash -n bin/common.sh tests/unit/test_common.sh \
  tests/integration/test_configuration_common.sh \
  tests/smoke/test_common_library.sh
shellcheck -x -P "$PWD" bin/common.sh tests/unit/test_common.sh \
  tests/integration/test_configuration_common.sh \
  tests/smoke/test_common_library.sh
bash tests/unit/test_common.sh
bash tests/integration/test_configuration_common.sh
bash tests/smoke/test_common_library.sh
```

The gate covers every public function, expected failures, paths containing
spaces, failed atomic producers, retry/status/output capture, SIGTERM cleanup,
checkpoint signatures, the Module 2 state interface, and an actual command in
`report.sif` with networking disabled. It performs no bioinformatics analysis.

## Preflight

Module 5 validation is performed with:

```bash
bash -n bin/preflight.sh run.sh tests/helpers/preflight_fixture.sh \
  tests/unit/test_preflight.sh tests/integration/test_preflight.sh \
  tests/smoke/test_preflight.sh
shellcheck -x -P "$PWD" bin/preflight.sh run.sh \
  tests/helpers/preflight_fixture.sh tests/unit/test_preflight.sh \
  tests/integration/test_preflight.sh tests/smoke/test_preflight.sh
bash tests/unit/test_preflight.sh
bash tests/integration/test_preflight.sh
bash tests/smoke/test_preflight.sh
```

Fixtures cover missing FASTQs, current and future containers, stage-deferred
annotation and ACMG databases, unreadable inputs, invalid permissions, malformed
configuration, incompatible references, aggregated failures, and success. The
smoke test uses real Module 4 SIFs and synthetic WES resources without
performing scientific analysis.
