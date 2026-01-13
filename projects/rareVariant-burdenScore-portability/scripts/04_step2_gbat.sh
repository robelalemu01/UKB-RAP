#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

STATE_ENV="$(dirname "${CFG}")/chr22_plumbing.state.env"
[[ -f "${STATE_ENV}" ]] || { echo "ERROR: missing ${STATE_ENV}. Run 01 first." >&2; exit 1; }
# shellcheck disable=SC1090
source "${STATE_ENV}"

dx select "${DX_PROJECT_ID}" >/dev/null

if [[ "${RUN_GBAT}" -ne 1 ]]; then
  echo "[INFO] RUN_GBAT=0, skipping Step2 GBAT (enable in config when ready)."
  exit 0
fi

# Wait for null model job
if [[ -n "${NULL_JOB_ID:-}" ]]; then
  echo "[INFO] Watching null model job: ${NULL_JOB_ID}"
  dx watch "${NULL_JOB_ID}"
fi

NULL_PREFIX="wes_oqfe_chr${CHR}_null_${TEST_MODE}"

pick_id() {
  local pattern="$1"
  local fname
  fname="$(dx ls "${DEST_SAIGE}" | grep -E "${pattern}" | head -n 1 || true)"
  [[ -n "${fname}" ]] || { echo "ERROR: Could not find output matching ${pattern} in ${DEST_SAIGE}" >&2; exit 1; }
  dx find data --path "${DEST_SAIGE}" --name "${fname}" --brief | head -n 1
}

MODEL_RDA_ID="$(pick_id "${NULL_PREFIX}.*rda")"
VR_ID="$(pick_id "${NULL_PREFIX}.*(variance|ratio|VR|varRatio).*")"

# Try to locate a group file in WGS v2 (best effort)
EXOME_BASE="${SRC_PROJ}:/Bulk/Exome sequences"
FOUND_GROUP="$(dx find data --path "${EXOME_BASE}" --name "${GROUP_FILE_PATTERN}" --brief | head -n 1 || true)"
if [[ -z "${FOUND_GROUP}" ]]; then
  echo "ERROR: Could not auto-find a group file with pattern: ${GROUP_FILE_PATTERN}" >&2
  echo "Try manual search, e.g.:" >&2
  echo "  dx find data --path \"${EXOME_BASE}\" --name \"*group*\" | head" >&2
  exit 1
fi

GROUP_ID="${FOUND_GROUP}"
echo "[INFO] Using group_txt: ${GROUP_ID}"

INSTANCE="${FULL_INSTANCE_TYPE}"
if [[ "${TEST_MODE}" -eq 1 ]]; then INSTANCE="${TEST_INSTANCE_TYPE}"; fi

OUT_PREFIX="wes_oqfe_chr${CHR}_gbat_${TEST_MODE}"

echo "=============================="
echo "[INFO] Stage 04: GBAT"
echo "[INFO] instance: ${INSTANCE}"
echo "[INFO] model_rda: ${MODEL_RDA_ID}"
echo "[INFO] var_ratio: ${VR_ID}"
echo "[INFO] bgen: ${BGEN_ID}"
echo "=============================="

ARGS=(
  --yes --brief
  --instance-type "${INSTANCE}"
  -igenotypes_bgen="${BGEN_ID}"
  -igenotypes_bgen_bgi="${BGI_ID}"
  -isample_txt="${SAMPLE_ID}"
  -imodel_rda="${MODEL_RDA_ID}"
  -ivariance_ratio_txt="${VR_ID}"
  -igroup_txt="${GROUP_ID}"
  -ioutput_file_prefix="${OUT_PREFIX}"
)

# In test mode, restrict region if we have a ranges file
if [[ "${TEST_MODE}" -eq 1 && -n "${RANGE_ID:-}" ]]; then
  ARGS+=(-iranges_to_include_file="${RANGE_ID}")
fi

JOB_ID="$(dx run "${APP_GBAT}" "${ARGS[@]}" --destination "${DEST_SAIGE}")"

echo "[OK] Submitted GBAT job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"
