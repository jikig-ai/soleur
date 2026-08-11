#!/usr/bin/env bash
# Follow-through verification for #5733 — operator confirms the 754ee124 strand is healed.
#
# Operator-confirmed pattern (per ship/SKILL.md §Step 3.5.B): AC12 is genuinely
# operator-driven — only the operator can retry /soleur:go on their live Concierge
# (needs a real Anthropic key + Concierge session; not CI-mechanizable). After the
# fix deploys, the operator retries on workspace 754ee124 and posts a verdict comment
# on #5733: `RESULT: PASS` (no strand) or `RESULT: FAIL` (still stranding). This probe
# reads that verdict — it does NOT eyeball a dashboard.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS       (operator posted RESULT: PASS; sweeper closes #5733)
#   1 = FAIL       (no verdict yet, or RESULT: FAIL; sweeper comments, leaves open)
#   * = TRANSIENT  (gh/network error; sweeper retries next sweep)
#
# Required secrets: GH_TOKEN (declared in the directive secrets= clause).
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

N=5733
# AUTHOR FILTER — load-bearing, and NOT optional. `jikig-ai/soleur` is a PUBLIC repo with issues
# open to the world, and this probe's exit code makes the sweeper act on the tracker. An unfiltered
# `.comments[].body` therefore accepts a verdict from ANY authenticated GitHub user: one HTTP POST
# of `RESULT: PASS` was enough. See #7448.
comments=$(gh issue view "$N" --repo jikig-ai/soleur --json comments --jq '.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") | .body' 2>/dev/null) || {
  echo "TRANSIENT: could not read #$N comments" >&2
  exit 2
}

if printf '%s\n' "$comments" | grep -qE '^RESULT: PASS'; then
  exit 0
fi
if printf '%s\n' "$comments" | grep -qE '^RESULT: FAIL'; then
  echo "FAIL: operator reported RESULT: FAIL on #$N — strand persists; capture the agent_readiness_self_stop .git shape and open a data-driven follow-up." >&2
  exit 1
fi
echo "FAIL: no RESULT: PASS/FAIL verdict on #$N yet (operator has not confirmed the post-deploy repro)." >&2
exit 1
