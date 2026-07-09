# Tasks — fix(ci): complete verify/068 jti_deny per-table drift guard (#6233)

Plan: `knowledge-base/project/plans/2026-07-08-fix-verify-068-jti-deny-per-table-assertions-plan.md`

> Context: The reported count-sentinel defect (23→26) is already fixed on `main` by PR #6229
> (verify-migrations green since `a4d8208e`; dev+prd live count = 26). Residual work only:
> complete the per-table presence half of the drift guard (21 named → 26 named) and close #6233.

## Phase 1 — Setup / verify preconditions
- [x] 1.1 Read `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` in full, noting the terminal `SELECT` of the `UNION ALL` chain and any trailing `;`.
- [x] 1.2 Confirm the count sentinel is `jti_deny_policies_count_26` asserting `count(*) = 26` (do NOT modify it). — confirmed line 78, unchanged.
- [x] 1.3 Confirm current per-table assertion count is 21: `grep -cE "_jti_not_denied_policy_present'" <file>`. — was 21, now 26.

## Phase 2 — Core implementation
- [x] 2.1 Insert 5 per-table presence assertions (mirroring existing style) for `workspace_activity`, `kb_files`, `beta_contacts`, `interview_notes`, `beta_contact_stage_transitions` — each `count(*) = 1`, RESTRICTIVE, exact `policyname` matching the migration's `CREATE POLICY` literal.
- [x] 2.2 Insertion point is MID-CHAIN: after the last per-table assertion `workspace_member_removals_jti_not_denied_policy_present` and BEFORE the anon-role REVOKE matrix block. Terminal `;` anon check kept terminal. Each new row separated by `UNION ALL`.
- [x] 2.3 Correct the header comment so it enumerates all 26 tables' provenance (21 base + 076 `workspace_activity` + 077 `kb_files` + 126 beta trio) — the "each of the 26 tables has its own policy" claim is now literally true.

## Phase 3 — Testing / verification
- [x] 3.1 `grep -cE "_jti_not_denied_policy_present'" <file>` returns 26.
- [x] 3.2 Parse the verify SQL — ran the full query read-only against dev via Supabase MCP: 35 rows returned (0 syntax errors), `failing_checks = 0`, `per_table_checks = 26`.
- [x] 3.3 Live dev `pg_policies` re-confirmed: all 26 per-table checks + count check pass (bad=0); all 5 new tables resolve to their policies.

## Phase 4 — Ship
- [ ] 4.1 PR body uses `Closes #6233`.
- [ ] 4.2 Post-merge: `Web Platform Release → verify-migrations` green on the merge commit (26 count check + 26 per-table checks, 0 failed) via `gh run list --workflow "Web Platform Release" --branch main`.
- [ ] 4.3 #6233 closed (auto via `Closes`).
