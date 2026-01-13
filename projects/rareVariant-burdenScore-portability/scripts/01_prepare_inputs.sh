#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-}"
[[ -n "${CFG}" && -f "${CFG}" ]] || { echo "Usage: $0 <config.env>" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CFG}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need dx
need awk
need head

echo "=============================="
echo "[INFO] Stage 01: prepare inputs"
echo "[INFO] CFG=${CFG}"
echo "[INFO] Using DNAnexus project: ${DX_PROJECT_ID}"
echo "=============================="

dx select "${DX_PROJECT_ID}" >/dev/null
echo "[INFO] dx pwd: $(dx pwd)"

# UKB OQFE paths (Exome sequences)
EXOME_BASE="${SRC_PROJ}:/Bulk/Exome sequences"
BGEN_FINAL="${EXOME_BASE}/Population level exome OQFE variants, BGEN format - final release"
PLINK_FINAL="${EXOME_BASE}/Population level exome OQFE variants, PLINK format - final release"

BGEN_NAME="ukb23159_c${CHR}_b0_v1.bgen"
BGI_NAME="ukb23159_c${CHR}_b0_v1.bgen.bgi"
SAMPLE_NAME="ukb23159_c${CHR}_b0_v1.sample"
PLINK_PREFIX="ukb23158_c${CHR}_b0_v1"

BED_NAME="${PLINK_PREFIX}.bed"
BIM_NAME="${PLINK_PREFIX}.bim"
FAM_NAME="${PLINK_PREFIX}.fam"

dx_find_one_or_die() {
  local p="$1" n="$2"
  local id
  id="$(dx find data --path "$p" --name "$n" --brief | head -n 1 || true)"
  [[ -n "${id}" ]] || { echo "ERROR: Could not find ${n} under ${p}" >&2; exit 1; }
  echo "${id}"
}

echo "[INFO] Resolving BGEN/BGI/SAMPLE IDs..."
BGEN_ID="$(dx_find_one_or_die "$BGEN_FINAL" "$BGEN_NAME")"
BGI_ID="$(dx_find_one_or_die "$BGEN_FINAL" "$BGI_NAME")"
SAMPLE_ID="$(dx_find_one_or_die "$BGEN_FINAL" "$SAMPLE_NAME")"

echo "[INFO] Resolving PLINK bed/bim/fam IDs..."
BED_ID="$(dx_find_one_or_die "$PLINK_FINAL" "$BED_NAME")"
BIM_ID="$(dx_find_one_or_die "$PLINK_FINAL" "$BIM_NAME")"
FAM_ID="$(dx_find_one_or_die "$PLINK_FINAL" "$FAM_NAME")"

echo "[INFO] BGEN_ID=${BGEN_ID}"
echo "[INFO] BGI_ID=${BGI_ID}"
echo "[INFO] SAMPLE_ID=${SAMPLE_ID}"
echo "[INFO] BED_ID=${BED_ID}"
echo "[INFO] BIM_ID=${BIM_ID}"
echo "[INFO] FAM_ID=${FAM_ID}"
echo "=============================="

# Create dest folders in your project storage
dx mkdir -p "${DEST_INPUTS}" >/dev/null
dx mkdir -p "${DEST_SAIGE}"  >/dev/null

# Local tmp
mkdir -p "${TMP_BASE}"
FULL_DIR="${TMP_BASE}/full"
SUB_DIR="${TMP_BASE}/subset"
mkdir -p "${FULL_DIR}" "${SUB_DIR}"

echo "[INFO] Downloading PLINK (chr${CHR}) locally (ephemeral)..."
dx download "${BED_ID}" -o "${FULL_DIR}/${BED_NAME}" --overwrite
dx download "${BIM_ID}" -o "${FULL_DIR}/${BIM_NAME}" --overwrite
dx download "${FAM_ID}" -o "${FULL_DIR}/${FAM_NAME}" --overwrite

# Choose TEST vs FULL behavior
SUB_PREFIX="${SUB_DIR}/${PLINK_PREFIX}"
KEEP_FILE="${SUB_DIR}/keep_${TEST_N_INDIV}.txt"
SNPLIST_FILE="${SUB_DIR}/snplist_${TEST_N_VARIANTS}.txt"

if [[ "${TEST_MODE}" -eq 1 ]]; then
  need plink2 || need plink

  echo "[INFO] TEST_MODE=1: creating downsampled PLINK set"
  echo "[INFO] Keeping N individuals: ${TEST_N_INDIV}"
  echo "[INFO] Thinning to N variants: ${TEST_N_VARIANTS}"

  # keep file must be FID IID
  head -n "${TEST_N_INDIV}" "${FULL_DIR}/${FAM_NAME}" | awk '{print $1, $2}' > "${KEEP_FILE}"

  # variant thinning list
  if command -v plink2 >/dev/null 2>&1; then
    plink2 --bfile "${FULL_DIR}/${PLINK_PREFIX}" --keep "${KEEP_FILE}" \
      --thin-count "${TEST_N_VARIANTS}" --write-snplist --out "${SUB_DIR}/tmp"
  else
    plink --bfile "${FULL_DIR}/${PLINK_PREFIX}" --keep "${KEEP_FILE}" \
      --thin-count "${TEST_N_VARIANTS}" --write-snplist --out "${SUB_DIR}/tmp"
  fi
  mv "${SUB_DIR}/tmp.snplist" "${SNPLIST_FILE}"

  # build subset bed/bim/fam
  if command -v plink2 >/dev/null 2>&1; then
    plink2 --bfile "${FULL_DIR}/${PLINK_PREFIX}" --keep "${KEEP_FILE}" --extract "${SNPLIST_FILE}" \
      --make-bed --out "${SUB_PREFIX}"
  else
    plink --bfile "${FULL_DIR}/${PLINK_PREFIX}" --keep "${KEEP_FILE}" --extract "${SNPLIST_FILE}" \
      --make-bed --out "${SUB_PREFIX}"
  fi
else
  echo "[INFO] TEST_MODE=0: using full PLINK set (no downsample)"
  cp "${FULL_DIR}/${BED_NAME}" "${SUB_PREFIX}.bed"
  cp "${FULL_DIR}/${BIM_NAME}" "${SUB_PREFIX}.bim"
  cp "${FULL_DIR}/${FAM_NAME}" "${SUB_PREFIX}.fam"
fi

echo "[INFO] Uploading subset PLINK to ${DEST_INPUTS} ..."
SUB_BED_ID="$(dx upload "${SUB_PREFIX}.bed" --path "${DEST_INPUTS}" --brief)"
SUB_BIM_ID="$(dx upload "${SUB_PREFIX}.bim" --path "${DEST_INPUTS}" --brief)"
SUB_FAM_ID="$(dx upload "${SUB_PREFIX}.fam" --path "${DEST_INPUTS}" --brief)"

# Dummy phenotype file from subset fam
PHENO_LOCAL="${SUB_DIR}/pheno_dummy_for_saige.tsv"
awk 'BEGIN{OFS="\t"; print "IID","pheno","sex"} {print $2,0,$5}' "${SUB_PREFIX}.fam" > "${PHENO_LOCAL}"

echo "[INFO] Preview phenotype file:"
head -n 5 "${PHENO_LOCAL}" || true

PHENO_ID="$(dx upload "${PHENO_LOCAL}" --path "${DEST_INPUTS}" --brief)"

# Optional: ranges_to_include for step2 test
RANGE_LOCAL="${SUB_DIR}/ranges_chr${CHR}_${TEST_RANGE_START}_${TEST_RANGE_END}.txt"
if [[ "${TEST_MODE}" -eq 1 ]]; then
  echo -e "${CHR}\t${TEST_RANGE_START}\t${TEST_RANGE_END}" > "${RANGE_LOCAL}"
  RANGE_ID="$(dx upload "${RANGE_LOCAL}" --path "${DEST_INPUTS}" --brief)"
else
  RANGE_ID=""
fi

# Write a state env file for later stages (do NOT commit)
STATE_ENV="$(dirname "${CFG}")/chr22_plumbing.state.env"
cat > "${STATE_ENV}" <<STATE
# Auto-generated by 01_prepare_inputs.sh on $(date)
DX_PROJECT_ID="${DX_PROJECT_ID}"
SRC_PROJ="${SRC_PROJ}"
CHR="${CHR}"
DEST_INPUTS="${DEST_INPUTS}"
DEST_SAIGE="${DEST_SAIGE}"
TMP_BASE="${TMP_BASE}"

# Full genotype files (BGEN)
BGEN_ID="${BGEN_ID}"
BGI_ID="${BGI_ID}"
SAMPLE_ID="${SAMPLE_ID}"

# Subset PLINK for sparse GRM / null model
PLINK_BED_ID="${SUB_BED_ID}"
PLINK_BIM_ID="${SUB_BIM_ID}"
PLINK_FAM_ID="${SUB_FAM_ID}"

# Phenotype file (dummy)
PHENO_ID="${PHENO_ID}"
PHENO_COL="pheno"
SAMPLE_ID_COL="IID"
COVARIATES="sex"
TRAIT_TYPE="quantitative"

# Range include file for step2 (optional)
RANGE_ID="${RANGE_ID}"

# App names
APP_SPARSE_GRM="${APP_SPARSE_GRM}"
APP_NULL_MODEL="${APP_NULL_MODEL}"
APP_GBAT="${APP_GBAT}"

# Params
TEST_MODE="${TEST_MODE}"
NUM_RANDOM_MARKER="${NUM_RANDOM_MARKER}"
RELATEDNESS_CUTOFF="${RELATEDNESS_CUTOFF}"
RUN_GBAT="${RUN_GBAT}"
GROUP_FILE_PATTERN="${GROUP_FILE_PATTERN}"

# Instance types
TEST_INSTANCE_TYPE="${TEST_INSTANCE_TYPE}"
FULL_INSTANCE_TYPE="${FULL_INSTANCE_TYPE}"
STATE

echo "=============================="
echo "[OK] Wrote state env: ${STATE_ENV}"
echo "[OK] Stage 01 complete."
