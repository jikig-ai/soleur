#!/usr/bin/env bash
# Follow-through verification for the consolidated `parked` merge-hold follow-up (filed from PR #12342).
#
# The `parked` label is a best-effort convention backed by a local hook and a drain-prs triage tier.
# It is not a server-side control (the hook is a text matcher with known bypasses, and several merge
# sites never read the label). This probe fires when the convention starts being relied on, so the
# server-side route is re-evaluated at the moment it matters instead of after a bypass.
#
# Re-evaluation trigger (OR): (a) a pull request other than the two baseline ones carries the
# `parked` label, or (b) the date backstop 2026-12-08 has passed. Baseline measured 2026-11-08:
# `gh pr list --label parked --state all` returned 2 (#12342, this PR; #10081, merged earlier), so
# both are excluded and the probe starts at 0.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   2 = NOT YET             neither trigger has fired
#   3 = CANNOT ESTABLISH    gh unreachable, no token, or an unreadable response
#   5 = ACTION REQUIRED     a trigger fired: re-evaluate the server-side enforcement (a human acts)
#  78 = REFUSED             running under `set -x` with a live GH_TOKEN (#7797)
#
# Directive (in the follow-up issue body, unfenced at column 0):
#   <!-- soleur:followthrough script=scripts/followthroughs/parked-merge-hold-enforcement-12342.sh earliest=2026-11-08T00:00:00Z secrets=GH_TOKEN -->
#
# Required env: GH_TOKEN with pull-requests:read (declared via the directive's secrets= clause).
set -uo pipefail

# Refuse to run traced with a live credential: `set -x` would expand the gh call, token included,
# into a public Actions log (same guard as the sibling probes, #7797).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
BASELINE_A=12342
BASELINE_B=10081
BACKSTOP_DATE="2026-12-08"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "CANNOT ESTABLISH: GH_TOKEN not set" >&2
  exit 3
fi

list_rc=0
extra=$(gh pr list --repo "$REPO" --label parked --state all --limit 100 --json number \
  --jq "[.[] | select(.number != ${BASELINE_A} and .number != ${BASELINE_B})] | length" 2>/dev/null) || list_rc=$?
if [[ "$list_rc" -ne 0 ]]; then
  echo "CANNOT ESTABLISH: gh pr list --label parked failed (rc ${list_rc})" >&2
  exit 3
fi
if [[ ! "$extra" =~ ^[0-9]+$ ]]; then
  echo "CANNOT ESTABLISH: gh pr list returned no numeric count" >&2
  exit 3
fi

if [[ "$extra" -ge 1 ]]; then
  echo "ACTION REQUIRED: ${extra} pull request(s) beyond the baseline carry the parked label. The label is now relied on: re-evaluate server-side enforcement of the parked hold." >&2
  exit 5
fi

now=$(date -u +%s)
backstop=$(date -u -d "$BACKSTOP_DATE" +%s 2>/dev/null) || backstop=""
if [[ ! "$now" =~ ^[0-9]+$ || ! "$backstop" =~ ^[0-9]+$ ]]; then
  echo "CANNOT ESTABLISH: could not compute the date backstop" >&2
  exit 3
fi
if [[ "$now" -ge "$backstop" ]]; then
  echo "ACTION REQUIRED: the ${BACKSTOP_DATE} backstop has passed with the parked hold still best-effort. Decide: enforce it server-side, or close this follow-up with the reason." >&2
  exit 5
fi

echo "NOT YET: no pull request beyond the baseline carries the parked label and ${BACKSTOP_DATE} has not been reached"
exit 2
