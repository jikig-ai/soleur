---
feature: feat-one-shot-key-delegation-state-persistence
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-fix-share-a-key-delegation-state-persistence-plan.md
brand_survival_threshold: single-user incident
related_prs: [4767, 4761]
---

# Tasks — fix "Share a key" delegation persistence / revoke / owner workspace resolution

Runner: **vitest** (`apps/web-platform/package.json scripts.test`). Tests under
`test/**/*.test.ts(x)` only. Invoke via `npm run --prefix apps/web-platform …`
(NO root `workspaces:` field — `-w` does not work).

## Phase 1 — Revoke arg alignment (symptom 3: cannot disable)

- [ ] 1.1 RED: create `apps/web-platform/test/api-delegation-revoke-route.test.ts`
  (or extend the grant test) asserting the DELETE handler calls
  `revoke_byok_delegation` with `{ p_delegation_id, p_actor_user_id, p_reason }`
  and `not.toHaveProperty` on `p_revoked_by_user_id` / `p_revocation_reason`.
  Mirror the mock shape in `api-delegation-grant-route.test.ts`. Confirm RED.
- [ ] 1.2 GREEN: in `app/api/workspace/delegations/route.ts` DELETE handler, change
  the `revoke_byok_delegation` arg object to the canonical 064 set
  (`p_delegation_id` / `p_actor_user_id` / `p_reason`); add a contract comment
  citing `064:496-498` + `scripts/byok-revoke.ts:154-158`.
- [ ] 1.3 Component test: in `test/delegation-toggle.test.tsx` add (a) revoke→200
  flips `aria-checked` to false with no alert; (b) revoke→400 keeps it on and
  alerts "Couldn't stop sharing the key…".

## Phase 2 — Owner-side workspace resolution convergence (symptoms 1 & 2)

- [ ] 2.1 RED: extend `test/team-membership-resolver.test.ts` with a two-workspace
  owner fixture (older V + current `current_workspace_id = W`); assert resolver
  returns `workspaceId === W` and reads delegations from W. Confirm RED against
  the current unordered-`[0]` derivation.
- [ ] 2.2 GREEN: in `server/team-membership-resolver.ts` replace the
  `workspaces.organization_id=orgId → [0]` workspace derivation with
  `resolveCurrentWorkspaceId(user.id, service)` (import from
  `@/server/workspace-resolver`); keep membership/role checks.
- [ ] 2.3 Sweep: grep `team/page.tsx` + `team-membership-resolver.ts` for every
  query filtering on `workspaceId`; confirm each consumes the converged id and
  none re-derives it independently.
- [ ] 2.4 Fail-closed test: resolver falls back to `user.id` (solo, never a
  sibling) on resolution error or membership mismatch (AC4).
- [ ] 2.5 Trace the owner NULL-`current_workspace_id` case (Sharp Edge): confirm
  the solo fallback reads the right delegations for an owner who created the org
  solo (N2: `workspace_id === user_id`).

## Phase 3 — Verification

- [ ] 3.1 `npm run --prefix apps/web-platform test:ci -- <touched test files>` GREEN.
- [ ] 3.2 Full delegation suite GREEN; existing grant/toggle tests unchanged (AC7).
- [ ] 3.3 `npm run --prefix apps/web-platform typecheck` + `lint` pass (AC8).
- [ ] 3.4 Confirm zero files changed under `apps/web-platform/supabase/migrations/` (AC6).

## Post-merge (operator)

- [ ] 4.1 Playwright MCP prod smoke on `app.soleur.ai` (AC9): owner toggles ON
  (no dialog) → reload persists ON → toggle OFF persists OFF. Automatable via
  `mcp__playwright__*` — not operator-manual.
