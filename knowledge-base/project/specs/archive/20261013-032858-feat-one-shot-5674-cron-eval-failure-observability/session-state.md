# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-29-fix-claude-eval-cron-failure-observability-plan.md
- Status: complete

### Errors
- None blocking. Two stale-CWD Read failures on subagent resume (recovered via find). One self-corrected planning defect (run-log final-attempt gate inversion) folded in as the headline P0 change.

### Decisions
- P0: gate ONLY the thrown path in run-log — a non-throwing `return {ok:false}` is terminal under Inngest retries:1, so it must be written on attempt 0 (original `if (failed && !isFinalAttempt) return` would drop the recorded failure). AC3 rewritten.
- Part 2 = classify-fatal, not flip-all: flip-all reverses the 2026-06-01 fix (#4730/PR#4727 — `claude --print` exits non-zero on healthy max-turns). Fatal classes (credit/auth/spawn-fault) flip red; benign non-zero stays green + records queryable reason. requires_cpo_signoff: true (departs from issue's literal text).
- Canary needs the 400 body: `postAnthropicMessage` discards it; widening it + 2-caller cross-consumer sweep is a blocking Phase-3 sub-task. Transient probe errors (429/500/529/network) re-throw, not false-page.
- Admin spend-trend "before exhaustion" alert cut to a `Ref #5674` follow-up (no balance endpoint; needs new sk-ant-admin secret + operator budget). Canary-at-exhaustion ships now with no new secret.
- Factual corrections from verify-negative pass: output-aware cohort is 8 crons (not 9/13); Sentry-extra tail is redactToken-only today (security F1 retrofit added).

### Components Invoked
- soleur:plan (STEP 1)
- soleur:deepen-plan (STEP 2): 8 parallel review agents (security-sentinel, user-impact-reviewer, code-simplicity-reviewer, data-integrity-guardian, spec-flow-analyzer, observability-coverage-reviewer, architecture-strategist, verify-the-negative Explore) synthesized + committed ebdeca9aa.
