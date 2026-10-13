# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-31-fix-cloud-task-heartbeat-inventory-false-positives-plan.md
- Status: complete

### Re-scope note
Original task asked to switch heartbeat detection to Inngest run-history. Halted before planning: #4708 (HEAD) proved Inngest `/v1/*` is loopback-gated and unreachable from the app container. Operator chose "fix inventory only" — keep GitHub-issue-label detection, drop non-producers, fix thresholds.

### Errors
None. (One transient Edit path-typo during planning, immediately retried and succeeded.)

### Decisions
- 3 non-producers re-verified in source and removed: bug-fixer, ux-audit (UX_AUDIT_DRY_RUN=true), daily-triage (no `gh issue create`).
- Thresholds re-derived from real cron cadences: legal-audit 9→95, content-generator 4→9, competitive-analysis 32→40, community-monitor 9→3; strategy-review & roadmap-review stay 9. Final inventory = 6 producers.
- community-monitor confirmed a producer (stays); no alert issue exists for it.
- Did NOT re-introduce the strict-mode bash numeric-comparison crash (TR9 replaced it with TS).
- TDD-first; runbook documents producers-only scoping + Sentry-liveness split (#4708) + loopback-gated /v1/* non-use.
- Post-merge: close #4691/#4690/#4685/#4687 (false positives); leave #4689/#4688/#4686/#4684 OPEN (genuine drift).

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan; Bash, Read, Write, Edit
