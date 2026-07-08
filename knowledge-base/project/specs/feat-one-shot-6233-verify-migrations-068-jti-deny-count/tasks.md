# Tasks — fix(ci): complete verify/068 jti_deny per-table drift guard (#6233)

Plan: `knowledge-base/project/plans/2026-07-08-fix-verify-068-jti-deny-per-table-assertions-plan.md`

> Context: The reported count-sentinel defect (23→26) is already fixed on `main` by PR #6229
> (verify-migrations green since `a4d8208e`; dev+prd live count = 26). Residual work only:
> complete the per-table presence half of the drift guard (21 named → 26 named) and close #6233.

## Phase 1 — Setup / verify preconditions
- [ ] 1.1 Read `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` in full, noting the terminal `SELECT` of the `UNION ALL` chain and any trailing `;`.
- [ ] 1.2 Confirm the count sentinel is `jti_deny_policies_count_26` asserting `count(*) = 26` (do NOT modify it).
- [ ] 1.3 Confirm current per-table assertion count is 21: `grep -cE "_jti_not_denied_policy_present'" <file>`.

## Phase 2 — Core implementation
- [ ] 2.1 Insert 5 per-table presence assertions (mirroring existing style) for `workspace_activity`, `kb_files`, `beta_contacts`, `interview_notes`, `beta_contact_stage_transitions` — each `count(*) = 1`, RESTRICTIVE, exact `policyname` matching the migration's `CREATE POLICY` literal.
- [ ] 2.2 Insertion point is MID-CHAIN: after the last per-table assertion `workspace_member_removals_jti_not_denied_policy_present` (~line 185) and BEFORE the `-- (29-31) anon-role REVOKE matrix` block. The file's terminal SELECT is the `;`-ended `is_jti_denied_from_jwt_anon_revoke_present` anon check — keep it terminal. Do NOT append at EOF (after the `;` = syntax error). Each new row separated by `UNION ALL`; the existing `UNION ALL` before the anon block chains the last new row in.
- [ ] 2.3 Correct the header comment so it enumerates all 26 tables' provenance (21 base + 076 `workspace_activity` + 077 `kb_files` + 126 beta trio) — the "each of the 26 tables has its own policy" claim is now literally true.

## Phase 3 — Testing / verification
- [ ] 3.1 `grep -cE "_jti_not_denied_policy_present'" <file>` returns 26.
- [ ] 3.2 Parse the verify SQL (repo verify-runner harness, or `psql -f` against a scratch DB) — 0 syntax errors.
- [ ] 3.3 (Optional, read-only) re-confirm live dev+prd `pg_policies` count = 26 and the 5 tables present (already verified at plan time).

## Phase 4 — Ship
- [ ] 4.1 PR body uses `Closes #6233`.
- [ ] 4.2 Post-merge: `Web Platform Release → verify-migrations` green on the merge commit (26 count check + 26 per-table checks, 0 failed) via `gh run list --workflow "Web Platform Release" --branch main`.
- [ ] 4.3 #6233 closed (auto via `Closes`).
