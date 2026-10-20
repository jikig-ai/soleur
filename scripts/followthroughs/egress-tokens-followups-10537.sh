#!/usr/bin/env bash
# Follow-through for the bundled review follow-ups of PR #10537 (egress-token mount on the deploy-started prod container).
#
# DATE TRIGGER (review-todo-structure.md, form 1): the directive's `earliest=` is the wall-clock gate and the probe body
# is trivial. The tracker's items (A-E) are NOT verified here: closure by this sweeper means 're-evaluate or re-file',
# never 'done' -- the issue body says so and keeps every box unchecked. Item D's real trigger is the production proof of
# the new mount; the date is only a floor.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh): 0 = PASS (close), 1 = FAIL, 2 = NOT YET, 3 = CANNOT
# ESTABLISH, 5 = ACTION REQUIRED, * = TRANSIENT.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). This probe reads no credential today; the refusal stays so a later edit that adds a
# probe body cannot leak one (scripts/lint-shell-trace-credential-refusal.py requires it in the prologue).
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: a probe may handle live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# Past `earliest=` the sweeper runs this: the date has arrived, so the re-evaluation is due.
exit 0
