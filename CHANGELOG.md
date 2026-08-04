# Changelog

All notable project changes are recorded here. Clinical releases will additionally
require signed validation and change-control records.

## Unreleased

### Added

- Seven isolated Mamba-managed runtime environments, shared automatic
  activation/path mapping, exact executable validation, explicit locks,
  resolved YAML exports, and post-validation conda-pack archives.
- Conda runtime installation, deployment, operations, provenance, validation,
  and environment-system tests.
- Source-only release automation with clean-tree, complete-test-suite, clean
  container-rebuild, reproducible-checksum, manifest, tag, and allowlisted
  GitHub Release gates.
- Automatic SIF structure/metadata checks, embedded definition tests, checksum
  verification, and a generated local container build report.
- Repository skeleton and documentation contracts.
- Non-operational `run.sh` entry point with explicit development-state behavior.
- Unit tests for the launcher exit-status contract.
- Structural smoke test and reproducible validation record for the repository
  skeleton.
- Pinned Apptainer build system and definitions for all seven runtime images.
- Container unit/smoke tests, per-tool validation report, and deployment SIF
  checksums.
- Container provenance review and explicit external model/data boundaries.
- Pure-Bash, allowlisted configuration and fixed-column sample-manifest parser.
- Aggregated configuration validation, immutable per-run resolved snapshots,
  configuration schemas/examples, and configuration unit/smoke tests.
- Shared Bash infrastructure for logging, errors, cleanup traps, atomic files,
  checkpoint signatures, command retries/capture, isolated Apptainer execution,
  structural file checks, provenance, progress, timing, and configuration access.
- Unit coverage for every common-library public function, a real-container smoke
  test, and configuration/common-library integration coverage.
- Aggregated preflight validation with atomic text/JSON reports, locked external
  resource manifests, permissions/free-space checks, reference/database
  compatibility, and read-only container integrity/executable checks.
- `run.sh` preflight-first execution and a safe `--preflight-only` mode.
- Source-safe container validation matrix shared by Module 4 release checks and
  Module 5 preflight.
- Reproducible Broad GRCh38 Full Analysis Set + Decoy + HLA preparation with
  locked official source provenance, Samtools/Picard indexes, ALT metadata, PAR
  derivation, and an explicit BWA-MEM2 high-memory build gate.
- Module 6 paired-end quality-control orchestration with raw FastQC,
  non-modifying fastp reporting, MultiQC aggregation, assay-profile policy
  evaluation, immutable provenance, integrity checks, and resumable checkpoints.
- Module 6 unit, real-container integration, and 50,000-pair HG002 smoke tests.
- Independently rewritten Module 7 alignment/BAM-processing orchestration for
  BWA-MEM2, coordinate sorting/indexing, Picard MarkDuplicates, GATK BQSR, final
  indexing, and strict analysis-ready BAM validation.
- Module 7 corruption-aware step checkpoints, immutable checksums, command/tool
  provenance, QC handoff verification, and deterministic output publication.
- Independent Module 7 unit tests, real-container synthetic integration tests,
  and an HG002 production-reference smoke-test harness.

### Changed

- Replaced the Apptainer runtime with Conda prefixes because production HPC
  policy disables both user namespaces and setuid execution. Scientific
  commands, module interfaces, ordering, outputs, and validation remain
  unchanged.
- Isolated DeepVariant and Octopus from the general variant prefix to satisfy
  incompatible Java/HTSlib constraints; selected the DeepVariant CPU TensorFlow
  build explicitly.
- Migrated preflight, QC, alignment, reference preparation, configuration,
  provenance, tests, documentation, and release metadata to the Conda runtime.
- Adopted recipe-only container distribution: users reproduce the validated
  runtime with `./containers/build.sh`; `.sif` files are never committed or
  uploaded to GitHub Releases.
- Made `versions.lock` the source of downloaded build artifacts and their
  checksums instead of duplicating those values in the builder.
- Documented the approved V2 consensus clarification: conventional normalization,
  no GA4GH VRS implementation, and no machine-learning consensus model.
- Made Module 5 external-resource and container validation conditional on the
  selected execution stage. Annotation inputs are informational through Module
  13, and ACMG inputs are informational through Module 14.
- Extended `run.sh` to execute stage-aware `ALIGNMENT` preflight, Module 6, then
  Module 7, while retaining a hard stop before Module 8.
- Locked Module 7 to the project-generated HPC BWA-MEM2 index for the Broad
  GRCh38 Full Analysis Set + Decoy + HLA reference; no third-party prebuilt
  index is accepted or referenced.

### Fixed

- Corrected missing container mounts, unchecked reference declarations,
  malformed BWA read groups, undeclared GATK indexes, self-referential output
  checksums, unsafe/incomplete checkpoints, and insufficient BAM validation in
  the former Module 7 implementation.
- Replaced mocked Module 7 integration/smoke coverage with tests that exercise
  real Apptainer containers and scientifically valid artifacts.

### Known issues

- Full-reference HG002 Module 7 validation requires a host with enough memory
  to load the production BWA-MEM2 index. The current 16 GB development host was
  terminated while reading the verified `.0123` component after reaching
  12,915,584 KB peak RSS; Module 7 remains unapproved pending the unchanged run
  on the project HPC.
