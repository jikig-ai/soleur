#!/usr/bin/env bash
# Follow-through for #9348 (PR B of #6604 step 7): the operator hold on the plaintext-wipe
# convergence PR must not outlive its two time bounds. Spec: the PR B plan's `## Operator Holds`
# (knowledge-base/project/plans/2026-10-01-feat-workspaces-plaintext-wipe-pr-b-convergence-plan.md).
#
# READ-ONLY and NOTIFY-ONLY: reads `gh` and nothing else. It never dispatches, merges or closes.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              #9348 is merged (the hold cleared through the normal path).
#   5 = ACTION REQUIRED   #9348 is open on or after 2026-10-15 (the abandon/expiry decision is due);
#                         OR the latest successful workspaces-plaintext-forget.yml run on main
#                         finished more than 48 h ago and #9348 is still unmerged (post-forget bound);
#                         OR #9348 was closed WITHOUT merging (the abandon branch: confirm its
#                         ledger-extension PR merged, then close the tracker by hand).
#   2 = NOT YET           open, before 2026-10-15, and no forget older than 48 h.
#   3 = CANNOT ESTABLISH  a `gh` call failed or returned something unparseable.
#
# Test seams: GH_BIN (the gh binary) and NOW_EPOCH (the clock). Suite: workspaces-plaintext-hold-9348.test.sh.

set -uo pipefail

REPO="${FT_REPO:-jikig-ai/soleur}"
PR=9348
DEADLINE_EPOCH=$(date -u -d '2026-10-15T00:00:00Z' +%s)
FORGET_BOUND_S=$((48 * 3600))
GH="${GH_BIN:-gh}"
NOW="${NOW_EPOCH:-$(date -u +%s)}"

if ! PR_JSON=$("$GH" pr view "$PR" --repo "$REPO" --json state,mergedAt 2>/dev/null); then
  echo "CANNOT ESTABLISH: gh pr view $PR failed" >&2
  exit 3
fi
STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null)
case "$STATE" in
  MERGED)
    echo "PASS: #$PR merged at $(printf '%s' "$PR_JSON" | jq -r '.mergedAt') — the hold cleared."
    exit 0 ;;
  CLOSED)
    echo "ACTION REQUIRED: #$PR was closed WITHOUT merging — the abandon branch applies. Confirm the ledger-extension PR merged (scripts/encryption-posture-ledger.json hcloud_volume.workspaces row), then close this tracker by hand."
    exit 5 ;;
  OPEN) ;;
  *)
    echo "CANNOT ESTABLISH: unexpected PR state '${STATE}'" >&2
    exit 3 ;;
esac

if [[ "$NOW" -ge "$DEADLINE_EPOCH" ]]; then
  echo "ACTION REQUIRED: #$PR is still open on or after 2026-10-15 — the abandon/expiry decision is due (plan ## Operator Holds)."
  exit 5
fi

if ! RUN_JSON=$("$GH" run list --repo "$REPO" --workflow workspaces-plaintext-forget.yml --branch main \
    --status success --limit 1 --json databaseId,updatedAt 2>/dev/null); then
  echo "CANNOT ESTABLISH: gh run list for workspaces-plaintext-forget.yml failed" >&2
  exit 3
fi
if ! FORGET_AT=$(printf '%s' "$RUN_JSON" | jq -er 'if length == 0 then "" else .[0].updatedAt end' 2>/dev/null); then
  echo "CANNOT ESTABLISH: could not parse the forget run list" >&2
  exit 3
fi
if [[ -n "$FORGET_AT" ]]; then
  if ! FORGET_EPOCH=$(date -u -d "$FORGET_AT" +%s 2>/dev/null); then
    echo "CANNOT ESTABLISH: unparseable forget updatedAt '$FORGET_AT'" >&2
    exit 3
  fi
  if (( NOW - FORGET_EPOCH > FORGET_BOUND_S )); then
    echo "ACTION REQUIRED: the forget run finished at $FORGET_AT (>48 h ago) and #$PR is still unmerged — the apply pause ends only by merging it (plan ## Operator Holds)."
    exit 5
  fi
  echo "NOT YET: forget ran at $FORGET_AT (<48 h ago); #$PR open, awaiting evidence fill + merge."
  exit 2
fi

echo "NOT YET: #$PR open before 2026-10-15; no successful forget run on main yet."
exit 2
