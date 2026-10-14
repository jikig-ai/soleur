#!/usr/bin/env bash
# Follow-through verification for #5813 (post-deploy confirmation of PR #5807).
#
# PR #5807 tightened the apply-inngest-rls.yml self-heal cron from daily
# (17 4 * * *) to hourly (17 * * * *), to bound the cosmetic
# rls_disabled_in_public advisor-recurrence window on soleur-inngest-prd
# (pigsfuxruiopinouvjwy) to <=1h. #8450 later relaxed it to 4-hourly
# (17 */4 * * *) for the org concurrency budget — the bound is now <=4h.
#
# This probe confirms the self-heal cadence stays live AND green, without any
# Supabase secret:
#   - Asserts >=1 SUCCESSFUL *scheduled* run of apply-inngest-rls.yml within the
#     last 6 hours. The workflow's success path requires its authoritative
#     catalog/grant gate to report violations=0, so a green scheduled run is a
#     direct proxy for "RLS lockdown holds AND advisor recurrence is bounded".
#   - A still-daily cron would fire once per 24h, so a rolling 6h window finds
#     ZERO scheduled runs ~75% of the time -> FAIL; the 4-hourly cadence
#     always places >=1 fire inside it (max tick gap 4h < 6h window). The
#     window was 2h while the cron was hourly; #8450's relaxation made ~50%
#     of 2h windows legitimately empty — a false FAIL/reopen shape.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>=1 successful scheduled run in the last 6h; sweeper closes #5813)
#   1 = FAIL       (no successful scheduled run in the window; sweeper comments, leaves open)
#   * = TRANSIENT  (gh/API unreachable or unparseable; retry next sweep)
#
# Required env: GH_TOKEN + GH_REPO (provided ONLY if named in the directive's `secrets=` clause -- run_one forwards nothing else; there is no baseline) — no extra secrets.
#
# Close criteria (from #5813 / PR #5807):
#   - apply-inngest-rls.yml has a conclusion=success, event=schedule run inside
#     the cadence window (now 6h — bounds the 4-hourly schedule post-#8450).

set -uo pipefail

WORKFLOW="apply-inngest-rls.yml"
WINDOW_SECONDS=21600  # 6 hours — > the 4h tick gap of the post-#8450 cadence

RUNS=$(gh run list --workflow "$WORKFLOW" --limit 30 \
  --json conclusion,event,createdAt 2>/dev/null)
RC=$?
if [[ "$RC" -ne 0 || -z "$RUNS" ]]; then
  echo "TRANSIENT: gh run list failed for $WORKFLOW (rc=$RC)" >&2
  exit 2
fi

# Cutoff = now - WINDOW_SECONDS, as an ISO-8601 UTC string for a lexicographic
# compare (ISO-8601 UTC 'Z' timestamps sort chronologically as strings).
CUTOFF=$(date -u -d "@$(( $(date -u +%s) - WINDOW_SECONDS ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
if [[ -z "$CUTOFF" ]]; then
  echo "TRANSIENT: could not compute cutoff timestamp" >&2
  exit 2
fi

FRESH_OK=$(printf '%s' "$RUNS" | jq -r --arg cutoff "$CUTOFF" '
  [ .[]
    | select(.event == "schedule")
    | select(.conclusion == "success")
    | select(.createdAt >= $cutoff)
  ] | length' 2>/dev/null)

if ! [[ "$FRESH_OK" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse run list JSON" >&2
  exit 2
fi

if [[ "$FRESH_OK" -ge 1 ]]; then
  echo "PASS: $FRESH_OK successful scheduled $WORKFLOW run(s) since $CUTOFF — self-heal cadence live and green (PR #5807 / #5813)"
  exit 0
fi

echo "FAIL: no successful scheduled $WORKFLOW run since $CUTOFF (window=${WINDOW_SECONDS}s)."
echo "      Either the 4-hourly cadence is not delivering, the schedule reverted to daily, or the self-heal gate is failing."
printf '%s' "$RUNS" | jq -r '.[] | select(.event == "schedule") | "  - \(.conclusion) @ \(.createdAt)"' 2>/dev/null | head -5
exit 1
