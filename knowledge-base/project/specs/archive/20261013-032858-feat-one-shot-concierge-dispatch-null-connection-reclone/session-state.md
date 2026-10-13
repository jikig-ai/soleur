# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-18-fix-concierge-dispatch-null-connection-reclone-plan.md
- Status: complete

### Errors
None. CWD verified on first call. Branch safety passed. All deepen-plan always-on gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) passed.

### Decisions
- Premise confirmed, mechanism sharpened: root cause is a two-read asymmetry — `installationId` via `resolve_workspace_installation_id` SECURITY DEFINER RPC returns NULL on membership-deny (indistinguishable from not-connected per mig 079), while `repoUrl`/`repo_status` come via direct RLS `.select`. They diverge (repoUrl non-null, install null) for a genuinely-connected team workspace, so `hasConnection` is false and the graft is skipped (repo-readiness-self-heal.ts:128,134-140).
- Candidate #2 (workspacePath vs sandbox-cwd mismatch) ruled out — same `workspacePath` local everywhere.
- Fix direction constrained by ADR-044: do NOT widen the RPC to return install on deny (re-opens the credential-leak surface ADR-044 closed). Instead disambiguate at the caller using `repoUrl` as the honest connection signal, and fail honestly with `RepoNotReadyError` + a new dispatch-time `repo-resolver-divergence` Sentry op.
- P0 deepen correction (architecture-strategist): the divergence helper must NOT persist `repo_status=error` — that would corrupt a healthy shared team workspace for its Owners and make a transient RPC blip sticky. Zero `workspaces` writes; Sentry op is the only durable record (AC1b).
- Observability: extend `RepoResolverDivergenceOp` union + add the missing `repo-resolver-divergence` Sentry alert rule. ADR-044 gets a dated amendment.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, general-purpose x2 (verify-the-negative + precedent-diff), architecture-strategist
