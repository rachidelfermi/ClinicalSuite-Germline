# HPC deployment

ClinicalSuite deploys validated conda-pack archives and never requires users to
activate an environment.

Verify the transferred archives:

```bash
sha256sum --check archive_checksums.sha256
```

Extract each archive beneath a common runtime root:

```bash
for name in qc alignment variant deepvariant octopus annotation report; do
  mkdir -p "/opt/clinicalsuite/envs/$name"
  tar -xzf "$name.tar.gz" -C "/opt/clinicalsuite/envs/$name"
  "/opt/clinicalsuite/envs/$name/bin/conda-unpack"
done
```

Configure:

```ini
ENV_DIR=/opt/clinicalsuite/envs
MAMBA_BIN=/opt/conda/envs/mamba/bin/mamba
```

`run.sh` selects `qc`, `alignment`, or later module-specific environments
automatically. Scheduler scripts must call `run.sh` directly and must not add
`conda activate`. Preflight confirms every required prefix, explicit lock,
resolved YAML, Mamba dependency listing, executable, and version before analysis.

References, BWA-MEM2 indexes, models, caches, annotation databases, and patient
data are deployed separately and referenced by validated absolute paths. They
must never be placed in an environment archive.

Archive relocation may change embedded runtime paths and provenance. Scientific
equivalence is checked from validated read/variant content and module output
contracts; timestamp- or path-bearing report bytes are not expected to match.
