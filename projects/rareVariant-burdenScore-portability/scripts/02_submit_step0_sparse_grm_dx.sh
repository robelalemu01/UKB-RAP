#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

: "${DX_PROJECT_ID:?Must set DX_PROJECT_ID}"
: "${APP_SPARSE_GRM:=saige_gwas_sparse_grm}"
: "${DEST_SAIGE:=/saige/chr22_test}"
: "${DEST_PERSIST:=/persist/rv_portability/saige_chr22_plumbing}"
: "${CHR:=22}"
: "${SPARSE_INSTANCE_TYPE:=mem1_hdd1_v2_x72}"
: "${NUM_RANDOM_MARKER:=200}"
: "${RELATEDNESS_CUTOFF:=0.125}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_LOCAL="${ROOT}/configs/manifest_ids.env"
STATE_LOCAL="${ROOT}/configs/chr22_plumbing.state.env"

dx select "${DX_PROJECT_ID}" >/dev/null

# If manifest missing locally (new JupyterLab), pull it from persist
if [[ ! -f "${MANIFEST_LOCAL}" ]]; then
  echo "[WARN] Missing local manifest. Downloading from ${DEST_PERSIST}/manifest_ids.env ..."
  dx download "${DX_PROJECT_ID}:${DEST_PERSIST}/manifest_ids.env" -o "${MANIFEST_LOCAL}" --overwrite
fi
# shellcheck disable=SC1090
source "${MANIFEST_LOCAL}"

OUT_PREFIX="wes_oqfe_chr${CHR}_sparseGRM"
echo "=============================="
echo "[INFO] Stage 02: submit sparse GRM"
echo "[INFO] instance: ${SPARSE_INSTANCE_TYPE}"
echo "[INFO] output_prefix: ${OUT_PREFIX}"
echo "=============================="

JOB_ID="$(dx run "${APP_SPARSE_GRM}" \
  --yes --brief \
  --instance-type "${SPARSE_INSTANCE_TYPE}" \
  -iplink_bed="${PLINK_BED_ID}" \
  -iplink_bim="${PLINK_BIM_ID}" \
  -iplink_fam="${PLINK_FAM_ID}" \
  -inum_random_marker="${NUM_RANDOM_MARKER}" \
  -irelatedness_cutoff="${RELATEDNESS_CUTOFF}" \
  -ioutput_prefix="${OUT_PREFIX}" \
  --destination "${DEST_SAIGE}")"

echo "[OK] Submitted sparse GRM job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"

# Append to local state + persist it
{
  echo "SPARSE_JOB_ID=\"${JOB_ID}\""
  echo "SPARSE_OUT_PREFIX=\"${OUT_PREFIX}\""
} >> "${STATE_LOCAL}"

dx upload "${STATE_LOCAL}" --path "${DEST_PERSIST}" --parents --overwrite >/dev/null
echo "[OK] Updated state persisted: ${DEST_PERSIST}/chr22_plumbing.state.env"
