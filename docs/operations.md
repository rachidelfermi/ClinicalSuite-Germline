# Operations

ClinicalSuite runs on Linux HPC nodes with Bash, Mamba, and installed
ClinicalSuite Conda prefixes. Apptainer is not required or invoked.

## Runtime installation

On a connected build node, run:

```bash
MAMBA_BIN=/opt/conda/envs/mamba/bin/mamba \
CONDA_PACK_BIN=/opt/conda/bin/conda-pack \
./envs/build.sh
```

The command creates or repairs prefixes without deleting them, validates the
complete environment set, freezes explicit locks and resolved YAML files, and
then creates portable archives. Package caches are reused by Mamba.

## HPC deployment

Copy `envs/*.tar.gz` and `envs/archive_checksums.sha256` to the HPC, verify the
checksums, extract each archive under a common root using its environment name,
and run `bin/conda-unpack` once after extraction. The resulting layout must be:

```text
/opt/clinicalsuite/envs/
├── qc/
├── alignment/
├── variant/
├── deepvariant/
├── octopus/
├── annotation/
└── report/
```

Set `ENV_DIR` to that root. Set `MAMBA_BIN` to the site Mamba executable used
for dependency/lock verification. Users do not activate prefixes; `run.sh` and
the shared runtime wrapper select the correct environment for each module.

## Run preparation

Keep source, external scientific resources, and patient runs separate. Do not
place references, databases, installed prefixes, archives, or patient data in
Git. Copy the configuration examples, use absolute site paths, and run
preflight before analysis.

```bash
./run.sh --config /site/run/clinical.conf \
  --samples /site/run/samples.tsv --preflight-only
```

Preflight verifies the resolved inputs, environment locks, executable versions,
reference identity, external resources required by the selected stage,
permissions, and disk capacity. It downloads and changes nothing.

## Scheduler use

`run.sh` is scheduler-neutral and can be called from Slurm, PBS, LSF, or an
interactive allocation. Request resources in the scheduler wrapper and keep
scientific parameters in validated ClinicalSuite configuration. Do not add
scheduler commands or manual activation to module scripts.

## Recovery

Modules write atomically and use content-aware completion markers. Re-run the
same command after correcting an operational failure; matching checkpoints are
reused. Never edit `.complete` markers or resolved configuration. Preserve logs
and incomplete artifacts until the failure has been reviewed.

## External data boundary

The locked Broad GRCh38 Full Analysis Set + Decoy + HLA reference, project-built
BWA-MEM2 indexes, trained caller models, VEP cache/plugins, and all annotation or
ACMG databases are mounted as ordinary external paths. They are not included in
Conda prefixes or archives.
