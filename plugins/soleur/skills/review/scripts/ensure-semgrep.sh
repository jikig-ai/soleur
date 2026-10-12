#!/usr/bin/env bash
# Ensure the semgrep CLI is on PATH AND RUNS. If missing or dead (resolves but
# crashes on invocation — the mise/python-latest shebang class, #9964),
# attempt an auto-install from the first available package manager. On success
# prints the path to the installed semgrep and exits 0. On failure prints a
# diagnostic to stderr and exits non-zero so callers can abort the review gate.
#
# Supported install paths (in order):
#   1. brew install semgrep         (macOS / Linuxbrew)
#   2. pipx install semgrep         (python user-env isolation)
#   3. python3 -m pip install --user semgrep  (pip user install)
#
# Exit codes:
#   0 - semgrep resolves on PATH AND `semgrep --version` executes
#   1 - install attempted but semgrep still does not run (incl. a fresh
#       install shadowed by a broken earlier PATH entry)
#   2 - no install path available (no brew, pipx, or python3 with pip) —
#       includes the dead-shim case: resolution is not enough to count as
#       present, so "no installer" is the honest code

set -euo pipefail

# semgrep_works: the single success gate — resolution AND execution. A
# `command -v` hit is necessary but not sufficient: a resolvable-but-dead
# shim must fall through to the install path exactly like an absent binary
# (#9964). Bounded when `timeout`/`gtimeout` exists — a mandatory gate that
# can hang is the same worst-shape failure as a vacuous pass.
semgrep_works() {
  command -v semgrep >/dev/null 2>&1 || return 1
  local t="" err
  if command -v timeout >/dev/null 2>&1; then t="timeout 30"; elif command -v gtimeout >/dev/null 2>&1; then t="gtimeout 30"; fi
  err="$($t semgrep --version 2>&1)" && return 0
  SEMGREP_VERSION_ERR="$err"
  return 1
}

dead_shim_diag() {
  local resolved
  resolved="$(command -v semgrep 2>/dev/null || echo "<unresolvable>")"
  echo "ERROR: semgrep resolves at $resolved but does not run (${SEMGREP_VERSION_ERR:-unknown error}) — a resolvable-but-dead shim (#9964)." >&2
}

if semgrep_works; then
  command -v semgrep
  exit 0
fi

if command -v semgrep >/dev/null 2>&1; then
  echo "semgrep resolves but does not run — treating as absent, attempting install" >&2
else
  echo "semgrep not found on PATH — attempting auto-install" >&2
fi

installed=0
if command -v brew >/dev/null 2>&1; then
  echo "installing via brew..." >&2
  if brew install semgrep >&2; then
    installed=1
    if semgrep_works; then command -v semgrep; exit 0; fi
  fi
  echo "brew install semgrep failed (or installed but still not runnable — a broken shim may be shadowing it)" >&2
fi

if command -v pipx >/dev/null 2>&1; then
  echo "installing via pipx..." >&2
  if pipx install semgrep >&2; then
    installed=1
    # pipx adds ~/.local/bin to PATH lazily; ensure binary is reachable.
    export PATH="$HOME/.local/bin:$PATH"
    if semgrep_works; then command -v semgrep; exit 0; fi
  fi
  echo "pipx install semgrep failed (or installed but still not runnable)" >&2
fi

if command -v python3 >/dev/null 2>&1; then
  echo "installing via python3 -m pip --user..." >&2
  if python3 -m pip install --user semgrep >&2; then
    installed=1
    export PATH="$HOME/.local/bin:$PATH"
    if semgrep_works; then command -v semgrep; exit 0; fi
  fi
  echo "pip --user install semgrep failed (or installed but still not runnable)" >&2
fi

if (( installed )); then
  dead_shim_diag
  echo "install path(s) ran but semgrep still does not run — remove the dead shim or fix PATH ordering" >&2
  exit 1
fi

if command -v semgrep >/dev/null 2>&1; then
  dead_shim_diag
  echo "no install path available (brew, pipx, or python3-pip required) — remove the dead shim or install a package manager" >&2
else
  echo "ERROR: no install path available (brew, pipx, or python3-pip required)" >&2
fi
exit 2
