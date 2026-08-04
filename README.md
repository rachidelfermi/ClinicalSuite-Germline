# ClinicalSuite Germline V2

ClinicalSuite Germline V2 is an open-source, clinically oriented, reproducible
human germline variant discovery framework for paired-end Illumina-compatible
short-read sequencing.

The project targets:

- Whole Genome Sequencing (WGS)
- Whole Exome Sequencing (WES)
- Illumina
- GeneMind (validated Illumina-compatible workflows)

ClinicalSuite is designed around reproducibility, transparency, modularity and
scientific validation rather than proprietary automation.

Every analytical decision is traceable, reproducible and version controlled.

---

> **Clinical Status**
>
> ClinicalSuite is **not** a validated clinical assay, an in-vitro diagnostic
> device, or a substitute for laboratory accreditation.
>
> Every laboratory must perform complete analytical and clinical validation
> using its own instruments, wet-lab workflow, personnel, and production
> environment before reporting patient results.

---

# Project Philosophy

ClinicalSuite follows several core principles.

- Fully open-source
- Fully reproducible
- Offline capable
- HPC friendly
- Bash-first workflow
- Deterministic execution
- Transparent evidence
- Modular implementation
- Minimal external dependencies

ClinicalSuite intentionally avoids proprietary knowledge bases,
black-box algorithms, machine learning classifiers, and closed
clinical interpretation engines.

Instead, it combines:

- validated scientific software
- peer-reviewed methodologies
- open clinical databases
- deterministic ACMG rules
- complete provenance

into a transparent clinical workflow.

---

# Runtime

ClinicalSuite uses isolated **Conda environments**.

The previous Apptainer runtime was removed because the target production HPC
does not support user namespaces or setuid Apptainer execution.

This change affects only runtime packaging.

The scientific workflow, module interfaces, validation strategy,
outputs, checkpoints and provenance remain unchanged.

Runtime principles:

- Mamba is the only supported installer.
- Users never manually activate environments.
- The launcher automatically selects the correct environment.
- Every package version is pinned.
- Every environment is validated before use.
- Every validated environment is frozen.
- Every environment is distributed as:
  - explicit lock file
  - resolved YAML
  - conda-pack archive
- References, annotation databases, VEP caches, models and plugins remain
  external resources.

---

# Project Status

| Module | Status |
|----------|---------|
| Repository Skeleton | ✅ Complete |
| Configuration System | ✅ Complete |
| Common Bash Library | ✅ Complete |
| Conda Runtime | ✅ Complete |
| Stage-aware Preflight | ✅ Complete |
| Quality Control | ✅ Complete |
| Alignment & BAM Processing | ✅ Complete |
| Coverage Analysis | 🚧 Pending |
| DeepVariant | 🚧 Pending |
| GATK HaplotypeCaller | 🚧 Pending |
| Octopus | 🚧 Pending |
| Consensus Variant Engine | 🚧 Pending |
| Variant Filtering | 🚧 Pending |
| Annotation | 🚧 Pending |
| Clinical ACMG Engine | 🚧 Pending |
| Clinical Reporting | 🚧 Pending |

The architecture is implemented incrementally.

Every module must pass:

- scientific review
- implementation review
- unit tests
- integration tests
- smoke tests
- production validation

before development continues.

---

# Supported Scope

ClinicalSuite V2 currently supports:

- Human nuclear germline SNVs
- Human nuclear germline small indels
- Paired-end Illumina-compatible sequencing
- Whole Genome Sequencing
- Whole Exome Sequencing
- Broad GRCh38 Full Analysis Set + Decoy + HLA
- One sample per analysis

Current release intentionally excludes:

- Somatic analysis
- Structural variants
- CNVs
- Repeat expansions
- Mitochondrial variants
- RNA sequencing
- Long-read sequencing
- Oxford Nanopore
- PacBio
- Pharmacogenomics
- HLA typing

These workflows will be implemented independently in future ClinicalSuite
projects.

---

# Requirements

ClinicalSuite requires:

- Linux x86-64
- Bash ≥ 4.4
- Mamba
- Conda
- conda-pack
- Git
- Standard POSIX utilities

Development validation additionally requires:

- ShellCheck

No reference genome, annotation database, trained model, VEP cache or plugin
is downloaded automatically.

All scientific resources remain external and version controlled.

---

# Runtime Installation

ClinicalSuite environments are built using Mamba.

Build every environment:

```bash
MAMBA_BIN=/path/to/mamba \
CONDA_PACK_BIN=/path/to/conda-pack \
./envs/build.sh
```

The runtime is divided into independent environments.

| Environment | Purpose |
|--------------|---------|
| qc | FastQC, fastp, MultiQC |
| alignment | BWA-MEM2, Samtools, Picard, Mosdepth |
| variant | GATK, bcftools, HTSlib, vt |
| deepvariant | DeepVariant runtime |
| octopus | Octopus runtime |
| annotation | VEP and annotation software |
| report | Python and reporting libraries |

The separation is intentional.

Different tools require incompatible versions of Java, HTSlib or Python.

Independent environments maximize reproducibility while minimizing dependency
conflicts.

After validation every environment produces:

- explicit package lock
- environment.yml
- conda-pack archive
- SHA256 checksum
- validation report

Installed environments are deployment artifacts and are never committed to Git.

Only:

- lock files
- YAML specifications
- validation reports
- checksums

are version controlled.

# Configuration

ClinicalSuite uses three validated configuration layers.

1. **Clinical configuration**

Contains site-specific settings such as:

- reference paths
- database paths
- thread counts
- memory limits
- runtime options
- environment locations

Example:

```bash
cp config/clinical.conf.example config/clinical.conf
```

---

2. **Sample manifest**

Contains one sample per row.

Example:

```bash
cp config/samples.tsv.example config/samples.tsv
```

Each sample defines:

- Sample ID
- Assay (WGS/WES)
- Platform (ILLUMINA / GENEMIND)
- FASTQ R1
- FASTQ R2
- Read Group
- Library
- Platform Unit
- Sequencing Center
- Expected sex chromosome complement
- Capture intervals (WES)
- Reportable intervals

---

3. **Reference & Database manifests**

ClinicalSuite validates every external resource before analysis.

These manifests include:

- filename
- version
- release
- checksum
- compatible reference genome
- compatibility status

No resource is accepted unless it matches the expected manifest.

---

# Runtime Configuration

Important runtime variables include:

```ini
ENV_DIR=/opt/clinicalsuite/envs

MAMBA_BIN=/opt/conda/bin/mamba

REFERENCE_DIR=/data/references/GRCh38

REFERENCE_BUILD=GRCh38
```

The parser performs strict validation.

Rejected automatically:

- unknown keys
- duplicate keys
- missing required values
- malformed values
- missing FASTQs
- duplicate sample IDs
- invalid assay names
- invalid platform names
- invalid read groups
- invalid reference paths

All configuration errors are collected and reported together.

No analysis begins until configuration validation succeeds.

The fully resolved configuration is copied into every run directory
for complete reproducibility.

---

# Running ClinicalSuite

## Preflight only

```bash
./run.sh \
    --config config/clinical.conf \
    --samples config/samples.tsv \
    --preflight-only
```

---

## Execute all implemented modules

```bash
./run.sh \
    --config config/clinical.conf \
    --samples config/samples.tsv
```

---

## Execute a module range

Examples

```bash
./run.sh --from qc
```

```bash
./run.sh --from alignment
```

```bash
./run.sh --from deepvariant
```

```bash
./run.sh --to filtering
```

---

# Runtime Flow

ClinicalSuite automatically selects the correct Conda environment.

Users never manually activate environments.

Current execution order:

```text
Preflight

↓

QC Environment

↓

Alignment Environment

↓

Coverage Environment

↓

Variant Environment

↓

DeepVariant Environment

↓

Octopus Environment

↓

Annotation Environment

↓

Report Environment
```

Every module executes inside its validated runtime.

The launcher automatically:

- activates the environment
- executes the module
- validates completion
- deactivates the environment
- records provenance

---

# Stage-aware Preflight

Preflight validates the complete execution environment before any scientific
analysis begins.

Validation includes:

- configuration
- sample manifest
- runtime environments
- package locks
- software versions
- references
- indexes
- databases
- permissions
- disk space
- checksums
- compatibility

Preflight never:

- downloads references
- downloads databases
- rebuilds environments
- modifies resources

It only validates.

---

# Stage-aware Resource Validation

ClinicalSuite validates resources only when they become necessary.

Through Module 13

Annotation resources are informational.

Modules 14–15

Annotation databases become mandatory.

Module 15

Clinical ACMG resources become mandatory.

This minimizes unnecessary failures during early pipeline development.

---

# Reference Contract

ClinicalSuite supports exactly one production reference.

```text
Broad GRCh38 Full Analysis Set + Decoy + HLA

GRCh38_full_analysis_set_plus_decoy_hla.fa
```

ClinicalSuite uses only:

- project-generated BWA-MEM2 index
- matching FASTA
- matching FAI
- matching sequence dictionary
- matching checksum inventory

The following are NOT supported:

- GRCh37
- UCSC hg38
- Ensembl Primary Assembly
- T2T-CHM13
- third-party prebuilt BWA indexes

Any mismatch between:

- FASTA
- dictionary
- index
- checksum

causes a preflight failure.

---

# Implemented Scientific Workflow

## Module 6 — Quality Control

Workflow

```text
FASTQ

↓

FastQC

↓

fastp

↓

FastQC

↓

MultiQC
```

Outputs

- validated FASTQ
- FastQC HTML
- FastQC ZIP
- fastp HTML
- fastp JSON
- MultiQC HTML
- provenance
- checksums
- signed checkpoint

The HG002 50,000-read dataset is included only for software validation.

It is NOT intended for analytical benchmarking.

---

## Module 7 — Alignment & BAM Processing

Workflow

```text
FASTQ

↓

BWA-MEM2

↓

Samtools

↓

Coordinate Sorting

↓

Picard MarkDuplicates

↓

GATK BaseRecalibrator

↓

GATK ApplyBQSR

↓

Analysis-ready BAM
```

Validation includes:

- BAM integrity
- BAM index
- duplicate metrics
- BQSR completion
- Samtools quickcheck
- Samtools flagstat
- Samtools stats
- Picard ValidateSamFile

Every completed module generates:

- provenance
- checksums
- runtime report
- signed checkpoint
- validation report

All outputs are written atomically.

# Validation

ClinicalSuite follows a validation-first development strategy.

No module is considered complete until it passes:

- Bash syntax validation
- ShellCheck
- Unit tests
- Integration tests
- Smoke tests
- Real execution
- Scientific review
- Documentation review

---

## Static Validation

```bash
find bin config envs references tests validation \
    -type f -name '*.sh' -print0 |
    xargs -0 -n1 bash -n

find bin config envs references tests validation \
    -type f -name '*.sh' -print0 |
    xargs -0 shellcheck

git diff --check
```

---

## Runtime Validation

```bash
MAMBA_BIN=/path/to/mamba \
./envs/validate.sh
```

Execute all validation suites:

```bash
bash tests/unit/test_environment_build.sh

bash tests/smoke/test_environment_system.sh

for test in \
tests/unit/test_*.sh \
tests/integration/test_*.sh \
tests/smoke/test_*.sh
do
    "$test"
done
```

---

## Production Validation

ClinicalSuite validation uses:

- GIAB HG002
- GIAB HG003
- GIAB HG004
- Broad GRCh38 Full Analysis Set + Decoy + HLA
- Production BWA-MEM2 indexes
- Real Illumina-compatible FASTQ

The included 50,000-read HG002 subset is intended only for software validation.

Clinical performance validation must always be performed using complete,
production-scale datasets.

---

# Development Roadmap

## Completed

| Module | Status |
|----------|---------|
| Repository Skeleton | ✅ |
| Configuration | ✅ |
| Common Bash Library | ✅ |
| Conda Runtime | ✅ |
| Preflight | ✅ |
| Quality Control | ✅ |
| Alignment & BAM Processing | ✅ |

---

## Planned

### Module 8

Coverage Analysis

Tools

- Mosdepth
- Picard CollectHsMetrics (WES)

Outputs

- Coverage reports
- Low coverage intervals
- Coverage statistics

---

### Module 9

DeepVariant

Official DeepVariant WGS/WES models

Outputs

- Raw VCF
- Filtered VCF

---

### Module 10

GATK HaplotypeCaller

Outputs

- Raw VCF
- Filtered VCF

---

### Module 11

Octopus

Outputs

- Raw VCF
- Filtered VCF

---

### Module 12

Consensus Variant Engine

The ClinicalSuite Consensus Engine is the central innovation of the pipeline.

This is **not** a VCF merge.

The workflow performs:

```text
Caller VCFs

↓

Variant Normalization

↓

Variant Harmonization

↓

Evidence Aggregation

↓

Conflict Resolution

↓

Confidence Assessment

↓

Consensus Variant Set
```

The engine is deterministic.

No majority voting.

No machine learning.

No AI.

Every decision preserves provenance and remains fully explainable.

---

### Module 13

Variant Filtering

Filtering combines:

- caller-native filters
- validated technical filters
- consensus confidence
- reportable regions
- coverage status

Every filter is preserved.

Variants are never silently discarded.

---

### Module 14

Clinical Annotation

ClinicalSuite uses

Ensembl VEP

with open annotation resources.

Annotation sources include:

- ClinVar
- ClinGen
- gnomAD
- dbSNP
- HPO
- PanelApp
- MANE
- APPRIS
- RefSeq
- Ensembl
- HGNC
- REVEL
- SpliceAI
- CADD
- LOFTEE
- dbNSFP
- GERP++
- phyloP

Optional resources

- OMIM
- GeneReviews
- DECIPHER
- Orphanet

All databases remain external.

Nothing is bundled into ClinicalSuite.

---

### Module 15

ClinicalSuite ACMG Rule Engine

ClinicalSuite implements a native, rule-based ACMG/AMP interpretation engine.

The engine evaluates every ACMG criterion independently.

Workflow

```text
Annotated Variant

↓

Evidence Collection

↓

Criterion Evaluation

↓

Evidence Ledger

↓

Official ACMG Combining Rules

↓

Preliminary Classification
```

The engine:

- is fully deterministic
- is fully explainable
- preserves provenance
- records every applied criterion
- records every rejected criterion
- records supporting evidence

No machine learning.

No Bayesian scoring.

No proprietary algorithms.

No black-box pathogenicity scores.

The engine follows the official ACMG/AMP guidelines together with ClinGen
recommendations.

Final classification remains subject to expert clinical review.

---

### Module 16

Clinical Reporting

ClinicalSuite generates:

- Clinical Report
- Technical Report
- QC Report
- Coverage Report
- Variant Summary
- Consensus Report
- Provenance Report

Every report records:

- software versions
- package versions
- reference version
- database versions
- runtime
- parameters
- checksums

ensuring complete reproducibility.

---

# Repository Structure

```text
ClinicalSuite/

├── bin/
├── config/
├── envs/
├── references/
├── databases/
├── docs/
├── tests/
├── validation/
├── Architecture.md
├── README.md
├── CHANGELOG.md
├── VERSION
└── run.sh
```

Patient data, run outputs, references, databases, caches,
models and packed environments are intentionally excluded
from version control.

---

# Documentation

Primary project documents

- Architecture.md
- README.md
- CHANGELOG.md

Technical documentation

- Operations
- Installation
- Deployment
- Validation Plan
- Scientific Decisions
- Configuration
- Runtime
- Preflight
- Quality Control
- Alignment

These documents define the authoritative behavior of ClinicalSuite.

---

# License

ClinicalSuite itself is released as open-source software.

Third-party software retains its original licenses.

ClinicalSuite intentionally relies on openly available tools and databases
whenever possible.

References, annotation databases, trained models and plugins remain external,
versioned resources supplied by the deploying laboratory.

---

# Acknowledgements

ClinicalSuite follows recommendations and best practices from:

- ACMG
- AMP
- ClinGen
- GA4GH
- CAP
- GIAB
- Broad Institute
- Ensembl
- NCBI

The project aims to provide a transparent, reproducible and clinically
oriented framework for human germline variant discovery while remaining fully
open, maintainable and scientifically rigorous.
