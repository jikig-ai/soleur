#!/usr/bin/env bash
# Pre-commit AGENTS.md "always-loaded" payload byte-cap gate.
#
# Computes B_ALWAYS = bytes(AGENTS.md) + bytes(AGENTS.core.md) via the
# shared library scripts/lib/agents-payload-bytes.sh, then:
#   - exits 1 with a ::error:: GitHub-Actions-style annotation when
#     B_ALWAYS exceeds AGENTS_BUDGET_CRITICAL_BYTES (default 22000)
#   - exits 0 with a ::warning:: annotation when B_ALWAYS exceeds
#     AGENTS_BUDGET_WARN_BYTES (default 20000) but is at or under critical
#   - exits 0 silently when B_ALWAYS is at or under the warn threshold
#
# Wired into lefthook.yml as the `agents-rule-budget` pre-commit command
# (priority 5). `--no-verify` bypasses per the precedent set by the sibling
# `gitleaks-staged` command — the load-bearing CI floor remains
# .github/workflows/scheduled-compound-promote.yml's post-apply revert.
#
# Issue: #3684. Plan:
# knowledge-base/project/plans/2026-05-12-chore-agents-md-precommit-hook-rule-budget-anchor-parity-plan.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/agents-payload-bytes.sh
source "$SCRIPT_DIR/lib/agents-payload-bytes.sh"

WARN_BYTES="${AGENTS_BUDGET_WARN_BYTES:-20000}"
CRITICAL_BYTES="${AGENTS_BUDGET_CRITICAL_BYTES:-22000}"

# compute_b_always prints `<index>\t<core>\t<sum>` on a single line.
read -r INDEX_BYTES CORE_BYTES TOTAL_BYTES < <(compute_b_always)

if (( TOTAL_BYTES > CRITICAL_BYTES )); then
  DELTA=$((TOTAL_BYTES - CRITICAL_BYTES))
  echo "::error file=AGENTS.core.md::AGENTS always-loaded payload ${TOTAL_BYTES} B exceeds harness performance threshold (${CRITICAL_BYTES} B) by ${DELTA} B. index=${INDEX_BYTES} core=${CORE_BYTES}. Trim before commit, or demote a wg-* rule from AGENTS.core.md to AGENTS.rest.md per CPO sign-off PR #3496 (only wg-* may be demoted; never hr-*). Bypass with --no-verify if you must (the load-bearing CI floor remains the post-apply revert in .github/workflows/scheduled-compound-promote.yml)." >&2
  exit 1
fi

if (( TOTAL_BYTES > WARN_BYTES )); then
  HEADROOM=$((CRITICAL_BYTES - TOTAL_BYTES))
  echo "::warning file=AGENTS.core.md::AGENTS always-loaded payload ${TOTAL_BYTES} B exceeds warn threshold (${WARN_BYTES} B); ${HEADROOM} B headroom under critical (${CRITICAL_BYTES} B). index=${INDEX_BYTES} core=${CORE_BYTES}. Consider trimming before adding more rules." >&2
fi

exit 0
