#!/usr/bin/env bash
# Follow-through soak gate for #6407 (AC10): the /health-corroboration fix must hold for a
# 7-day soak with ZERO false `[ci/inngest-down]` P1s attributable to a TRANSIENT functions-query
# failure. Before #6407, a transient `/v0/gql functions` blip (→ `__FETCH_FAILED__` → the
# `inngest-inventory: FATAL` sentinel) false-positived as `inngest_down` → restart, even though
# inngest-server was UP (loopback `/health`=200). #6407 corroborates against `/health` and routes
# a `/health`=200 blip to the SOFT `functions_query_degraded` mode (no restart, no P1). This gate
# PASSES only when, over the window from just-after deploy to now, NO regression is observed.
#
# Two signals, both no-SSH:
#   (1) GitHub issues — no `[ci/inngest-down]` issue CREATED since deploy whose body/comments name
#       a functions-query / `__FETCH_FAILED__` root cause (that would mean the un-corroborated FATAL
#       path re-emerged). A GENUINE down (`/health` != 200) is NOT a regression and does not fail
#       this gate — only a functions-query-rooted false down does.
#   (2) Better Stack — the `SOLEUR_INNGEST_LIVENESS_VERDICT` marker stream (tag `inngest-inventory`).
#       A `mode=degraded health_code=200` row is the fix WORKING (a blip correctly soft-classified).
#       A `mode=down health_code=200` row would be a CONTRADICTION (down verdict despite /health=200)
#       and fails the gate. `mode=down health_code=<000|5xx>` is a genuine down (informational).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (no functions-query-rooted false down since deploy; sweeper closes the tracker)
#   1 = FAIL       (a functions-query-rooted `[ci/inngest-down]` OR a mode=down+health_code=200
#                   contradiction since deploy — the regression #6407 closes; leave open, investigate)
#   * = TRANSIENT  (GitHub / Better Stack unreachable or the deploy anchor unset; retry next sweep)
#
# Required env: GH_TOKEN + GH_REPO (GitHub issue read); BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}
# (read by scripts/betterstack-query.sh — already wired in scheduled-followthrough-sweeper.yml).
# Pin INNGEST_6407_DEPLOY_UTC to the merge/deploy UTC; the earliest= directive defers the first real
# check to >= deploy+7d.
# Directive for the tracking issue (#6407) body:
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-watchdog-functions-query-6407.sh earliest=<deploy+7d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,GH_TOKEN -->

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BQ="${INNGEST_6407_BQ_OVERRIDE:-$SCRIPT_DIR/../betterstack-query.sh}"
WINDOW="${INNGEST_6407_SOAK_WINDOW:-7d}"
GH_REPO="${GH_REPO:-}"

# Absolute window start — PIN to just after the #6407 deploy. Placeholder until pinned; the
# earliest= gate in the issue directive still defers the first real check to >= deploy+7d.
DEPLOY_UTC="${INNGEST_6407_DEPLOY_UTC:-<POST_DEPLOY_UTC>}"

if [[ "$DEPLOY_UTC" == "<POST_DEPLOY_UTC>" ]]; then
  echo "TRANSIENT: INNGEST_6407_DEPLOY_UTC not pinned — cannot scope the soak window to post-deploy." >&2
  exit 2
fi
if [[ -z "$GH_REPO" ]]; then
  echo "TRANSIENT: GH_REPO unset — cannot read GitHub issues." >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "TRANSIENT: gh CLI unavailable." >&2
  exit 2
fi

# --- (1) GitHub: any [ci/inngest-down] issue created since deploy with a functions-query root cause? ---
# The watchdog files ONE [ci/inngest-down] issue per episode; a functions-query regression would
# name __FETCH_FAILED__ / "functions query" in the body or a comment. list numbers created >= deploy.
DOWN_JSON="$(gh issue list --repo "$GH_REPO" --state all --label ci/inngest-down \
  --search "created:>=${DEPLOY_UTC}" --json number,title,body --limit 50 2>/dev/null)" || {
  echo "TRANSIENT: gh issue list failed (auth/network)." >&2; exit 2
}

REGRESSION_ISSUES=""
if [[ -n "$DOWN_JSON" && "$DOWN_JSON" != "[]" ]]; then
  # Fetch each issue's comments too — the root cause often lands in the failure_detail comment.
  while IFS= read -r num; do
    [[ -z "$num" ]] && continue
    body="$(gh issue view "$num" --repo "$GH_REPO" --json body,comments \
      --jq '.body + " " + ([.comments[].body] | join(" "))' 2>/dev/null || echo "")"
    if printf '%s' "$body" | grep -qiE '__FETCH_FAILED__|/v0/gql functions|functions[- ]query'; then
      REGRESSION_ISSUES="$REGRESSION_ISSUES #$num"
    fi
  done < <(printf '%s' "$DOWN_JSON" | jq -r '.[].number')
fi

if [[ -n "$REGRESSION_ISSUES" ]]; then
  echo "FAIL: [ci/inngest-down] issue(s) created since ${DEPLOY_UTC} carry a functions-query/__FETCH_FAILED__ root cause:${REGRESSION_ISSUES}. The un-corroborated FATAL path re-emerged — #6407 corroboration is not holding. Investigate before closing."
  exit 1
fi

# --- (2) Better Stack: SOLEUR_INNGEST_LIVENESS_VERDICT marker stream (fix working vs contradiction) ---
if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2; exit 2
fi
VERDICTS="$("$BQ" --since "$WINDOW" --grep SOLEUR_INNGEST_LIVENESS_VERDICT --limit 5000 2>/dev/null)"; bq_rc=$?
if [[ "$bq_rc" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (auth/config/network)." >&2; exit 2
fi

# A `mode=down health_code=200` row is a CONTRADICTION — a down verdict despite /health=200, which
# #6407 must never emit (that path is exactly what corroboration downgrades to degraded). Fail on it.
CONTRADICTIONS="$(printf '%s\n' "$VERDICTS" | grep -E 'mode=down[^0-9]+health_code=200|health_code=200[^0-9]+mode=down' | grep -c . || true)"
if [[ "$CONTRADICTIONS" -gt 0 ]]; then
  echo "FAIL: ${CONTRADICTIONS} SOLEUR_INNGEST_LIVENESS_VERDICT row(s) with mode=down AND health_code=200 since ${DEPLOY_UTC} — a down verdict despite /health=200 contradicts the #6407 corroboration. Investigate."
  exit 1
fi

DEGRADED="$(printf '%s\n' "$VERDICTS" | grep -c 'mode=degraded' || true)"
GENUINE_DOWN="$(printf '%s\n' "$VERDICTS" | grep -c 'mode=down' || true)"
echo "PASS: no functions-query-rooted [ci/inngest-down] and no mode=down/health_code=200 contradiction since ${DEPLOY_UTC} — #6407 /health-corroboration holds. (Markers in window: mode=degraded=${DEGRADED} soft-classified correctly; mode=down=${GENUINE_DOWN} genuine down/wedged, informational.)"
exit 0
