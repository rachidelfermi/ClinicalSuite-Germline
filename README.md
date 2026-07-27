# ClinicalSuite V2

ClinicalSuite is a containerized, clinically oriented framework for reproducible
human germline small-variant analysis from paired-end short-read whole-genome
sequencing (WGS) and whole-exome sequencing (WES).

The V2 implementation is being developed as a sequence of independently tested
modules. The repository currently provides the validated configuration,
shared-runtime, Apptainer-container, preflight, and paired-end FASTQ
quality-control modules. Alignment and later analysis modules are not yet
operational.

> [!CAUTION]
> ClinicalSuite V2 is development software. It is not a validated clinical
> assay, diagnostic product, or medical device. It must not be used for patient
> care until the complete workflow has undergone laboratory-specific analytical
> validation, accreditation review, change control, and qualified expert review.

Current version: **2.0.0-dev**

## Table of contents

- [Project status](#project-status)
- [Design goals](#design-goals)
- [Supported scope](#supported-scope)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Preflight validation](#preflight-validation)
- [Container system](#container-system)
- [Quality control](#quality-control)
- [External references and databases](#external-references-and-databases)
- [Testing](#testing)
- [HG002 QC test fixture](#hg002-qc-test-fixture)
- [Repository layout](#repository-layout)
- [Runtime outputs](#runtime-outputs)
- [Exit codes](#exit-codes)
- [Documentation](#documentation)
- [Data safety](#data-safety)
- [Development roadmap](#development-roadmap)

## Project status

| Module | Status | Evidence |
| --- | --- | --- |
| 1. Repository skeleton | Complete | [Validation record](validation/repository-skeleton.md) |
| 2. Configuration system | Complete | [Validation record](validation/configuration-system.md) |
| 3. Common Bash library | Complete | [Validation record](validation/common-bash-library.md) |
| 4. Apptainer container system | Complete | [Container validation report](containers/container_validation_report.txt) |
| 5. Preflight validation | Complete | [Validation record](validation/preflight.md) |
| 6. Quality control | Complete | [Validation record](validation/quality-control.md) |
| 7–16. Scientific and reporting modules | Pending | Not implemented |
| 17. Integration testing | Pending | Module-level integration tests exist; complete workflow pending |
| 18. End-to-end validation | Pending | Not started |

`run.sh` currently executes mandatory preflight followed by Module 6 quality
control. It stops after QC and does not start alignment, variant calling,
annotation, interpretation, or reporting.

The authoritative live status is maintained in
[docs/implementation-status.md](docs/implementation-status.md).

## Design goals

- Fail before analysis when configuration, inputs, software, permissions, or
  external resources are invalid.
- Run scientific software exclusively through pinned Apptainer images.
- Keep the host runtime small: Bash, Apptainer, and standard POSIX utilities.
- Keep reference genomes, annotation databases, caches, plugins, and trained
  models external to both Git and container images.
- Preserve the exact resolved configuration and sample manifest used for a run.
- Produce explicit logs, checksums, checkpoints, provenance, and validation
  artifacts.
- Keep scientific parameters in validated assay profiles rather than hidden in
  scripts.
- Aggregate validation errors so operators can correct all detected problems in
  one pass.

## Supported scope

The approved initial V2 scope is:

- Human nuclear germline single-nucleotide variants and small indels
- Paired-end short-read WGS
- Hybrid-capture paired-end short-read WES
- Illumina sequencing
- GeneMind sequencing after separate assay-specific validation
- GRCh38

The following are outside the initial V2 scope:

- Somatic or tumor/normal analysis
- Copy-number variants and structural variants
- Repeat expansions
- Mitochondrial variant analysis
- RNA sequencing
- Long-read Oxford Nanopore or PacBio analysis
- Methylation or single-cell analysis
- Other reference assemblies

See [Architecture.md](Architecture.md) for the complete scientific scope,
decision record, and future module contracts.

## Architecture

```text
clinical.conf + samples.tsv
            |
            v
  Configuration validation
            |
            +--> immutable resolved_config/
            |
            v
     Mandatory preflight
       |      |      |
       |      |      +--> references and databases
       |      +---------> containers and checksums
       +----------------> FASTQs, filesystem, permissions
            |
            v
  Scientific modules 6–16
       (under development)
            |
            v
 Integration and end-to-end validation
```

The runtime contract separates four concerns:

1. **Source code** — Bash orchestration, schemas, definitions, and tests stored
   in Git.
2. **Software** — pinned, immutable Apptainer SIF images.
3. **External resources** — versioned references, databases, caches, and models
   mounted read-only.
4. **Run state** — resolved configuration, logs, checkpoints, intermediate
   files, results, and provenance stored below the configured run root.

Docker is never required at runtime. Conda and Mamba environments are not part
of the V2 runtime.

## Requirements

### Runtime

- Linux on `x86_64`
- Bash 4.4 or newer
- Apptainer
- Standard utilities checked by preflight, including `awk`, `date`, `df`,
  `dirname`, `find`, `grep`, `hostname`, `mktemp`, `mv`, `readlink`, `sed`,
  `sha256sum`, `stat`, `uname`, and `wc`

The current container set was built and validated with:

```text
Apptainer 1.5.2
Architecture linux/amd64
```

### Container builds

Container builds additionally require:

- Network access to the pinned upstream OCI and source locations
- `curl`
- Apptainer fakeroot support or equivalent build privileges
- Sufficient storage for seven SIF images and the reusable build cache

No reference genome or annotation database is downloaded by the container
builder.

## Installation

Clone the repository:

```bash
git clone git@github.com:rachidelfermi/ClinicalSuite.git
cd ClinicalSuite
```

Confirm the host tools:

```bash
bash --version
apptainer --version
sha256sum --version
```

Build and validate all pinned containers:

```bash
./containers/build.sh
```

The build system reuses verified downloads from `containers/.build/`. Generated
SIF files remain local deployment artifacts and are intentionally excluded from
Git.

Confirm the launcher interface:

```bash
./run.sh --help
```

ClinicalSuite does not currently install reference data or databases. Prepare
those resources separately according to the documented manifest contracts
before running preflight.

## Configuration

ClinicalSuite accepts two non-executable, allowlisted input files:

- `clinical.conf` — operational paths, resource limits, and the approved assay
  profile.
- `samples.tsv` — fixed-schema sample and paired FASTQ metadata.

Create local working copies:

```bash
cp config/clinical.conf.example config/clinical.conf
cp config/samples.tsv.example config/samples.tsv
```

Edit every site-specific path and all sample metadata:

```bash
${EDITOR:-vi} config/clinical.conf config/samples.tsv
```

Validate without creating run files:

```bash
./config/validate.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv \
  --check-only
```

Validate and create the immutable resolved configuration:

```bash
./config/validate.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv
```

On success, ClinicalSuite writes:

```text
RUN_ROOT/RUN_ID/resolved_config/
├── clinical.conf
└── samples.tsv
```

These read-only files contain normalized absolute paths and represent the exact
configuration supplied to downstream modules. An existing resolved
configuration is never silently overwritten.

The parser:

- rejects unknown and duplicate keys;
- rejects missing or empty mandatory values;
- validates integers, enums, identifiers, permissions, and paths;
- resolves configuration paths relative to `clinical.conf`;
- resolves FASTQ and interval paths relative to `samples.tsv`;
- validates the exact sample-manifest schema;
- rejects duplicate sample IDs and read-group IDs;
- requires paired, readable FASTQ files;
- requires explicit assay, platform, read-group, and interval metadata; and
- never sources or evaluates configuration as shell code.

All supported keys, defaults, and validation rules are documented in
[config/README.md](config/README.md).

## Preflight validation

Preflight is the mandatory first runtime module:

```bash
./run.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv \
  --preflight-only
```

An optional report-directory override is available:

```bash
./run.sh \
  --config config/clinical.conf \
  --samples config/samples.tsv \
  --preflight-only \
  --preflight-dir /absolute/path/to/preflight
```

Preflight performs aggregated checks for:

- Configuration and sample-manifest validity
- Bash, Apptainer, and required host utilities
- FASTQ readability, structure, pairing, and mate identifiers
- Output and scratch permissions
- Configurable free-space requirements
- Presence and SHA-256 integrity of every SIF required through the selected stage
- Executable availability and locked tool-version compatibility
- GRCh38 FASTA, indexes, dictionaries, and interval files
- Stage-required references, databases, caches, plugins, and trained models
- Assembly and reference/database compatibility
- Required checksums and external-resource manifest consistency

It does not start scientific analysis and does not download missing resources.
`bin/preflight.sh --stage STAGE` selects the validation boundary. The current
default is `VARIANT_FILTERING` (Module 13), so annotation and ACMG resources are
reported informationally and do not block execution.

Successful or failed validation produces atomic reports:

```text
RUN_ROOT/RUN_ID/preflight/
├── preflight.json
├── preflight.log
└── preflight_report.txt
```

See [docs/preflight.md](docs/preflight.md) for mandatory resource identifiers
and report semantics.

## Container system

ClinicalSuite uses seven runtime images:

| Image | Pinned runtime |
| --- | --- |
| `qc.sif` | FastQC 0.12.1, fastp 1.3.6, MultiQC 1.35 |
| `alignment.sif` | BWA-MEM2 2.3 asset, Samtools/HTSlib 1.24, Picard 3.4.0, mosdepth 0.3.14 |
| `gatk.sif` | GATK 4.6.2.0, bcftools/HTSlib 1.24 |
| `octopus.sif` | Octopus 0.7.4 |
| `deepvariant.sif` | Official DeepVariant 1.10.0 CPU runtime |
| `annotation.sif` | Ensembl VEP 116.0 runtime |
| `report.sif` | CPython 3.12.12 with pinned reporting libraries |

Build selected images:

```bash
./containers/build.sh --no-validate qc alignment
```

Validate an existing complete image set without rebuilding:

```bash
./containers/build.sh --validate-only
```

Verify deployment checksums:

```bash
(cd containers && sha256sum --check checksums.sha256)
```

Important container metadata:

- [containers/versions.lock](containers/versions.lock) records component
  versions, immutable sources, digests, and licenses.
- [containers/checksums.sha256](containers/checksums.sha256) records the current
  local deployment-image hashes.
- [containers/container_validation_report.txt](containers/container_validation_report.txt)
  records executable and version checks.
- [docs/container-provenance.md](docs/container-provenance.md) records the
  provenance review.

`qc.sif` is a validated, stable Module 6 dependency. Quality-control
orchestration must not change its tool versions or contents unless a critical
software defect is discovered.

## Quality control

After preflight succeeds, `run.sh` executes Module 6 through `bin/qc.sh`.
For every paired-end sample, the module runs raw-read FastQC, generates a
fastp report in explicitly non-modifying pass-through mode, and aggregates the
reports with MultiQC. Original FASTQs remain unchanged and are exposed to the
next module through checksummed symbolic links.

QC thresholds and `BLOCK`/`REVIEW` policies come from the validated assay
profile, not the orchestration script. A matching `.complete` signature makes
reruns resumable; changed configuration, profile, container, or FASTQ content
is rejected rather than silently mixed with an existing result.

See [docs/quality-control.md](docs/quality-control.md) for the output contract
and [validation/quality-control.md](validation/quality-control.md) for the
HG002 software-validation result.

## External references and databases

ClinicalSuite containers contain no reference genomes, annotation databases,
VEP caches, plugins, truth sets, or trained calling models.

Preflight expects versioned external manifests:

```text
REFERENCE_DIR/
└── reference_manifest.tsv

DATABASE_DIR/
└── database_manifest.tsv
```

Requirements are stage-aware. Through Module 13, the configured GRCh38 FASTA
and indexes, reportable/capture intervals, known-indel resources, caller
containers, and matching DeepVariant model are mandatory. ClinVar, dbSNP,
gnomAD, VEP cache, LOFTEE, SpliceAI, and dbNSFP become mandatory at Module 14.
ACMG resources are deferred until Module 15; REVEL is optional at that stage.

Resource rows carry an assembly declaration and checksum. Database rows also
record the compatible FASTA SHA-256 so preflight can reject mixed reference
builds.

ClinicalSuite never infers, downloads, replaces, or updates these resources
during a run. Consult:

- [references/README.md](references/README.md)
- [Reference preparation status](validation/reference-preparation.md)
- [databases/README.md](databases/README.md)
- [config/schemas/reference_manifest.schema.tsv](config/schemas/reference_manifest.schema.tsv)
- [config/schemas/database_manifest.schema.tsv](config/schemas/database_manifest.schema.tsv)

## Testing

Run syntax checks:

```bash
find . -type f -name '*.sh' -not -path './containers/.build/*' \
  -exec bash -n {} +
```

Run unit tests:

```bash
for test in tests/unit/test_*.sh; do
  bash "$test"
done
```

Run integration tests:

```bash
for test in tests/integration/test_*.sh; do
  bash "$test"
done
```

Run smoke tests:

```bash
for test in tests/smoke/test_*.sh; do
  bash "$test"
done
```

Run ShellCheck when it is installed:

```bash
find bin config containers tests validation -type f -name '*.sh' -print0 |
  xargs -0 shellcheck
```

The container smoke test requires the complete local SIF deployment set.
Configuration and preflight tests use isolated temporary fixtures and do not
download references or databases.

## HG002 QC test fixture

The repository includes a small real paired-end Genome in a Bottle HG002
fixture:

```text
tests/data/fastq/HG002_test_R1.fastq.gz
tests/data/fastq/HG002_test_R2.fastq.gz
```

It contains exactly 50,000 synchronized read pairs from the official NIST
Illumina 2 × 250 bp PCR-free WGS data. It exists only for unit, integration, and
smoke testing. It must not be used for analytical validation, benchmarking, or
clinical interpretation.

Verify it with:

```bash
(cd tests/data/fastq && sha256sum --check SHA256SUMS)
```

Full provenance, accession identifiers, source URLs, publication, checksums,
and the reproducible bounded-stream generator are documented in
[tests/data/fastq/README.md](tests/data/fastq/README.md).

## Repository layout

```text
ClinicalSuite/
├── Architecture.md              # Approved V2 architecture and decisions
├── VERSION                      # Development version
├── run.sh                       # Preflight-first command-line entry point
├── bin/
│   ├── common.sh                # Shared Bash runtime library
│   └── preflight.sh             # Aggregated environment validation
├── config/
│   ├── clinical.conf.example    # Configuration template
│   ├── samples.tsv.example      # Sample-manifest template
│   ├── parser.sh                # Pure-Bash parser and validator
│   ├── validate.sh              # Configuration validation CLI
│   └── schemas/                 # Configuration and manifest contracts
├── containers/
│   ├── build.sh                 # Reproducible image builder
│   ├── validate.sh              # Runtime image validation
│   ├── versions.lock            # Pinned software provenance
│   ├── checksums.sha256         # Deployment SIF checksums
│   ├── definitions/             # Apptainer definition files
│   └── requirements/            # Locked runtime requirements
├── references/                  # External-reference contract
├── databases/                   # External-database contract
├── docs/                        # Architecture and operational documentation
├── tests/
│   ├── data/                    # Approved non-patient test fixture
│   ├── helpers/                 # Test fixture helpers
│   ├── unit/
│   ├── integration/
│   └── smoke/
└── validation/                  # Module validation records and fixtures
```

## Runtime outputs

The configured run root will contain immutable inputs, validation reports, and
future module outputs:

```text
RUN_ROOT/
└── RUN_ID/
    ├── resolved_config/
    │   ├── clinical.conf
    │   └── samples.tsv
    └── preflight/
        ├── preflight.json
        ├── preflight.log
        └── preflight_report.txt
```

Later module directories will be added only when those modules are implemented
and validated.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Requested validation completed successfully |
| `1` | Unexpected internal or report-generation failure |
| `64` | Command-line usage error |
| `69` | Configuration, preflight, or unavailable-analysis validation failure |

No downstream module may run after a preflight exit code other than `0`.

## Documentation

- [Architecture](Architecture.md)
- [Implementation status](docs/implementation-status.md)
- [Scientific decision record](docs/scientific-decisions.md)
- [Validation plan](docs/validation-plan.md)
- [Operations](docs/operations.md)
- [Configuration system](config/README.md)
- [Common Bash library](bin/README.md)
- [Container system](containers/README.md)
- [Container provenance](docs/container-provenance.md)
- [Preflight validation](docs/preflight.md)
- [Reference contract](references/README.md)
- [Database contract](databases/README.md)
- [Test strategy](tests/README.md)
- [Changelog](CHANGELOG.md)

## Data safety

- Never commit patient identifiers, sample manifests, local configuration,
  FASTQs, BAM/CRAM files, VCFs, reports, credentials, or site paths.
- Treat `.gitignore` as a convenience, not as a data-loss-prevention control.
- Keep input data and external resources in access-controlled storage.
- Mount reference and database resources read-only.
- Preserve logs, resolved configuration, checksums, software versions, and
  provenance according to the laboratory quality-management system.
- Review every generated interpretation and report through an approved clinical
  process.

The bundled HG002 files are the only approved real human sequencing fixture in
the repository.

## Development roadmap

Modules are implemented and validated in this order:

1. Repository skeleton
2. Configuration system
3. Common Bash library
4. Apptainer container system
5. Preflight validation
6. Quality control
7. Alignment and BAM processing
8. Coverage analysis
9. DeepVariant
10. GATK HaplotypeCaller
11. Octopus
12. Consensus engine
13. Variant filtering
14. Annotation
15. ACMG/AMP decision support
16. Reporting
17. Integration tests
18. End-to-end validation

Each module must pass Bash syntax checks, ShellCheck, unit tests, integration or
smoke tests as applicable, and `git diff --check` before the next module begins.
Development stops at any failed release gate.

Third-party software remains subject to its own license. Component sources and
licenses are recorded in [containers/versions.lock](containers/versions.lock).
