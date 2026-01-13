#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

: "${DX_PROJECT_ID:?Must set DX_PROJECT_ID}"
: "${APP_NULL_MODEL:=saige_gwas_grm}"
: "${DEST_SAIGE:=/saige/chr22_test}"
: "${DEST_PERSIST:=/persist/rv_portability/saige_chr22_plumbing}"
: "${CHR:=22}"
: "${NULL_INSTANCE_TYPE:=mem1_hdd1_v2_x16}"
: "${TRAIT_TYPE:=quantitative}"
: "${PHENO_COL:=pheno}"
: "${SAMPLE_ID_COL:=IID}"
: "${COVARIATES:=sex}"
: "${INVERSE_NORMALIZE:=false}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_LOCAL="${ROOT}/configs/manifest_ids.env"
STATE_LOCAL="${ROOT}/configs/chr22_plumbing.state.env"

dx select "${DX_PROJECT_ID}" >/dev/null

# Pull manifest if missing
if [[ ! -f "${MANIFEST_LOCAL}" ]]; then
  echo "[WARN] Missing local manifest. Downloading from ${DEST_PERSIST}/manifest_ids.env ..."
  dx download "${DX_PROJECT_ID}:${DEST_PERSIST}/manifest_ids.env" -o "${MANIFEST_LOCAL}" --overwrite
fi
# shellcheck disable=SC1090
source "${MANIFEST_LOCAL}"

# Pull state if missing
if [[ ! -f "${STATE_LOCAL}" ]]; then
  echo "[WARN] Missing local state. Downloading from ${DEST_PERSIST}/chr22_plumbing.state.env ..."
  dx download "${DX_PROJECT_ID}:${DEST_PERSIST}/chr22_plumbing.state.env" -o "${STATE_LOCAL}" --overwrite || true
fi
# shellcheck disable=SC1090
source "${STATE_LOCAL}" || true

SPARSE_PREFIX="${SPARSE_OUT_PREFIX:-wes_oqfe_chr${CHR}_sparseGRM}"
NULL_PREFIX="wes_oqfe_chr${CHR}_null"

die() { echo "ERROR: $*" >&2; exit 1; }

pick_one() {
  local pattern="$1"
  local id
  id="$(dx find data --path "${DEST_SAIGE}" --name "${pattern}" --brief | head -n 1 || true)"
  [[ -n "${id:-}" ]] || die "Could not find output matching: ${pattern} in ${DEST_SAIGE}"
  echo "$id"
}

echo "=============================="
echo "[INFO] Stage 03: submit null model"
echo "[INFO] instance: ${NULL_INSTANCE_TYPE}"
echo "[INFO] sparse prefix: ${SPARSE_PREFIX}"
echo "=============================="

# Sparse GRM outputs vary; try common patterns
SPARSE_MTX_ID="$(pick_one "${SPARSE_PREFIX}*.mtx")"
SPARSE_IDS_ID="$(pick_one "${SPARSE_PREFIX}*ids*")"

echo "[INFO] SPARSE_MTX_ID=${SPARSE_MTX_ID}"
echo "[INFO] SPARSE_IDS_ID=${SPARSE_IDS_ID}"

JOB_ID="$(dx run "${APP_NULL_MODEL}" \
  --yes --brief \
  --instance-type "${NULL_INSTANCE_TYPE}" \
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
  -iinverse_normalize="${INVERSE_NORMALIZE}" \
  -ioutput_file_prefix="${NULL_PREFIX}" \
  --destination "${DEST_SAIGE}")"

echo "[OK] Submitted null model job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"

{
  echo "SPARSE_MTX_ID=\"${SPARSE_MTX_ID}\""
  echo "SPARSE_IDS_ID=\"${SPARSE_IDS_ID}\""
  echo "NULL_JOB_ID=\"${JOB_ID}\""
  echo "NULL_OUT_PREFIX=\"${NULL_PREFIX}\""
} >> "${STATE_LOCAL}"

dx upload "${STATE_LOCAL}" --path "${DEST_PERSIST}" --parents --overwrite >/dev/null
echo "[OK] Updated state persisted: ${DEST_PERSIST}/chr22_plumbing.state.env"
