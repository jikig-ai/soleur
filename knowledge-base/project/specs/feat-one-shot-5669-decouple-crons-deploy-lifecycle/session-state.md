# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-29-fix-infra-decouple-crons-deploy-graceful-drain-plan.md
- Status: complete

### Errors
None. Two transient retries handled inline (Edit re-Read after a notification; one Edit reworded for IaC-hook framing). One BROKEN kb-citation is the intentionally to-be-created ADR-078.

### Decisions
- Chose Option 1 (graceful cron drain in `ci-deploy.sh`) over Option 2 (isolated cron-worker container). Option 2 deferred via ADR-078 with re-eval criteria + tracking issue (blocked by 8GB cx33 host budget ~6.9GB peak + duplicated-runtime surface). No deploy-topology change → no C4 impact.
- Drain lives host-side in `ci-deploy.sh`, not the Node SIGTERM handler (hard-bounded 8s < 12s `docker stop`); placed AFTER canary teardown / before old-prod stop to avoid sustained ~6.9GB dwell.
- Domain review corrected two FALSE safety premises: cron ceiling is per-function (15→70 min, so `CRON_DRAIN_TIMEOUT` default = MAX = 4200s); claude-eval runs outside `cron-platform` (agent-runtime + cc-go), so detection is pool-agnostic and "wait = max not sum."
- Deploy wall-clock is a four-constant fail-closed invariant (asserted at `web-platform-release.yml:357`) raised in lockstep to 4800s; wrapper constant shared/sourced. Native Inngest pause/resume closes the start-race; next-deploy resume-if-paused reconcile for the untrappable-SIGKILL wedge.
- 19 spec-flow gaps (G1–G19) carried as a deepen-plan/work checklist; brand-survival threshold = single-user incident (`requires_cpo_signoff: true`).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: feature-dev:code-explorer, learnings-researcher (×2), cto, platform-strategist, spec-flow-analyzer
- Gates passed: Code-Review Overlap (#3220), Domain Review, User-Brand Impact, GDPR (N/A), IaC routing, Observability, ADR-078; deepen-plan halts 4.6/4.7/4.8/4.9; precedent-diff + verify-the-negative
