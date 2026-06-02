#!/usr/bin/env bash
# Follow-through verification for #3950 (review: cla-evidence scripts hardening
# bundle). Machine-verified close gate for a deferred-scope-out issue — the
# first instance wiring a `deferred-scope-out` + `do-not-autoclose` issue into
# the follow-through sweeper. Returns:
#   0 = PASS      (close-criteria met -> sweeper auto-closes #3950)
#   1 = FAIL      (hardening regression -> sweeper leaves open, comments FAIL)
#   * = TRANSIENT (no post-merge green run yet / gh API failure -> retry next sweep)
#
# Requires GH_TOKEN. The sweeper runs verification scripts under `env -i`
# (PATH + HOME + directive-declared secrets= only), so this gh-using probe's
# directive MUST declare `secrets=GH_TOKEN` — otherwise `gh` is unauthenticated
# on the CI runner (where auth comes from GH_TOKEN, not ~/.config/gh) and part
# (b) returns exit 2 (transient) on every sweep, so #3950 never closes.
#
# Close criteria (the #3950 re-evaluation trigger, event-grep shape):
#   (a) the 4 hardening markers from PR #4784 are still present in-tree
#       (regression guard — a marker disappearing is a FAIL, not a close), AND
#   (b) at least one cla-evidence.yml run created AFTER the #4784 merge
#       (2026-06-02T09:14:45Z) completed green (no-regression confirmed).
#
# This script does NOT edit or close #3950 — the sweeper owns the close on exit 0.

set -uo pipefail

# ── Part (a): hardening-marker regression assertion (in-tree, no network) ────
# Runs FIRST (cheap) — the only exit-1/FAIL path. Resolve repo root so the
# script works regardless of the sweeper's CWD.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
CLA="$ROOT/apps/cla-evidence/scripts"
missing=0
[[ -f "$CLA/_cf-admin-token.sh" ]] || { echo "FAIL: missing _cf-admin-token.sh"; missing=1; }
[[ -f "$CLA/_r2-endpoint.sh"     ]] || { echo "FAIL: missing _r2-endpoint.sh"; missing=1; }
grep -qF 'env -u CF_ADMIN_TOKEN doppler run' "$CLA/gdpr-override.sh" 2>/dev/null \
  || { echo "FAIL: gdpr-override.sh lost the CF_ADMIN_TOKEN bearer scrub"; missing=1; }
grep -qE '^[[:space:]]*tombstone\)' "$CLA/inspect-evidence.sh" 2>/dev/null \
  || { echo "FAIL: inspect-evidence.sh lost the tombstone) case"; missing=1; }
if [[ "$missing" -ne 0 ]]; then
  echo "exit: FAIL (cla-evidence hardening regression — #3950 must stay open)"
  exit 1
fi

# ── Part (b): no-regression green-run probe (post-#4784 merge) ───────────────
# Absence of a post-merge green run is a wait-for-next-tick condition (exit 2),
# NOT a hardening FAIL — only part (a) returns exit 1.
MERGE_CUTOFF="2026-06-02T09:14:45Z"   # PR #4784 mergedAt (verified)
WORKFLOW="cla-evidence.yml"
RUN_LIMIT=20

# `gh run list --created '>=<ISO>'` filters server-side (no client-side date math).
RUNS_JSON=$(gh run list \
  --workflow "$WORKFLOW" \
  --status success \
  --created ">=${MERGE_CUTOFF}" \
  --limit "$RUN_LIMIT" \
  --json conclusion,createdAt \
  2>/dev/null)
GH_RC=$?
if [[ "$GH_RC" -ne 0 ]]; then
  echo "TRANSIENT: gh run list exited ${GH_RC} (network or auth failure)"
  exit 2
fi
if [[ -z "$RUNS_JSON" || "$RUNS_JSON" == "[]" ]]; then
  echo "TRANSIENT: no post-merge green ${WORKFLOW} run yet (waiting for next tick)"
  exit 2
fi
GREEN_COUNT=$(printf '%s' "$RUNS_JSON" | jq 'length' 2>/dev/null || echo 0)
if [[ "$GREEN_COUNT" -ge 1 ]]; then
  echo "PASS: ${GREEN_COUNT} post-merge green ${WORKFLOW} run(s); hardening markers intact."
  echo "exit: PASS (#3950 hardening verified — sweeper closes)"
  exit 0
fi
echo "TRANSIENT: parsed 0 post-merge green runs from gh response"
exit 2
