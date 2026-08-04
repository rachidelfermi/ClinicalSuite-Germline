#!/usr/bin/env bash
# Source-safe ClinicalSuite Conda runtime contract.

if [[ "${CLINICAL_ENVIRONMENT_LIBRARY_LOADED:-0}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly CLINICAL_ENVIRONMENT_LIBRARY_LOADED=1

readonly -a CLINICAL_ENVIRONMENTS=(
    qc alignment variant deepvariant octopus annotation report
)

clinical_environment_first_module() {
    case "$1" in
        qc) printf '6\n' ;;
        alignment) printf '7\n' ;;
        variant) printf '9\n' ;;
        deepvariant) printf '9\n' ;;
        octopus) printf '11\n' ;;
        annotation) printf '14\n' ;;
        report) printf '16\n' ;;
        *) return 1 ;;
    esac
}

# Callback arguments: environment, label, expected regex, expected status,
# followed by the exact command. This single matrix is shared by installation
# validation and stage-aware preflight.
clinical_environment_each_runtime_check() {
    local callback="$1"

    "$callback" qc FastQC '0\.12\.1' 0 fastqc --version
    "$callback" qc fastp '1\.3\.6' 0 fastp --version
    "$callback" qc MultiQC '1\.35' 0 multiqc --version
    "$callback" alignment BWA-MEM2 '(2\.2\.1|2\.3)' 0 bwa-mem2 version
    "$callback" alignment Samtools '^samtools 1\.24' 0 samtools --version
    "$callback" alignment Picard '^Version:3\.4\.0$' 1 picard MarkDuplicates --version
    "$callback" alignment mosdepth '0\.3\.14' 0 mosdepth --version
    "$callback" alignment GATK 'v?4\.6\.2\.0' 0 gatk --version
    "$callback" variant GATK 'v?4\.6\.2\.0' 0 gatk --version
    "$callback" variant bcftools '^bcftools 1\.24' 0 bcftools --version
    "$callback" variant htslib 'htslib.*1\.24' 0 htsfile --version
    "$callback" variant Samtools '^samtools 1\.24' 0 samtools --version
    "$callback" deepvariant DeepVariant 'Runs all 3 steps' 1 run_deepvariant --help
    "$callback" octopus Octopus 'octopus version 0\.7\.4' 0 octopus --version
    "$callback" annotation VEP 'ensembl-vep[[:space:]]*: 116\.0' 0 vep --help
    "$callback" report Python '^Python 3\.12\.12' 0 python --version
    "$callback" report reporting-libraries '^imports-ok$' 0 \
        python -c 'import jinja2, matplotlib, pandas; print("imports-ok")'
}
