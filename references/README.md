# External GRCh38 reference contract

ClinicalSuite uses one explicit analysis set for development and future pipeline
execution:

- **Assembly:** GRCh38 (`GCA_000001405.15`, no later patch sequences)
- **Analysis set:** Broad GATK hg38/v0 `Homo_sapiens_assembly38`
- **Contig naming:** `chr1`–`chr22`, `chrX`, `chrY`, `chrM`, ALT, decoy, and
  other non-primary contigs supplied by the locked analysis set
- **Source:** Broad public reference bucket, immutable Google object generation
  `1575676516681666`

Run `prepare_grch38.sh` to download only the FASTA and ALT-mapping metadata and
to generate indexes with the validated ClinicalSuite alignment container:

```bash
./references/prepare_grch38.sh
```

The default deployment path is `references/GRCh38/`. Downloads are resumable,
source size and MD5 are verified against the immutable object, and every final
artifact receives a SHA-256 checksum. Existing complete bundles are verified and
reused.

The script generates:

- Samtools 1.24 FASTA index;
- Picard 3.4.0 sequence dictionary;
- BWA-MEM2 2.3 release-asset indexes;
- ALT-contig mapping metadata;
- GRCh38 X/Y pseudoautosomal BED intervals derived from the NCBI assembly region
  report;
- `reference_manifest.tsv`;
- `source_provenance.tsv`; and
- `checksums.sha256`.

BWA-MEM2 documents a high peak-memory requirement for index construction. The
preparer therefore requires at least 96 GB of physical RAM before starting that
step. On smaller systems it preserves verified downloads and completed
Samtools/Picard/PAR artifacts, writes `source_downloads.tsv`, and exits with a
clear error. Rerunning on a suitable build host reuses those artifacts. A
complete `reference_manifest.tsv`, final checksum set, and `.complete` marker
are written only after the BWA-MEM2 index succeeds.

No annotation database, known-sites VCF, truth set, trained model, or assay
interval is downloaded by this reference preparation step.

## Expected contents

The final filenames are selected by the site profile and recorded in a manifest.
Deploy it as `REFERENCE_DIR/reference_manifest.tsv` using
`config/schemas/reference_manifest.schema.tsv`.
The following logical files are required:

| Logical item | Expected filename pattern | Version/compatibility requirement |
|---|---|---|
| GRCh38 FASTA | `GRCh38.fa` | One approved analysis set; sequence and contig set locked by SHA-256 |
| FASTA index | `GRCh38.fa.fai` | Generated from the exact FASTA with the pinned Samtools version |
| sequence dictionary | `GRCh38.dict` | Generated from the exact FASTA with the pinned Picard/GATK version |
| BWA-MEM2 indexes | `GRCh38.fa.*` | Generated from the exact FASTA with the pinned BWA-MEM2 version |
| known indels | `known_indels_GRCh38.vcf.gz` and `.tbi` | Site-approved GATK-compatible resource |
| Mills/1000G indels | `Mills_and_1000G_gold_standard.indels.GRCh38.vcf.gz` and `.tbi` | Site-approved GRCh38 release |
| PAR intervals | `GRCh38_PAR.bed` | Coordinates must match the selected FASTA and caller ploidy behavior |
| validation strata | `stratifications/*.bed.gz` | Versioned GIAB/GA4GH GRCh38 strata used only as declared |
| WES capture intervals | `assays/<ASSAY_ID>/capture.bed` | Exact manufacturer/laboratory capture design |
| WES reportable range | `assays/<ASSAY_ID>/reportable.bed` | Laboratory-approved clinical reportable range |

## Required manifest fields

Each item must record logical name, absolute deployment path, release/version,
assembly, contig naming convention, source provenance, SHA-256, index relationships,
license/access notes, approval state, and approval date.

Preflight reports all absent or incompatible items together and exits before
analysis. DeepVariant model directories are declared as
`DEEPVARIANT_MODEL_WGS`/`DEEPVARIANT_MODEL_WES` and remain external to SIFs.
Files placed here locally are ignored by git except for this README.

Known indels, Mills/1000G indels, DeepVariant models, validation strata, and
assay-specific interval files remain separate future deployment inputs. They are
not part of the FASTA/index preparation script. Annotation resources such as
ClinVar, dbSNP, gnomAD, VEP cache, LOFTEE, REVEL, SpliceAI, and dbNSFP are
explicitly outside the current preparation scope.
