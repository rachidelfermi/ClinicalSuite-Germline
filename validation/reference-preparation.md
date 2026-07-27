# GRCh38 reference preparation status

Reference preparation began on 2026-07-24 using the locked Broad GATK hg38/v0
`Homo_sapiens_assembly38.fasta` analysis set (GRCh38,
`GCA_000001405.15`). No annotation database, known-sites VCF, truth set, or
trained model was downloaded.

## Verified artifacts

| Artifact | State | SHA-256 |
|---|---|---|
| `Homo_sapiens_assembly38.fasta` | downloaded and source-MD5 verified | `93157a161863464c9435062fd67c173fdaf99cb8b32f1455018361387ffa5564` |
| `Homo_sapiens_assembly38.fasta.fai` | generated with Samtools 1.24 | recorded locally |
| `Homo_sapiens_assembly38.dict` | generated with Picard 3.4.0 | recorded locally |
| `Homo_sapiens_assembly38.fasta.64.alt` | downloaded and source-MD5 verified | `d9254da07b8030e26129dc29d9d02b9c30a360b233a367ce041691c00407d510` |
| `GCA_000001405.15_GRCh38_assembly_regions.txt` | downloaded and SHA-256 verified | `6b91d2c7961a322936db8fd09b7fb4a9143a590882f28c0a628a4ef26897f6c7` |
| `GRCh38_PAR.bed` | derived; four 0-based half-open X/Y PAR rows | recorded locally |

The FASTA, `.fai`, and dictionary each contain 3,366 contigs. Exact immutable
source URLs, object generations, source digests, sizes, and local SHA-256
digests are in the ignored deployment artifact
`references/GRCh38/source_downloads.tsv`.

## Open blocker

The BWA-MEM2 2.3 index is not complete. The first local build was killed with
exit 137 after the host exhausted its 15 GiB RAM and 2 GiB swap. BWA-MEM2's
documented construction estimate is about 28 times the reference size; the
preparer now requires at least 96 GB physical RAM before starting the build.
All downloads, the failed build cache, and completed indexes were preserved.

Consequently, `reference_manifest.tsv`, the final `checksums.sha256`, and the
reference `.complete` marker have intentionally not been issued. Reference
preparation must be resumed on a host meeting the memory gate before Module 7
can be implemented or validated.

## Validation

`references/prepare_grch38.sh` passes `bash -n` and ShellCheck 0.10.0. A rerun
verified and reused the existing downloads, `.fai`, and dictionary, regenerated
the deterministic PAR file, then failed early at the memory gate without
starting another index process.
