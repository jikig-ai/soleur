# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause is substrate-cadence, not code: GHA hourly cron drift produces 150-min median gaps and 293-min max gaps over the post-#3964 window, far exceeding the May 18 fix's 30-min `checkin_margin_minutes`. The May 18 plan fixed the heartbeat shape but used an incorrect GHA-cron timing model.
- Structural fix: migrate scheduled-oauth-probe to Inngest cron substrate (established precedent: PR #3985 cron-daily-triage TR9 PR-1, PR #4062 cron-follow-through-monitor TR9 PR-2). Inngest fires deterministically with ≤2-min jitter.
- Scope: oauth-probe only. Sister hourly workflow `scheduled-github-app-drift-guard` deferred to a paired tracking issue (`code-review`-labeled follow-up, not `deferred-scope-out` — same top-level dir).
- Dropped `Closes #3236` from PR body (already CLOSED by PR #3811). Only `Closes #3203` (trap-RETURN cleanup, resolved by workflow deletion) remains.
- Deepen-plan halt gates all PASSED: Phase 4.6 User-Brand Impact (`threshold: none`), Phase 4.7 Observability (5 schema fields, no SSH in discoverability_test), Phase 4.8 PAT-shape (clean).

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash: gh pr/issue/run/label, grep, find, cat
- Edit: 7 plan edits (AC5, AC19, AC20, AC21, AC22, Files to Edit, Resume Prompt)
- Write: initial plan file
