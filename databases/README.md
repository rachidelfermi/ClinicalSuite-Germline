# External database contract

ClinicalSuite does not download, redistribute, or silently update annotation or
interpretation databases. A site supplies lawful, versioned, checksum-locked data
and mounts it read-only. Database age and missing layers must be visible in every
applicable report.

## Expected resource layout

Exact releases are frozen by the approved assay profile. Placeholders below show
the required naming convention; `<VERSION>` is never resolved to `latest`.
Deploy declarations as `DATABASE_DIR/database_manifest.tsv` using
`config/schemas/database_manifest.schema.tsv`; each row includes the compatible
GRCh38 FASTA SHA-256.

| Resource | Expected path or filename | Role |
|---|---|---|
| Ensembl VEP cache | `vep/<ENSEMBL_RELEASE>_GRCh38/` | Core offline consequence annotation; cache release must equal VEP release |
| VEP plugins | `vep/Plugins_<VERSION>/` | Pinned, individually validated plugins |
| gnomAD genomes | `gnomad/gnomad.genomes.<VERSION>.sites.GRCh38.vcf.bgz` | Population frequency |
| gnomAD exomes | `gnomad/gnomad.exomes.<VERSION>.sites.GRCh38.vcf.bgz` | Population frequency |
| gnomAD constraint | `gnomad/constraint_metrics.<VERSION>.tsv.gz` | LOEUF gene context |
| dbSNP | `dbsnp/dbsnp_<BUILD>_GRCh38.vcf.gz` | Variant identifiers only |
| ClinVar | `clinvar/clinvar_<YYYYMMDD>_GRCh38.vcf.gz` | Clinical assertions with review metadata |
| ClinGen | `clingen/<DATASET>_<VERSION>.*` | Gene-disease validity and expert specifications |
| HGNC | `hgnc/hgnc_complete_set_<YYYYMMDD>.txt` | Approved gene identifiers |
| HPO | `hpo/hp_<VERSION>.obo` and association files | Structured phenotype relationships |
| PanelApp | `panelapp/panels_<VERSION>.json` | Reviewed panel/gene context |
| MANE | `mane/MANE.GRCh38.<VERSION>.*` | Select and Plus Clinical transcripts |
| APPRIS | `appris/appris_human_<VERSION>.*` | Transcript context |
| REVEL | `predictors/revel_<VERSION>.*` | Calibrated missense evidence input |
| SpliceAI | `predictors/spliceai_<VERSION>.vcf.gz` | Splicing prediction evidence input |
| CADD | `predictors/cadd_<VERSION>_GRCh38.tsv.gz` | Supporting functional context |
| LOFTEE | `predictors/loftee_<VERSION>/` | Loss-of-function annotation support |
| dbNSFP | `predictors/dbnsfp_<VERSION>.gz` | Predictor source data; correlated scores are not independent evidence |
| GERP++/phyloP | `conservation/<RESOURCE>_<VERSION>.*` | Conservation context only |
| OMIM | `licensed/omim_<VERSION>.*` | Licensed disease knowledge |
| GeneReviews | `disease/genereviews_<VERSION>.*` | Disease review context |
| DECIPHER | `licensed/decipher_<VERSION>.*` | Licensed rare-disease context |
| Orphanet | `disease/orphanet_<VERSION>.*` | Rare-disease context |
| InterVar data | `acmg/intervar_<VERSION>/` | Preliminary ACMG decision support |
| AutoACMG services/data | `acmg/autoacmg_<VERSION>/` | Fully local SeqRepo and pinned local service data only |

Every tabix-queryable VCF must have its matching index. All data must match GRCh38
and the reference bundle's contig convention. Licensed resources are optional
until lawfully supplied but their absence is never concealed. AutoACMG must not
send patient variant coordinates to public endpoints.

Preflight treats ClinVar, dbSNP, gnomAD, VEP cache, LOFTEE, SpliceAI, and
dbNSFP as mandatory minimum resources beginning at Module 14. Before annotation
they are informational and cannot block variant discovery through Module 13.
ACMG-stage resources are informational until Module 15. REVEL is optional when
Module 15 is selected. Additional database rows default to Module 14 unless
their identifier marks an ACMG/interpretation resource.

Files placed here locally are ignored by git except for this README.
