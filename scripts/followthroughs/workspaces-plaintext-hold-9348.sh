#!/usr/bin/env bash
# Follow-through for tracker #9380: the operator hold on PR #9348 (PR B of #6604 step 7, the
# plaintext-wipe convergence PR) must not outlive its two time bounds. Spec: PR #9348's plan,
# section `## Operator Holds` (that plan lives on #9348's branch until it merges, so it is cited
# by PR and section, not by a path that would 404 on main).
#
# READ-ONLY: this probe reads `gh` and nothing else; it never dispatches, merges or comments.
# It is NOT notify-only: exit 0 makes the sweeper CLOSE tracker #9380, so a false 0 would close
# it while the hold is live. Exit 0 is reachable only from a MERGED #9348 into main with a
# recorded mergedAt. The probe never exits 1.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              #9348 is merged into main (the hold cleared through the normal path).
#   5 = ACTION REQUIRED   #9348 is open on or after DEADLINE_ISO (the abandon/expiry decision is
#                         due, whether or not wipe dispatch D ran); OR the earliest successful
#                         workspaces-plaintext-forget.yml run on main finished more than 48 h ago
#                         and #9348 is still unmerged (post-forget bound; the first success is the
#                         run that removed the addresses, so an idempotent re-dispatch cannot
#                         restart the clock); OR #9348 was closed WITHOUT merging (the abandon
#                         branch: confirm its ledger-extension PR merged, then close the tracker
#                         by hand).
#   2 = NOT YET           open, before DEADLINE_ISO, and no forget older than 48 h.
#   3 = CANNOT ESTABLISH  a `gh`/`jq`/`date` call failed or returned something unusable.
#
# Credentials: needs GH_TOKEN. The sweeper runs probes under `env -i`, so the tracker directive
# must declare `secrets=GH_TOKEN` (it does). The probe never prints the token.
#
# Test seams: GH_BIN (the gh binary), NOW_EPOCH (the clock), FT_REPO (the repo). The sweeper's
# `env -i` does not forward them, so they are inert in production.
#
# RETIREMENT: delete this probe, scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh and
# the `run_suite "scripts/workspaces-plaintext-hold-9348"` line (with its comment) in
# scripts/test-all.sh once tracker #9380 is closed.

set -uo pipefail

REPO="${FT_REPO:-jikig-ai/soleur}"
PR=9348
DEADLINE_ISO='2026-10-15T00:00:00Z'
FORGET_BOUND_S=$((48 * 3600))
GH="${GH_BIN:-gh}"

DEADLINE_EPOCH=$(date -u -d "$DEADLINE_ISO" +%s 2>/dev/null)
NOW="${NOW_EPOCH:-$(date -u +%s 2>/dev/null)}"
if ! [[ "$DEADLINE_EPOCH" =~ ^[0-9]+$ && "$NOW" =~ ^[0-9]+$ ]]; then
  echo "CANNOT ESTABLISH: the clock or the deadline did not resolve to an epoch" >&2
  exit 3
fi

ERR_FILE=$(mktemp)
trap 'rm -f "$ERR_FILE"' EXIT

# First line of the last gh stderr, printable and bounded, so a tracker comment names the cause.
gh_err() { head -n 1 "$ERR_FILE" 2>/dev/null | tr -cd '[:print:]' | cut -c1-200; }

if ! PR_JSON=$("$GH" pr view "$PR" --repo "$REPO" --json state,mergedAt,baseRefName 2>"$ERR_FILE"); then
  echo "CANNOT ESTABLISH: gh pr view $PR failed: $(gh_err)" >&2
  exit 3
fi
STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null)
case "$STATE" in
  MERGED)
    MERGED_AT=$(printf '%s' "$PR_JSON" | jq -r '.mergedAt // empty' 2>/dev/null)
    BASE=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // empty' 2>/dev/null)
    if [[ -z "$MERGED_AT" || "$BASE" != "main" ]]; then
      echo "CANNOT ESTABLISH: #$PR reports MERGED but mergedAt/base is not a merge into main (base='$(printf '%.40s' "$BASE" | tr -cd '[:print:]')')" >&2
      exit 3
    fi
    echo "PASS: #$PR merged into main at $MERGED_AT — the hold cleared."
    exit 0 ;;
  CLOSED)
    echo "ACTION REQUIRED: #$PR was closed WITHOUT merging — the abandon branch applies. Confirm the ledger-extension PR merged (scripts/encryption-posture-ledger.json hcloud_volume.workspaces row), then close this tracker by hand."
    exit 5 ;;
  OPEN) ;;
  *)
    echo "CANNOT ESTABLISH: unexpected PR state '$(printf '%.40s' "$STATE" | tr -cd '[:print:]')'" >&2
    exit 3 ;;
esac

if [[ "$NOW" -ge "$DEADLINE_EPOCH" ]]; then
  echo "ACTION REQUIRED: #$PR is still open on or after ${DEADLINE_ISO%%T*} — the abandon/expiry decision is due (PR #9348 plan, ## Operator Holds)."
  exit 5
fi

if ! RUN_JSON=$("$GH" run list --repo "$REPO" --workflow workspaces-plaintext-forget.yml --branch main \
    --status success --limit 100 --json updatedAt 2>"$ERR_FILE"); then
  echo "CANNOT ESTABLISH: gh run list for workspaces-plaintext-forget.yml failed: $(gh_err)" >&2
  exit 3
fi
# The earliest successful forget run is the one that removed the addresses. The list must be an
# array of rows each carrying a string updatedAt; anything else is "could not measure", never
# "no forget yet".
if ! FORGET_AT=$(printf '%s' "$RUN_JSON" | jq -er '
    if type != "array" then error("not an array")
    elif length == 0 then ""
    elif all(.[]; (.updatedAt | type) == "string" and (.updatedAt | length) > 0) then (map(.updatedAt) | min)
    else error("row without updatedAt") end' 2>/dev/null); then
  echo "CANNOT ESTABLISH: could not parse the forget run list" >&2
  exit 3
fi
if [[ -n "$FORGET_AT" ]]; then
  if ! [[ "$FORGET_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
      || ! FORGET_EPOCH=$(date -u -d "$FORGET_AT" +%s 2>/dev/null); then
    echo "CANNOT ESTABLISH: unparseable forget updatedAt '$(printf '%.40s' "$FORGET_AT" | tr -cd '[:print:]')'" >&2
    exit 3
  fi
  if (( NOW - FORGET_EPOCH > FORGET_BOUND_S )); then
    echo "ACTION REQUIRED: the first successful forget run ended at $FORGET_AT (>48 h ago) and #$PR is still unmerged — the apply pause ends only by merging it (PR #9348 plan, ## Operator Holds)."
    exit 5
  fi
  echo "NOT YET: forget ran at $FORGET_AT (<48 h ago); #$PR open, awaiting evidence fill + merge."
  exit 2
fi

echo "NOT YET: #$PR open before ${DEADLINE_ISO%%T*}; no successful forget run on main yet."
exit 2
