# Tasks — feat: multi-owner ownership RPCs reconcile (#5756)

Plan: `knowledge-base/project/plans/2026-06-30-feat-multi-owner-ownership-rpcs-reconcile-plan.md`
Lane: single-domain · Threshold: single-user incident (requires CPO sign-off) · Deepened 2026-06-30 (5 agents)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm next migration index = 117, next ADR = ADR-072.
- [ ] 0.2 Confirm `092_transfer_ownership_caller_override.sql` exists on origin/main.
- [ ] 0.3 `COMMENT ON FUNCTION` apply-role: risk near-zero (092:193 + 094:278 already COMMENT these functions, apply green). Probe `git grep -n 'COMMENT ON FUNCTION public' apps/web-platform/supabase/migrations/` as a cheap precondition; fallback = ADR-only + inline prose; never `CREATE OR REPLACE` re-emit.
- [ ] 0.4 Capture VERBATIM current COMMENT strings from 092:193-198 + 094:278-283 for down.sql (092's is a multi-line adjacent-string concat, NO inserted space).
- [ ] 0.5 Read-only research owner_user_id consumers (workspace-resolver:491-516, dsar-export:975, account-delete:708-741) AND the THREE writers (transfer 092:145-147; anonymise_organization_membership mig 081:52-75; none in promotion/invite). No edits.

## Phase 1 — ADR-072 (headline)
- [ ] 1.1 `soleur:architecture` create → `ADR-072-workspaces-support-n-co-owners.md` (title: multi-owner workspaces + `organizations.owner_user_id` primary-owner pointer).
- [ ] 1.2 Decision body: ≥1 owner; invite-as-owner + promotion grant paths; transfer = hand-off-and-step-down; owner_user_id = primary/billing/DSAR pointer; at-least-one-owner invariant; carve-outs (transfer rejects already-owner; remove blocks any owner).
- [ ] 1.2b Enumerate ALL THREE owner_user_id writers (transfer 092; anonymise_organization_membership mig 081 — promotes oldest member, a wart; none in promotion/invite). State the derived "references-a-current-owner" invariant + its Phase-6 breakage trigger + the demote→remove no-repoint dead-end + the consumer-tolerance contract.
- [ ] 1.3 C4: one-line model.c4:9 citation refresh (ADR-038 → ADR-038, ADR-072); no topology edit.
- [ ] 1.4 Frame as resolving the ADR-038-vs-mig-075 contradiction + supersede #4520 / mig 075 single-owner-strict.

## Phase 2 — migration 117 (CONTRACT; before tests)
- [ ] 2.1 `117_reconcile_ownership_rpc_comments_multi_owner.sql` — `COMMENT ON FUNCTION` only on the two 4-arg RPCs (no CREATE/ALTER/GRANT/REVOKE/DROP/UPDATE).
- [ ] 2.2 `117_*.down.sql` — restore prior COMMENT text verbatim (reproduce 092's concatenated value exactly); header note: down + verify/117 are version-paired.

## Phase 3 — verify/117 sentinel (lock durable invariant)
- [ ] 3.1 No single-owner constraint: partial UNIQUE index (pg_index indpred ILIKE '%owner%') + EXCLUDE/UNIQUE constraint (pg_constraint contype IN ('u','x')). Assert absence, NOT row-count. Header note: trigger-vector + message-proxy limits.
- [ ] 3.2 At-least-one-owner guard present in update_workspace_member_role 4-arg (pin signature; functiondef ILIKE '%cannot demote the last owner%').
- [ ] 3.3 service_role-only grant lock (NOT authenticated-EXECUTE) for: update_workspace_member_role(4-arg, NEW), create_workspace_invitation(6-arg, NEW), accept_workspace_invitation(2-arg, NEW). transfer already locked by verify/092 (optional re-assert).
- [ ] 3.4 3-arg `update_workspace_member_role(uuid,uuid,text)` overload does NOT exist (symmetry with verify/092 check 3).
- [ ] 3.5 (secondary, droppable) transfer COMMENT NOT ILIKE '%single-owner strict%'.

## Phase 4 — test (after contract migration)
- [ ] 4.1 First grep existing tests for two-owner coverage; DEFAULT = extend `workspace-invitations-accept.integration.test.ts`, not a new file. Verify vitest include globs + path; run `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
- [ ] 4.2 Two owner rows coexist; member→owner promotion no-raise; demote-one-of-two succeeds; demote-last raises.
- [ ] 4.3 Sentinel negative proof: name location (inline BEGIN;...ROLLBACK; with CREATE UNIQUE INDEX ... WHERE role='owner', or test/fixtures/ SQL) and assert verify/117 returns bad>0.
- [ ] 4.4 Document expected owner_user_id behavior on pointed-to-owner demotion + the no-repoint dead-end.

## Phase 5 — cross-link
- [ ] 5.1 domain-model.md BR-WS-3 source cite → ADR-072.
- [ ] 5.2 ADR-044 2026-06-30 amendment → link ADR-072.
- [ ] 5.3 model.c4:9 founder-actor citation (ADR-038) → (ADR-038, ADR-072); re-run c4-code-syntax.test.ts + c4-render.test.ts.

## Phase 6 — deferred follow-up
- [ ] 6.1 File issue: reconcile `organizations.owner_user_id` data under N owners (backfill/junction). Re-eval triggers: (a) product-reachable owner-demote/remove-of-pointer-target route exposed; (b) mig-081 promote-oldest produces wrong primary owner surfaced by DSAR/billing; (c) DSAR/billing needs a non-pointer owner set.

## Exit
- [ ] tsc --noEmit clean (in-package); new test green; verify/117 bad=0; c4 tests green; CPO sign-off; PR body `Closes #5756`.
