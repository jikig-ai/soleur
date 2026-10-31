#!/usr/bin/env bash
# Follow-through verification: date-triggered re-evaluation of the scope-outs filed from PR #11653
# (dead-man heartbeat feeder). The directive's `earliest=` carries the date; the sweeper does not run this
# probe before it, so reaching this line means the re-evaluation is DUE and a human must act.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh): 5 = ACTION REQUIRED (rendered as such,
# the issue stays open). This probe never exits 0, so the sweeper never closes the issue by itself.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

echo "ACTION REQUIRED: the dated re-evaluation trigger for this scope-out (filed from PR #11653) has passed. Re-read the issue body, decide to do / drop / re-date, and record the decision here."
exit 5
