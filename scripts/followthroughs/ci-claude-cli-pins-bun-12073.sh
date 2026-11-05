#!/usr/bin/env bash
# Follow-through verification for the review follow-up of PR 12073 (Ref #12026): the CI-side claude CLI
# pin in scheduled-marketplace-drift.yml no longer embeds a Bun below 1.4.4.
#
# The shipped web-platform binaries moved to the 2.1.311 / 0.3.311 pair (Bun 1.4.4) in PR 12073. This CI
# workflow still installs claude-code 2.1.228 (a pre-existing pin, outside that PR's scope) and the
# claude-code-action uses bundle their own CLI. This probe tracks the one pin a plain version compare can
# see, and escalates once #12026 has closed.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       CLI_VERSION in scheduled-marketplace-drift.yml on main is >= 2.1.311 (sweeper closes)
#   2 = NOT YET    the pin is still old and #12026 is still open (the trigger has not fired)
#   3 = CANNOT ESTABLISH  gh unreachable, no token, or an unreadable workflow / issue response
#   5 = ACTION REQUIRED   #12026 is closed and the pin is still below 2.1.311: bump it (and re-check the
#                  claude-code-action uses; whether those jobs decode network Brotli is unverified)
#  78 = REFUSED    running under `set -x` with a live GH_TOKEN (#7797)
#
# Required env: GH_TOKEN with contents:read and issues:read (declared via the directive's secrets= clause).
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
WORKFLOW=".github/workflows/scheduled-marketplace-drift.yml"
FLOOR="2.1.311"
TRIGGER_ISSUE=12026

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "CANNOT ESTABLISH: GH_TOKEN not set" >&2
  exit 3
fi

content_rc=0
raw=$(gh api "repos/${REPO}/contents/${WORKFLOW}?ref=main" --jq '.content' 2>/dev/null) || content_rc=$?
if [[ "$content_rc" -ne 0 || -z "$raw" ]]; then
  echo "CANNOT ESTABLISH: reading ${WORKFLOW} on main failed (rc ${content_rc})" >&2
  exit 3
fi
decode_rc=0
body=$(printf '%s' "$raw" | base64 -d 2>/dev/null) || decode_rc=$?
if [[ "$decode_rc" -ne 0 || -z "$body" ]]; then
  echo "CANNOT ESTABLISH: ${WORKFLOW} content did not decode (rc ${decode_rc})" >&2
  exit 3
fi

# Exactly one `CLI_VERSION: "x.y.z"` assignment is expected; zero or several is an unreadable shape.
mapfile -t versions < <(printf '%s\n' "$body" | sed -n 's/^[[:space:]]*CLI_VERSION:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p')
if [[ "${#versions[@]}" -ne 1 || ! "${versions[0]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "CANNOT ESTABLISH: expected exactly one CLI_VERSION x.y.z assignment in ${WORKFLOW}, found ${#versions[@]}" >&2
  exit 3
fi
pin="${versions[0]}"

lowest=$(printf '%s\n%s\n' "$pin" "$FLOOR" | sort -V | head -1)
if [[ "$lowest" == "$FLOOR" ]]; then
  echo "PASS: ${WORKFLOW} pins claude-code ${pin}, at or above ${FLOOR}"
  exit 0
fi

state_rc=0
state=$(gh issue view "$TRIGGER_ISSUE" --repo "$REPO" --json state --jq '.state' 2>/dev/null) || state_rc=$?
if [[ "$state_rc" -ne 0 || ! "$state" =~ ^(OPEN|CLOSED)$ ]]; then
  echo "CANNOT ESTABLISH: reading #${TRIGGER_ISSUE} state failed (rc ${state_rc})" >&2
  exit 3
fi

if [[ "$state" == "OPEN" ]]; then
  echo "NOT YET: ${WORKFLOW} pins ${pin} (< ${FLOOR}); #${TRIGGER_ISSUE} is still open, so the trigger has not fired"
  exit 2
fi

echo "ACTION REQUIRED: #${TRIGGER_ISSUE} is closed and ${WORKFLOW} still pins claude-code ${pin} (< ${FLOOR}). Bump CLI_VERSION and its pin-table test row, and re-check the claude-code-action uses." >&2
exit 5
