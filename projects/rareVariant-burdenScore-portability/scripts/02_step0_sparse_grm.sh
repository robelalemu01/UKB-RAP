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

INSTANCE="${FULL_INSTANCE_TYPE}"
if [[ "${TEST_MODE}" -eq 1 ]]; then INSTANCE="${TEST_INSTANCE_TYPE}"; fi

OUT_PREFIX="wes_oqfe_chr${CHR}_sparseGRM_${TEST_MODE}"
echo "=============================="
echo "[INFO] Stage 02: sparse GRM"
echo "[INFO] instance: ${INSTANCE}"
echo "[INFO] output_prefix: ${OUT_PREFIX}"
echo "=============================="

JOB_ID="$(dx run "${APP_SPARSE_GRM}" \
  --yes --brief \
  --instance-type "${INSTANCE}" \
  -iplink_bed="${PLINK_BED_ID}" \
  -iplink_bim="${PLINK_BIM_ID}" \
  -iplink_fam="${PLINK_FAM_ID}" \
  -inum_random_marker="${NUM_RANDOM_MARKER}" \
  -irelatedness_cutoff="${RELATEDNESS_CUTOFF}" \
  -ioutput_prefix="${OUT_PREFIX}" \
  --destination "${DEST_SAIGE}")"

echo "[OK] Submitted sparse GRM job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"

# Save job id to state file
echo "SPARSE_JOB_ID=\"${JOB_ID}\"" >> "${STATE_ENV}"
