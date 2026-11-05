#!/usr/bin/env bash
# Follow-through for the items PR 12136 (Closes #12102) leaves open after moving every claude-code-action
# pin in this repository to v1.0.263: (1) a real dispatched run of the operator-digest workflow in the private
# operator-digest repository after the updated asset is re-provisioned there (copies already provisioned keep
# the old pin until then; the lockstep guard cannot see them), and (2) a refresh path for repositories that
# already ran soleur:constraint-scaffold (the script refuses to overwrite), and (3) stripping the action version
# tags from the Art. 30 register so they cannot go stale again (CLO ruling 2026-11-05). The tracking issue
# (#12146) carries one checklist box per item; this probe fires only once #12102 has closed and never auto-closes the issue
# while a box is unticked, because the items are independent and fixing one must not close the tracker.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       every checklist box in the tracking issue is ticked (sweeper closes)
#   2 = NOT YET    #12102 is still open (the trigger has not fired)
#   3 = CANNOT ESTABLISH  no token, an unreadable response, the tracking issue is not the expected open one
#                  (wrong title or missing deferred-scope-out label), or it has fewer than MIN_BOXES boxes
#   5 = ACTION REQUIRED   #12102 is closed and at least one box in the tracking issue is still unticked
#  78 = REFUSED    running under `set -x` with a live GH_TOKEN (#7797)
#
# Required env: GH_TOKEN with issues:read (declared via the directive's secrets= clause).
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
TRIGGER_ISSUE=12102
TRACKER_ISSUE=12146
TITLE_PREFIX="review: claude-code-action v1.0.263 follow-ups (operator-digest run, scaffold refresh)"
MIN_BOXES=2

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "CANNOT ESTABLISH: GH_TOKEN not set" >&2
  exit 3
fi

state_rc=0
state=$(gh issue view "$TRIGGER_ISSUE" --repo "$REPO" --json state --jq .state 2>/dev/null) || state_rc=$?
if [[ "$state_rc" -ne 0 || ( "$state" != "OPEN" && "$state" != "CLOSED" ) ]]; then
  echo "CANNOT ESTABLISH: reading #${TRIGGER_ISSUE} state failed (rc ${state_rc})" >&2
  exit 3
fi
if [[ "$state" == "OPEN" ]]; then
  echo "NOT YET: #${TRIGGER_ISSUE} is still open"
  exit 2
fi

# Read the tracker by number: a list scan is capped (hundreds of open deferred-scope-out issues) and would
# silently lose it once enough newer ones exist.
view_rc=0
raw=$(gh issue view "$TRACKER_ISSUE" --repo "$REPO" --json state,title,body,labels 2>/dev/null) || view_rc=$?
if [[ "$view_rc" -ne 0 || -z "$raw" ]]; then
  echo "CANNOT ESTABLISH: reading tracking issue #${TRACKER_ISSUE} failed (rc ${view_rc})" >&2
  exit 3
fi

pick_rc=0
body=$(printf '%s' "$raw" | jq -r --arg p "$TITLE_PREFIX" \
  'if .state == "OPEN" and (.title | startswith($p)) and (any(.labels[]; .name == "deferred-scope-out")) then .body else error("not the expected open tracker") end' \
  2>/dev/null) || pick_rc=$?
if [[ "$pick_rc" -ne 0 || -z "$body" ]]; then
  echo "CANNOT ESTABLISH: #${TRACKER_ISSUE} is not the open '${TITLE_PREFIX}...' deferred-scope-out issue (rc ${pick_rc})" >&2
  exit 3
fi

# `grep -c` prints 0 and exits 1 on no match; that is an answer, not a failure. Boxes may be indented or use `*`.
total=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*[-*] \[[ xX]\] ' || true)
unticked=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*[-*] \[ \] ' || true)
if [[ ! "$total" =~ ^[0-9]+$ || ! "$unticked" =~ ^[0-9]+$ || "$total" -lt "$MIN_BOXES" ]]; then
  echo "CANNOT ESTABLISH: expected at least ${MIN_BOXES} checklist boxes in #${TRACKER_ISSUE}, found '${total}'" >&2
  exit 3
fi

if [[ "$unticked" -gt 0 ]]; then
  echo "ACTION REQUIRED: #${TRIGGER_ISSUE} is closed and ${unticked} of ${total} checklist items in #${TRACKER_ISSUE} are still unticked"
  exit 5
fi
echo "PASS: all ${total} checklist items in #${TRACKER_ISSUE} are ticked"
exit 0
