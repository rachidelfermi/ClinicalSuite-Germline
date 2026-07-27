# Preflight validation

`bin/preflight.sh` is the mandatory first runtime module. It validates inputs and
the execution environment, writes reports, and exits. It never starts scientific
analysis.

## Usage

```bash
bin/preflight.sh --config clinical.conf --samples samples.tsv \
  --stage VARIANT_FILTERING
./run.sh --config clinical.conf --samples samples.tsv --preflight-only
```

Valid configuration writes to `RUN_ROOT/RUN_ID/preflight`; `--output-dir` can
override this location. Exit status is `0` for a pass, `69` for validation
failure, `64` for CLI misuse, and `1` if reports cannot be produced.

`--stage` selects the last module whose complete runtime requirements must be
available. It accepts module numbers 6–16 or the names `QC`, `ALIGNMENT`,
`COVERAGE`, `DEEPVARIANT`, `HAPLOTYPECALLER`, `OCTOPUS`, `CONSENSUS`,
`VARIANT_FILTERING`, `ANNOTATION`, `ACMG`, and `REPORTING`. The development
default is `VARIANT_FILTERING` (Module 13).

Resources first consumed after the selected stage are reported as `INFO`. Their
absence, empty directories, checksum validation, executable validation, and
compatibility checks do not make preflight fail. Once the selected stage reaches
their first consumer, the manifest's `MANDATORY` or `OPTIONAL` policy applies.

## External resource manifests

Preflight reads `REFERENCE_DIR/reference_manifest.tsv` and
`DATABASE_DIR/database_manifest.tsv`. Exact columns are defined in
`config/schemas/`. Paths may be absolute or relative to their resource root.
Files carry SHA-256 values; directories use `-`. Versions are pinned and genomic
resources declare `GRCh38`. From Module 7 onward, `GRCH38_FASTA` must resolve to
`GRCh38_full_analysis_set_plus_decoy_hla.fa`; that FASTA, its FAI, dictionary,
BWA-MEM2 index, and PAR intervals must use version
`GRCh38_full_analysis_set_plus_decoy_hla-20150309`. This locks Broad GRCh38 Full
Analysis Set + Decoy + HLA as the only V2 alignment and calling reference.

From alignment onward, mandatory reference IDs are `GRCH38_FASTA`, `GRCH38_FASTA_FAI`,
`GRCH38_SEQUENCE_DICTIONARY`, `BWA_MEM2_INDEX`, `GRCH38_PAR_INTERVALS`,
`KNOWN_INDELS`, `KNOWN_INDELS_INDEX`, `MILLS_INDELS`, `MILLS_INDELS_INDEX`, and
the assay-specific `DEEPVARIANT_MODEL_WGS`/`DEEPVARIANT_MODEL_WES`. PAR and
DeepVariant models first become mandatory at Module 9.

At Module 14, mandatory annotation database IDs are `CLINVAR`, `CLINVAR_INDEX`, `DBSNP`, `DBSNP_INDEX`,
`GNOMAD`, `GNOMAD_INDEX`, `VEP_CACHE`, `LOFTEE`, `SPLICEAI`,
`SPLICEAI_INDEX`, and `DBNSFP`. Before Module 14 they are informational.
`REVEL` and IDs prefixed for ACMG/ClinGen/phenotype/interpretation use are
deferred until Module 15; `REVEL` remains optional and produces a warning when
absent at that stage. Additional database rows default to Module 14 unless their
ID identifies an ACMG-stage resource. Database rows record the compatible FASTA
SHA-256.

## Validation and reports

Checks cover Module 2 inputs and resolved identity, Bash/utilities, Apptainer,
permissions, FASTQ structure/pair names, intervals, SIF checksums and executable
versions, external-resource checksums, exact locked-reference compatibility, and
disk space.
Container executable/version expectations come directly from
`containers/lib.sh`, the same matrix used by Module 4 release validation.
`MIN_RUN_FREE_GB`, `MIN_SCRATCH_FREE_GB`, and `DISK_SPACE_POLICY` control the
operational free-space gate.

Outputs are written atomically:

- `preflight_report.txt`: human-readable aggregated result;
- `preflight.json`: schema-versioned input for later modules, including
  `execution_stage`, `execution_module`, and informational findings;
- `preflight.log`: plain-text shared-library log.
