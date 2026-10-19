# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-kb-drift-ingest-host-and-public-path-plan.md
- Status: complete

### Errors
None. (One transient write-hook block on the IaC-routing gate — resolved by adding the `iac-routing-ack: plan-phase-2-8-reviewed` comment after confirming the plan prescribes no manual provisioning, only a single TF string-default edit inside existing IaC.)

### Decisions
- Both root causes verified against the codebase before planning: TF default at kb-drift.tf:52 is wrong-host apex with ignore_changes=[value] (keep); route absent from PUBLIC_PATHS (lib/routes.ts); middleware 307s unauthed POSTs (middleware.ts:289-291); route returns 401/2xx once reached; workflow asserts 2xx.
- Narrow exact path /api/internal/kb-drift-ingest, NOT broad /api/internal prefix (matcher uses pathname === p || startsWith(p + "/"); broad prefix would session-bypass future internal routes). /api/inngest is the canonical precedent.
- Test coverage targets test/middleware.test.ts (has isPublicPath() helper + prefix-collision block) for bypass-session assertion. Runner is vitest, not bun.
- No Doppler mutation in this PR — live value operator-pre-applied; TF edit only fixes fresh-tenant baseline default.
- Threshold = none; diff touches middleware.ts/app/api/infra but adds no new processing activity; HMAC stays load-bearing.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Artifacts committed: plan + tasks.md (commits fa1e0737, d3110f3b)
