#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

: "${DX_PROJECT_ID:?Must set DX_PROJECT_ID}"
: "${APP_GBAT:=saige_gwas_gbat}"
: "${DEST_SAIGE:=/saige/chr22_test}"
: "${DEST_PERSIST:=/persist/rv_portability/saige_chr22_plumbing}"
: "${CHR:=22}"
: "${GBAT_INSTANCE_TYPE:=mem1_hdd1_v2_x16}"
: "${MAX_MAF_FOR_GROUP_TEST:=0.01}"
: "${TEST_RANGE_START:=1}"
: "${TEST_RANGE_END:=5000000}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_LOCAL="${ROOT}/configs/manifest_ids.env"
STATE_LOCAL="${ROOT}/configs/chr22_plumbing.state.env"

dx select "${DX_PROJECT_ID}" >/dev/null

# Pull manifest if missing
if [[ ! -f "${MANIFEST_LOCAL}" ]]; then
  dx download "${DX_PROJECT_ID}:${DEST_PERSIST}/manifest_ids.env" -o "${MANIFEST_LOCAL}" --overwrite
fi
# shellcheck disable=SC1090
source "${MANIFEST_LOCAL}"

# Pull state if missing
if [[ ! -f "${STATE_LOCAL}" ]]; then
  dx download "${DX_PROJECT_ID}:${DEST_PERSIST}/chr22_plumbing.state.env" -o "${STATE_LOCAL}" --overwrite || true
fi
# shellcheck disable=SC1090
source "${STATE_LOCAL}" || true

die() { echo "ERROR: $*" >&2; exit 1; }

pick_one() {
  local pattern="$1"
  local id
  id="$(dx find data --path "${DEST_SAIGE}" --name "${pattern}" --brief | head -n 1 || true)"
  [[ -n "${id:-}" ]] || die "Could not find output matching: ${pattern} in ${DEST_SAIGE}"
  echo "$id"
}

NULL_PREFIX="${NULL_OUT_PREFIX:-wes_oqfe_chr${CHR}_null}"

MODEL_RDA_ID="$(pick_one "${NULL_PREFIX}*.rda")"
VR_ID="$(pick_one "${NULL_PREFIX}*variance*ratio*")"

# group file: prefer explicit ID
GROUP_ID="${GROUP_TXT_ID:-}"
if [[ -z "${GROUP_ID}" ]]; then
  # Attempt search pattern (may fail)
  if [[ -n "${GROUP_FILE_PATTERN:-}" ]]; then
    echo "[WARN] GROUP_TXT_ID not set; trying to find with pattern: ${GROUP_FILE_PATTERN}"
    GROUP_ID="$(dx find data --path "${SRC_PROJ}:/Bulk" --name "${GROUP_FILE_PATTERN}" --brief | head -n 1 || true)"
  fi
fi
[[ -n "${GROUP_ID}" ]] || die "Missing group file. Set GROUP_TXT_ID in chr22_plumbing.env (recommended)."

OUT_PREFIX="wes_oqfe_chr${CHR}_gbat"

echo "=============================="
echo "[INFO] Stage 04: submit GBAT"
echo "[INFO] instance: ${GBAT_INSTANCE_TYPE}"
echo "[INFO] model_rda: ${MODEL_RDA_ID}"
echo "[INFO] variance_ratio: ${VR_ID}"
echo "[INFO] group_txt: ${GROUP_ID}"
echo "=============================="

JOB_ID="$(dx run "${APP_GBAT}" \
  --yes --brief \
  --instance-type "${GBAT_INSTANCE_TYPE}" \
  -igenotypes_bgen="${BGEN_ID}" \
  -igenotypes_bgen_bgi="${BGI_ID}" \
  -isample_txt="${SAMPLE_ID}" \
  -imodel_rda="${MODEL_RDA_ID}" \
  -ivariance_ratio_txt="${VR_ID}" \
  -igroup_txt="${GROUP_ID}" \
  -imax_maf_for_group_test="${MAX_MAF_FOR_GROUP_TEST}" \
  -istart="${TEST_RANGE_START}" \
  -iend="${TEST_RANGE_END}" \
  -ioutput_file_prefix="${OUT_PREFIX}" \
  --destination "${DEST_SAIGE}")"

echo "[OK] Submitted GBAT job: ${JOB_ID}"
echo "[INFO] Watch with: dx watch ${JOB_ID}"

{
  echo "GBAT_JOB_ID=\"${JOB_ID}\""
  echo "GBAT_OUT_PREFIX=\"${OUT_PREFIX}\""
  echo "MODEL_RDA_ID=\"${MODEL_RDA_ID}\""
  echo "VR_ID=\"${VR_ID}\""
  echo "GROUP_TXT_ID_RESOLVED=\"${GROUP_ID}\""
} >> "${STATE_LOCAL}"

dx upload "${STATE_LOCAL}" --path "${DEST_PERSIST}" --parents --overwrite >/dev/null
echo "[OK] Updated state persisted: ${DEST_PERSIST}/chr22_plumbing.state.env"
