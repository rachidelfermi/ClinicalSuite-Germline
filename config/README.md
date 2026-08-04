# Configuration system

ClinicalSuite uses two non-executable, allowlisted inputs: `clinical.conf` and a
fixed-column `samples.tsv`. They are parsed as data by pure Bash; neither file is
sourced or evaluated. Unknown/duplicate keys and columns, missing fields, invalid
types, unsafe identifiers, and missing input files are reported together.

## Usage

```bash
cp config/clinical.conf.example config/clinical.conf
cp config/samples.tsv.example config/samples.tsv
$EDITOR config/clinical.conf config/samples.tsv

config/validate.sh --config config/clinical.conf --samples config/samples.tsv
```

Successful validation creates read-only normalized files at
`RUN_ROOT/RUN_ID/resolved_config/{clinical.conf,samples.tsv}`. Existing resolved
configuration is never overwritten. For diagnostics without writing files, add
`--check-only`. Future Bash modules source `config/parser.sh` and call
`clinical_validate`; validated configuration keys, `SAMPLES_TSV`, and `RUN_DIR`
are exported, while manifest values are exposed through the `CLINICAL_SAMPLES`
associative array as `sample_id.column` keys.

Relative configuration paths resolve against the directory containing
`clinical.conf`. Relative manifest paths resolve against the directory containing
`samples.tsv`. Resolved copies contain absolute paths.

`REFERENCE_DIR/reference_manifest.tsv` must declare the only supported V2
reference: `GRCh38_full_analysis_set_plus_decoy_hla.fa`, version
`GRCh38_full_analysis_set_plus_decoy_hla-20150309`. `REFERENCE_BUILD=GRCh38`
does not select among bundles; it names the assembly of this single locked
reference. From alignment onward, preflight rejects any other FASTA basename or
reference version.

## Supported configuration keys

| Key | Required | Default | Rule |
|---|---:|---|---|
| `RUN_ID` | yes | — | safe identifier |
| `RUN_ROOT` | yes | — | existing writable directory |
| `REFERENCE_DIR` | yes | — | existing readable directory containing the locked Broad GRCh38 Full Analysis Set + Decoy + HLA manifest |
| `DATABASE_DIR` | yes | — | existing readable directory |
| `ENV_DIR` | yes | — | existing readable directory containing validated environments and locks |
| `ASSAY_PROFILE_DIR` | yes | — | existing readable directory |
| `ASSAY_PROFILE` | yes | — | named/versioned safe identifier |
| `SCRATCH_DIR` | yes | — | existing writable directory |
| `MAMBA_BIN` | yes | — | executable Mamba used for integrity checks and environment maintenance |
| `REFERENCE_BUILD` | no | `GRCh38` | `GRCh38` only |
| `THREADS` | no | `8` | integer 1–1024 |
| `MEMORY_GB` | no | `32` | integer 1–65536 |
| `CALLER_CONCURRENCY` | no | `3` | integer 1–3 |
| `TIMEZONE` | no | `UTC` | `UTC` only |
| `LOCALE` | no | `C.UTF-8` | `C` or `C.UTF-8` |
| `FILE_UMASK` | no | `0027` | four octal digits |
| `MIN_RUN_FREE_GB` | no | `50` | integer 0–999999 |
| `MIN_SCRATCH_FREE_GB` | no | `100` | integer 0–999999 |
| `DISK_SPACE_POLICY` | no | `ERROR` | `ERROR` or `WARNING` |

These defaults are operational, not clinical thresholds. QC thresholds, calling
interval policy, filtering cutoffs, and consensus parameters are deliberately not
configuration keys here; they belong to the named, approved assay profile.

Module 6 reads `ASSAY_PROFILE_DIR/ASSAY_PROFILE/qc.conf`. The tracked
`config/assay_profiles/illumina-wgs-v1/qc.conf.example` documents the exact
allowlisted keys. A deployment must copy it to `qc.conf`, assign a versioned
profile identifier, and approve the read-count and FastQC review/block policies
under its own change-control process.

## Sample manifest

The exact twelve-column header is shown in `samples.tsv.example` and documented in
`schemas/samples.tsv.schema.tsv`. Columns may be reordered, but may not be missing,
duplicated, or extended. Identifiers allow ASCII letters, digits, `.`, `_`, and
`-`, and may not start with punctuation. `WGS` requires `capture_intervals=NA`;
`WES` requires a readable BED. No missing metadata are inferred.

Local `clinical.conf` and `samples.tsv` files are ignored by Git to reduce the risk
of committing site paths or patient/sample metadata.
