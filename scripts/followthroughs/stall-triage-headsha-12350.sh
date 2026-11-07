#!/usr/bin/env bash
# Follow-through verification for the scope-out filed from PR #12350 (review round, agent-native seat, P3).
#
# The merge-queue stall issue body's Triage step 2 tells the reader to correlate merge_group runs "by
# headSha/createdAt", but its `gh run list --json` field list has no `headSha`. Pre-existing (PR #12295). The fix
# is one token in .github/workflows/merge-queue-stall-check.yml; the PR that filed this left the issue-body
# template byte-identical on purpose (technical ruling E2).
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS            (the template's step 2 field list now carries headSha; the sweeper closes the issue)
#   3 = CANNOT ESTABLISH (the workflow file or the step 2 line is not readable in the checkout)
#   5 = ACTION REQUIRED (the dated re-evaluation trigger passed and the gap is still open: do, drop or re-date)
#
# No secrets: the probe reads one file in the sweeper's checkout.

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || { echo "CANNOT ESTABLISH: could not resolve the repository root"; exit 3; }
WF="$ROOT/.github/workflows/merge-queue-stall-check.yml"
[ -f "$WF" ] || { echo "CANNOT ESTABLISH: $WF is not in the checkout"; exit 3; }

# The Triage step 2 command line is the only one that lists runs by `--event merge_group` with a `--json` field list.
line="$(grep -F -- '--event merge_group --limit 100 --json ' "$WF" || true)"
[ -n "$line" ] || { echo "CANNOT ESTABLISH: the Triage step 2 gh run list line was not found (the template moved?)"; exit 3; }

# The same physical line also carries the prose "correlate ... by headSha/createdAt", so the test must read the --json
# FIELD LIST itself (the comma-separated token after --json), never the whole line.
fields="${line#*--event merge_group --limit 100 --json }"; fields="${fields%%[[:space:]]*}"
[ -n "$fields" ] || { echo "CANNOT ESTABLISH: the --json field list is empty"; exit 3; }

case ",$fields," in
  *,headSha,*) echo "PASS: the Triage step 2 --json field list now carries headSha"; exit 0 ;;
  *) echo "ACTION REQUIRED: the dated re-evaluation trigger for this scope-out (filed from PR #12350) has passed and the Triage step 2 --json field list still lacks headSha. Re-read the issue body, decide to do / drop / re-date, and record the decision here."; exit 5 ;;
esac
