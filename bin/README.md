# Shared Bash infrastructure

Every future pipeline module sources `bin/common.sh`. The library changes no
caller shell options and performs no work merely by being sourced.

`bin/preflight.sh` is the first executable module. It consumes Module 2 state and
the helpers below, validates the complete runtime, and never starts analysis.

`bin/qc.sh` is Module 6. It is invoked only after successful preflight and
orchestrates the immutable `qc.sif` dependency. It performs raw FastQC,
non-modifying fastp reporting, MultiQC aggregation, policy evaluation,
provenance capture, atomic publication, and checkpoint reuse.

## Public API

- Initialization/logging: `common_init`, `log_info`, `log_warning`, `log_error`,
  `log_success`, `log_debug`
- Errors/preconditions: `die`, `warn`, `require_file`, `require_directory`,
  `require_command`
- Temporary paths: `register_cleanup`, `create_temp_directory`, `cleanup`,
  `setup_cleanup_traps`
- Filesystem/checkpoints: `create_directory`, `safe_copy`, `safe_move`,
  `atomic_write`, `create_complete_marker`, `check_complete_marker`
- Execution: `run_command`, `run_container`
- Structural validation: `check_fastq`, `check_bam`, `check_vcf`, `check_index`,
  `calculate_checksum`, `check_checksum`
- Provenance: `get_tool_version`, `get_container_version`,
  `get_pipeline_version`, `report_environment`
- Progress/timing/configuration: `report_progress`, `start_timer`, `stop_timer`,
  `config_get`, `config_require`

`common_init MODULE [LOG_FILE [QUIET [VERBOSE]]]` establishes the logging
context. Quiet and verbose are `0`/`1`; logs are always plain text while terminal
color is controlled by `CLINICAL_COLOR=auto|always|never` and `NO_COLOR`.

`atomic_write TARGET [MODE] [-- WRITER ARG...]` consumes standard input, or runs
the supplied writer, and renames a temporary sibling only after a complete write.
Command mode is required when producer failure must be distinguished from a clean
end of input. Copy/move helpers refuse existing targets.
Temporary directories use an output-variable argument so registration occurs in
the caller rather than a command-substitution subshell:

```bash
create_temp_directory work_dir "$SCRATCH_DIR" alignment
```

`run_command` supports `--retries N`, `--retry-delay SECONDS`, `--timing`,
`--stdout FILE`, and `--stderr FILE`, followed by `-- COMMAND ARG...`. It records
the final status and elapsed whole seconds in `RUN_COMMAND_STATUS` and
`RUN_COMMAND_ELAPSED_SECONDS`.

`run_container` accepts an image, zero or more
`--bind-ro HOST CONTAINER`/`--bind-rw HOST CONTAINER` triples, then `-- COMMAND`.
It uses validated `APPTAINER_BIN` unless `--apptainer PATH` is explicitly supplied.
The wrapper uses a clean, contained environment and a `none` network namespace.
No reference, database, run, or scratch paths are hard-coded.

Checkpoint signatures are 64-character SHA-256 digests. Future modules must make
the signature cover the resolved command plus input/output checksums. An optional
provenance file may be embedded in the marker. Configuration helpers only access
Module 2's validated `CLINICAL_CONFIG` and allowlist; they never parse configuration.
