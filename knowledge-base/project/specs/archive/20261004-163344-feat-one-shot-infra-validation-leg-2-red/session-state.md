# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-04-fix-cron-egress-self-heal-suite-sigpipe-disposition-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None

### Decisions
- Guard only the shim's flood pipeline (`{ head | tr; } 2>/dev/null || exit 141`); drop the unreachable `echo || exit 141`.
- Test-first: five rows that force SIGPIPE ignored on entry (`with_sigpipe_ignored` helper + /proc check); floors 116->121 and 23->24 in place.
- Fleet sweep found no other infra suite that changes exit code between default and ignored SIGPIPE.
- PR closes the open duplicate-defect issue 9473 with a correction (write-more-bytes direction cannot fix it).
- Earlier reds at b77bee370 (evidence freshness) and c6ae165d0e (leg 4/4) are out of scope.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, plus review agents (see plan)

## Work Phase
- Status: implementation complete, affected gate green (rc=0, 170/170 selected suites; infra runner ran nested)
- Evidence (for the PR body "Red to green" heading):
  - RED default ambient, before the shim fix: `self-heal suite: 119 passed, 2 failed (121 cases)`; failing rows: `control, SIGPIPE ignored: ... (want='141' got='0')` and `mutant caught: SIGPIPE ignored: ...`
  - RED CI ambient (`bash -c "trap '' PIPE; bash <suite>"`), before the fix: `117 passed, 4 failed (121 cases)` (the 2 existing ambient rows plus the 2 forced rows)
  - GREEN after the fix, both ambients: `121 passed, 0 failed (121 cases)`; 5 runs per ambient, 0 failures, no "Broken pipe" text
  - Mutation battery (scratch copies, restore verified): revert guard -> 2 forced rows RED; neuter helper -> canary + routing + ignored mutant RED; wrong status (exit 1) -> both control rows RED; unconditional guard -> both capture-form rows RED; drop probe_out prefix -> routing + ignored mutant RED
  - guard-vacuity-floor 23/23, lint-guard-contract ok, lint-infra-no-human-steps ok, shellcheck clean, markdownlint clean, discoverability probe prints 1
