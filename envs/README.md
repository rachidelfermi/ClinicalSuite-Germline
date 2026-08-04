# Conda runtime environments

ClinicalSuite uses isolated Conda environments built exclusively with
Mamba. Pipeline launchers select the required environment automatically; users
must not activate environments manually.

| Environment | Runtime scope |
|---|---|
| `qc` | FastQC, fastp, MultiQC, and headless font support |
| `alignment` | BWA-MEM2, Samtools, Picard, mosdepth, and GATK BQSR |
| `variant` | GATK, bcftools/HTSlib, and Samtools for calling/normalization |
| `deepvariant` | DeepVariant and its Java 11 runtime |
| `octopus` | Octopus with its compatible HTSlib runtime |
| `annotation` | Ensembl VEP runtime only; caches/plugins remain external |
| `report` | Python and pinned reporting libraries |

Build, validate, freeze, and pack all environments:

```bash
MAMBA_BIN=/path/to/mamba CONDA_PACK_BIN=/path/to/conda-pack ./envs/build.sh
```

The build sequence is strict: `mamba create`/`mamba install`, executable and
dependency validation, explicit lock generation, resolved YAML export, then
`conda-pack`. An environment is never packed before all validation checks pass.

Bioconda's DeepVariant 1.10.0 recipe omits the executable ZIP payloads.
`build_deepvariant_runtime.sh` therefore extracts the byte-identical ZIPs from
the already validated official CPU payload
`google/deepvariant@sha256:962e5a83b1d76aae6990625d47102785f791603f2138aa1fa9aa4fb6a2eecbe6`,
creates a relocation-only launcher package, and installs it with Mamba. The
helper uses `unsquashfs`; it does not execute a container. Models are excluded.

`*.lock`, `*.yml`, `environment_validation_report.txt`, and
`archive_checksums.sha256` are repository evidence. Environment directories and
portable `*.tar.gz` archives are deployment artifacts and are ignored by Git.
