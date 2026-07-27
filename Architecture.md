# ClinicalSuite V2 architecture

**Document status:** approved architecture baseline; incremental implementation
in progress

**Scientific review date:** 2026-07-20

**Intended use:** development and site validation of an Illumina-compatible,
paired-end, short-read human germline WGS/WES workflow

## 0. Approved V2 implementation clarification

The implementation directive dated 2026-07-20 narrows two future-facing design
elements in this document. For ClinicalSuite V2:

- GA4GH VRS is not implemented. V2 uses conventional reference-validated
  left-alignment, minimal representation, and multiallelic decomposition with
  bcftools/vt-compatible representations. Provenance and internal interfaces must
  leave room for a future VRS identifier without requiring it.
- The consensus engine does not use machine learning or logistic regression. V2
  uses a deterministic, configurable, evidence-aware strategy that preserves
  caller evidence and conflicts and is explicitly not majority voting or simple
  VCF merging. Its exact rules require a consensus-module scientific decision
  record and validation before implementation.

These instructions supersede the V2 implementation portions of sections 3.7 and
3.9. Their VRS and calibrated-model discussions are retained as evaluated future
directions, not current implementation requirements. All other architecture
constraints and clinical validation gates remain in force.

The approved Module 4 directive dated 2026-07-21 further narrows container
contents: trained caller models, VEP caches/plugins, references, and databases
remain external; `annotation.sif` contains VEP and its runtime only; and
`report.sif` contains only the pinned Python reporting runtime. This supersedes
the broader bundling descriptions in sections 8 and 10.2 without changing any
scientific workflow.

The approved staged-preflight directive dated 2026-07-27 makes external
resource requirements conditional on the selected execution stage. Resources
first consumed by annotation are informational through Module 13 and become
mandatory at Module 14. Resources first consumed by ACMG decision support are
informational through Module 14 and become mandatory at Module 15. This changes
only validation timing; it does not change any scientific workflow or resource
compatibility requirement.

## 1. Clinical status and scope

ClinicalSuite V2 is designed to become a reproducible clinical bioinformatics
framework. The software alone is not a clinically validated assay, a medical
device, or a substitute for laboratory accreditation, assay-specific analytical
validation, expert variant review, or clinical sign-out. A laboratory must
validate the complete wet-lab and computational process in its own environment
before reporting patient results. ACMG requires reproducibility and preservation
of the exact pipeline component versions used for each test, and AMP/CAP requires
validation in the real operating environment [1,2,3].

The first release supports only:

- human nuclear germline SNVs and small indels;
- paired-end short-read WGS and hybrid-capture WES;
- Illumina and GeneMind instruments that emit Sanger/Phred+33 paired FASTQ;
- Broad GRCh38 Full Analysis Set + Decoy + HLA as the single locked reference;
  and
- one sample per analysis. Family-aware interpretation may consume supplied
  pedigree evidence later, but family joint calling is not part of this release.

It does not support somatic analysis, mosaic calling, long reads, RNA, methylation,
single-cell data, GRCh37 liftover, or nonhuman genomes. CNVs, structural variants,
repeat expansions, mitochondrial variants, pharmacogenomics, HLA typing, and
aneuploidy are also outside this initial small-variant workflow. A report must
state these limitations. WGS/WES from this release must not be represented as a
comprehensive negative germline test.

GeneMind support is conditional rather than presumed equivalent to Illumina.
Published GenoLab M WGS/WES work supports technical feasibility, but is limited
and used platform-adapted DNAscope models [4]. Each GeneMind instrument, chemistry,
library preparation, and assay therefore requires its own end-to-end validation;
an Illumina validation cannot be transferred to it.

## 2. Evidence standard and design rules

Decisions use the following evidence order:

1. current professional standards and expert guidance (ACMG/AMP, ClinGen,
   AMP/CAP, GA4GH);
2. current official tool and resource documentation;
3. GIAB/NIST reference materials and precisionFDA challenge evidence;
4. peer-reviewed benchmarking, prioritizing independent and recent studies; and
5. local, assay-specific analytical validation.

Popularity, a high global F1 score on one specimen, and a vendor claim are not
sufficient. Benchmark performance must be stratified by variant class, genotype,
genome context, reportable range, assay, platform, and coverage. GA4GH specifically
recommends truth VCFs together with truth regions, sophisticated haplotype-aware
comparison, and stratified performance reporting [5]. GIAB also cautions that its
benchmarks are not perfect or complete outside their defined regions [6,7].

The implementation rules are:

- keep raw inputs and every decision-bearing intermediate immutable;
- tag excluded records instead of silently deleting them;
- never infer clinical meaning from caller agreement alone;
- never combine correlated caller probabilities as if they were independent;
- never turn a software prediction directly into a signed-out ACMG class;
- pin every tool, image, model, database, reference, and parameter set;
- fail before analysis if required inputs are missing or incompatible; and
- choose the simpler implementation when validation shows equivalent performance.

## 3. Scientific architecture decision record

### 3.1 Reference assembly

ClinicalSuite V2 supports exactly one reference: Broad GRCh38 Full Analysis Set
+ Decoy + HLA, distributed as
`GRCh38_full_analysis_set_plus_decoy_hla.fa`. Its locked ClinicalSuite identity
is `GRCh38_full_analysis_set_plus_decoy_hla-20150309`. The FASTA has `chr`
contig naming and includes primary chromosomes, unlocalized and unplaced
scaffolds, alternate loci, patches, decoys, and HLA sequences.

The FASTA sequence, contig set, ALT metadata, PAR coordinates, and generated
indexes form one indivisible reference release identified by SHA-256 checksums.
Any other FASTA filename, reference identity, contig convention, or unmatched
FASTA/index/database combination is a hard preflight error from alignment
onward. Liftover is not performed in the clinical path because it can introduce
ambiguous or failed mappings. Annotation databases remain external and must
declare the exact compatible FASTA SHA-256 when their stage is enabled.

### 3.2 FASTQ quality control and preprocessing

FastQC, fastp, and MultiQC remain appropriate, simple tools for technical QC.
fastp provides machine-readable JSON and paired-end adapter detection [8]. These
tools do not establish clinical acceptability by themselves.

Default behavior is deliberately conservative:

- run FastQC on raw reads;
- run fastp in report/pass-through mode;
- do not perform generic quality-tail trimming, poly-X trimming, base correction,
  read merging, deduplication, or complexity filtering by default;
- enable adapter trimming only in a validated assay profile, preferably with the
  known library adapter sequence; and
- run FastQC again only when reads were changed, then aggregate with MultiQC.

This avoids changing evidence merely to make QC plots look better. GATK regards
FASTQ modification as optional, and preprocessing choices must be validated [9].
fastp defaults must not be inherited implicitly across versions.

QC thresholds are laboratory configuration, not universal biological constants.
Failures are retained in the run state and propagated to reports. A failed sample
does not automatically proceed to clinical interpretation unless an authorized
override, reason, user, and timestamp are recorded.

### 3.3 Alignment and BAM preparation

BWA-MEM2 is retained. It accelerates the established BWA-MEM algorithm while
preserving its alignment approach, and BWA remains part of the documented GATK
preprocessing path [10]. Samtools performs streaming conversion, coordinate sort,
indexing, integrity checks, and summary metrics. Picard MarkDuplicates marks rather
than removes duplicates. Read groups are required and are built from manifest
fields, never guessed from filenames.

GATK BaseRecalibrator and ApplyBQSR produce the declared analysis-ready BAM, using
only locked, assembly-matched known-sites resources. GATK still documents BQSR in
its standard preprocessing workflow [10]. The original-quality, duplicate-marked
BAM is retained until the run is complete so that validation can compare BQSR and
non-BQSR calling. The production choice to feed BQSR reads to all three callers
must pass a caller-specific ablation study; DeepVariant and Octopus do not derive
their authority from GATK Best Practices.

DRAGMAP and proprietary DRAGEN were reviewed. GATK now recommends a DRAGEN-GATK
single-sample path, and a recent DRAGEN study reports better aggregate small-
variant accuracy than BWA plus DeepVariant or HaplotypeCaller [11,12]. They are not
adopted here because the requested portable Bash/Apptainer design must run without
licensed hardware/software, and the entire three-caller workflow would need to be
revalidated after an aligner change. This decision should be revisited at each
major validation cycle; it is not a claim that BWA-MEM2 is more accurate.

### 3.4 Coverage analysis

Mosdepth supplies efficient whole-genome and interval coverage distributions.
For WES, Picard CollectHsMetrics additionally reports bait/target enrichment and
capture-specific metrics. WES uses two explicit site-provided interval sets:

- the capture design used for calling; and
- the clinically reportable range used for coverage and reporting.

ClinicalSuite will not invent padding or merge target definitions. Per-base or
per-interval low-coverage regions, the configured thresholds, and the fraction of
the reportable range meeting each threshold are report inputs. ACMG guidance
requires coverage limitations to be assessed and reported; for genome sequencing,
an exome-defined coverage measure should also be available [2].

### 3.5 Germline callers

The proposed callers are retained provisionally:

| Caller | Evidence-supported role | Important limitation |
|---|---|---|
| DeepVariant | Primary accuracy anchor. It remains a high-performing Illumina WGS/WES germline caller with official assay-specific models and an official container [13,14]. | Its own project states that it is research software and not intended for clinical use. The exact WGS/WES model and image digest require local validation. |
| GATK HaplotypeCaller | Established local-assembly caller with mature clinical usage, detailed documentation, ploidy support, and a direct single-sample workflow [15,16]. | Single-sample output is sensitive before filtering; its scores and errors are correlated with the same reads used by the other callers. |
| Octopus | Haplotype-aware Bayesian caller with support for complex replacements and published competitive performance; this provides a meaningfully different model from DeepVariant and HaplotypeCaller [17]. | Independent recent clinical benchmarking is limited, and the distributed germline forest requires validation for each assay/platform. Maintenance and image reproducibility are release gates. |

DeepVariant, HaplotypeCaller, Octopus, and Strelka2 have all shown strong results in
comparative work, with caller choice often affecting coding-region performance
more than aligner choice [18]. The evidence does not establish one universal best
three-caller ensemble for this exact clinical use. A recent DRAGEN implementation
has stronger aggregate results but is proprietary [12]; Sentieon/DNAscope is also
proprietary and GeneMind-specific evidence used a tailored model [4]. Strelka2 has
good benchmark performance but no clear evidence that replacing one of the three
requested callers improves this exact consensus design. No replacement is made.
The precisionFDA Truth Challenge V2 is valuable evidence about difficult-to-map
regions, but its region- and technology-specific rankings do not validate a fixed
multi-caller consensus for routine WGS/WES [39].

All callers consume the same sample, reference bundle, reportable/calling region,
and declared ploidy map. WGS and WES use the corresponding official DeepVariant
model. Octopus uses its individual germline model and a pinned germline forest;
the model file is treated as a versioned reference. HaplotypeCaller uses its
single-sample mode. Caller-native unfiltered and filtered outputs are both kept.

For XX/XY sex chromosomes, PAR and non-PAR ploidy must be explicit. Current
DeepVariant supports haploid contigs with PAR exclusions, GATK supports
region-specific ploidy, and Octopus supports contig ploidies [19,20,21]. The
manifest must provide the expected chromosome complement if sex chromosomes are
in the reportable range. Sequence-derived sex-chromosome QC is a concordance flag,
not a clinical karyotype inference. If the expected complement is absent or QC is
discordant, sex-chromosome calls cannot enter the high-confidence set. The GIAB
HG002 X/Y benchmark is required for validation [22].

### 3.6 Why a consensus is not a merge or vote

No professional guideline establishes simple caller majority voting as clinical
best practice for germline SNVs/indels. Intersections can increase precision while
losing true variants unique to a strong caller; unions increase sensitivity and
false positives. Callers also inspect the same reads and therefore are not
independent experiments. GIAB itself integrates diverse technologies and methods,
identifies uncertain regions, and stratifies errors rather than treating votes as
truth [6].

The consensus engine is therefore a transparent, validation-trained confidence
layer over a lossless candidate union. It must demonstrate an advantage over the
best single caller on held-out specimens. Until then it is experimental and must
not be the sole source of clinical calls.

### 3.7 Variant normalization and representation harmonization

Each caller VCF passes these ordered steps while the raw record is preserved:

1. validate header, sample, reference allele, contig, ploidy, and VCF semantics;
2. split multiallelic records into biallelic allele records while correctly
   remapping allele-specific INFO/FORMAT fields and genotypes;
3. trim common suffix/prefix bases and left-align against the locked FASTA with
   `bcftools norm`; and
4. create a GA4GH VRS fully justified Allele and computed identifier for the
   canonical allele.

bcftools provides reference checking, minimal representation, left alignment, and
multiallelic decomposition [23]. GA4GH VRS provides normalization across the full
region of representational ambiguity and stable computed identifiers [24,25].
Ordinary normalization alone cannot reconcile every complex but biologically
equivalent representation; GA4GH benchmarking recommends haplotype-aware
comparison for that reason [5].

Records with the same VRS allele identifier are allele-equivalent. Nearby compound
or overlapping records are additionally compared by applying phased alleles to a
bounded reference window and comparing the resulting local haplotype sequence.
The bound is defined in configuration and validated with complex-variant fixtures.
Unphased or overlapping calls that cannot be reconciled without assumptions form
an explicit `REPRESENTATION_CONFLICT` block. They are never silently collapsed.
MNPs are not atomized by default because atomization can discard phase and alter
the biological assertion.

Every harmonized allele retains source caller, original coordinates/alleles,
original record ID, filter, genotype, likelihood/quality fields, phase set, and
normalization operations. The output VCF uses conventional left-normalized VCF;
VRS identifiers are additional provenance, not a replacement file format.

### 3.8 Consensus evidence aggregation and conflict resolution

The engine constructs one evidence row per harmonized allele and sample. It
contains:

- caller presence and caller-native PASS state separately for each caller;
- caller genotype, phasing, GQ/QUAL-like values, DP, AD/allele fraction, and the
  original missingness state without pretending the fields share a scale;
- genotype agreement category, not merely number of callers;
- caller-independent, consistently defined read evidence recomputed from the
  analysis-ready BAM where reliable (depth, allele observations, mapping/base
  quality summaries, strand and read-position balance);
- variant class and length;
- reportable/callable status, coverage status, ploidy, and validated genome-context
  strata; and
- all normalization, representation, and conflict flags.

Conflict handling is deterministic:

1. reference or sample incompatibility is a fatal error;
2. equivalent allele and concordant genotype evidence is aggregated;
3. equivalent allele with discordant genotypes is retained as
   `GENOTYPE_CONFLICT`;
4. non-equivalent overlapping alleles are retained in one conflict block;
5. a resolved local-haplotype equivalence is recorded with the exact transformation;
6. no unresolved conflict can be high-confidence; and
7. no record is discarded because only one caller emitted it.

### 3.9 Consensus confidence model

There is no hard-coded “two of three” rule and no arbitrary weighted sum. The first
candidate model is an interpretable L2-regularized logistic regression estimating
the empirical probability that the allele and genotype match truth within the
validated reportable range. Separate locked models are required for WGS and WES;
platform-specific models are required if held-out validation shows material
platform effects. SNV/indel class and relevant context are model terms rather than
unexamined global thresholds.

Only the evidence fields listed above may be features. Clinical annotations such
as ClinVar, consequence, gene, or predicted pathogenicity are forbidden features:
detection confidence must not be increased because a variant looks medically
interesting. Correlated caller qualities are learned as correlated features and
are never multiplied as independent probabilities.

Model development uses multiple GIAB genomes and assay-matched replicates. Splits
are by specimen and sequencing replicate, not random variants, to prevent leakage.
Thresholds are selected on development specimens for laboratory-defined minimum
precision/sensitivity, frozen, and then evaluated once on held-out specimens.
Calibration curves, Brier score, precision, recall, F1, false positives/negatives,
and confidence intervals are reported by required strata. DeepVariant work has
shown that caller GQ calibration differs between callers, reinforcing the need not
to compare raw GQ values directly [26].

The engine emits three operational states:

- `HIGH_CONFIDENCE`: meets a locked, externally validated threshold, lies in the
  validated reportable/callable range, and has no unresolved conflict;
- `REVIEW`: candidate retained but not meeting the high-confidence conditions; and
- `REJECTED_TECHNICAL`: demonstrable incompatibility or a locked technical filter,
  with the exact reason retained.

`CONSENSUS_SCORE` describes analytical detection/genotype confidence only. It has
no relation to pathogenicity, ACMG evidence strength, or reportability. If the
model fails to outperform or show prespecified noninferiority to the best single
caller on held-out validation, the production default becomes the best validated
single caller and consensus remains review-only.

### 3.10 Variant filtering

Filtering is intentionally small:

- apply each caller's pinned, recommended model/filter and preserve its result;
- apply reportable-range, callability, ploidy, coverage, representation-conflict,
  and validated consensus-confidence tags;
- do not use VQSR by default for a single sample; and
- do not add generic DP, allele-balance, QUAL, or strand thresholds unless the
  assay validation demonstrates and locks them.

GATK documents hard filtering when VQSR is unsuitable, while DeepVariant states
that no filtering beyond a chosen quality threshold is generally needed, and
Octopus prefers its germline random forest when suitable training data exist
[27,28,29]. Those caller-specific scores are inputs, not universal truth. All
filters are soft filters in the evidence VCF. Only the separately generated
high-confidence view excludes nonpassing records.

### 3.11 Clinical annotation

Ensembl VEP in offline/cache mode is the primary consequence engine. The VEP
executable and cache release must match; Ensembl explicitly documents this
pairing [30]. Annotation never calls the network at runtime.

MANE Select is the default reporting transcript, with MANE Plus Clinical retained
where needed; all transcript consequences remain available. The joint NCBI/Ensembl
MANE project recommends these transcripts as a clinical reporting standard [31].
APPRIS, Ensembl, RefSeq, HGNC identifiers, transcript versions, and HGVS strings
are preserved. A “most severe” consequence never deletes alternate clinically
relevant transcripts.

Resource roles are deliberately separated:

| Layer | Resources | Permitted use |
|---|---|---|
| Population/identity | gnomAD genomes and exomes, ancestry-aware popmax, dbSNP | Population frequency and stable identifiers. dbSNP membership is not pathogenicity evidence. |
| Gene constraint | gnomAD LOEUF | Gene-level context, not variant-level pathogenicity by itself. |
| Clinical assertions | ClinVar with review status, assertion date, condition, submitter/evidence links; ClinGen gene-disease validity and relevant expert specifications | Evidence for human review. Conflicts and old assertions remain visible. |
| Transcript/gene | MANE Select/Plus Clinical, Ensembl, RefSeq, APPRIS, HGNC | Consequence and transcript selection. |
| Functional prediction | REVEL, SpliceAI, CADD, LOFTEE, dbNSFP | Supporting evidence only under applicable calibrated ClinGen criteria. Correlated predictors are not counted independently. |
| Conservation | GERP++, phyloP | Context only; not an independent stack of ACMG votes. |
| Disease/phenotype | OMIM, HPO, PanelApp, GeneReviews, DECIPHER, Orphanet | Gene-condition-phenotype review and prioritization; never automatic pathogenicity. License and redistribution terms apply. |

ClinGen provides calibrated recommendations for applying PP3/BP4 computational
evidence [32]. Consequently, a configured, gene-appropriate calibrated predictor
may contribute one evidence line at the allowed strength; CADD, REVEL, SpliceAI,
conservation, and dbNSFP contents must not be naively counted as multiple
independent criteria. LOFTEE may support PVS1 assessment but does not implement
the ClinGen PVS1 decision tree, which requires disease mechanism and transcript
context [33].

Databases are read-only external inputs. Nothing is downloaded by the workflow.
Each resource has a checksum, release date/version, assembly, license/access note,
expected filename, and compatibility status in `databases/README.md` or
`references/README.md`. Missing core resources cause one aggregated preflight
failure. Missing optional/licensed resources disable only their declared layer and
appear prominently in the technical and clinical drafts.

### 3.12 ACMG/AMP decision support

InterVar and AutoACMG are retained only as two independent decision-support views.
InterVar automates a subset of the 2015 criteria and explicitly requires manual
adjustment [34]. AutoACMG is comparatively new and currently implements only a
subset of criteria while emphasizing transparent reasons [35]. Neither is a
validated autonomous classifier for this workflow.

InterVar's ANNOVAR-derived data and licenses are external deployment requirements.
AutoACMG's documented setup relies on SeqRepo plus REEV, annonars, mehari, and
dotty API endpoints. Remote clinical use is prohibited: before this module can be
implemented, all required services and data must run locally, be version-pinned,
work without external network access, and pass a privacy and reproducibility
review. If that cannot be demonstrated, AutoACMG remains a blocked validation
adapter rather than silently sending variant coordinates to a public service.

For every variant, the module preserves:

- tool version, ruleset, disease/gene/transcript context, database versions, and
  timestamp;
- every criterion considered, result, strength, source records, and reason for
  application, rejection, or inability to evaluate;
- raw InterVar and AutoACMG outputs without overwriting either;
- a comparison identifying agreement, disagreement, and missing evidence;
- applicable ClinGen SVI and gene-specific VCEP specifications; and
- curator changes as append-only records containing user, time, reason, and source.

The preliminary class is generated with the 2015 ACMG/AMP combining rules and may
also show the ClinGen-compatible Bayesian point representation, but the ruleset is
explicit and never silently upgraded [36,37]. Automated criteria that depend on
phenotype specificity, segregation, phase, de novo status, functional studies, or
disease mechanism remain unevaluated unless structured, reviewable evidence is
provided. The output says `COMPUTATIONAL PRELIMINARY CLASSIFICATION — EXPERT REVIEW
REQUIRED`; it cannot populate a final clinical classification field.

### 3.13 Reporting

Reporting creates immutable drafts, not signed clinical reports:

- clinical review draft: sample/assay identity, QC and coverage status, reportable
  range, candidate variants, preliminary ACMG evidence, limitations, and required
  reviewer/sign-out fields;
- technical report: complete module status, commands, parameters, checksums,
  software/images/models/databases, reference bundle, warnings, overrides, and
  resource use;
- coverage report: WGS and/or WES distributions plus every below-threshold
  reportable interval;
- consensus report: caller overlap only as descriptive data, conflicts, score
  calibration version, confidence distribution, and per-stratum validation scope;
- variant metrics: counts by type, genotype, filter, region, Ti/Tv as QC context,
  and annotation status; and
- machine-readable provenance and evidence files alongside human-readable HTML/PDF.

A negative draft is prohibited when sample QC, coverage, required resources, or
the reportable range is incomplete. Patient identifiers are not written to command
lines or general logs. Sample IDs are treated as sensitive data, output permissions
default to owner/group only, and temporary files remain inside the run directory.

## 4. Complete workflow

```text
manifest + config + paired FASTQ + external reference/database bundle
                              |
                    aggregated preflight
                              |
         raw FastQC -> fastp/pass-through -> post FastQC -> MultiQC
                              |
            BWA-MEM2 -> coordinate sort -> MarkDuplicates
                              |
                  BQSR -> analysis-ready BAM + index
                              |
               mosdepth (+ CollectHsMetrics for WES)
                              |
          +-------------------+-------------------+
          |                   |                   |
     DeepVariant      HaplotypeCaller          Octopus
          |                   |                   |
          +---------- raw and filtered VCFs ------+
                              |
        validate -> split/normalize -> VRS/haplotype harmonize
                              |
     lossless evidence matrix -> conflicts -> calibrated confidence
                              |
        evidence VCF + high-confidence view + review/conflict set
                              |
               offline VEP + clinical resource joins
                              |
              InterVar + AutoACMG evidence views
                              |
          clinical/technical/coverage/consensus report drafts
```

No annotation or pathogenicity field feeds backward into analytical consensus.

## 5. Module contracts

| Module | Inputs | Required outputs | Failure behavior |
|---|---|---|---|
| `00_preflight` | config, sample TSV, paths, SIFs, reference/database manifests | resolved configuration, compatibility/checksum report, one missing-input report | Collect all missing/incompatible items, print once, exit without starting tools. |
| `01_qc` | paired FASTQ, assay profile | raw/processed FastQC, fastp JSON/HTML, MultiQC, final FASTQ or immutable pass-through links | Record QC failures; stop before alignment unless an audited override is allowed. |
| `02_alignment` | final FASTQ, reference/index, read-group metadata | marked BAM, BQSR table, analysis-ready BAM/BAI, duplicate/alignment metrics | Remove only incomplete temporary outputs; preserve logs and atomic completed files. |
| `03_coverage` | analysis-ready BAM, reportable/capture intervals | mosdepth files; WES HsMetrics; failed-region BED/TSV | Coverage failure blocks a negative report and is propagated to all drafts. |
| `04_deepvariant` | BAM, FASTA, regions, assay model | raw gVCF if enabled, raw VCF, caller-filtered VCF, logs | Caller failure prevents consensus; no two-caller degraded clinical mode. |
| `05_haplotypecaller` | BAM, FASTA, regions, ploidy map | raw VCF, caller-filtered VCF, logs | Same as above. |
| `06_octopus` | BAM, FASTA, regions, ploidy map, forest | raw VCF, forest-filtered VCF, logs | Same as above. |
| `07_consensus` | three caller VCF pairs, BAM, FASTA, model/context bundle | normalized provenance VCFs, evidence TSV/JSON, evidence VCF, high-confidence VCF, review VCF, conflict report | Any dropped/untraceable record or model mismatch is fatal. |
| `08_annotation` | high-confidence and review VCFs, VEP cache/resources | annotated VCF, transcript-level TSV/JSON, resource coverage report | Core-resource absence is fatal; optional-layer absence is explicit and non-silent. |
| `09_acmg` | structured annotations, phenotype/case evidence, ACMG resources | raw outputs from both tools, criterion evidence ledger, comparison, preliminary class | Tool failure blocks preliminary classification but not the technical report. |
| `10_report` | all metrics, evidence, provenance, limitations | clinical review draft, technical report, coverage/consensus/variant reports | Never emit a complete/negative clinical draft with unresolved blocking flags. |

All modules write to a temporary sibling path, validate the result, then rename it
atomically. A `.complete` marker contains input/output checksums and the exact
module signature. Resume is permitted only when that signature matches.

## 6. Repository and run layout

```text
ClinicalSuite/
├── Architecture.md
├── README.md
├── CHANGELOG.md
├── run.sh
├── config/
│   ├── clinical.conf.example
│   ├── samples.tsv.example
│   └── schemas/
├── bin/
│   ├── common.sh
│   ├── preflight.sh
│   ├── qc.sh
│   ├── alignment.sh
│   ├── coverage.sh
│   ├── call_deepvariant.sh
│   ├── call_haplotypecaller.sh
│   ├── call_octopus.sh
│   ├── consensus.py
│   ├── annotate.sh
│   ├── acmg.sh
│   └── report.py
├── containers/
│   ├── definitions/
│   ├── checksums.sha256
│   ├── versions.lock
│   ├── qc.sif
│   ├── alignment.sif
│   ├── gatk.sif
│   ├── octopus.sif
│   ├── deepvariant.sif
│   ├── annotation.sif
│   └── report.sif
├── references/
│   └── README.md
├── databases/
│   └── README.md
├── validation/
│   ├── README.md
│   ├── expected/
│   ├── fixtures/
│   └── scripts/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── smoke/
└── docs/
    ├── scientific-decisions.md
    ├── validation-plan.md
    └── operations.md
```

Patient runs are outside the source tree:

```text
RUN_ID/
├── resolved_config/
├── qc/
├── alignment/
├── coverage/
├── callers/{deepvariant,gatk,octopus}/
├── consensus/
├── annotation/
├── acmg/
├── reports/
├── logs/
├── provenance/
└── tmp/
```

## 7. Runtime and HPC architecture

The host runtime requires Bash 4.4+ and Apptainer only, plus ordinary POSIX core
utilities invoked by the shell. There is no runtime Conda environment and no
Python requirement on the host. Python runs only inside `report.sif` or
`annotation.sif` for the consensus, annotation support, ACMG, and report modules.

`run.sh` is a strict, scheduler-neutral orchestrator. A user may submit it from
Slurm, PBS, LSF, or an interactive node; scheduler commands are not embedded in
the scientific workflow. Configuration supplies threads, memory, scratch, and
caller concurrency. The workflow uses:

- interval scatter/gather only where the tool officially supports deterministic
  gathering;
- DeepVariant native sharding;
- bounded background concurrency with explicit PID/exit-status collection;
- no nested oversubscription;
- local node scratch when configured, with checksum-verified staging; and
- signal traps that stop children and leave diagnosable, non-final temporary files.

The same resolved command is recorded whether run locally or under a scheduler.
Locale, timezone used in outputs, umask, thread counts, Java heap, and random seeds
are explicit. Re-running identical locked inputs must be reproducible within each
tool's documented determinism; byte identity is tested where practical and
semantic VCF identity otherwise.

## 8. Container strategy

Every scientific executable runs in one of the requested SIFs:

| Image | Contents/role |
|---|---|
| `qc.sif` | FastQC, fastp, MultiQC |
| `alignment.sif` | BWA-MEM2, Samtools, Picard, mosdepth |
| `gatk.sif` | GATK plus bcftools/htslib used for VCF validation and normalization |
| `octopus.sif` | Octopus and its pinned germline forest |
| `deepvariant.sif` | Apptainer conversion of the official stable CPU OCI image |
| `annotation.sif` | Ensembl VEP/plugins, InterVar, AutoACMG and their language runtimes; data remain external |
| `report.sif` | Pinned Python environment for consensus, VRS, validation helpers, and reporting |

Each image is built from a reviewed definition or, for DeepVariant, a pinned OCI
digest. Floating tags such as `latest` are forbidden. `versions.lock` records the
upstream version, source URL, source/container digest, build date, definition
checksum, licenses, and validation status. SIF SHA-256 values are verified during
preflight and recorded per run. No Conda activation occurs inside or outside the
images; final images contain only the resolved runtime environment.

Images are read-only. The reference and database roots are bound read-only,
the run directory read-write, and scratch read-write. Host home is not required.
Network access is disabled during analysis. GPU DeepVariant is deferred until a
separate image and equivalence/performance validation are approved; CPU is the
simple default.

## 9. Configuration philosophy

Configuration has three small, validated inputs:

1. a non-executable `KEY=VALUE` site/run file parsed from an allowlist;
2. a tab-delimited sample manifest with fixed columns; and
3. versioned reference/database manifests with checksums and compatibility keys.

The sample manifest includes sample ID, assay (`WGS`/`WES`), platform
(`ILLUMINA`/`GENEMIND`), FASTQ pair, library, lane/platform unit, center,
read-group ID, expected chromosome complement when applicable, capture interval,
and reportable interval. Paths are absolute after resolution. Unknown keys,
duplicate sample IDs, unsafe identifiers, or missing columns are fatal.

Defaults encode operational behavior, not unvalidated clinical thresholds.
Clinical QC thresholds, calling intervals, filter cutoffs, and consensus model
must come from a named, versioned, approved assay profile. The resolved
configuration is immutable and copied into the run. Command-line overrides are
limited, validated, and recorded; no hidden environment variable may change a
scientific parameter.

## 10. Validation strategy and release gates

### 10.1 Software checks after every module

- Bash: `bash -n` and ShellCheck with documented, narrow suppressions;
- Python: compilation, formatting/lint checks, type checks where useful, and unit
  tests;
- fixture tests for success, malformed inputs, missing resources, interrupted
  writes, resume signatures, and paths containing spaces;
- VCF/BAM validation, indexes, checksums, sample/contig identity, and expected
  metadata; and
- a minimal end-to-end smoke test.

`./run.sh` with databases absent must stop in preflight, list all missing required
references/databases once, produce no traceback or shell diagnostic, and perform
no partial analysis.

### 10.2 Container checks

Every image must pass executable presence and version checks, including the
specified examples. Results, exit codes, SIF hashes, and timestamps are written to
`container_validation_report.txt`. A container cannot be released if its reported
version differs from `versions.lock` or a tool writes an unexpected error while
returning zero.

At minimum, validation invokes:

```bash
apptainer exec containers/qc.sif fastqc --version
apptainer exec containers/qc.sif fastp --version
apptainer exec containers/qc.sif multiqc --version
apptainer exec containers/alignment.sif bwa-mem2 version
apptainer exec containers/alignment.sif samtools --version
apptainer exec containers/alignment.sif mosdepth --version
apptainer exec containers/gatk.sif gatk --version
apptainer exec containers/gatk.sif bcftools --version
apptainer exec containers/octopus.sif octopus --help
apptainer exec containers/deepvariant.sif run_deepvariant --help
apptainer exec containers/annotation.sif vep --help
apptainer exec containers/report.sif python --version
```

Picard, the Octopus forest, DeepVariant model metadata, VEP plugins, VRS library,
InterVar, AutoACMG, and report-library imports receive additional targeted checks;
a binary version command alone does not validate models or data compatibility.

### 10.3 Analytical and scientific validation

The initial validation matrix includes:

- multiple GIAB reference materials, keeping specimens/replicates used to fit the
  consensus model separate from held-out evaluation;
- GIAB v4.2.1 GRCh38 small-variant truth and confident regions for autosomes,
  plus current medically relevant gene and HG002 X/Y benchmarks where applicable
  [7,22];
- actual WGS and each supported WES capture assay at representative lower/nominal/
  upper coverage;
- actual Illumina and GeneMind instrument/chemistry/library combinations;
- within-run, between-run, operator, reagent-lot, and compute-node reproducibility;
- previously characterized clinical samples and difficult local variants not
  adequately represented in GIAB; and
- contamination, sample swap, low coverage, adapter contamination, and missing-
  database challenge cases.

hap.py with vcfeval is the primary GA4GH-compatible comparator. Results are
stratified by SNV/indel, indel length, genotype, chromosome/ploidy, reportable
range, GC, homopolymer/tandem repeat, low complexity, segmental duplication,
mappability, MHC, and other GIAB stratifications. Overall F1 is never the sole
release metric. False positives and false negatives in clinically important genes
receive manual root-cause review.

The laboratory defines acceptance criteria before testing. At minimum, each caller
and consensus is compared with DeepVariant alone, and changes are assessed for
precision, sensitivity, genotype accuracy, no-call behavior, difficult regions,
and reproducibility. A release requires documented approval of:

- reportable range and limitations;
- assay/platform-specific performance claims with confidence intervals;
- QC and coverage thresholds;
- consensus model calibration and locked threshold;
- annotation correctness on a curated variant fixture set;
- ACMG evidence extraction concordance against expert-curated examples; and
- full traceability from every report statement to source evidence.

Any tool, model, container, parameter, reference, database schema, VEP cache, or
clinical rule update enters change control. Risk assessment determines regression
scope; a major caller/reference/model change requires analytical revalidation.
In-silico specimens may support update validation but do not replace appropriate
physical reference materials [38].

## 11. Critical self-review and implementation gates

This design is intentionally not approved for clinical production. The following
issues must be resolved empirically:

1. **Consensus evidence gap.** There is no current clinical recommendation for
   this exact three-caller ensemble. The model and confidence threshold must be
   trained without leakage and beat or meet a prespecified DeepVariant baseline on
   held-out WGS, WES, platform, and difficult-region data. Otherwise consensus is
   review-only.
2. **Octopus evidence and maintenance.** Its method is strong, but recent
   independent clinical and GeneMind evidence is limited and its distributed
   forest is an assay-transfer risk. Container buildability, release activity,
   forest calibration, and incremental value are gates. Failure removes Octopus
   only after a documented comparison and triggers redesign/revalidation.
3. **GeneMind transferability.** One favorable platform benchmark does not validate
   DeepVariant's Illumina model or the full proposed ensemble on GeneMind. Native
   data and characterized samples are mandatory before support is advertised.
4. **Preprocessing ablations.** fastp pass-through versus validated adapter
   trimming, and marked-duplicate versus BQSR input for each caller, must be tested.
   The simpler, better-validated branch becomes the locked profile.
5. **Representation complexity.** VRS handles canonical allele identity, but
   unphased compound calls still need local haplotype reconciliation. Fixtures must
   prove that decomposition, phasing, genotype, and provenance are not corrupted.
6. **ACMG automation.** InterVar is old and subset-based; AutoACMG is new and
   subset-based. Their presence satisfies decision-support and comparison needs,
   not clinical classification. Expert review and a complete evidence ledger are
   non-negotiable.
7. **Incomplete variant spectrum.** The current scope omits clinically important
   CNV/SV/STR/mtDNA classes. Reports must say so; “clinical-grade germline variant
   discovery” is not an acceptable unqualified claim for V2's first release.
8. **Licenses and freshness.** OMIM and some other resources have access or
   redistribution constraints. A site must supply lawful data. Database freshness
   policy and reanalysis policy require governance outside the code.

The architecture is suitable to begin only the repository skeleton and preflight
module. Scientific calling, consensus, annotation, and ACMG modules remain blocked
until their versioned decision records, test fixtures, and acceptance criteria are
approved module by module.

## 12. Sources

1. ACMG, [Clinical laboratory standards for next-generation sequencing](https://pmc.ncbi.nlm.nih.gov/articles/PMC4098820/).
2. ACMG, [Next-generation sequencing for constitutional variants in the clinical laboratory: 2021 revision](https://www.nature.com/articles/s41436-021-01139-4).
3. AMP/CAP, [Standards and guidelines for validating NGS bioinformatics pipelines](https://www.amp.org/AMP/assets/File/pressreleases/2017/AMP_NGS_Informatics_Guideline_FINAL.pdf?pass=43).
4. Li et al., [Accuracy benchmark of the GeneMind GenoLab M sequencing platform for WGS and WES](https://pmc.ncbi.nlm.nih.gov/articles/PMC9308344/).
5. GA4GH, [Best practices for benchmarking germline small-variant calls](https://www.nature.com/articles/s41587-019-0054-x).
6. Zook et al., [An open resource for accurately benchmarking small variant and reference calls](https://www.nist.gov/publications/open-resource-accurately-benchmarking-small-variant-and-reference-calls).
7. NIST, [Genome in a Bottle resources](https://www.nist.gov/programs-projects/genome-bottle).
8. Chen et al., [fastp: an ultra-fast all-in-one FASTQ preprocessor](https://pmc.ncbi.nlm.nih.gov/articles/PMC6129281/).
9. GATK, [FASTQ QC and adapter-trimming discussion](https://gatk.broadinstitute.org/hc/en-us/community/posts/360062203391-Do-I-need-to-perform-fastqc-and-adapters-trimming-before-gatk-pipeline).
10. GATK, [Data pre-processing for variant discovery](https://gatk.broadinstitute.org/hc/en-us/articles/360035535912-).
11. GATK, [Single-sample germline short-variant discovery in DRAGEN mode](https://gatk.broadinstitute.org/hc/en-us/articles/4407897446939--How-to-Run-germline-single-sample-short-variant-discovery-in-DRAGEN-mode).
12. Behera et al., [Comprehensive genome analysis and variant detection at scale using DRAGEN](https://www.nature.com/articles/s41587-024-02382-1).
13. Poplin et al., [A universal SNP and small-indel variant caller using deep neural networks](https://doi.org/10.1038/nbt.4235).
14. Google, [DeepVariant repository and official images](https://github.com/google/deepvariant).
15. GATK, [Germline short variant discovery](https://gatk.broadinstitute.org/hc/en-us/articles/360035535932-Germline-short-variant-discovery-SNPs-Indels-).
16. GATK, [HaplotypeCaller documentation](https://gatk.broadinstitute.org/hc/en-us/articles/4405451272731-HaplotypeCaller).
17. Cooke et al., [A unified haplotype-based method for accurate and comprehensive variant calling](https://pubmed.ncbi.nlm.nih.gov/33782612/).
18. Barbitoff et al., [Systematic benchmark of state-of-the-art variant calling pipelines](https://pmc.ncbi.nlm.nih.gov/articles/PMC8862519/).
19. Google, [DeepVariant X/Y and haploid support](https://github.com/google/deepvariant/blob/r1.9/docs/deepvariant-haploid-support.md).
20. GATK, [HaplotypeCaller ploidy documentation](https://gatk.broadinstitute.org/hc/en-us/articles/30332006386459-HaplotypeCaller).
21. Octopus, [Individual germline calling and contig ploidy](https://luntergroup.github.io/octopus/docs/guides/models/individual/).
22. Wagner et al., [Small variant benchmark from complete X and Y assemblies](https://www.nature.com/articles/s41467-024-55710-z).
23. Samtools, [bcftools norm documentation](https://samtools.github.io/bcftools/bcftools#norm).
24. GA4GH, [Variation Representation Specification](https://www.ga4gh.org/product/variation-representation/).
25. GA4GH, [VRS normalization](https://vrs.ga4gh.org/en/1.3/impl-guide/normalization.html).
26. Yun et al., [Accurate, scalable cohort variant calls using DeepVariant and GLnexus](https://pmc.ncbi.nlm.nih.gov/articles/PMC8023681/).
27. GATK, [When VQSR cannot be used](https://gatk.broadinstitute.org/hc/en-us/articles/360037499012-I-am-unable-to-use-VQSR-recalibration).
28. Google, [DeepVariant filtering guidance](https://github.com/google/deepvariant).
29. Octopus, [Germline random-forest filtering](https://luntergroup.github.io/octopus/docs/guides/filtering/forest/).
30. Ensembl, [VEP cache and annotation sources](https://www.ensembl.org/info/docs/tools/vep/script/vep_cache.html).
31. Morales et al., [A joint NCBI and EMBL-EBI transcript set for clinical genomics and research](https://pubmed.ncbi.nlm.nih.gov/35388217/).
32. ClinGen SVI, [Calibration of computational tools and PP3/BP4 recommendations](https://pubmed.ncbi.nlm.nih.gov/36413997/).
33. ClinGen SVI, [Recommendations for interpreting the PVS1 criterion](https://pubmed.ncbi.nlm.nih.gov/30192042/).
34. Li and Wang, [InterVar](https://pmc.ncbi.nlm.nih.gov/articles/PMC5294755/).
35. AutoACMG, [Implementation documentation](https://auto-acmg.readthedocs.io/en/latest/).
36. ACMG/AMP, [Standards and guidelines for interpretation of sequence variants](https://pmc.ncbi.nlm.nih.gov/articles/PMC4544753/).
37. ClinGen SVI, [Variant classification guidance](https://www.clinicalgenome.org/tools/clingen-variant-classification-guidance/).
38. AMP/API/CAP, [Recommendations for use of in-silico approaches in NGS pipeline validation](https://www.guidelinecentral.com/guideline/2117214/).
39. FDA/NIST, [precisionFDA Truth Challenge V2: variants in difficult-to-map regions](https://www.fda.gov/media/160617/download).
