#!/usr/bin/env bash
# code-to-prd: reverse-engineer a Next.js codebase into a PRD.
#
# Entry point for the code-to-prd skill (#2726).
# Walker + extractor + redaction orchestrator. v1 = Next.js only.
#
# Usage:
#   bash code-to-prd.sh <target-codebase-path>
#
# Exit codes:
#   0 — PRD written successfully
#   1 — redaction sentinel halted the write (Layer 2 or Layer 3)
#   2 — preflight failed (gitleaks missing, no package.json, empty walker, not Next.js)
#   3 — IO error or write-deletion failure
#
# Phase 0 (this commit) — scaffold + preflight only. Phases 1-9 land in subsequent commits.
# See knowledge-base/project/specs/feat-code-to-prd-2726/tasks.md for phase progress.

set -uo pipefail

# Resolve skill and repo roots for sibling-script invocations.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_DIR="$(cd "${SKILL_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

REDACT_SENTINEL="${PLUGIN_DIR}/skills/incident/scripts/redact-sentinel.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: code-to-prd.sh <target-codebase-path>" >&2
  exit 2
fi

TARGET="$1"

# Phase 0 preconditions (FR6.2 revised + FR1.1).
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "code-to-prd: gitleaks not found on PATH; install via 'brew install gitleaks' or equivalent." >&2
  echo "  Layer 3 verifier is mandatory (single-user incident threshold)." >&2
  exit 2
fi

if [[ ! -d "${TARGET}" ]]; then
  echo "code-to-prd: target directory does not exist: ${TARGET}" >&2
  exit 2
fi

if [[ ! -f "${TARGET}/package.json" ]]; then
  echo "code-to-prd: no package.json at target root: ${TARGET}/package.json" >&2
  exit 2
fi

if [[ ! -x "${REDACT_SENTINEL}" ]]; then
  echo "code-to-prd: incident/scripts/redact-sentinel.sh missing or not executable." >&2
  echo "  expected at: ${REDACT_SENTINEL}" >&2
  exit 2
fi

# Phase 1+ (walker, framework detection, extraction, render, redaction, gap-analysis)
# lands in subsequent commits.
echo "code-to-prd: Phase 0 preconditions passed."
echo "  target: ${TARGET}"
echo "  gitleaks: $(gitleaks version 2>&1 | head -1)"
echo "  redact-sentinel: present"
echo "code-to-prd: implementation in progress (see tasks.md)."
exit 0
