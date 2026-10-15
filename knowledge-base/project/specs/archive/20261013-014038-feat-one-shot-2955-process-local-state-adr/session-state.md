# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2955-process-local-state-adr/knowledge-base/project/plans/2026-05-11-arch-process-local-state-adr-plan.md
- Status: complete

### Errors
None.

### Decisions
- ADR shape: rich (8 sections) — two rubric triggers fire: principle declaration (AP-013 is new) and teeth-bearing alternatives (Redis / PG NOTIFY / sticky LB).
- ADR number: 027 (verified — ADR-021 through ADR-026 already exist).
- Inventory expanded from 5 to 10+1 process-local Maps. Research Reconciliation table captures every stale `file:line` from the issue body (3 of 5 line numbers wrong; `activeSessions` moved to `agent-session-registry.ts:33`; 5 additional Maps the issue missed). Buckets: A cross-replica-fatal, B cross-replica-degrading, C per-process-OK.
- Enforcement at 4 surfaces: governance (ADR-027) + principle (AP-013) + runtime (`assertSingleReplicaInvariant()` reading `WEB_PLATFORM_REPLICAS`, fail-closed, `ALLOW_MULTI_REPLICA=1` override) + deploy (`ci-deploy.sh` pre-`docker run` `docker ps --filter` assertion).
- Test runner correction during deepen pass: project uses vitest, not Bun test; test files live in `apps/web-platform/test/`. AC updated to `npx vitest run`.

### Components Invoked
- `soleur:plan` skill (Phases 0 → 6 inline; pipeline-mode exit gate)
- `soleur:deepen-plan` skill (Phase 4.6 User-Brand Impact halt gate passed)
- Inline verifications: `gh issue view 2955`, `gh pr view 2954`, `gh label list`, grep AGENTS.rest.md, ADR template rubric, NFR register, principles register, package.json test-runner detection.
