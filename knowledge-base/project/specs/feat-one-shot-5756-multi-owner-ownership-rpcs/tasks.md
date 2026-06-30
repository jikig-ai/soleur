# Tasks — feat: multi-owner ownership RPCs reconcile (#5756)

Plan: `knowledge-base/project/plans/2026-06-30-feat-multi-owner-ownership-rpcs-reconcile-plan.md`
Lane: single-domain · Threshold: single-user incident (requires CPO sign-off) · Deepened 2026-06-30 (5 agents)

## Phase 0 — Preconditions
- [x] 0.1 Confirm next migration index = 117, next ADR = ADR-072.
- [x] 0.2 Confirm `092_transfer_ownership_caller_override.sql` exists on origin/main.
- [x] 0.3 `COMMENT ON FUNCTION` apply-role: risk near-zero (092:193 + 094:278 already COMMENT these functions, apply green). Probe `git grep -n 'COMMENT ON FUNCTION public' apps/web-platform/supabase/migrations/` as a cheap precondition; fallback = ADR-only + inline prose; never `CREATE OR REPLACE` re-emit.
- [x] 0.4 Capture VERBATIM current COMMENT strings from 092:193-198 + 094:278-283 for down.sql (092's is a multi-line adjacent-string concat, NO inserted space).
- [x] 0.5 Read-only research owner_user_id consumers (workspace-resolver:491-516, dsar-export:975, account-delete:708-741) AND the THREE writers (transfer 092:145-147; anonymise_organization_membership mig 081:52-75; none in promotion/invite). No edits.

## Phase 1 — ADR-072 (headline)
- [x] 1.1 `soleur:architecture` create → `ADR-072-workspaces-support-n-co-owners.md` (title: multi-owner workspaces + `organizations.owner_user_id` primary-owner pointer).
- [x] 1.2 Decision body: ≥1 owner; invite-as-owner + promotion grant paths; transfer = hand-off-and-step-down; owner_user_id = primary/billing/DSAR pointer; at-least-one-owner invariant; carve-outs (transfer rejects already-owner; remove blocks any owner).
- [x] 1.2b Enumerate ALL THREE owner_user_id writers (transfer 092; anonymise_organization_membership mig 081 — promotes oldest member, a wart; none in promotion/invite). State the derived "references-a-current-owner" invariant + its Phase-6 breakage trigger + the demote→remove no-repoint dead-end + the consumer-tolerance contract.
- [x] 1.3 C4: one-line model.c4:9 citation refresh (ADR-038 → ADR-038, ADR-072); no topology edit.
- [x] 1.4 Frame as resolving the ADR-038-vs-mig-075 contradiction + supersede #4520 / mig 075 single-owner-strict.

## Phase 2 — migration 117 (CONTRACT; before tests)
- [x] 2.1 `117_reconcile_ownership_rpc_comments_multi_owner.sql` — `COMMENT ON FUNCTION` only on the two 4-arg RPCs (no CREATE/ALTER/GRANT/REVOKE/DROP/UPDATE).
- [x] 2.2 `117_*.down.sql` — restore prior COMMENT text verbatim (reproduce 092's concatenated value exactly); header note: down + verify/117 are version-paired.

## Phase 3 — verify/117 sentinel (lock durable invariant)
- [x] 3.1 No single-owner constraint: partial UNIQUE index (pg_index indpred ILIKE '%owner%') + EXCLUDE/UNIQUE constraint (pg_constraint contype IN ('u','x')). Assert absence, NOT row-count. Header note: trigger-vector + message-proxy limits.
- [x] 3.2 At-least-one-owner guard present in update_workspace_member_role 4-arg (pin signature; functiondef ILIKE '%cannot demote the last owner%').
- [x] 3.3 service_role-only grant lock (NOT authenticated-EXECUTE) for: update_workspace_member_role(4-arg, NEW), create_workspace_invitation(6-arg, NEW), accept_workspace_invitation(2-arg, NEW). transfer already locked by verify/092 (optional re-assert).
- [x] 3.4 3-arg `update_workspace_member_role(uuid,uuid,text)` overload does NOT exist (symmetry with verify/092 check 3).
- [x] 3.5 (secondary, droppable) transfer COMMENT NOT ILIKE '%single-owner strict%'.

## Phase 4 — test (after contract migration)
- [x] 4.1 DEVIATION: `workspace-invitations-accept.integration.test.ts` does not exist. Dominant local convention = static SQL-shape migration test (no live DB), per `092-*.test.ts` / `094-*.test.ts`. Added `test/supabase-migrations/117-reconcile-ownership-rpc-comments-multi-owner.test.ts` (15 tests, green) — the canonical PR-time gate per learning 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.
- [x] 4.2 Behavioral DB invariants (two owners coexist; member→owner no-raise; demote-one-of-two; demote-last raises) locked at apply-time by verify/117 on the release migrate+verify path; not DB-exercised here (no live DB). Static test pins the guard predicate + verify checks.
- [x] 4.3 Sentinel negative proof: `apps/web-platform/test/fixtures/verify-117-single-owner-negative.sql` (named fixture) — BEGIN;...ROLLBACK; CREATE UNIQUE INDEX ... WHERE role='owner', asserts check 1 bad>0. AUTHORED, not executed (no live DB); static test asserts its shape.
- [x] 4.4 Document expected owner_user_id behavior on pointed-to-owner demotion + the no-repoint dead-end.

## Phase 5 — cross-link
- [x] 5.1 domain-model.md BR-WS-3 source cite → ADR-072.
- [x] 5.2 ADR-044 2026-06-30 amendment → link ADR-072.
- [x] 5.3 model.c4:9 founder-actor citation (ADR-038) → (ADR-038, ADR-072); re-run c4-code-syntax.test.ts + c4-render.test.ts.

## Phase 6 — deferred follow-up
- [x] 6.1 Filed **#5805** (milestone Post-MVP / Later; labels domain/engineering + type/feature): reconcile `organizations.owner_user_id` data under N owners (backfill/junction), with the three re-eval triggers.

## Exit
- [x] tsc --noEmit clean (exit 0); new migration-117 test green (15/15); c4-code-syntax + c4-render green (23/23).
- [ ] verify/117 bad=0 — deferred to the release-workflow migrate+verify path (the merge is the apply; no live DB in this env).
- [ ] CPO sign-off (threshold = single-user incident) — review-time gate.
- [ ] PR body `Closes #5756` — PR not opened by this pipeline phase.
