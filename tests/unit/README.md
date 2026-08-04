# Unit tests

Current unit coverage includes the stable `run.sh` interface, environment build
metadata, and the configuration/sample-manifest parser. Configuration tests cover
valid exports, defaults, malformed and duplicate keys, malformed manifests,
duplicate samples, missing files, invalid paths, assay rules, and CLI behavior.

`test_common.sh` exercises every public function in `bin/common.sh`, including
success and expected-failure paths for logging, cleanup, atomic files,
checkpoints, commands, Conda environments, structural validators, provenance, timers, and
validated configuration access.

`test_preflight.sh` covers aggregation, JSON safety, FASTQ pairing, resource path
safety, disk-space policy, atomic reports, and the CLI contract.

`test_alignment.sh` covers escaped read-group construction, locked-reference and
known-site manifest validation, checksum failures, unsafe and duplicate manifest
rows, Module 6 handoff integrity, and per-step checkpoint corruption.
