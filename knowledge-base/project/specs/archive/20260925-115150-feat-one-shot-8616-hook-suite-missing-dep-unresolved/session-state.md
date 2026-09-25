# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-test-hook-suite-missing-dep-not-green-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- guardrails hook blocked `gh issue create` twice (body file under /tmp unreadable / not written in the same call); fixed by writing the body inside the spec dir, filed #8773.
- Sharp-edges catalogue cites `.claude/hooks/memory-backstop.sh` as the portable-timeout example; it has no `gtimeout`. Real example: `git-commit-secret-scan.sh`. Plan corrected; catalogue itself not edited.

### Decisions
- Exit 3 (UNRESOLVED) for "a required tool is missing"; `run_suite` renders it as `[FAIL]` (same as 1) and top-level exits 1 — not-green end to end. test-all.sh and ci.yml unchanged.
- Missing file under test → exit 1 `FAIL:`; a single check skipped for a missing tool → exit non-zero.
- Applies to 40 (suite, tool) guard pairs across 25 `.claude/hooks/*.test.sh` files, incl. git arms.
- Regression guard: new `.claude/hooks/hook-suite-dep-unresolved.test.sh` re-runs each guarded suite with the tool shadowed off PATH; plus a static scan; promoted in `scripts/guard-vacuity-floor.test.sh`.
- Reverses #7190 item 5 with reasons; other test dirs tracked in #8773.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery, dhh/kieran/simplicity reviewers, cto, test-design-reviewer
