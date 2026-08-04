# Runtime installation

Install Mamba and conda-pack on a connected Linux x86-64 build host. ClinicalSuite
never invokes `conda create` or `conda install`.

```bash
export MAMBA_BIN=/opt/conda/envs/mamba/bin/mamba
export CONDA_PACK_BIN=/opt/conda/bin/conda-pack
./envs/build.sh
```

Existing healthy prefixes are repaired in place with `mamba install`; they are
not deleted. Mamba reuses its package cache. New prefixes are created with
`mamba create`. The complete environment matrix must pass before locks, YAML
exports, or portable archives are published.

The build host also needs `unsquashfs` to read the already validated official
DeepVariant CPU payload. This is extraction only: no container is executed and
the production HPC needs neither Apptainer nor Docker. The source payload is
digest-pinned, executable ZIPs remain byte-identical, and trained models are not
copied.

Successful installation produces seven prefixes, seven explicit `.lock` files,
seven resolved `.yml` files, seven `.tar.gz` archives, an archive checksum
manifest, and an environment validation report.

To validate without rebuilding:

```bash
MAMBA_BIN=/opt/conda/envs/mamba/bin/mamba ./envs/validate.sh
```
