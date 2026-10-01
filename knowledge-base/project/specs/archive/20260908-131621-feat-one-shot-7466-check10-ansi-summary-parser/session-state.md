# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-08-fix-check10-ansi-summary-parser-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Four self-inflicted issues caught and corrected in-session:

1. Four false universal negatives in the first draft ("the only ANSI-strip filter" — five sites
   exist; "zero sibling parsers" — one exists; "no learning covers ANSI" — three do; "nothing greps
   this file's output" — one prose hit). Each from a grep that was shell-mangled or too narrow.
   Recorded as a Sharp Edge.
2. A design that would have introduced a NEW fail-open: the `-` sentinel reaching
   `[[ "-" -lt 131 ]]` returns false rather than crashing, silently disabling a SUT floor. Fixed by
   normalising inside the measured branch and gating each floor at its own comparison.
3. An `expect`-inclusive "measured" predicate would have misdiagnosed the all-skip run — the one
   case the gate exists to catch — as an unparseable summary.
4. A markdownlint (MD038) and a guard-contract-lint regression from the planner's own edits; the
   second (a dropped `**Mutation matrix**` label silently scoring 0 rows) is a recorded Sharp Edge.

`scripts/test-all.sh` could not run as a full gate — it refuses while a sibling worktree holds one
(#7553). That made the original AC concurrency-dependent, so the AC was rewritten
(`cq-ac-must-not-depend-on-concurrent-sessions`).

### Decisions
- Parser is PURE (path in, one line of five fields out, `-` for unread) rather than assigning caller
  globals. Measured: a process substitution is a pipe, so a multi-read parser returns `122 - - - -`
  for every fixture while the live path returns all five — self-checks and live run would disagree
  in exactly the way the bug looks.
- `summary_measured` reads `pass` and `fail` only, never `expect`. Bun omits `expect() calls` when
  zero, so including it would report the all-skip suppression case as unparseable.
- A three-token verdict enum was cut for a boolean — it created its own fall-through fail-open.
- Strip widened to ECMA-48 ranges under `LC_ALL=C`, not the issue's suggested `\x1b` SGR-only form:
  `\x1b` is GNU-only, and the narrow class leaves colon-SGR, DECSC and charset escapes standing.
- Rejected a reviewer-proposed `CHECK10_LOG_OVERRIDE` test seam: it would ship an env-var bypass
  into the gate whose thesis is that a suite asserting nothing is indistinguishable from one that
  passed.

Plan carries 14 mutation rows, 5 harness rows, 24 acceptance criteria.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents repo-research-analyst,
learnings-researcher, engineering:cto, scoped strong-model advisor consult, review panel
(dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist,
spec-flow-analyzer); scripts lint-guard-contract.py, lint-infra-no-human-steps.py,
lint-trap-tempfile-ownership.py, guard-vacuity-floor.test.sh, test-all.sh.
