#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

STATE_ENV="$(dirname "${CFG}")/chr22_plumbing.state.env"
[[ -f "${STATE_ENV}" ]] || { echo "ERROR: missing ${STATE_ENV}. Run 01_prepare_inputs.sh first." >&2; exit 1; }
# shellcheck disable=SC1090
source "${STATE_ENV}"

dx select "${DX_PROJECT_ID}" >/dev/null

# Wait for sparse job if it’s still running (optional)
if [[ -n "${SPARSE_JOB_ID:-}" ]]; then
  echo "[INFO] Watching sparse GRM job: ${SPARSE_JOB_ID}"
  dx watch "${SPARSE_JOB_ID}"
fi

# Find sparse outputs in DEST_SAIGE by prefix (best-effort pattern)
OUT_PREFIX="wes_oqfe_chr${CHR}_sparseGRM_${TEST_MODE}"

pick_id() {
  local pattern="$1"
  local fname
  fname="$(dx ls "${DEST_SAIGE}" | grep -E "${pattern}" | head -n 1 || true)"
  [[ -n "${fname}" ]] || { echo "ERROR: Could not find output matching ${pattern} in ${DEST_SAIGE}" >&2; exit 1; }
  dx find data --path "${DEST_SAIGE}" --name "${fname}" --brief | head -n 1
}

SPARSE_MTX_ID="$(pick_id "${OUT_PREFIX}.*(mtx|sparse).*")"
SPARSE_IDS_ID="$(pick_id "${OUT_PREFIX}.*(ids|sample).*")"

INSTANCE="${FULL_INSTANCE_TYPE}"
if [[ "${TEST_MODE}" -eq 1 ]]; then INSTANCE="${TEST_INSTANCE_TYPE}"; fi

NULL_PREFIX="wes_oqfe_chr${CHR}_null_${TEST_MODE}"
echo "=============================="
echo "[INFO] Stage 03: null model"
echo "[INFO] instance: ${INSTANCE}"
echo "[INFO] sparse_mtx: ${SPARSE_MTX_ID}"
echo "[INFO] sparse_ids: ${SPARSE_IDS_ID}"
echo "=============================="

JOB_ID="$(dx run "${APP_NULL_MODEL}" \
  --yes --brief \
  --instance-type "${INSTANCE}" \
  -iplink_bed="${PLINK_BED_ID}" \
  -iplink_bim="${PLINK_BIM_ID}" \
  -iplink_fam="${PLINK_FAM_ID}" \
  -iphenotype_file="${PHENO_ID}" \
  -ipheno_col="${PHENO_COL}" \
  -icovariates="${COVARIATES}" \
  -isample_id_col="${SAMPLE_ID_COL}" \
  -itrait_type="${TRAIT_TYPE}" \
  -isparse_grm_mtx="${SPARSE_MTX_ID}" \
  -isparse_grm_sample_id_txt="${SPARSE_IDS_ID}" \
  -iinverse_normalize=false \
  -ioutput_file_prefix="${NULL_PREFIX}" \
  --destination "${DEST_SAIGE}")"

echo "[OK] Submitted null model job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"

echo "NULL_JOB_ID=\"${JOB_ID}\"" >> "$(dirname "${CFG}")/chr22_plumbing.state.env"
