---
feature: feat-one-shot-5733-agent-container-fs-divergence
lane: cross-domain
posture: verification-only
implemented_by: "#5734 (commit 190ab58a5, merged 2026-06-30 16:32)"
plan: knowledge-base/project/plans/2026-06-30-fix-ownerless-workspace-agent-strand-divergence-plan.md
---

# Tasks — Verify #5733 strand fix on the agent surface (implementation already merged)

> **STALE-PREMISE NOTE.** The code fix is ALREADY on main (#5734 / `190ab58a5`):
> gitdir-pointer heal, agent-readiness self-stop observability, and N-co-owner
> tolerance (754ee124 has 2 legitimate co-owners — it is NOT owner-less; the
> "restore the canary" premise is REFUTED). This is now an **investigate-first
> verification** task set. Do NOT write a fourth code fix — that would duplicate
> merged code. Open a new fix branch ONLY if V3 surfaces a residual strand with
> NEW live evidence.

## Phase 0 — Establish ground truth (READ-ONLY; blocking)

- [ ] 0.1 Confirm `190ab58a5` (#5734) is in the running prod web-platform image.
      Query `deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access via Doppler
      `prd_terraform`) for the deployed SHA/version, or confirm #5734's release
      workflow completed. Record the version in the spec.
- [ ] 0.2 Read the shipped code to confirm the three deliverables are present in
      this worktree's tree (already verified at plan time; re-confirm at /work):
      `ensure-workspace-repo.ts:154` (`isStrandingFilePointer`),
      `repo-resolver-divergence.ts:98` (`reportAgentReadinessSelfStop`),
      `workspace-reconcile-on-push.ts:254-293` (select-all-owners).

## Phase 1 — Exec-path confirmation via Sentry (the load-bearing learning)

- [ ] 1.1 `scripts/sentry-issue.sh search` (EU host `jikigai-eu.sentry.io`,
      `SENTRY_ISSUE_RO_TOKEN`) for op `agent_readiness_self_stop` scoped to
      `754ee124`'s `activeWorkspaceIdHash`, recent window. Record presence/absence
      and the latest event's `extra` (`gitValid`, `gitKind`, escape boolean).
- [ ] 1.2 Confirm `ownerless-reconcile` STOPPED firing for `754ee124` post-merge
      (pre-fix: 28×; post-fix expect 0) — corroborates the N-co-owner fix
      executes on the live surface.
- [ ] 1.3 Record the Sentry verdict: does the merged observability path actually
      execute on the agent/dispatch surface for `754ee124`? (If a fresh strand
      shows ZERO `agent_readiness_self_stop`, re-trace which path fires — do NOT
      assume.)

## Phase 2 — Live Supabase de-anomalization check (READ-ONLY; Supabase MCP)

- [ ] 2.1 `workspace_members` for `754ee124`: assert **≥2 `role='owner'` rows**
      (confirms co-owner topology → refutes "missing canary", confirms #5591
      reframing). NO WRITE — multi-owner is by design.
- [ ] 2.2 `user_session_state.current_workspace_id` for the operator: record
      whether `== 754ee124` (rules residual-H3 in/out).
- [ ] 2.3 `organizations.owner_user_id` via `workspaces.organization_id` join:
      record org-owner lineage for the audit trail (no write).

## Phase 3 — Reproduce on the operator surface + close-out

- [ ] 3.1 Reproduce `/soleur:go` on `754ee124`.
- [ ] 3.2 **PASS** (agent reads `jikig-ai/soleur`, no strand): `gh issue close
      #5733` with a comment citing #5734 + the V1/V2 evidence. Use `Ref #5591`
      (its fix is in PR #5783 — do NOT duplicate).
- [ ] 3.3 **FAIL** (residual strand): capture the `agent_readiness_self_stop`
      event (`gitValid` + `gitKind` + hash), THEN open a NEW fix branch with that
      NEW live evidence — the next layer is now data-driven. Do NOT pre-author.
- [ ] 3.4 Disposition WIP PR **#5788**: convert to a verification-evidence PR
      (this reconciled plan + tasks + V0–V3 findings, NO code) OR close it and
      record verification on #5733. Do NOT push a re-implementation over a
      0-ahead-of-main tree.

## Notes
- ADR-044 / C4: #5734 already shipped the behavioral change; if its ADR/C4
  amendment did not land with #5734, that is a separate docs-only follow-up — do
  NOT gate the verification on it. Check `git log --oneline -- knowledge-base/engineering/architecture/`
  for an ADR-044 touch in #5734's commit before filing.
- Typecheck/test (only if V3 forces a new fix branch):
  `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + the package's
  real runner (read `package.json` scripts + `vitest.config.ts` globs).
