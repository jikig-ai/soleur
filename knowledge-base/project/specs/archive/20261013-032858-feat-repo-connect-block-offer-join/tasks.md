---
feature: repo-connect-block-offer-join
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-29-feat-repo-connect-block-duplicate-plan.md
---

# Tasks — Block duplicate solo repo-connect + switch redirect

## Phase 1 — Connect-time check (TS, reuse resolver)
- [x] 1.1 Write failing **guard unit** tests for `server/repo-connect-guard.ts` (pure, injected service client): different-user solo → decline (RED); plus the branch-order fixture where `activeWorkspaceId==user.id==founderId` → proceed (NOT switch).
- [x] 1.2 Create `apps/web-platform/server/repo-connect-guard.ts` (HTTP-only route stays clean); it calls `resolveSoloFounderForInstallation(installationId, repoUrl, serviceClient)`.
- [x] 1.3 Implement the branch **in this order** (`activeWorkspaceId` before `user.id`): `none`/`founderId==activeWorkspaceId` → proceed; `founderId==user.id && ready` → switch; `founderId==user.id && !ready` → decline; `founderId!=user.id` → decline; `ambiguous`/`db-error` → decline + `reportSilentFallback`.
- [x] 1.4 For the two `founderId==user.id` arms, add the explicit `serviceClient.from("workspaces").select("repo_status").eq("id", founderId)` read (resolver does NOT return `repo_status`; reuse `active-repo/route.ts:67` shape).
- [x] 1.5 Return `{outcome, code, existingWorkspaceId, canRequestJoin:false}` — set `existingWorkspaceId` **only** in the switch arm; null/absent on every decline sub-case (in body AND structured payload). Mirror `workspace_switch_required` for switch.
- [x] 1.6 Wire the guard into `setup/route.ts` before the `:202-215` cloning flip.
- [x] 1.7 GREEN: guard unit tests for all six branches + branch-order + decline-non-leak pass.

## Phase 2 — UI states (extend failed-state.tsx, no new component)
- [x] 2.0 Run `cq-union-widening-grep-three-patterns` over consumers of `FailedState.primaryCta.action` before widening it with `'switch'`; add the `existingWorkspaceId` prop.
- [x] 2.1 STATE 1 (switch): copy entry + `primaryCta.action:'switch'`. Call `set_current_workspace_id` **server-side** (mirror `accept-invite:78`/`active-repo:59`) OR browser-RPC + `supabase.auth.refreshSession()` **before** redirect — the `current_workspace_id` JWT claim is minted at refresh (ADR-044 Decision.3); redirecting without it lands on the old workspace.
- [x] 2.2 Switch failure (revoked/deleted between read and click) → fall back to generic decline + refresh.
- [x] 2.3 STATE 2 (decline): copy entry + non-disclosing CTA ("ask the repository's workspace owner to invite you") + "Pick a different repository"; no workspace/user/"taken" mention. (Optional: distinct copy for the `ambiguous`/`db-error` transient sub-case so a legit user isn't told to "ask the owner".)
- [x] 2.4 Tests: (a) decline `{409, body}` byte-identical across decline **sub-cases** (different-user / ambiguous / db-error) — NOT decline-vs-proceed; (b) no decline sub-case serializes `founderId`/`existingWorkspaceId` in body or structured payload; (c) switch redirect lands on the **new** workspace (claim refreshed).

## Phase 3 — Detection-only deploy query
- [x] 3.1 Add the TR1 detection query as a deploy-verification step (Supabase MCP / read-only) — with `array_agg(... ORDER BY created_at)` + per-row detail (exact repo_url, created_at) and case-variant-group annotation ("not incident-causing, NG4").
- [x] 3.2 Test the query against synthesized duplicate fixtures (never prod).
- [x] 3.3 Document the operator keep-which surfacing (no automated remediation).

## Phase 4 — ADR + resolver backstop + C4
- [x] 4.1 Amend ADR-044: application-enforced scoped solo-uniqueness Decision + Alternatives row (vs rejected global `UNIQUE(repo_url)`); status `adopting`. **Cite Amendment 2026-06-17b R7** ("enforced nowhere structurally — only by the connect path + runtime `>1` fail-closed") as the gap this connect-path check closes.
- [x] 4.2 Comment `resolve-founder-for-installation.ts:131` as the post-block backstop; reachability unit test.
- [x] 4.3 Generalize the `resolve-founder-for-installation.ts:46-48` header comment so the "server-derived install, never request-supplied" invariant covers the new setup-route caller, not just the webhook.
- [x] 4.4 Confirm `op:founder-ambiguous` Sentry alert intact.
- [x] 4.5 C4: confirm no `.c4` edit needed (enumeration in plan); run c4 tests only if edited.

## Phase 5 — Verify & ship
- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.2 Full test suite green (use `package.json` runner; vitest path globs).
- [ ] 5.3 PR body uses `Ref #5673` (not `Closes`); post-merge soak (AC8) before `gh issue close 5673`.
