#!/usr/bin/env bash
set -euo pipefail

# Resolve project root robustly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CFG="${ROOT}/configs/chr22_plumbing.env"
[[ -f "${CFG}" ]] || { echo "ERROR: missing config ${CFG}" >&2; exit 1; }

# shellcheck disable=SC1090
source "${CFG}"

# Defaults (avoid unbound vars)
: "${DX_PROJECT_ID:?Must set DX_PROJECT_ID in config}"
: "${DX_LOG_DIR:=/persist/logs/rv_portability/saige_chr22_plumbing}"
: "${DEST_PERSIST:=/persist/rv_portability/saige_chr22_plumbing}"

LOG_DIR="${ROOT}/logs"
mkdir -p "${LOG_DIR}"

ts="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="${LOG_DIR}/chr22_plumbing_${ts}.log"
touch "${RUN_LOG}"

echo "[INFO] Project root: ${ROOT}"
echo "[INFO] Config: ${CFG}"
echo "[INFO] Log: ${RUN_LOG}"

# Run pipeline in background (submission + small prep happens locally; heavy compute runs on DNAnexus jobs)
nohup bash -lc "
  set -euo pipefail
  echo '[INFO] Starting pipeline at:' \$(date)
  echo '[INFO] PWD:' \$(pwd)
  echo '[INFO] Using config:' '${CFG}'

  # Ensure dx context
  dx select '${DX_PROJECT_ID}' >/dev/null
  dx mkdir -p '${DX_LOG_DIR}' >/dev/null || true
  dx mkdir -p '${DEST_PERSIST}' >/dev/null || true

  stage() {
    echo '=============================='
    echo \"[INFO] Stage: \$1\"
    echo '=============================='
  }

  sync_log() {
    # Best-effort: persist the latest log snapshot to DNAnexus
    dx upload '${RUN_LOG}' --path '${DX_LOG_DIR}' --parents --overwrite --brief >/dev/null 2>&1 || true
  }

  stage '01_prepare_inputs'
  '${ROOT}/scripts/01_prepare_inputs.sh' '${CFG}'
  sync_log

  stage '02_submit_sparse_grm'
  '${ROOT}/scripts/02_submit_step0_sparse_grm_dx.sh' '${CFG}'
  sync_log

  stage '03_submit_null_model'
  '${ROOT}/scripts/03_submit_step1_null_model_dx.sh' '${CFG}'
  sync_log

  if [[ '${RUN_GBAT}' == '1' ]]; then
    stage '04_submit_gbat'
    '${ROOT}/scripts/04_submit_step2_gbat_dx.sh' '${CFG}'
    sync_log
  else
    echo '[INFO] RUN_GBAT=0; skipping Step2 GBAT submission.'
    sync_log
  fi

  echo '[OK] Pipeline submission finished at:' \$(date)
  sync_log
" > "${RUN_LOG}" 2>&1 &

PID=$!
echo "${PID}" > "${LOG_DIR}/chr22_plumbing_${ts}.pid"

echo "[OK] Background runner PID=${PID}"
echo "[OK] Log file: ${RUN_LOG}"
echo "To follow log: tail -f ${RUN_LOG}"
echo "To find persisted log later: dx ls ${DX_LOG_DIR}"
