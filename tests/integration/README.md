# Integration tests

Integration tests begin after at least two adjacent runtime modules are
implemented and individually validated.

`test_alignment.sh` is intentionally a real-container test. It builds a small
deterministic reference and matching BWA-MEM2/FAI/dictionary/VCF indexes, then
executes alignment, duplicate marking, BQSR, final indexing, strict validation,
and step-checkpoint reuse. It does not mock Apptainer or accept placeholder BAMs.
