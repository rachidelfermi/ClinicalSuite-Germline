# Tests

Tests are grouped by intent:

- `unit/`: isolated function and parser behavior;
- `integration/`: contracts between implemented modules; and
- `smoke/`: minimal executable success and expected-failure paths.

Tests must not require patient data or download external references/databases.
The configuration/common integration test verifies that `bin/common.sh` consumes
Module 2's validated state directly without reparsing either input.
Preflight tests use synthetic non-biological files and either a controlled Mamba
fixture or the approved local environments. They never download resources.

Module 6 has pure-function unit coverage, a one-pair synthetic real-runtime
integration test, and an end-to-end launcher smoke test using the approved
50,000-pair HG002 fixture. These tests validate software behavior only; they are
not analytical or clinical validation.

Module 7 has independently rewritten unit tests, a deterministic synthetic
real-runtime integration test, and an HG002/full-reference smoke test. The
smoke test checks strict BAM validity, BQSR, checkpoints, output checksums, and
reproducibility; it is not a sensitivity or accuracy benchmark.

`release.sh` discovers and executes every `test_*.sh` file in all three groups
after validating and packing the environments. A missing real-validation input is therefore a
release blocker rather than an implicit skip. Its release-interface unit test
also verifies that only locks, YAMLs, validation evidence, checksums, and portable
environment archives can enter the runtime release allowlist.
