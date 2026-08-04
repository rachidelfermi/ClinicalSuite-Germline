# Locked ClinicalSuite V2 reference

ClinicalSuite V2 supports exactly one reference genome bundle:

- **Name:** Broad GRCh38 Full Analysis Set + Decoy + HLA
- **FASTA:** `GRCh38_full_analysis_set_plus_decoy_hla.fa`
- **ClinicalSuite identity:**
  `GRCh38_full_analysis_set_plus_decoy_hla-20150309`
- **Assembly:** GRCh38 (`GCA_000001405.15`)
- **Contig naming:** `chr1`–`chr22`, `chrX`, `chrY`, `chrM`
- **Additional sequence classes:** unlocalized, unplaced, ALT, patch, decoy,
  and HLA
- **FASTA SHA-256:**
  `3b103f4742abfd54938fb0333e19ad067635c8eb86f1dbf0ce44b165c4292b50`
- **Official distribution:** [1000 Genomes GRCh38 reference directory](https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/)
- **Source description:** [official bundle README](https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/GRCh38_reference_genome/README.20150309.GRCh38_full_analysis_set_plus_decoy_hla)

No alternate GRCh38 FASTA or deployment-selected bundle is supported. Alignment,
variant calling, consensus, filtering, and their validation must use derivatives
of this exact 3,366-contig FASTA.

## Preparation

Run:

```bash
./references/prepare_grch38.sh
```

The preparer downloads only the locked FASTA and its official ALT, source README,
and regions metadata. Every source has a pinned byte size and SHA-256. Downloads
are resumable and verified before reuse.

The validated alignment environment generates:

- `GRCh38_full_analysis_set_plus_decoy_hla.fa.fai` with Samtools 1.24;
- `GRCh38_full_analysis_set_plus_decoy_hla.dict` with Picard 3.4.0;
- `bwa-mem2/` indexes with BWA-MEM2 2.3 and the official `.fa.alt`; and
- `GRCh38_full_analysis_set_plus_decoy_hla_PAR.bed`.

The final bundle also contains:

- `reference_manifest.tsv`;
- `source_provenance.tsv`;
- `checksums.sha256`; and
- `.complete`.

BWA-MEM2 indexing has a high peak-memory requirement. The preparer requires at
least 96 GB of physical RAM before starting that step. On smaller hosts it
preserves verified downloads and completed Samtools/Picard/PAR artifacts, writes
`source_downloads.tsv`, and exits clearly. A final manifest, checksum inventory,
and completion marker are issued only after BWA-MEM2 succeeds.

## Runtime contract

Deploy `reference_manifest.tsv` at `REFERENCE_DIR/reference_manifest.tsv` using
`config/schemas/reference_manifest.schema.tsv`. The five bundle-defining rows
`GRCH38_FASTA`, `GRCH38_FASTA_FAI`, `GRCH38_SEQUENCE_DICTIONARY`,
`BWA_MEM2_INDEX`, and `GRCH38_PAR_INTERVALS` must all declare version
`GRCh38_full_analysis_set_plus_decoy_hla-20150309`.

From Module 7 onward, preflight checks the exact FASTA basename, reference
identity, checksums, assembly, and index consistency. A different reference is a
compatibility failure.

Assay-specific capture/reportable intervals, trained caller models, known-sites
resources, and validation strata remain separate versioned deployment inputs.
They must match this FASTA and are never inferred.

## Excluded resources

Reference preparation does not download annotation or interpretation resources.
In particular, it does not acquire ClinVar, dbSNP, gnomAD, VEP cache, LOFTEE,
REVEL, SpliceAI, dbNSFP, CADD, or ACMG resources. It also does not download GIAB
truth sets. Those resources remain external and stage-gated.

Large local reference artifacts are ignored by Git; this contract and the
reproducible preparer are tracked.
