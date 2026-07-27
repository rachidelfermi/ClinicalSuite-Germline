# Scientific decision record

`Architecture.md` is the approved scientific design and evidence review.
Implementation-specific scientific decisions are appended here before the
affected module is written.

## SDR-001: V2 consensus implementation boundary

**Status:** approved clarification, 2026-07-20

ClinicalSuite V2 will use conventional reference-validated normalization and a
deterministic, configurable, evidence-aware consensus. It will not implement
GA4GH VRS or a machine-learning/logistic-regression consensus model. This does not
authorize majority voting or simple VCF merging. The exact consensus rules remain
blocked until the consensus module receives its own literature-backed decision
record, fixtures, and acceptance criteria.

The clarification is also recorded in section 0 of `Architecture.md` so the design
and implementation contract cannot silently diverge.

## SDR-002: Module 4 external-resource boundary

**Status:** approved implementation directive, 2026-07-21

Module 4 packages executables and runtime libraries only. Trained DeepVariant and
Octopus models, VEP caches/plugins, reference genomes, and annotation databases
remain external, versioned deployment resources. The annotation image contains
VEP only; ACMG decision-support tools are deferred to their own reviewed module.

This narrower boundary supersedes earlier architecture text that placed an
Octopus forest or ACMG tools/plugins in these images. It does not change caller,
normalization, annotation, or interpretation workflow design. See
`docs/container-provenance.md` for the release and packaging review.

## SDR-003: Stage-aware preflight resource gates

**Status:** approved implementation directive, 2026-07-27

Preflight validates only resources consumed at or before the selected execution
stage. Annotation resources are informational through Module 13 and mandatory
according to their manifest policy from Module 14. ACMG/interpretation resources
are informational through Module 14 and enforced from Module 15.

This changes validation timing only. It does not weaken checksum, assembly,
version, or compatibility checks once a resource enters scope, and it does not
change any scientific workflow.

## SDR-004: ClinicalSuite V2 reference lock

**Status:** approved implementation directive, 2026-07-27

Broad GRCh38 Full Analysis Set + Decoy + HLA is the only supported V2 reference.
The exact FASTA basename is `GRCh38_full_analysis_set_plus_decoy_hla.fa`; the
ClinicalSuite reference identity is
`GRCh38_full_analysis_set_plus_decoy_hla-20150309`, and the locked FASTA
SHA-256 is
`3b103f4742abfd54938fb0333e19ad067635c8eb86f1dbf0ce44b165c4292b50`.

Alignment, variant calling, consensus, filtering, and their validation inputs
must use indexes and intervals derived from this exact FASTA. Preflight rejects
another FASTA basename or reference identity from Module 7 onward. Annotation
and interpretation databases remain external and are not acquired by reference
preparation.
