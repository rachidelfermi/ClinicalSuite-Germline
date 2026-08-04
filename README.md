# ClinicalSuite Germline V2

ClinicalSuite is a reproducible, clinically oriented Bash framework for
paired-end human germline WGS/WES. It currently executes preflight, quality
control, alignment, duplicate marking, and BQSR (Modules 5–7). Later discovery,
annotation, interpretation, and reporting modules remain staged work.

> Clinical status: this software is not a validated clinical assay or medical
> device. Each laboratory must perform end-to-end, assay-specific validation in
> its production environment before patient reporting.

## Runtime migration

ClinicalSuite uses isolated Conda environments because the production HPC does
not permit Apptainer user namespaces or setuid execution. This migration changes
only runtime packaging. Scientific commands, module interfaces, ordering,
configuration, checkpoints, provenance, and output contracts are unchanged.

- Mamba is the only permitted installer (`mamba create` / `mamba install`).
- Users never activate environments; launchers select them automatically.
- Every direct package is version-pinned.
- Every validated prefix has an explicit lock and resolved YAML.
- `conda-pack` archives are produced only after validation succeeds.
- References, models, caches, plugins, and databases remain external.

## Project status

| Module | Status |
|---|---|
| 1 Repository skeleton | Complete |
| 2 Configuration system | Complete |
| 3 Common Bash library | Complete |
| 4 Conda runtime system | Migrated; validation evidence in `envs/` |
| 5 Stage-aware preflight | Complete; migrated to Conda checks |
| 6 Quality control | Complete; Conda revalidation included |
| 7 Alignment and BAM processing | Independently rewritten; full-reference validation is RAM constrained on the development host |
| 8–16 downstream scientific modules | Pending |

See [implementation status](docs/implementation-status.md) and the
[architecture](Architecture.md) for the authoritative boundaries.

## Supported scope

- Human nuclear germline SNVs and small indels
- Paired-end short-read WGS and hybrid-capture WES
- Illumina and validated GeneMind Phred+33 FASTQ
- One sample per analysis
- Broad `GRCh38_full_analysis_set_plus_decoy_hla.fa` exclusively

Somatic, mosaic, long-read, RNA, CNV, structural-variant, repeat-expansion,
mitochondrial, pharmacogenomic, and HLA-typing analyses are out of scope.

## Requirements

- Linux x86-64
- Bash 4.4 or newer
- Mamba
- conda-pack
- ShellCheck for development validation
- Git and standard POSIX utilities

The locked production reference and BWA-MEM2 indexes are external inputs. No
reference genome or annotation database is downloaded during runtime setup.

## Install the runtime

Build, verify, freeze, and pack all environments:

```bash
MAMBA_BIN=/path/to/mamba \
CONDA_PACK_BIN=/path/to/conda-pack \
./envs/build.sh
```

The environment set is deliberately split where upstream constraints conflict:

| Environment | Primary software |
|---|---|
| `qc` | FastQC 0.12.1, fastp 1.3.6, MultiQC 1.35 |
| `alignment` | BWA-MEM2 2.3, Samtools 1.24, Picard 3.4.0, mosdepth 0.3.14, GATK 4.6.2.0 |
| `variant` | GATK 4.6.2.0, bcftools/HTSlib 1.24, Samtools 1.24 |
| `deepvariant` | DeepVariant 1.10.0, CPU TensorFlow 2.11.1 |
| `octopus` | Octopus 0.7.4 |
| `annotation` | Ensembl VEP 116.0 runtime only |
| `report` | Python 3.12.12 and pinned reporting libraries |

DeepVariant, GATK, and Octopus cannot safely share one prefix because their
Java and HTSlib constraints differ. The extra isolation is a packaging detail;
the variant-calling module interfaces do not change.

For each environment, setup produces:

- `envs/NAME.lock` — `mamba list --explicit` reconstruction lock;
- `envs/NAME.yml` — resolved, human-readable environment export;
- `envs/NAME.tar.gz` — relocatable deployment archive;
- `envs/archive_checksums.sha256` — archive integrity manifest; and
- `envs/environment_validation_report.txt` — activation/tool validation.

Prefixes and archives are local deployment artifacts and are not committed to
Git. Locks, YAML specifications, checksums, and reports are traceability files.

### Deploy a packed environment

```bash
mkdir -p /opt/clinicalsuite/envs/alignment
tar -xzf alignment.tar.gz -C /opt/clinicalsuite/envs/alignment
/opt/clinicalsuite/envs/alignment/bin/conda-unpack
```

Install all archives beneath the configured `ENV_DIR` using their exact names.

## Configuration

Copy the examples and edit site-specific paths:

```bash
cp config/clinical.conf.example config/clinical.conf
cp config/samples.tsv.example config/samples.tsv
```

Important runtime keys:

```ini
ENV_DIR=/opt/clinicalsuite/envs
MAMBA_BIN=/opt/conda/envs/mamba/bin/mamba
REFERENCE_DIR=/data/references/GRCh38
REFERENCE_BUILD=GRCh38
```

The pure-Bash parser rejects unknown/duplicate keys, empty required values,
malformed types, invalid paths, invalid assay/platform names, missing FASTQs,
duplicate sample IDs, and invalid read-group metadata. It reports all errors
together. Exact resolved inputs are copied under `RUN_ID/resolved_config/`.

See [configuration documentation](config/README.md).

## Run

Preflight only:

```bash
./run.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv \
  --preflight-only
```

Execute all currently implemented modules:

```bash
./run.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv
```

The launcher runs:

```text
preflight -> qc environment -> alignment environment
```

It invokes the correct prefix without shell activation and propagates the
module's exit status. Module scripts retain stable logical path arguments; the
common runtime wrapper maps those paths to validated host resources.

## Preflight

Preflight aggregates configuration, manifest, runtime, environment-lock,
executable, reference, database, permission, disk-space, and compatibility
checks. It downloads or rebuilds nothing.

Resource requirements are stage-aware:

- through Module 13, annotation/ACMG resources are informational;
- at Module 14, annotation resources become mandatory;
- at Module 15, ACMG resources become mandatory.

Outputs are `preflight_report.txt` and `preflight.json`. Exit code `69` means a
validation failure; `1` means an unexpected internal failure.

## Reference contract

ClinicalSuite V2 supports exactly:

```text
Broad GRCh38 Full Analysis Set + Decoy + HLA
GRCh38_full_analysis_set_plus_decoy_hla.fa
```

Use only the project-generated production BWA-MEM2 index. The reference must
have its `.fai`, sequence dictionary, BWA-MEM2 index set, checksum inventory,
and compatibility manifest. Other GRCh38 bundles and third-party prebuilt
indexes are not supported. See [references/README.md](references/README.md).

## Implemented workflows

### Module 6 — Quality control

For each pair, the module runs raw FastQC, fastp, processed FastQC, and MultiQC.
It writes validated FASTQs, HTML/ZIP reports, JSON, logs, provenance, checksums,
and a signed completion marker. The approved HG002 fixture contains 50,000
paired reads and is for software testing only.

### Module 7 — Alignment and BAM processing

The independently reviewed workflow is intentionally limited to:

1. BWA-MEM2 alignment with explicit read group;
2. SAM-to-BAM conversion and coordinate sorting;
3. BAM indexing;
4. Picard MarkDuplicates;
5. GATK BaseRecalibrator;
6. GATK ApplyBQSR and final indexing; and
7. Samtools/Picard analysis-ready BAM validation.

Checkpoint signatures include configuration, FASTQs, reference/index identity,
runtime lock, commands, and outputs. See [Module 7 review](validation/alignment-independent-review.md).

## Validation

Static validation:

```bash
find bin config envs references tests validation -type f -name '*.sh' -print0 |
  xargs -0 -n1 bash -n
find bin config envs references tests validation -type f -name '*.sh' -print0 |
  xargs -0 shellcheck
git diff --check
```

Runtime and tests:

```bash
MAMBA_BIN=/path/to/mamba ./envs/validate.sh
bash tests/unit/test_environment_build.sh
bash tests/smoke/test_environment_system.sh --require-archives

for test in tests/unit/test_*.sh tests/integration/test_*.sh tests/smoke/test_*.sh; do
  "$test"
done
```

Real-data smoke tests use `tests/data/fastq/HG002_test_R{1,2}.fastq.gz` and are
software checks, not analytical benchmarking. Full-reference BWA-MEM2 loading
requires production-class RAM and must be completed on the target HPC.

## Repository layout

```text
.
├── bin/          module entry points and common Bash runtime
├── config/       examples, schemas, and pure-Bash parser
├── envs/         Mamba specs, locks, activation, validation, packing
├── references/   external-reference contract and preparation helper
├── databases/    external database contract (no bundled data)
├── docs/         architecture support and operations
├── tests/        unit, integration, smoke, and approved HG002 fixture
└── validation/   reports, fixtures, and expected output
```

Patient data, run outputs, references, databases, installed prefixes, and packed
archives are excluded from source control.

## Exit codes and safety

| Code | Meaning |
|---:|---|
| 0 | Success |
| 64 | Invalid command-line usage |
| 69 | Validation/preflight failure or unavailable required input |
| 1 | Unexpected internal/tool error |

Scripts use strict Bash mode, atomic outputs, signal cleanup, explicit error
propagation, plain-text logs, checksums, provenance, and content-aware resume
markers. ClinicalSuite never infers missing sample metadata and never downloads
external scientific resources during analysis.

## Documentation

- [Architecture](Architecture.md)
- [Operations](docs/operations.md)
- [Installation](docs/installation.md)
- [Deployment](docs/deployment.md)
- [Validation plan](docs/validation-plan.md)
- [Environment runtime](envs/README.md)
- [Configuration](config/README.md)
- [Preflight](docs/preflight.md)
- [Quality control](docs/quality-control.md)
- [Alignment](docs/alignment.md)
- [Scientific decisions](docs/scientific-decisions.md)
- [Implementation status](docs/implementation-status.md)

## License

ClinicalSuite's project license does not replace or relicense third-party tools.
Their upstream licenses and redistribution terms apply independently.
