# Tasks — Shared workspace email-triage inbox  ✅ COMPLETE

Plan: `knowledge-base/project/plans/2026-06-17-feat-shared-workspace-email-triage-inbox-plan.md`
Branch: `feat-one-shot-fix-notification-button-404` · PR: #5494
Threshold: single-user incident · `requires_cpo_signoff: true`
ADR: ADR-066 · C4: model.c4 + views.c4 updated (email ingress + Owner-shared)

## Phase 0 — Live topology verification (DONE, read-only)
- [x] EMAIL_TRIAGE_OWNER_USER_ID → ops@jikigai.com; rows user_id=754ee124
- [x] jean.deruelle@ (52af49c2) role='owner' of workspace 754ee124 → TRUE
- [x] workspace_id == owner uid (backfill target = user_id) → TRUE

## Phase 1 — Failing tests (RED) — AC7  [x]
- [x] New test/inbox-email-detail-page.test.ts (error-mirror / absence / render / id-only gate)
- [x] route + tools tests flipped to assert RLS-only gating
- [x] WORM integration test: workspace-owner semantics + shared-owner case (j)

## Phase 2 — Migration 111  [x]
- [x] workspace_id column + backfill GUC arm + WORM hard-freeze
- [x] is_email_triage_workspace_owner SECURITY DEFINER helper (role='owner')
- [x] owner-membership SELECT RLS; set_email_triage_status workspace-owner re-auth
- [x] .down.sql restores mig-102 shape (data-integrity-guardian: faithful)
- [x] verify/111 sentinel; applied to dev — 8/8 sentinels green; 11/11 worm tests green

## Phase 3 — Write path  [x]
- [x] email-on-received.ts stamps workspace_id = ownerId

## Phase 4 — Read paths + mirror  [x]
- [x] detail page → workspace gate + reportSilentFallback(inbox-detail-lookup-error)
- [x] inbox list route (3 queries) → RLS-only
- [x] email-triage-tools (list/get/reply) → RLS-only
- [x] status-handler comment refreshed (RPC is the DB enforcement)

## Phase 5 — GDPR  [x]
- [x] gdpr-gate: anonymise/DSAR unchanged-by-design; pseudonym question ruled (Suggestion/defensible)

## Phase 6 — Verify + architecture  [x]
- [x] tsc --noEmit clean; full vitest 10625 passed / 0 failed
- [x] ADR-066 + C4 (model/views) email-ingress modeling; c4-code-syntax + c4-render green
- [x] Adversarial review: data-integrity + security-sentinel + observability — all clean
