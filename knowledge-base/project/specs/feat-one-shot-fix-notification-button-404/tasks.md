# Tasks — Shared workspace email-triage inbox

Plan: `knowledge-base/project/plans/2026-06-17-feat-shared-workspace-email-triage-inbox-plan.md`
Branch: `feat-one-shot-fix-notification-button-404` · PR: #5494 (draft)
Threshold: single-user incident · `requires_cpo_signoff: true`

## Phase 0 — Live topology verification (DONE 2026-06-17, read-only)
- [x] 0.1 Confirm `EMAIL_TRIAGE_OWNER_USER_ID` → ops@jikigai.com; rows user_id=754ee124
- [x] 0.2 Confirm jean.deruelle@ (52af49c2) role='owner' of workspace 754ee124 → TRUE
- [x] 0.3 Confirm workspace_id == owner uid (backfill target = user_id) → TRUE

## Phase 1 — Failing tests (RED) — AC7
- [ ] 1.1 RLS: owner-of-workspace reads row; non-owner member + non-member do NOT
- [ ] 1.2 status RPC: Owner authorized; non-owner rejected (no-oracle error)
- [ ] 1.3 detail-page query-error path mirrors once with error object
- [ ] 1.4 confirm tests FAIL before code

## Phase 2 — Migration 111 — AC1/2/3/10
- [ ] 2.1 Add `workspace_id uuid REFERENCES workspaces(id) ON DELETE RESTRICT`
- [ ] 2.2 Add `app.email_triage_backfill_in_progress` GUC arm to WORM trigger; add workspace_id to hard-frozen set
- [ ] 2.3 Backfill existing rows (workspace_id = user_id) under the GUC
- [ ] 2.4 `is_email_triage_workspace_owner(p_workspace_id, p_user_id)` SECURITY DEFINER plpgsql (role='owner'-scoped, mig 068 pattern)
- [ ] 2.5 Replace owner-SELECT RLS with owner-membership predicate
- [ ] 2.6 Re-auth `set_email_triage_status` → workspace-owner pin
- [ ] 2.7 `.down.sql` restores mig 102 shape verbatim
- [ ] 2.8 Migration safety: next ordinal, no BEGIN/COMMIT, no CONCURRENTLY

## Phase 3 — Write path — AC4
- [ ] 3.1 `email-on-received.ts` claim-insert sets workspace_id (= ownerId)

## Phase 4 — Read paths + diagnostic mirror — AC5/AC6
- [ ] 4.1 detail page → workspace gate + reportSilentFallback on error
- [ ] 4.2 `app/api/inbox/emails/route.ts` (3 queries) → workspace gate
- [ ] 4.3 `server/email-triage-tools.ts` (list/get/status) → workspace gate
- [ ] 4.3b `server/email-triage/email-triage-status-handler.ts` (acknowledge/archive handler) → widen any user_id pre-gate; RPC re-auth is DB enforcement
- [ ] 4.4 dashboard renders via /api/inbox/emails (covered by 4.2); routes [id]/{acknowledge,archive} are thin exports (no change)

## Phase 5 — GDPR verification — AC8
- [ ] 5.1 anonymise still NULLs user_id; row survives via workspace_id
- [ ] 5.2 DSAR allowlist keeps ownerField=user_id
- [ ] 5.3 gdpr-gate: solo workspace_id==user_id pseudonym question; Art.30 §(c) note

## Phase 6 — Verify — AC9/AC10
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 6.2 `./node_modules/.bin/vitest run` new + notifications.test.ts
- [ ] 6.3 ADR + C4 update (email-triage read edge User→Workspace(Owner))
