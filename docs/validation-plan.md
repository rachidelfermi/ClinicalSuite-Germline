# Incremental validation plan

Validation proves software execution, interfaces, provenance, checkpointing,
and reproducibility. It is not analytical validation or clinical performance
qualification.

## Universal gates

Every implemented shell module must pass:

```bash
find bin config envs references tests validation -type f -name '*.sh' -print0 |
  xargs -0 -n1 bash -n
find bin config envs references tests validation -type f -name '*.sh' -print0 |
  xargs -0 shellcheck
git diff --check
```

Unit, integration, and smoke tests run after static checks. Integration/smoke
tests use actual Conda executables unless the test explicitly targets an error
path with a controlled mock.

## Conda runtime gates

```bash
MAMBA_BIN=/path/to/mamba ./envs/validate.sh
bash tests/unit/test_environment_build.sh
bash tests/smoke/test_environment_system.sh --require-archives
(cd envs && sha256sum --check archive_checksums.sha256)
```

For every environment, validation checks:

- prefix activation through `envs/activate.sh`;
- `mamba list` dependency integrity;
- required executable availability;
- exact reported tool versions;
- reporting-library imports where applicable;
- explicit package lock generation;
- resolved YAML generation; and
- archive creation/checksum only after the complete validation matrix passes.

The DeepVariant runtime must resolve the CPU TensorFlow build and contain no CUDA
runtime packages. References, models, caches, plugins, and databases must be
absent from every prefix/archive.

## Configuration and common library

Configuration tests cover unknown/duplicate/missing keys, malformed values,
invalid paths, sample columns and metadata, FASTQ pairing, aggregate errors, and
immutable resolved configuration. Common-library tests cover logs, errors,
cleanup, atomic operations, checksums, commands, environment execution/path
mapping, provenance, timers, progress, and safe configuration access.

## Preflight

Preflight tests cover missing FASTQs, environments, locks, references,
databases, permissions, malformed configuration, assembly incompatibility,
stage deferral, successful execution, text/JSON report validity, and exit codes.
It verifies runtime state but never installs, repairs, or downloads anything.

## Quality control

Module 6 uses a synthetic pair for integration and the approved 50,000-pair GIAB
HG002 fixture for smoke validation. FastQC HTML/ZIP, fastp FASTQ/JSON/HTML,
MultiQC, logs, checksums, provenance, completion markers, checkpoint reuse, and
input-change invalidation are checked through the `qc` environment.

## Alignment and BAM processing

Module 7 unit tests independently assert command order and scientific contract.
Real integration runs BWA-MEM2, Samtools, Picard, and GATK from the `alignment`
environment against a synthetic reference. It checks coordinate sorting,
indexes, duplicate metrics, BQSR, analysis-ready BAM integrity, read groups,
logs, provenance, step checkpoints, reuse, and invalidation.

The production-reference smoke test uses the approved HG002 fixture and the
locked Broad GRCh38 Full Analysis Set + Decoy + HLA with the project-generated
BWA-MEM2 indexes. Loading that index requires a production-class HPC memory
allocation; a memory-constrained development-host failure is recorded, never
misreported as module success.

## Runtime equivalence

Migration equivalence is evaluated at the scientific interface rather than by
requiring byte-identical archives or reports that contain timestamps/paths.
Checks compare record/read counts, validated output structures, sorting/read
groups, QC metrics, checkpoints, and normalized scientific content. Any
scientific difference is fatal; expected provenance/runtime-path differences
are documented.

## Future modules

Modules 8–16 must add their own unit, real-runtime integration, HG002 smoke,
checkpoint, provenance, and reproducibility gates. Annotation resources do not
block through Module 13; annotation becomes mandatory at Module 14 and ACMG
resources at Module 15.
