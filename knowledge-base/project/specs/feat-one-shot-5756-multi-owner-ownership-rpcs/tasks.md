# Tasks — feat: multi-owner ownership RPCs reconcile (#5756)

Plan: `knowledge-base/project/plans/2026-06-30-feat-multi-owner-ownership-rpcs-reconcile-plan.md`
Lane: single-domain · Threshold: single-user incident (requires CPO sign-off)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm next migration index = 117, next ADR = ADR-072.
- [ ] 0.2 Confirm `092_transfer_ownership_caller_override.sql` exists on origin/main.
- [ ] 0.3 `COMMENT ON FUNCTION` apply-role probe: `git grep -n 'COMMENT ON FUNCTION public' apps/web-platform/supabase/migrations/`. If no clean precedent, plan fallback (ADR-only + inline prose); never `CREATE OR REPLACE` re-emit.
- [ ] 0.4 Read-only research `organizations.owner_user_id` consumers (workspace-resolver, dsar-export(-allowlist), account-delete) to ground the ADR pointer-semantics decision. No edits.

## Phase 1 — ADR-072 (headline)
- [ ] 1.1 `soleur:architecture` create → `ADR-072-workspaces-support-n-co-owners.md` (title: multi-owner workspaces + `organizations.owner_user_id` primary-owner pointer).
- [ ] 1.2 Decision body: ≥1 owner; invite-as-owner + promotion grant paths; transfer = hand-off-and-step-down; owner_user_id = primary/billing/DSAR pointer; at-least-one-owner invariant; carve-outs (transfer rejects already-owner; remove blocks any owner).
- [ ] 1.3 C4: "No C4 impact" with the actor/system/relationship enumeration citation.
- [ ] 1.4 Supersede #4520 / mig 075 single-owner-strict.

## Phase 2 — migration 117 (CONTRACT; before tests)
- [ ] 2.1 `117_reconcile_ownership_rpc_comments_multi_owner.sql` — `COMMENT ON FUNCTION` only on the two 4-arg RPCs (no CREATE/ALTER/GRANT/REVOKE/DROP/UPDATE).
- [ ] 2.2 `117_*.down.sql` — restore prior COMMENT text verbatim.

## Phase 3 — verify/117 sentinel (lock durable invariant)
- [ ] 3.1 No single-owner-enforcing constraint on workspace_members (assert absence, not row-count).
- [ ] 3.2 At-least-one-owner guard present in update_workspace_member_role (functiondef ILIKE '%cannot demote the last owner%').
- [ ] 3.3 Both 4-arg RPCs NOT EXECUTE-able by authenticated (service_role-only).
- [ ] 3.4 (secondary) transfer COMMENT NOT ILIKE '%single-owner strict%'.

## Phase 4 — test (after contract migration)
- [ ] 4.1 Verify vitest include globs + path; run via `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
- [ ] 4.2 Two owner rows coexist; member→owner promotion no-raise; demote-one-of-two succeeds; demote-last raises.
- [ ] 4.3 Document expected owner_user_id behavior on pointed-to-owner demotion.

## Phase 5 — cross-link
- [ ] 5.1 domain-model.md BR-WS-3 source cite → ADR-072.
- [ ] 5.2 ADR-044 2026-06-30 amendment → link ADR-072.

## Phase 6 — deferred follow-up
- [ ] 6.1 File issue: reconcile `organizations.owner_user_id` data under N owners (backfill/junction), gated on ADR-072.

## Exit
- [ ] tsc --noEmit clean (in-package); new test green; verify/117 bad=0; CPO sign-off; PR body `Closes #5756`.
