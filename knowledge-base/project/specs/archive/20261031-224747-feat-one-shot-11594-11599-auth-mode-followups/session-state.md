# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-31-feat-auth-mode-followups-recovery-copy-and-delegated-api-key-plan.md
- Status: complete
- cto_spawns=3 (planning phase: three CTO rounds; no further spawns this pipeline run)

### Errors
- Worktree was removed mid-planning by an outside process; the subagent re-created it on the existing branch and rewrote the plan.
- Plan file was corrupted by a bad splice and rebuilt from scratch copies; gates pass (lint-guard-contract, markdown-lint, check-adr-ordinals).
- Deepen-plan broad fan-out skipped (five-reviewer plan-review panel plus CLO/CTO/CPO rulings covered it); recorded in the plan.
- Technical-ruling gate failed on row shapes in decision-challenges.md; fixed by moving parentheticals after the date and reclassifying CPO/planner rows as taste.

### Decisions
- CLO (real spawn): ALLOW-WITH-CONDITIONS for the api-key bypass of the grantor-subscription refusal: resolve mode first, skip the SELECT and refusal only on exact api-key and same-workspace binding; every other outcome refuses as today; delegated managed-mode fallback is out of scope.
- CTO: two new lease causes (auth_mode_unresolved, auth_mode_unavailable) and two WS codes, call-site Sentry mirror skipped at five points; threshold single-user incident; ADR-048 amended, no new ADR, no C4 change.
- Recovery sentence on every oauth_token copy cell except session_expired, beginning "If you have an Anthropic API key saved...".
- Two commits: #11594 lease work, then #11599 copy; Closes only if every acceptance criterion is verified; one follow-up issue planned (copy for delegate dead ends).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: legal:clo, engineering:cto x3, product:cpo, learnings-researcher, dhh/kieran/code-simplicity/architecture reviewers, spec-flow-analyzer.
