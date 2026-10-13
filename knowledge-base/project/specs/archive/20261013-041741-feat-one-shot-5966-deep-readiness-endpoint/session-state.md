# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-03-feat-deep-readiness-endpoint-workspaces-mount-plan.md
- Status: complete

### Errors
None. CWD verified on first call; both `soleur:plan` and `soleur:deepen-plan` ran to completion.

### Decisions
- New internal `/internal/readyz` returning 200/503, gated on loopback transport peer (`socket.remoteAddress`); `/health` left untouched (liveness-only per ADR-068).
- Separate `readiness.ts` module to physically enforce the "/health untouched" invariant.
- `st_dev` mountpoint check replaced with write+unlink probe + populated-count (`lost+found` excluded) — st_dev is inert inside the container bind-mount.
- Cut `git_data_consistent` tautology (fail-open dead code); completed fail-closed route try/catch → 503; added latched boot-time Sentry mirror `verifyWorkspacesMountOnce`.
- Flap-safety as a hard AC (drain requires N>=2 consecutive not-ready reads). ADR-068 amendment is the architecture deliverable; threshold = single-user-incident, requires_cpo_signoff.

### Components Invoked
- Skill: soleur:plan (#5966), soleur:deepen-plan
- Deepen panel: architecture-strategist, data-integrity-guardian, security-sentinel, code-simplicity-reviewer, observability-coverage-reviewer, user-impact-reviewer, spec-flow-analyzer, general-purpose
