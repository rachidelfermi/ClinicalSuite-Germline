# Module 6 quality-control validation

Validated on 2026-07-24 with the pinned `qc.sif` image and the approved HG002
development fixture. The work is software validation, not analytical or
scientific benchmarking.

## Commands and results

```bash
bash tests/unit/test_qc.sh
# PASS: QC unit tests

bash tests/integration/test_qc.sh
# PASS: QC integration test

bash tests/smoke/test_qc_hg002.sh
# PASS: HG002 QC smoke test
```

The integration test used one synthetic paired record and the real container.
It verified FastQC HTML/ZIP output, fastp JSON/HTML output, MultiQC aggregation,
final FASTQ handoff, and a no-work checkpoint rerun.

The smoke test executed `run.sh`, including preflight, against 50,000 HG002
read pairs. It produced two FastQC HTML files, two FastQC ZIP files, fastp
JSON/HTML, and MultiQC HTML/data. Output checksums verified successfully.

## HG002 result

```text
sample_id  fastqc_failures  fastqc_warnings  read_pairs  decision
HG002      1                3                50000       REVIEW
```

The result is intentionally `REVIEW` under the development profile. It confirms
policy routing and does not assert biological acceptability.

The complete launcher smoke test took 70.52 seconds wall-clock and reached a
maximum resident set size of 1,246,212 KiB. Module 6's internal timer reported
13 seconds; the remaining time was preflight container validation.

## Static validation

All repository Bash files pass `bash -n`. Module 6, its launcher integration,
reference preparer, and affected tests pass ShellCheck 0.10.0. `git diff
--check` also passes.

No QC container, scientific workflow after QC, reference database, annotation
database, or trained model was changed or downloaded by Module 6.
