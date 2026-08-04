# Module 2 configuration-system validation

Module 2 validates configuration inputs only. It performs no scientific analysis
and does not load references, databases, models, or runtime environments.

## Implemented contract

- `clinical.conf` is parsed as non-executable `KEY=VALUE` data against a strict
  allowlist. Missing, empty, unknown, duplicate, malformed, path, enum, and
  integer errors are aggregated.
- `samples.tsv` uses the twelve fields approved in `Architecture.md`. Header,
  row width, identifiers, metadata enums, read groups, paired FASTQs, and assay
  interval requirements are validated without inference.
- Relative paths are resolved from the input file that contains them and exported
  as absolute paths.
- Successful validation can create read-only, non-overwriting
  `RUN_ROOT/RUN_ID/resolved_config/clinical.conf` and `samples.tsv` snapshots.
- Only operational defaults exist here. Scientific settings remain the
  responsibility of the named, versioned assay profile.

## Validation commands

```bash
bash -n config/parser.sh config/validate.sh \
  tests/unit/test_configuration.sh tests/smoke/test_configuration_system.sh
shellcheck -x -P "$PWD" config/parser.sh config/validate.sh \
  tests/unit/test_configuration.sh tests/smoke/test_configuration_system.sh
bash tests/unit/test_configuration.sh
bash tests/smoke/test_configuration_system.sh
bash tests/unit/test_run_interface.sh
bash tests/unit/test_environment_build.sh
bash tests/smoke/test_repository_skeleton.sh
bash tests/smoke/test_environment_system.sh
git diff --check
```

ShellCheck 0.8.0 was unpacked into a temporary directory for validation because
the host did not have ShellCheck installed. It was not added as a runtime or
repository dependency.

## Result

Validated on 2026-07-22. Bash syntax, ShellCheck, configuration unit tests,
configuration smoke tests, existing launcher/runtime unit tests, existing
repository/environment smoke tests, and `git diff --check` all passed. The working
tree was intentionally left uncommitted.
