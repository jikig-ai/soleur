---
plan: knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-coverage-plan.md
spec: knowledge-base/project/specs/feat-dsar-workspace-member-4230/spec.md
issue: 4230
draft_pr: 4294
branch: feat-dsar-workspace-member-4230
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
estimate_days: 3-4
follow_ups:
  - 4319 (author-only message redaction split)
date: 2026-05-22
---

# Tasks — DSAR Departed-Workspace-Member Coverage (#4230)

## Phase 0 — Preconditions

- [ ] **0.1** Read `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` L41-141 + L267-401 verbatim. Confirm WORM-trigger shape, anonymise RPC shape, REVOKE matrix, AC-FLOW4 guards.
- [ ] **0.2** Locate `account-delete.ts` cascade-order insertion point: `git ls-files | grep account-delete` then read existing anonymise cascade.
- [ ] **0.3** Verify supabase-js `.or()` syntax at `node_modules/@supabase/postgrest-js/src/PostgrestFilterBuilder.ts` v2.99.2. Plan-time grep confirmed; AC4 fixture exercises.
- [ ] **0.4** Invoke `/soleur:architecture create 'DSAR departed-member coverage via removal-event ledger'`. Confirm ADR-039 file path.

## Phase 1 — Migration 062 (workspace_member_removals + remove_rpc_update)

- [ ] **1.1** Create `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql`:
  - Table DDL: `(id uuid PK, workspace_id uuid NOT NULL REFERENCES workspaces ON DELETE RESTRICT, removed_user_id uuid NULL REFERENCES users ON DELETE RESTRICT, removed_by_user_id uuid NULL REFERENCES users ON DELETE RESTRICT, removed_at timestamptz NOT NULL DEFAULT now())`
  - Covering index `(workspace_id, removed_at DESC)`
  - REVOKE INSERT/UPDATE/DELETE FROM `PUBLIC, anon, authenticated`
  - SELECT-for-members RLS policy mirroring 058:64-66
  - WORM trigger function mirroring 058:72-141 (DELETE always rejected; UPDATE only allowed for `removed_user_id IS NULL` and `removed_by_user_id IS NULL` transitions; lineage columns `id`, `workspace_id`, `removed_at` immutable)
  - BEFORE UPDATE + BEFORE DELETE triggers mirroring 058:130-137

- [ ] **1.2** `anonymise_workspace_member_removals(p_user_id uuid)` SECURITY DEFINER RPC mirroring 058:342-362 — UPDATE setting `removed_user_id = NULL` AND `removed_by_user_id = NULL` for rows where either column matches `p_user_id`; preserve `id`, `workspace_id`, `removed_at`.

- [ ] **1.3** `CREATE OR REPLACE FUNCTION public.remove_workspace_member`:
  - **PASTE 058:267-331 VERBATIM** (do not paraphrase)
  - Preserve `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, `GRANT EXECUTE TO authenticated`
  - Add `INSERT INTO public.workspace_member_removals (workspace_id, removed_user_id, removed_by_user_id) VALUES (p_workspace_id, p_user_id, v_caller_user_id);` BEFORE the DELETE at line 320
  - All existing AC-FLOW4 guards preserved (owner-self-remove rejection, owner-target rejection, idempotent-not-a-member RETURN 0)

- [ ] **1.4** pg_cron retention sweep at 36-mo:
  - GUC name: `app.workspace_member_removal_anonymise_in_progress`
  - Sweep RPC sets GUC to `'true'` before DELETE then resets
  - WORM trigger bypass clause: `current_setting('app.workspace_member_removal_anonymise_in_progress', true) = 'true' AND current_user = 'service_role'`
  - Schedule per `041:383-395` shape

- [ ] **1.5** Create `062_workspace_member_removals_and_remove_rpc_update.down.sql`:
  - DROP retention-sweep job
  - DROP triggers
  - DROP `anonymise_workspace_member_removals` function
  - DROP `workspace_member_removals` table
  - `CREATE OR REPLACE FUNCTION public.remove_workspace_member` reverting to pre-change body (verbatim copy from 058:267-326)

## Phase 2 — DSAR export pipeline

- [ ] **2.1** `apps/web-platform/server/dsar-export.ts` L609-630: add historical-attestations query `service.from("workspace_member_attestations").select("workspace_id").eq("invitee_user_id", X)`; merge into `workspaceIds` via `new Set([...current, ...historical])` before the L639 length check; preserve `CrossTenantViolation` assertion.

- [ ] **2.2** `apps/web-platform/server/dsar-export.ts` L678-697:
  - Replace `.eq("invitee_user_id", expectedUserId)` with `.or("invitee_user_id.eq." + expectedUserId + ",inviter_user_id.eq." + expectedUserId)`
  - Update `assertReadScope` at L689-691 to two-arm validator: `row.invitee_user_id === expectedUserId || row.inviter_user_id === expectedUserId` (Kieran P1-1)
  - Update L672-677 comment: remove stale "exporting both sides under one ownerField avoids the gap" claim

- [ ] **2.3** `apps/web-platform/server/dsar-export.ts`: add `workspace_member_removals` export block following the attestations pattern (analog to L672-697), keyed on `.eq("removed_user_id", expectedUserId)`.

- [ ] **2.4** `apps/web-platform/server/dsar-export-allowlist.ts`: add `workspace_member_removals: { ownerField: "removed_user_id", article: "15" }` entry. Add comment block following existing style.

## Phase 3 — Integration test

- [ ] **3.1** Create `apps/web-platform/test/dsar-departed-member.integration.test.ts`:
  - Synthesize two users (`Harry`, `Jean`) + organization + workspace
  - Jean invites Harry, Harry accepts (attestation row written)
  - Harry sends messages in conversations Harry owns
  - Harry invites Bob (another synthesized user); Bob accepts — Harry now has an INVITER-side attestation row
  - Jean removes Harry via `removeWorkspaceMember`
  - Harry triggers `dsar-reauth` then full export pipeline (verifies AC6(d) post-removal reauth works)
  - Assert: (a) bundle contains workspace metadata for Jean's workspace
  - Assert: (b) bundle contains `workspace_member_removals` row recording the removal event
  - Assert: (c) bundle contains BOTH invitee-side AND inviter-side attestation rows for Harry
  - Use `cq-test-fixtures-synthesized-only` pattern

- [ ] **3.2** Add FK-violation propagation test for AC2:
  - Invoke `remove_workspace_member` with a `removed_user_id` that violates `users` FK RESTRICT
  - Assert: RPC raises an exception
  - Assert: post-RPC, the membership row remains intact (DELETE did NOT execute)

## Phase 4 — Legal docs + cascade order

- [ ] **4.1** Insert PA-19 row in `knowledge-base/legal/article-30-register.md`:
  - Title: "Processing Activity 19 — Workspace Member Removal Audit Ledger (`workspace_member_removals`)"
  - Controller, Art. 6(1)(c) lawful basis
  - 36-mo retention (deviates from 24-mo PA-PII envelope; rationale in ADR-039)
  - Cross-doc references to PR #4289

- [ ] **4.2** Update `knowledge-base/legal/compliance-posture.md` DSAR Active Item row: reference this PR + cascade-order extension for the new table.

- [ ] **4.3** Create `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`:
  - Art. 12(6) ID-verification template
  - 30-day SLA per Art. 12(3)
  - Audit-log template (received_at, responded_at, identity_proof, decision)
  - CLO escalation clause

- [ ] **4.4** Extend `apps/web-platform/server/account-delete.ts` cascade order: call `anonymise_workspace_member_removals(p_user_id)` AFTER `anonymise_workspace_member_attestations` and BEFORE `auth.admin.deleteUser()`.

## Phase 5 — PR + ship gates

- [ ] **5.1** PR body authoring:
  - `Ref #4230` (NOT `Closes`; ops-remediation class per `wg-use-closes-n-in-pr-body-not-title-to`)
  - Cross-link PR #4289 (legal scaffolding) and #4319 (redaction split)
  - Comment: "departed-member legal text rides PR #4289; redaction predicate moved to #4319 per plan-review"

- [ ] **5.2** Invoke `/soleur:gdpr-gate` on final diff. Confirm no Critical findings beyond known-folded items.

- [ ] **5.3** Invoke `/soleur:preflight` Check 6 (USER_BRAND_CRITICAL gate). Confirm User-Brand Impact section populated.

- [ ] **5.4** Mark PR #4294 `ready`. No cross-PR `ready`-state gate on #4289 (body cross-link sufficient per plan-review consensus).

- [ ] **5.5** `user-impact-reviewer` agent invoked at PR review (auto-fires on `USER_BRAND_CRITICAL=true`).

## Post-merge (automated)

- [ ] **PM.1** `web-platform-release.yml#migrate` applies migration 062 to prd-Supabase. Verification: `mcp__plugin_supabase_supabase__*` query for `workspace_member_removals` table + RPC + RLS policy count.

- [ ] **PM.2** `gh issue close 4230` triggered after PM.1 confirms. Comment: "Approach A+B shipped; brand-survival path closed. Redaction split tracked at #4319."

- [ ] **PM.3** Re-evaluate follow-through #4284 (flag-flip) once PM.1+PM.2 + PR #4289 merge are all green.

## Verification Checklist (mapped to ACs)

- AC1 → 1.1, 1.3, 1.5
- AC2 → 3.2
- AC3 → 2.1, 3.1(a)
- AC4 → 2.2, 3.1(c)
- AC5 → 2.4
- AC6 → 3.1
- AC7 → 0.4, 4.1, 4.2, 4.3
- AC8 → 5.2, 5.3, 5.5; cq-pg-security-definer verified by Phase 0.1 + 1.3 grep
- AC9 → PM.1
- AC10 → PM.2, PM.3
