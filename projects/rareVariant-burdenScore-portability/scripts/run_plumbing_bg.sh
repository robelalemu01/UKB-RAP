#!/usr/bin/env bash
set -euo pipefail

# Resolve project root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CFG="${ROOT}/configs/chr22_plumbing.env"
LOG_DIR="${ROOT}/logs"
mkdir -p "${LOG_DIR}"

ts="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="${LOG_DIR}/chr22_plumbing_${ts}.log"
touch "${RUN_LOG}"

echo "[INFO] Project root: ${ROOT}"
echo "[INFO] Config: ${CFG}"
echo "[INFO] Log: ${RUN_LOG}"
[[ -f "${CFG}" ]] || { echo "ERROR: missing config ${CFG}" >&2; exit 1; }

nohup bash -lc "
  set -euo pipefail
  cd '${ROOT}'
  echo '[INFO] Starting pipeline at:' \$(date)
  echo '[INFO] PWD:' \$(pwd)
  echo '[INFO] Using config:' '${CFG}'

  '${ROOT}/scripts/01_prepare_inputs.sh' '${CFG}'
  '${ROOT}/scripts/02_step0_sparse_grm.sh'  '${CFG}'
  '${ROOT}/scripts/03_step1_null_model.sh'  '${CFG}'
  '${ROOT}/scripts/04_step2_gbat.sh'        '${CFG}'

  echo '[OK] Pipeline finished at:' \$(date)
" > "${RUN_LOG}" 2>&1 &

PID=$!
echo "${PID}" > "${LOG_DIR}/chr22_plumbing_${ts}.pid"

echo "[OK] Background runner PID=${PID}"
echo "[OK] Log file: ${RUN_LOG}"
echo "To follow log: tail -f ${RUN_LOG}"
