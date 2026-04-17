#!/usr/bin/env bash
# Ensure the semgrep CLI is on PATH. If missing, attempt an auto-install
# from the first available package manager. On success prints the path to
# the installed semgrep and exits 0. On failure prints a diagnostic to
# stderr and exits non-zero so callers can abort the review gate.
#
# Supported install paths (in order):
#   1. brew install semgrep         (macOS / Linuxbrew)
#   2. pipx install semgrep         (python user-env isolation)
#   3. python3 -m pip install --user semgrep  (pip user install)
#
# Exit codes:
#   0 - semgrep available on PATH (pre-installed or just installed)
#   1 - install attempted but failed
#   2 - no install path available (no brew, pipx, or python3 with pip)

set -euo pipefail

if command -v semgrep >/dev/null 2>&1; then
  command -v semgrep
  exit 0
fi

echo "semgrep not found on PATH — attempting auto-install" >&2

if command -v brew >/dev/null 2>&1; then
  echo "installing via brew..." >&2
  if brew install semgrep >&2; then
    command -v semgrep
    exit 0
  fi
  echo "brew install semgrep failed" >&2
fi

if command -v pipx >/dev/null 2>&1; then
  echo "installing via pipx..." >&2
  if pipx install semgrep >&2; then
    # pipx adds ~/.local/bin to PATH lazily; ensure binary is reachable.
    export PATH="$HOME/.local/bin:$PATH"
    if command -v semgrep >/dev/null 2>&1; then
      command -v semgrep
      exit 0
    fi
  fi
  echo "pipx install semgrep failed" >&2
fi

if command -v python3 >/dev/null 2>&1; then
  echo "installing via python3 -m pip --user..." >&2
  if python3 -m pip install --user semgrep >&2; then
    export PATH="$HOME/.local/bin:$PATH"
    if command -v semgrep >/dev/null 2>&1; then
      command -v semgrep
      exit 0
    fi
  fi
  echo "pip --user install semgrep failed" >&2
fi

echo "ERROR: no install path available (brew, pipx, or python3-pip required)" >&2
exit 2
