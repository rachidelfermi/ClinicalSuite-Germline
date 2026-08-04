# ClinicalSuite Germline V2 Architecture

**Document Status**

Approved architecture baseline

Incremental implementation in progress

---

**Scientific Review**

2026

---

**Project Goal**

ClinicalSuite Germline V2 is an open-source, clinically oriented,
reproducible framework for human germline small-variant discovery,
annotation, interpretation and reporting from Illumina-compatible
paired-end short-read Whole Genome Sequencing (WGS) and Whole Exome
Sequencing (WES).

ClinicalSuite is designed around:

- reproducibility
- transparency
- scientific validation
- deterministic execution
- explainable evidence
- modular implementation
- long-term maintainability

The objective is not to replace clinical expertise.

The objective is to provide a scientifically rigorous computational
framework that supports expert clinical interpretation.

---

# 0. Approved V2 Implementation Clarifications

ClinicalSuite V2 follows several architectural constraints.

These constraints supersede any previous implementation drafts.

---

## Runtime

ClinicalSuite uses isolated Conda environments.

The previous Apptainer runtime has been removed because the production
HPC environment does not support user namespaces or setuid container
execution.

This affects only runtime packaging.

The scientific workflow remains unchanged.

Requirements:

- Mamba-only installation
- isolated environments
- pinned package versions
- explicit package locks
- conda-pack archives
- reproducible deployment

References, trained models, annotation databases, VEP caches and plugins
remain external resources.

---

## Variant Representation

ClinicalSuite V2 uses conventional VCF representation.

Variant normalization follows:

- left alignment
- minimal representation
- multiallelic decomposition

using

- bcftools
- vt

GA4GH VRS remains a future direction.

ClinicalSuite V2 does not require VRS identifiers.

---

## Consensus Engine

The Consensus Variant Engine is deterministic.

It is **not**

- majority voting
- machine learning
- logistic regression
- Bayesian ensemble
- AI

Instead it performs

- variant normalization
- representation harmonization
- evidence aggregation
- conflict resolution
- confidence assessment

using explicit rule-based logic.

Every decision must remain completely explainable.

---

## ACMG Interpretation

ClinicalSuite V2 intentionally removes proprietary interpretation
dependencies.

ANNOVAR is not part of the architecture.

InterVar is not part of the architecture.

Instead ClinicalSuite implements a native
**ClinicalSuite ACMG Rule Engine**.

The engine evaluates ACMG/AMP criteria directly using open clinical
resources.

The implementation must remain:

- deterministic
- transparent
- reproducible
- fully offline
- fully auditable

No proprietary interpretation engine is required.

---

# 1. Clinical Scope

ClinicalSuite is designed as a clinical bioinformatics framework.

The software itself is **not**

- a clinical assay
- an in-vitro diagnostic
- a medical device
- a replacement for laboratory accreditation

Every laboratory remains responsible for:

- analytical validation
- clinical validation
- assay validation
- wet-lab validation
- expert review
- clinical sign-out

ClinicalSuite provides computational support only.

---

## Supported Analyses

Current release supports only

- Human nuclear germline SNVs
- Human nuclear germline small indels
- Paired-end Illumina-compatible sequencing
- Whole Genome Sequencing
- Whole Exome Sequencing
- Broad GRCh38 Full Analysis Set + Decoy + HLA

One sample is processed per analysis.

Joint calling is outside the current scope.

---

## Unsupported Analyses

The following workflows are intentionally excluded.

- Somatic variants
- Mosaic variants
- Structural variants
- Copy-number variants
- Repeat expansions
- Mitochondrial variants
- Long-read sequencing
- Oxford Nanopore
- PacBio
- RNA sequencing
- Single-cell sequencing
- Pharmacogenomics
- HLA typing
- Non-human genomes

These workflows will be implemented independently in future
ClinicalSuite projects.

---

## GeneMind

GeneMind support is conditional.

ClinicalSuite supports only validated Illumina-compatible GeneMind
workflows.

Every GeneMind chemistry, instrument and library preparation requires
independent validation.

Validation performed on Illumina cannot automatically be transferred to
GeneMind.

---

# 2. Scientific Design Principles

ClinicalSuite follows the following evidence hierarchy.

1. ACMG / AMP recommendations

2. ClinGen recommendations

3. GA4GH recommendations

4. CAP recommendations

5. GIAB benchmarking

6. Official software documentation

7. Peer-reviewed scientific literature

8. Laboratory-specific analytical validation

Popularity alone is never sufficient.

Benchmarking must always be stratified by

- variant type
- genome context
- genotype
- assay
- sequencing platform
- reportable region
- coverage

---

## Core Principles

ClinicalSuite follows these implementation rules.

- Raw inputs are immutable.
- Every decision remains traceable.
- Every intermediate file is reproducible.
- Every output preserves provenance.
- No evidence is silently discarded.
- Missing evidence is never inferred.
- Clinical meaning is never inferred from caller agreement alone.
- Every software version is pinned.
- Every database version is pinned.
- Every reference version is pinned.
- Every trained model is pinned.
- Every environment is version controlled.
- Missing required resources always fail before analysis begins.
- When two scientifically equivalent implementations exist, the simpler
  implementation is preferred.

ClinicalSuite favors transparency over automation.

Every classification must be understandable by a human reviewer.

# 3. Scientific Architecture Decision Record

ClinicalSuite V2 follows a modular, deterministic workflow designed for
clinical germline WGS/WES using Illumina-compatible paired-end short-read
sequencing.

Every analytical step is independently validated.

Every module preserves complete provenance.

No downstream module modifies the outputs of previous modules.

The workflow is intentionally modular so that individual components may be
updated and revalidated without redesigning the entire pipeline.

---

# 3.1 Reference Genome

ClinicalSuite supports exactly one production reference.

```
Broad GRCh38 Full Analysis Set + Decoy + HLA

GRCh38_full_analysis_set_plus_decoy_hla.fa
```

This reference is permanently locked.

Every production deployment must use:

- identical FASTA
- identical FAI
- identical sequence dictionary
- identical BWA-MEM2 index
- identical checksum inventory

ClinicalSuite rejects:

- GRCh37
- UCSC hg38
- Ensembl Primary Assembly
- T2T-CHM13
- third-party BWA indexes
- mismatched FASTA/index combinations

Reference validation is performed before alignment.

---

# 3.2 Quality Control

Quality control is intentionally conservative.

ClinicalSuite does not aggressively modify sequencing reads.

Workflow

```
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

fastp operates in validated pass-through mode.

Default workflow avoids:

- excessive quality trimming
- poly-X trimming
- overlap correction
- read merging
- deduplication
- complexity filtering

Adapter trimming is enabled only when validated for a specific assay.

QC failures remain part of the permanent run record.

QC never silently removes samples.

---

# 3.3 Alignment & BAM Processing

Alignment follows Broad GATK Best Practices while remaining fully open source.

Workflow

```
FASTQ

↓

BWA-MEM2

↓

SAM

↓

Coordinate Sorted BAM

↓

Picard MarkDuplicates

↓

GATK BaseRecalibrator

↓

GATK ApplyBQSR

↓

Analysis-ready BAM
```

Analysis-ready BAM becomes the only alignment input for downstream modules.

Read Groups are mandatory.

Duplicate reads are marked.

They are never removed.

Original BAMs remain available for validation.

---

# 3.4 Coverage Analysis

Coverage analysis serves two purposes.

Technical validation

and

Clinical reportability.

Tools

- Mosdepth
- Picard CollectHsMetrics (WES)

Outputs

- whole genome coverage
- exon coverage
- reportable interval coverage
- low coverage intervals
- coverage statistics

Coverage failures propagate into final reports.

ClinicalSuite never reports unsupported regions as negative findings.

---

# 3.5 Germline Variant Calling

ClinicalSuite intentionally uses three independent callers.

Each caller contributes different strengths.

Workflow

```
Analysis-ready BAM

↓

DeepVariant

↓

GATK HaplotypeCaller

↓

Octopus
```

Every caller executes independently.

No caller influences another.

Caller outputs remain unchanged.

Caller-native filtering is preserved.

Raw VCFs remain available throughout the pipeline.

---

## DeepVariant

Role

Primary accuracy anchor.

Strengths

- deep learning
- excellent SNP accuracy
- excellent indel accuracy
- official WGS/WES models
- extensive benchmarking

Limitations

- requires trained models
- research software
- assay-specific validation required

---

## GATK HaplotypeCaller

Role

Clinical reference implementation.

Strengths

- mature
- local assembly
- broad clinical adoption
- extensive documentation

Limitations

- conservative
- correlated evidence with alignment workflow

---

## Octopus

Role

Independent haplotype-aware Bayesian caller.

Strengths

- complex variants
- haplotype modeling
- complementary evidence

Limitations

- smaller user community
- fewer clinical validation studies
- assay-specific validation required

---

ClinicalSuite intentionally excludes

- FreeBayes
- Strelka2
- Clair3
- Long-read callers

Current architecture is limited to Illumina-compatible short-read sequencing.

---

# 3.6 Consensus Variant Engine

The Consensus Variant Engine is the scientific centerpiece of ClinicalSuite.

It is NOT

- VCF merging
- majority voting
- caller intersection
- caller union
- AI
- machine learning

Instead it performs

```
Caller VCFs

↓

Variant Normalization

↓

Representation Harmonization

↓

Evidence Aggregation

↓

Conflict Resolution

↓

Confidence Assessment

↓

Consensus Variant Set
```

---

## Variant Normalization

Every caller VCF undergoes

- left alignment
- minimal representation
- multiallelic decomposition
- reference validation

using

- bcftools
- vt

---

## Representation Harmonization

Equivalent biological variants may have different VCF representations.

ClinicalSuite identifies

- equivalent alleles
- equivalent haplotypes
- representation conflicts

without modifying original caller outputs.

---

## Evidence Aggregation

Evidence collected includes

- caller support
- genotype agreement
- allele balance
- depth
- mapping quality
- caller quality
- variant class
- genome context
- reportable status

Every evidence item retains its source.

---

## Conflict Resolution

ClinicalSuite never silently resolves conflicts.

Conflicts remain explicit.

Examples

- genotype disagreement
- overlapping variants
- incompatible representations
- reference inconsistencies

Every conflict remains traceable.

---

## Confidence Assessment

Consensus confidence is deterministic.

No machine learning.

No Bayesian model.

No weighted voting.

Instead ClinicalSuite uses transparent evidence rules.

Outputs

- High Confidence
- Review
- Technical Rejection

Every decision remains explainable.

---

# 3.7 Variant Filtering

Filtering remains intentionally conservative.

ClinicalSuite preserves

- caller-native filters
- technical filters
- coverage filters
- reportable region filters
- confidence filters

No variant is silently removed.

Every filtered variant remains available in evidence outputs.

---

# 3.8 Clinical Annotation

ClinicalSuite uses

Ensembl VEP

as the single annotation engine.

The annotation workflow remains fully offline.

Resources include

Population

- gnomAD
- dbSNP

Clinical

- ClinVar
- ClinGen

Gene

- HGNC
- Ensembl
- RefSeq
- MANE
- APPRIS

Prediction

- REVEL
- SpliceAI
- CADD
- LOFTEE
- dbNSFP

Conservation

- GERP++
- phyloP

Phenotype

- HPO
- PanelApp

Optional

- OMIM
- GeneReviews
- DECIPHER
- Orphanet

Databases remain external.

Nothing is bundled into ClinicalSuite.

---

# 3.9 ClinicalSuite ACMG Rule Engine

ClinicalSuite implements its own native ACMG interpretation engine.

No proprietary software is required.

No ANNOVAR.

No InterVar.

The workflow is

```
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

Every ACMG criterion is evaluated independently.

Examples

Population

- BA1
- BS1
- PM2

Computational

- PP3
- BP4

Loss-of-function

- PVS1

Functional

- PS3
- BS3

Segregation

- PP1
- BS4

Phenotype

- PP4

Every criterion records

- applied
- not applied
- evidence
- source
- rationale

No black-box classification exists.

ClinicalSuite simply implements official ACMG/AMP rules using open evidence.

Expert review remains mandatory.

---

# 3.10 Clinical Reporting

ClinicalSuite produces

- Technical Report
- QC Report
- Coverage Report
- Consensus Report
- Variant Summary
- Clinical Review Draft

Reports remain drafts.

Final clinical interpretation always requires laboratory review and sign-off.

# 4. Complete Scientific Workflow

ClinicalSuite follows a deterministic, modular workflow.

Every stage produces immutable outputs.

Every stage records provenance.

Every stage can be independently validated.

```
Configuration
+
Sample Manifest
+
Reference Bundle
+
External Databases

                │
                ▼

         Stage-aware Preflight

                │
                ▼

      FastQC → fastp → FastQC → MultiQC

                │
                ▼

             BWA-MEM2 Alignment

                │
                ▼

      Coordinate Sorting

                │
                ▼

      Picard MarkDuplicates

                │
                ▼

             GATK BQSR

                │
                ▼

        Analysis-ready BAM

                │
                ▼

     Mosdepth (+ HsMetrics for WES)

                │
                ▼

     ┌──────────┬──────────┬──────────┐
     │          │          │
DeepVariant   GATK HC   Octopus
     │          │          │
     └──────────┴──────────┘

                ▼

      Variant Normalization

                ▼

   Representation Harmonization

                ▼

     Evidence Aggregation

                ▼

      Conflict Resolution

                ▼

     Consensus Variant Set

                ▼

        Ensembl VEP

                ▼

 ClinicalSuite Annotation Layer

                ▼

 ClinicalSuite ACMG Rule Engine

                ▼

      Clinical Review Draft
```

No annotation evidence is allowed to influence analytical variant calling or consensus generation.

Analytical confidence and clinical pathogenicity are intentionally separated.

---

# 5. Module Contracts

Every module has a strict contract.

## Module 00 — Preflight

**Inputs**

- Configuration
- Sample Manifest
- Reference Manifest
- Database Manifest
- Conda Runtime

**Outputs**

- Resolved Configuration
- Validation Report
- Compatibility Report

Failure prevents all downstream analysis.

---

## Module 01 — Quality Control

**Inputs**

- FASTQ

**Outputs**

- FastQC
- fastp
- MultiQC
- Validated FASTQ

QC never silently removes data.

---

## Module 02 — Alignment

**Inputs**

- Validated FASTQ
- Reference
- Read Groups

**Outputs**

- Analysis-ready BAM
- BAM Index
- Duplicate Metrics
- BQSR Tables

---

## Module 03 — Coverage

**Inputs**

- Analysis-ready BAM

**Outputs**

- Mosdepth Coverage
- WES HsMetrics
- Low Coverage Regions

Coverage limitations propagate into the final report.

---

## Module 04 — DeepVariant

Outputs

- Raw VCF
- Filtered VCF
- Logs

---

## Module 05 — GATK HaplotypeCaller

Outputs

- Raw VCF
- Filtered VCF
- Logs

---

## Module 06 — Octopus

Outputs

- Raw VCF
- Filtered VCF
- Logs

---

## Module 07 — Consensus Variant Engine

Inputs

- Three caller VCFs
- Analysis-ready BAM
- Reference

Outputs

- Evidence VCF
- Consensus VCF
- High-confidence Variant Set
- Review Variant Set
- Conflict Report

Every original caller record remains recoverable.

---

## Module 08 — Annotation

Inputs

- Consensus Variant Set

Outputs

- Annotated VCF
- Transcript Annotation
- Clinical Annotation
- Population Annotation

Annotation uses only Ensembl VEP plus external resources.

---

## Module 09 — ClinicalSuite ACMG Rule Engine

Inputs

- Annotated Variants
- Clinical Databases
- Phenotype Information

Outputs

- ACMG Evidence Ledger
- Applied Criteria
- Preliminary Classification
- Complete Audit Trail

The engine never produces a final clinical diagnosis.

Expert review is mandatory.

---

## Module 10 — Reporting

Outputs

- Technical Report
- QC Report
- Coverage Report
- Consensus Report
- Clinical Review Draft
- Provenance Report

Every report records exact software, reference, database and runtime versions.

---

# 6. Repository Layout

```
ClinicalSuite/

├── Architecture.md
├── README.md
├── CHANGELOG.md
├── VERSION
├── run.sh

├── bin/
├── config/
├── envs/
├── references/
├── databases/
├── docs/
├── tests/
└── validation/
```

Run outputs remain outside the repository.

```
RUN_ID/

├── resolved_config/
├── qc/
├── alignment/
├── coverage/
├── callers/
├── consensus/
├── annotation/
├── acmg/
├── reports/
├── provenance/
├── logs/
└── tmp/
```

Patient data is never stored inside the source repository.

---

# 7. Runtime Architecture

ClinicalSuite uses isolated Conda environments.

Every module executes inside its validated runtime.

Users never manually activate environments.

The launcher automatically selects the required environment.

Environment layout

| Environment | Purpose |
|--------------|---------|
| qc | Quality control |
| alignment | Alignment and BAM processing |
| variant | GATK + variant utilities |
| deepvariant | DeepVariant |
| octopus | Octopus |
| annotation | VEP + annotation tools |
| report | Reporting |

Every environment is

- version pinned
- validated
- frozen
- packed
- checksum verified

Reference genomes, trained models, annotation databases and caches remain external.

---

# 8. Conda Runtime Strategy

ClinicalSuite requires

- Conda
- Mamba
- conda-pack

Environment construction uses only

```
mamba create

mamba install
```

Every validated environment produces

- environment.yml
- explicit package lock
- conda-pack archive
- SHA256 checksum
- validation report

Environments are packed only after successful validation.

The launcher automatically executes software inside the appropriate runtime.

The runtime is completely reproducible.

---

# 9. Configuration Philosophy

ClinicalSuite intentionally keeps configuration simple.

Three inputs define every analysis.

1. Clinical Configuration

2. Sample Manifest

3. Resource Manifests

No hidden configuration exists.

Scientific thresholds are never hardcoded.

Assay-specific parameters belong to validated assay profiles.

Every execution records the exact resolved configuration.

No runtime environment variable is allowed to silently change scientific behavior.

Configuration is immutable once analysis begins.

# 10. Validation Strategy

ClinicalSuite follows a validation-first development model.

No scientific module is considered complete until it has passed:

- Scientific review
- Software review
- Static validation
- Unit testing
- Integration testing
- Smoke testing
- Real-data validation
- Documentation review

Every module must be independently validated before downstream development
continues.

---

## 10.1 Software Validation

Every module must pass:

### Bash

- `bash -n`
- ShellCheck
- Strict Bash mode

### Runtime

- Environment validation
- Executable validation
- Version validation
- Package integrity

### Testing

- Unit tests
- Integration tests
- Smoke tests

### File Validation

- BAM validation
- VCF validation
- FASTQ validation
- Index validation
- Checksum validation

### Reproducibility

Every module must produce identical outputs when executed with identical:

- input
- configuration
- reference
- databases
- software versions

---

## 10.2 Runtime Validation

Every Conda environment must pass:

- activation
- dependency integrity
- executable validation
- version validation

The validation process verifies:

QC

- FastQC
- fastp
- MultiQC

Alignment

- BWA-MEM2
- Samtools
- Picard
- Mosdepth

Variant

- GATK
- bcftools
- HTSlib
- vt

DeepVariant

- DeepVariant runtime
- TensorFlow
- Official WGS/WES models

Octopus

- Octopus
- bcftools
- HTSlib

Annotation

- Ensembl VEP
- Perl
- BioPerl
- Annotation utilities

Report

- Python
- Reporting libraries

Environment validation reports become permanent project artifacts.

Environments are packed only after successful validation.

---

## 10.3 Scientific Validation

Scientific validation uses

GIAB reference materials.

Validation includes

- WGS
- WES
- Illumina
- GeneMind

Analytical validation measures

- Precision
- Recall
- F1
- Genotype concordance
- False positives
- False negatives

Results are stratified by

- SNP
- Indel
- Genome context
- Difficult regions
- Reportable regions
- Coverage

Overall F1 score alone is never considered sufficient.

---

## 10.4 Consensus Validation

The Consensus Variant Engine must demonstrate value beyond a single caller.

ClinicalSuite must demonstrate that the Consensus Engine is at least
non-inferior to DeepVariant alone before it becomes the production default.

Validation includes

- concordance
- difficult regions
- genotype agreement
- reproducibility
- conflict handling

Consensus remains fully deterministic.

---

## 10.5 Annotation Validation

Annotation validation verifies

- transcript correctness
- HGVS correctness
- database compatibility
- annotation reproducibility

Databases remain external.

Every database version is recorded.

Every annotation remains traceable.

---

## 10.6 ACMG Validation

The ClinicalSuite ACMG Rule Engine validates

every ACMG criterion independently.

Each criterion records

- applied
- rejected
- unavailable

together with

- supporting evidence
- source database
- rationale
- timestamp

ClinicalSuite never hides evidence.

The ACMG engine follows

- ACMG/AMP recommendations
- ClinGen SVI recommendations

without introducing proprietary algorithms.

Final clinical interpretation always requires expert review.

---

# 11. Critical Self Review

ClinicalSuite intentionally remains conservative.

Several areas require continuous validation.

## Consensus Engine

The Consensus Engine must continue to demonstrate value beyond
single-caller workflows.

If future validation shows no benefit,

ClinicalSuite will revert to the best-performing single caller.

---

## Octopus

Octopus remains under continuous review.

Future benchmarking may justify replacement.

Until then,

DeepVariant

+

GATK

+

Octopus

remain the approved production callers.

---

## GeneMind

GeneMind requires independent validation.

Support cannot automatically be transferred from Illumina.

---

## ACMG Rule Engine

ClinicalSuite intentionally implements a transparent rule engine.

It does not attempt to replace expert clinical review.

Future improvements may include

- ClinGen gene-specific specifications
- disease-specific ACMG refinements
- additional evidence sources

without changing the deterministic architecture.

---

## Scope

ClinicalSuite currently supports

- germline SNVs
- germline small indels

Future projects will independently implement

- CNVs
- Structural Variants
- Mitochondrial Variants
- Repeat Expansions
- Pharmacogenomics
- Somatic Analysis

---

# 12. Release Policy

Every production release must include

- Git tag
- CHANGELOG
- README
- Architecture
- Version
- Environment locks
- environment.yml
- Validation reports
- SHA256 checksums

Large runtime environments are not committed to Git.

Only reproducibility metadata is version controlled.

ClinicalSuite can always reconstruct the validated runtime from the
published lock files.

---

# 13. Long-term Vision

ClinicalSuite aims to become

- fully open source
- clinically reproducible
- scientifically transparent
- HPC friendly
- offline capable
- deterministic

without relying on proprietary interpretation software.

The project intentionally favors

- explainability
- reproducibility
- scientific rigor

over opaque automation.

Every analytical decision should remain understandable by a human reviewer.

ClinicalSuite is designed to support clinical scientists,

not replace them.

# 14. Scientific References

ClinicalSuite is developed according to a hierarchy of scientific evidence.

The project does **not** adopt tools or algorithms based solely on popularity,
benchmark rankings, or commercial adoption.

Scientific decisions follow this order:

1. International professional guidelines
2. ClinGen expert recommendations
3. GA4GH best practices
4. CAP / AMP laboratory recommendations
5. GIAB benchmark datasets
6. Official software documentation
7. Peer-reviewed literature
8. Internal analytical validation

---

## Primary Standards

ClinicalSuite follows recommendations from:

- ACMG
- AMP
- ClinGen
- GA4GH
- CAP
- GIAB

These documents define the scientific framework used throughout the project.

---

## Core Scientific Software

ClinicalSuite is built around the following primary software:

Quality Control

- FastQC
- fastp
- MultiQC

Alignment

- BWA-MEM2
- Samtools
- Picard
- GATK BQSR

Coverage

- Mosdepth
- Picard CollectHsMetrics

Variant Calling

- DeepVariant
- GATK HaplotypeCaller
- Octopus

Normalization

- bcftools
- vt

Annotation

- Ensembl VEP

Reporting

- Python
- R

Only officially maintained and scientifically validated software is adopted.

---

## Core Clinical Resources

ClinicalSuite uses open clinical resources whenever possible.

Primary resources include:

Population

- gnomAD
- dbSNP

Clinical

- ClinVar
- ClinGen

Gene Annotation

- Ensembl
- RefSeq
- HGNC
- MANE
- APPRIS

Phenotype

- HPO
- PanelApp

Prediction

- REVEL
- SpliceAI
- LOFTEE
- CADD
- dbNSFP

Conservation

- GERP++
- phyloP

Optional resources

- OMIM
- GeneReviews
- DECIPHER
- Orphanet

These resources remain external and independently versioned.

---

## Reproducibility

Every ClinicalSuite analysis records:

- software versions
- package versions
- Conda environment lock
- reference genome version
- reference checksum
- database versions
- model versions
- execution parameters
- runtime metadata
- checksums

This guarantees complete analytical reproducibility.

---

## Change Control

Any modification to:

- software
- Conda environment
- reference genome
- annotation database
- prediction algorithm
- ACMG logic
- filtering strategy
- consensus strategy

requires:

1. Scientific review
2. Documentation update
3. Validation update
4. Regression testing
5. Version increment
6. Changelog update

No scientific change is introduced without documented justification.

---

# 15. Future Roadmap

ClinicalSuite V2 focuses on clinically validated germline SNV and small-indel analysis.

Future independent projects may include:

- ClinicalSuite Somatic
- ClinicalSuite CNV
- ClinicalSuite Structural Variants
- ClinicalSuite Mitochondrial
- ClinicalSuite Pharmacogenomics
- ClinicalSuite RNA
- ClinicalSuite Long Reads

These will be developed as separate architectures to preserve simplicity and maintainability.

---

# 16. Final Architectural Principles

ClinicalSuite follows a small number of permanent engineering principles.

- Scientific correctness takes priority over feature count.
- Simplicity is preferred when two approaches provide equivalent validated performance.
- Every analytical decision must remain explainable.
- Every output must be reproducible.
- Every module must be independently testable.
- Every external dependency must be versioned.
- Every clinical resource must be traceable.
- Every classification must preserve supporting evidence.
- Automation supports expert review; it never replaces it.

ClinicalSuite intentionally avoids unnecessary complexity.

The project aims to provide a transparent, reproducible, clinically oriented framework for human germline variant discovery that can be validated, maintained, and deployed by clinical laboratories without dependence on proprietary interpretation software or black-box algorithms.