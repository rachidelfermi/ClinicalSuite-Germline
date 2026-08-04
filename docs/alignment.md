# Module 7 alignment and BAM processing

Module 7 converts the immutable FASTQ handoff from Module 6 into a validated,
analysis-ready BAM. It implements only alignment and BAM preprocessing; coverage
analysis and variant calling remain outside this module.

## Scientific contract

For every sample, `bin/alignment.sh` executes:

1. BWA-MEM2 paired-end alignment with the manifest read group, a fixed
   100,000,000-base input batch (`-K`) for deterministic thread-independent
   output, and `-Y` supplementary soft clipping;
2. streaming SAM-to-uncompressed-BAM conversion and coordinate sorting;
3. indexing of the coordinate-sorted BAM;
4. Picard MarkDuplicates with duplicate removal disabled;
5. GATK BaseRecalibrator with the locked, assembly-matched Broad known-indel and
   Mills resources;
6. GATK ApplyBQSR;
7. explicit final BAM indexing; and
8. strict analysis-ready BAM validation.

This ordering follows GATK data preprocessing: map and coordinate sort, mark
duplicates, then create and apply the BQSR model. Picard marks duplicate records
instead of deleting evidence. Read-group values come only from the validated
sample manifest.

## Inputs

- validated `clinical.conf` and `samples.tsv`;
- a complete Module 6 directory whose checkpoint and every published checksum
  verify;
- Broad `GRCh38_full_analysis_set_plus_decoy_hla.fa`, identity
  `GRCh38_full_analysis_set_plus_decoy_hla-20150309`;
- the matching FAI, sequence dictionary, BWA-MEM2 index including the official
  ALT map, and pinned Broad GRCh38 known-indel VCFs plus indexes; and
- the validated `alignment` Conda environment and its explicit lock.

The module verifies all manifest file checksums, reference identity, first-contig
agreement, the 3,366-contig locked-reference invariant, and every required
BWA-MEM2 index component before starting. A Module 6 `BLOCK` decision is fatal;
`REVIEW` is logged and propagated.

## Output contract

```text
RUN_DIR/alignment/
├── .complete
├── commands.tsv
├── environment.tsv
├── output_checksums.sha256
├── provenance.tsv
├── tool_versions.tsv
├── checkpoints/
├── logs/alignment.log
└── samples/SAMPLE_ID/
    ├── SAMPLE_ID.sorted.bam
    ├── SAMPLE_ID.sorted.bam.bai
    ├── SAMPLE_ID.duplicates_marked.bam
    ├── SAMPLE_ID.duplicates_marked.bai
    ├── SAMPLE_ID.duplicate_metrics.txt
    ├── SAMPLE_ID.recal.table
    ├── SAMPLE_ID.analysis_ready.bam
    ├── SAMPLE_ID.analysis_ready.bam.bai
    ├── logs/
    └── validation/
        ├── header.sam
        ├── picard_validate_summary.txt
        ├── samtools.flagstat.txt
        ├── samtools.idxstats.txt
        ├── samtools.stats.txt
        └── validation.tsv
```

Validation requires Samtools quickcheck, flagstat, stats and idxstats; strict
Picard ValidateSamFile with exhaustive index validation; coordinate sort order;
the exact configured read group; a populated BQSR report; duplicate metrics; and
preservation of primary-read and duplicate-flag counts across BQSR.

## Checkpoint and failure behavior

Each of the seven execution stages has a signature-bound SHA-256 checkpoint.
An interrupted run resumes only if its module/configuration/input/reference/
environment signature still matches and every checkpointed artifact verifies.
Invalid step outputs are regenerated without deleting valid earlier steps.

Final publication is an atomic sibling-directory rename. Every file is included
in `output_checksums.sha256`, the completion marker binds the run signature, and
published files become read-only. An incompatible existing output or work
directory is rejected rather than overwritten.

This is software validation infrastructure. Approval of Module 7 does not by
itself establish analytical sensitivity, specificity, reportability, or clinical
fitness for a particular WGS/WES assay.
