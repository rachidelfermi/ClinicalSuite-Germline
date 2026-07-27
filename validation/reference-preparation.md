# Locked reference preparation status

On 2026-07-27, ClinicalSuite V2 locked Broad GRCh38 Full Analysis Set + Decoy +
HLA as its sole reference. The official 1000 Genomes distribution was used.
No annotation database, known-sites VCF, truth set, or trained model was
downloaded.

## Verified source artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `GRCh38_full_analysis_set_plus_decoy_hla.fa` | 3,263,683,042 | `3b103f4742abfd54938fb0333e19ad067635c8eb86f1dbf0ce44b165c4292b50` |
| `GRCh38_full_analysis_set_plus_decoy_hla.fa.alt` | 487,553 | `d9254da07b8030e26129dc29d9d02b9c30a360b233a367ce041691c00407d510` |
| `README.20150309.GRCh38_full_analysis_set_plus_decoy_hla` | 1,973 | `f8662c7ff1b9abdf986eca668559d38a509d4b65cc553b0fa2ee64fe3d217ea1` |
| `20150713_location_of_centromeres_and_other_regions.txt` | 1,300 | `998b492d65a60cc557735d90c9215bf934289f8040e4583bd4df8aa4c073c881` |

The FASTA contains 3,366 sequences and the expected `chr`, decoy, and HLA contig
classes. The source URL, locked size, source digest, and local digest are written
to the ignored deployment artifact `references/GRCh38/source_downloads.tsv`.

## Derived artifacts

The preparer generates the exact-name Samtools FAI, Picard dictionary,
pseudoautosomal BED, and BWA-MEM2 index. The FAI and dictionary must each contain
the same 3,366 sequences as the FASTA. The PAR file contains the GRCh38 PAR1 and
PAR2 intervals for both X and Y in 0-based, half-open coordinates.

| Derived artifact | SHA-256 |
|---|---|
| `GRCh38_full_analysis_set_plus_decoy_hla.fa.fai` | `f361f004bdae5ca68d632458b01a3848d02834ac7176f378e177344d148a6a6d` |
| `GRCh38_full_analysis_set_plus_decoy_hla.dict` | `222dd182767fba8fd9a94c39f79a6083b28cd555fd18c59ba4442fe9b045a7bb` |
| `GRCh38_full_analysis_set_plus_decoy_hla_PAR.bed` | `458b432da788109bd72cfb647ec3f61ffc067dc729af75153fb483012f2711a6` |

## Current host limitation

The BWA-MEM2 2.3 index is not complete on this development host. Its 15 GiB RAM
is below the preparer's 96 GB physical-memory gate. Verified source artifacts
and any completed lightweight indexes are preserved. The final
`reference_manifest.tsv`, `checksums.sha256`, and `.complete` marker are
intentionally withheld until indexing completes on a suitable build host.

This is a deployment-capacity limitation, not permission to use another
reference. Rerunning `references/prepare_grch38.sh` on a suitable host reuses all
verified artifacts and continues from the latest completed step.

## Validation contract

The preparer must pass Bash syntax, ShellCheck, locked-source verification,
contig-class/count checks, and deterministic rerun checks. Preflight additionally
rejects any other FASTA basename or reference identity from Module 7 onward.

Validation on 2026-07-27 passed Bash syntax, ShellCheck 0.10.0, source size and
SHA-256 checks, FAI/dictionary count checks, preflight unit/integration/real-SIF
smoke tests, configuration unit/smoke tests, and `git diff --check`. The
unsupported-basename and unsupported-version preflight fixtures both failed with
exit 69 as designed. A reference-preparer rerun reused the FAI and dictionary,
then stopped at the memory gate with exit 1 and no completion marker.
