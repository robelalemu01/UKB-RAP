#!/usr/bin/env bash
set -euo pipefail

# RAP bootstrap: make session setup repeatable & safe.
# Run with:  bash bootstrap/rap_bootstrap.sh
# (Do NOT "source" it.)

echo "== RAP bootstrap =="
echo "pwd: $(pwd)"
echo "whoami: $(whoami)"
echo "date: $(date)"

# --- dx env / project selection ---
if command -v dx >/dev/null 2>&1; then
  echo "dx detected: $(dx --version 2>/dev/null || true)"

  # If available, load dx environment variables (harmless if already set)
  eval "$(dx env --bash)" || true

  # Ensure DX_WORKSPACE_ID set (some apps expect it)
  if [[ -z "${DX_WORKSPACE_ID:-}" && -n "${DX_PROJECT_CONTEXT_ID:-}" ]]; then
    export DX_WORKSPACE_ID="${DX_PROJECT_CONTEXT_ID}"
  fi

  echo "DX_PROJECT_CONTEXT_ID=${DX_PROJECT_CONTEXT_ID:-}"
  echo "DX_WORKSPACE_ID=${DX_WORKSPACE_ID:-}"

  # If you want, uncomment this to auto-select current project context
  # if [[ -n "${DX_PROJECT_CONTEXT_ID:-}" ]]; then
  #   dx select "${DX_PROJECT_CONTEXT_ID}" >/dev/null || true
  # fi
else
  echo "dx not found in PATH (ok if you're not using dx in this session)."
fi

# --- ssh-agent (for github) ---
# Start an agent only if not running
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  echo "Starting ssh-agent..."
  eval "$(ssh-agent -s)" >/dev/null
fi

# Add key if it exists
if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  ssh-add "${HOME}/.ssh/id_ed25519" >/dev/null 2>&1 || true
  echo "ssh key added (if not already)."
else
  echo "No ${HOME}/.ssh/id_ed25519 found (ok)."
fi

# --- repo sanity ---
# Helpful git identity for commits inside RAP containers (safe defaults)
if command -v git >/dev/null 2>&1; then
  git config --global user.name  "Robel Alemu" || true
  # Use GitHub noreply email to avoid exposing personal email
  git config --global user.email "robelalemu01@users.noreply.github.com" || true
  echo "git configured: $(git config --global user.name) / $(git config --global user.email)"
fi

echo "Bootstrap done."