# Tests

Tests are grouped by intent:

- `unit/`: isolated function and parser behavior;
- `integration/`: contracts between implemented modules; and
- `smoke/`: minimal executable success and expected-failure paths.

Tests must not require patient data or download external references/databases.
The configuration/common integration test verifies that `bin/common.sh` consumes
Module 2's validated state directly without reparsing either input.
Preflight tests use synthetic non-biological files and either a mock Apptainer
interface or the approved local SIFs. They never download resources.

Module 6 has pure-function unit coverage, a one-pair synthetic real-container
integration test, and an end-to-end launcher smoke test using the approved
50,000-pair HG002 fixture. These tests validate software behavior only; they are
not analytical or clinical validation.
