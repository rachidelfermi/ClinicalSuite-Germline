# Module 7 independent revalidation

Date: 2026-07-31

The pre-existing Module 7 implementation and tests were treated as untrusted.
The implementation and all three test levels were independently replaced after
review against Architecture.md, GATK preprocessing and tool documentation.

## Scientific assessment

The accepted workflow boundary is BWA-MEM2 alignment, SAM-to-BAM conversion,
coordinate sorting/indexing, Picard duplicate marking, BaseRecalibrator,
ApplyBQSR, final indexing, and analysis-ready BAM validation. It neither trims
reads nor performs coverage or variant calling.

The implementation deliberately:

- preserves duplicates and records Picard metrics;
- uses a fixed BWA input batch and the manifest read group;
- retains both sorted and duplicate-marked pre-BQSR BAMs for audit;
- leaves GATK's default covariates and read filters intact;
- uses only assembly-matched known polymorphism resources declared in the
  reference manifest; and
- applies the recalibration table to the same duplicate-marked BAM from which it
  was learned.

## Defects found in the untrusted implementation

1. GATK and Picard commands referenced files that were not mounted.
2. Reference checksums were parsed but never checked.
3. Known-site versions were incorrectly forced to equal the FASTA version.
4. An unused PAR resource was required while the BQSR resource contract was
   incomplete.
5. Raw sample-manifest FASTQs bypassed the Module 6 handoff.
6. Container parameters and a BAM validation function were dead code.
7. Validation was limited to quickcheck; read counts, read groups, sort order,
   duplicate marking, BQSR, statistics, and strict Picard validation were absent.
8. The final checksum inventory included itself and could never be immutable.
9. There were no safely reusable per-step checkpoints.
10. A read-group argument used literal tab characters. BWA-MEM2 copied them into
    its `@PG CL` field, producing a malformed SAM header rejected by HTSJDK.
11. GATK created an undeclared implicit BAM index in addition to the explicit
    final index.
12. The “integration” test mocked Apptainer, used dummy images and fake/empty
    BAMs, and contained unevaluated checksum substitutions. The smoke test only
    exercised `--help`.
13. The previously deployed local BWA-MEM2 index was interrupted: its checksum
    inventory was written while two files were still growing, and BWA-MEM2
    failed to load it with `Unexpected end of file`. It is not used by the
    replacement implementation or validation.
14. `run.sh` neither invoked Module 7 nor selected `ALIGNMENT` for stage-aware
    preflight, so the module was not part of the supported launcher path.

## Replacement test model

- Unit tests validate exact escaped read-group construction, manifest/checksum
  rejection, path safety, QC handoff integrity, and corruption-aware checkpoints.
- Integration testing executes the real images on a deterministic random
  reference with real BAM, BAI, VCF/TBI, duplicate, BQSR and validation outputs.
- Smoke testing executes the approved 50,000-pair HG002 fixture against the exact
  locked full reference, runs strict validation, executes a second independent
  run, compares deterministic scientific artifacts, and tests published
  checkpoint reuse.

## Validation status

Unit and real-container synthetic integration testing pass. Bash syntax,
ShellCheck 0.11.0, and whitespace validation pass for the replacement files.
The project-generated HPC BWA-MEM2 index for the locked Broad GRCh38 Full
Analysis Set + Decoy + HLA has replaced the unusable local index as the sole
production index. Its FASTA identity, 3,366-contig FAI, index inventory, and all
declared SHA-256 checksums pass verification. The full HG002 run is in progress;
Module 7 remains unapproved until its BAM validation, checkpoint reuse, and
reproducibility checks pass.

## Evidence reviewed

- Broad GATK, *Data pre-processing for variant discovery*:
  <https://gatk.broadinstitute.org/hc/en-us/articles/360035535912-Data-pre-processing-for-variant-discovery>
- GATK BaseRecalibrator and ApplyBQSR tool documentation:
  <https://gatk.broadinstitute.org/hc/en-us/articles/30332011267355-BaseRecalibrator>
  and
  <https://gatk.broadinstitute.org/hc/en-us/articles/9570337264923-ApplyBQSR>
- Picard command documentation and validation guidance:
  <https://broadinstitute.github.io/picard/command-line-overview.html> and
  <https://broadinstitute.github.io/picard/faq>
- BWA-MEM2 upstream documentation and acceleration paper:
  <https://github.com/bwa-mem2/bwa-mem2> and
  <https://arxiv.org/abs/1907.12931>
- GA4GH SAM/BAM specification landing page:
  <https://www.ga4gh.org/product/sam-bam/>
- NIST GIAB HG002 BWA-MEM2/BQSR implementation evidence:
  <https://github.com/usnistgov/giab-HG002-mosaic-benchmark>
- Shafin et al., *Short-read aligner performance in germline variant
  identification*, Bioinformatics 2023:
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC10421969/>
