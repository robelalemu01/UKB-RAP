#!/usr/bin/env bash
# File: bootstrap/rap_bootstrap.sh
#
# RAP bootstrap: make session setup repeatable & SAFE.
# Run with:
#   bash bootstrap/rap_bootstrap.sh
# Do NOT run with:
#   source bootstrap/rap_bootstrap.sh
#
# This script is intentionally non-fatal for convenience steps (ssh/git pull),
# so it won't "kill" your JupyterLab terminal if something minor fails.

set -u
set -o pipefail

echo "== RAP bootstrap =="
echo "pwd:    $(pwd)"
echo "whoami: $(whoami)"
echo "date:   $(date)"
echo

###############################################################################
# 1) DNAnexus (dx) environment
###############################################################################
if command -v dx >/dev/null 2>&1; then
  echo "[dx] detected: $(dx --version 2>/dev/null || echo 'version unavailable')"

  # Load dx env vars if possible (do not fail if it errors)
  if eval "$(dx env --bash 2>/dev/null)"; then
    :
  else
    echo "[dx] dx env --bash failed (often OK in some sessions)."
  fi

  # Ensure DX_WORKSPACE_ID is set (some apps expect it)
  if [[ -z "${DX_WORKSPACE_ID:-}" && -n "${DX_PROJECT_CONTEXT_ID:-}" ]]; then
    export DX_WORKSPACE_ID="${DX_PROJECT_CONTEXT_ID}"
  fi

  echo "[dx] DX_PROJECT_CONTEXT_ID=${DX_PROJECT_CONTEXT_ID:-}"
  echo "[dx] DX_WORKSPACE_ID=${DX_WORKSPACE_ID:-}"

  # Show current project (best-effort)
  echo "[dx] pwd: $(dx pwd 2>/dev/null || echo 'dx pwd failed')"
else
  echo "[dx] dx not found in PATH (ok if you're not using dx in this session)."
fi
echo

###############################################################################
# 2) SSH agent (for GitHub)
###############################################################################
echo "[ssh] ensuring ssh-agent is running..."
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  # Start agent (best-effort)
  if eval "$(ssh-agent -s)" >/dev/null 2>&1; then
    echo "[ssh] ssh-agent started."
  else
    echo "[ssh] could not start ssh-agent (continuing)."
  fi
else
  echo "[ssh] ssh-agent already running."
fi

KEY_PATH="${HOME}/.ssh/id_ed25519"
if [[ -f "$KEY_PATH" ]]; then
  # Add key (do not fail if it errors)
  ssh-add "$KEY_PATH" >/dev/null 2>&1 || echo "[ssh] ssh-add failed (continuing)."
  echo "[ssh] key present: $KEY_PATH"
else
  echo "[ssh] no key at $KEY_PATH (ok)."
fi

# Show loaded keys (best-effort)
ssh-add -l 2>/dev/null || echo "[ssh] no keys loaded (or agent unavailable)."
echo

###############################################################################
# 3) Git identity + optional fast-forward pull (safe)
###############################################################################
if command -v git >/dev/null 2>&1; then
  # Safe defaults (won't error if already set)
  git config --global user.name  "Robel Alemu" >/dev/null 2>&1 || true
  git config --global user.email "robelalemu01@users.noreply.github.com" >/dev/null 2>&1 || true

  echo "[git] configured:"
  echo "      name : $(git config --global user.name 2>/dev/null || echo '')"
  echo "      email: $(git config --global user.email 2>/dev/null || echo '')"

  # Only attempt git operations if we're inside a repo
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[git] repo: $(git rev-parse --show-toplevel 2>/dev/null || echo '')"
    echo "[git] remote (first 2 lines):"
    git remote -v | head -n 2 || true

    # Optional update: fast-forward only; do NOT fail if it can't
    if git pull --ff-only >/dev/null 2>&1; then
      echo "[git] pull: fast-forwarded (or already up-to-date)."
    else
      echo "[git] pull: skipped (not fast-forward, local changes, or auth issue)."
    fi
  else
    echo "[git] not inside a git repo (skipping pull)."
  fi
else
  echo "[git] git not found (skipping)."
fi
echo

echo "[OK] RAP bootstrap complete."