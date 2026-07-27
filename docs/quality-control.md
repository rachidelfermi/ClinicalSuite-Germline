# Module 6 quality control

Module 6 validates raw paired-end FASTQ quality without changing read sequence,
quality, order, names, or pair membership. It runs only after Module 5 preflight
has completed successfully.

## Execution contract

```bash
./run.sh --config config/clinical.conf --samples config/samples.tsv
```

The launcher invokes `bin/qc.sh`, which:

1. reuses the Module 2 parser and Module 3 runtime helpers;
2. validates the selected `qc.conf` assay profile;
3. verifies the pinned `qc.sif` image and computes a complete input signature;
4. runs FastQC on both raw FASTQs;
5. runs fastp with adapter trimming, poly-G trimming, quality filtering, and
   length filtering disabled, discarding its sequence stream and retaining only
   JSON/HTML metrics;
6. verifies that fastp before/after read counts are identical and paired;
7. creates links to the unchanged source FASTQs;
8. runs MultiQC over FastQC and fastp results;
9. evaluates explicit profile policies as `PASS`, `REVIEW`, or `BLOCK`; and
10. writes checksums, provenance, and a signed completion marker before
    atomically publishing the result directory.

`BLOCK` exits with status 69. `REVIEW` is a successful software execution that
requires downstream operator review. An existing output is reused only when its
signature matches the module code, common library, parser, configuration,
manifest, profile, container, and both FASTQ checksums.

## Assay profile

The allowlisted keys are:

| Key | Rule |
|---|---|
| `PROFILE_ID` | must equal configured `ASSAY_PROFILE` |
| `PROFILE_VERSION` | non-empty version identifier |
| `SUPPORTED_ASSAYS` | comma-separated `WGS` and/or `WES` |
| `SUPPORTED_PLATFORMS` | comma-separated `ILLUMINA` and/or `GENEMIND` |
| `FASTP_MODE` | `PASS_THROUGH` only |
| `FASTQC_FAIL_POLICY` | `BLOCK` or `REVIEW` |
| `FASTQC_WARNING_POLICY` | `BLOCK` or `REVIEW` |
| `MIN_READ_PAIRS` | non-negative integer |

Unknown, duplicate, empty, or malformed values are rejected. The example is
`config/assay_profiles/illumina-wgs-v1/qc.conf.example`; it is a development
example, not a laboratory-approved clinical threshold set.

## Output contract

```text
RUN_DIR/qc/
├── .complete
├── commands.tsv
├── environment.tsv
├── final_fastq.tsv
├── logs/
│   ├── multiqc.stderr
│   ├── multiqc.stdout
│   └── qc.log
├── multiqc/
│   ├── multiqc_report.html
│   └── multiqc_report_data/
├── output_checksums.sha256
├── provenance.tsv
├── qc_status.tsv
└── samples/SAMPLE_ID/
    ├── fastp/
    ├── final/
    ├── logs/
    └── raw_fastqc/
```

`final_fastq.tsv` is the handoff contract for Module 7. Its paths are relative
to the QC directory and point to unchanged, structurally revalidated FASTQs.
`qc_status.tsv` records the aggregate FastQC failure/warning counts, paired-read
count, and decision for each sample.

This module provides software validation only. FastQC flags are not diagnoses,
and successful execution is not analytical validation of an assay.
