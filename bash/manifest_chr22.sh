#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# manifest_chr22.sh
# Create and upload file-path manifests for Graphtyper pVCFs
# (Example uses chr22 by default)
# ============================================================

CHR="${1:-22}"

# DNAnexus source location (WGS v2 project is referenced read-only)
PVCF_BASE="WGS v2:/Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants, pVCF format [500k release]"

# Local helper CSV you already extracted
COORD_CSV="/opt/notebooks/work/tmp/helper/graphtyper_pvcf_coordinates/graphtyper_pvcf_coordinates.csv"

# Local output directory (ephemeral; will upload results)
OUTDIR="/opt/notebooks/work/manifests"
mkdir -p "$OUTDIR"

# DNAnexus destination folder (in your working project)
DX_OUT="/manifests/wgs_v2/graphtyper_pvcf"
dx mkdir -p "$DX_OUT" >/dev/null

echo "[info] Using CHR=$CHR"
echo "[info] PVCF_BASE=$PVCF_BASE"
echo "[info] COORD_CSV=$COORD_CSV"
echo "[info] Writing outputs to $OUTDIR"
echo "[info] Uploading outputs to $(dx pwd):$DX_OUT"

# Basic sanity checks
if ! dx ls "$PVCF_BASE/chr${CHR}" >/dev/null 2>&1; then
  echo "[error] Cannot access: $PVCF_BASE/chr${CHR}"
  echo "        Check spelling and your access to the WGS v2 project."
  exit 1
fi

if [[ ! -f "$COORD_CSV" ]]; then
  echo "[error] Missing $COORD_CSV"
  echo "        Download/unzip graphtyper_pvcf_coordinates.zip first."
  exit 1
fi

VCF_MAN="$OUTDIR/chr${CHR}_graphtyper_pvcf_vcf_paths.txt"
TBI_MAN="$OUTDIR/chr${CHR}_graphtyper_pvcf_tbi_paths.txt"

# Build VCF manifest from coordinates CSV
# Note: CSV chromosome column is numeric (e.g., 22), but chr folder is chr22
awk -F',' -v chr="$CHR" 'NR>1 && $2==chr {print $1}' "$COORD_CSV" \
  | sort -V \
  | awk -v base="$PVCF_BASE/chr'"$CHR"'" '{print base "/" $0}' \
  > "$VCF_MAN"

# Build TBI manifest (same lines with .tbi suffix)
sed 's/\.vcf\.gz$/.vcf.gz.tbi/' "$VCF_MAN" > "$TBI_MAN"

echo "[info] Manifest counts:"
wc -l "$VCF_MAN" "$TBI_MAN"

echo "[info] Preview first 3 lines:"
head -n 3 "$VCF_MAN" | sed 's|WGS v2:||'

# Upload manifests to your working project
dx upload "$VCF_MAN" --path "$DX_OUT/" >/dev/null
dx upload "$TBI_MAN" --path "$DX_OUT/" >/dev/null

echo "[done] Uploaded:"
echo "       $DX_OUT/$(basename "$VCF_MAN")"
echo "       $DX_OUT/$(basename "$TBI_MAN")"