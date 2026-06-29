---
feature: repo-connect-block-offer-join
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-29-feat-repo-connect-block-duplicate-plan.md
---

# Tasks — Block duplicate solo repo-connect + switch redirect

## Phase 1 — Connect-time check (TS, reuse resolver)
- [ ] 1.1 Write failing route test for `setup/route.ts`: different-user solo owner → decline (RED).
- [ ] 1.2 In `setup/route.ts`, before the `:202-215` cloning flip, call `resolveSoloFounderForInstallation(installationId, repoUrl, serviceClient)`.
- [ ] 1.3 Implement the branch: `none`/`founderId==activeWorkspaceId` → proceed; `founderId==user.id && ready` → switch; `founderId==user.id && !ready` → decline; `founderId!=user.id` → decline; `ambiguous`/`db-error` → decline + `reportSilentFallback`.
- [ ] 1.4 Return the structured outcome `{outcome, code, existingWorkspaceId, canRequestJoin:false}` (mirror `workspace_switch_required` for switch).
- [ ] 1.5 GREEN: route tests for all six branches pass.

## Phase 2 — UI states (extend failed-state.tsx, no new component)
- [ ] 2.1 STATE 1 (switch): copy entry + `primaryCta.action:'switch'` → `set_current_workspace_id(existingWorkspaceId)`; redirect to that workspace's dashboard on success.
- [ ] 2.2 Switch failure (revoked/deleted between read and click) → fall back to generic decline + refresh.
- [ ] 2.3 STATE 2 (decline): copy entry + non-disclosing CTA ("ask the repository's workspace owner to invite you") + "Pick a different repository"; no workspace/user/"taken" mention.
- [ ] 2.4 Tests: decline shape fixed `{409, body}` identical regardless of owner existence (no side channel).

## Phase 3 — Detection-only deploy query
- [ ] 3.1 Add the TR1 detection query as a deploy-verification step (Supabase MCP / read-only).
- [ ] 3.2 Test the query against synthesized duplicate fixtures (never prod).
- [ ] 3.3 Document the operator keep-which surfacing (no automated remediation).

## Phase 4 — ADR + resolver backstop + C4
- [ ] 4.1 Amend ADR-044: application-enforced scoped solo-uniqueness Decision + Alternatives row (vs rejected global `UNIQUE(repo_url)`); status `adopting`.
- [ ] 4.2 Comment `resolve-founder-for-installation.ts:131` as the post-block backstop; reachability unit test.
- [ ] 4.3 Confirm `op:founder-ambiguous` Sentry alert intact.
- [ ] 4.4 C4: confirm no `.c4` edit needed (enumeration in plan); run c4 tests only if edited.

## Phase 5 — Verify & ship
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.2 Full test suite green (use `package.json` runner; vitest path globs).
- [ ] 5.3 PR body uses `Ref #5673` (not `Closes`); post-merge soak (AC8) before `gh issue close 5673`.
