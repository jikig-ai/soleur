---
feature: byok-delegation-consent-enforcement
issue: 4625
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-feat-byok-delegation-consent-enforcement-plan.md
---

# Tasks — BYOK Delegation Consent Enforcement

TDD (RED → GREEN) per phase. Migrations ship with `.down.sql`. Every `CREATE OR REPLACE`
DEFINER fn re-asserts REVOKE/GRANT + `pg_default_acl` audit.

## Phase 1 — Server-owned canonical version (security prerequisite)
- [ ] 1.1 Precondition greps: next mig = 083; `resolve_byok_key_owner` unchanged (064:583); read WORM shapes (064:245-355) + `revocation_reason` enum (064:95-99); no existing `BYOK_SIDE_LETTER_VERSION`.
- [ ] 1.2 Create `server/byok-side-letter.ts` exporting `BYOK_SIDE_LETTER_VERSION` (e.g. `"1.0"`).
- [ ] 1.3 Create SQL `current_byok_side_letter_version()` (`IMMUTABLE`, pinned search_path) — same literal.
- [ ] 1.4 RED: parity test (TS const === SQL output), wire as CI gate.
- [ ] 1.5 Edit `accept/route.ts` + `delegation-acceptance-modal.tsx` + request type: drop `sideLetterVersion` field; route stamps server const.
- [ ] 1.6 RED→GREEN: stored `side_letter_version` always === server const regardless of body.

## Phase 2 — Consent gate in resolver (mig 083)
- [ ] 2.1 Create `083_byok_delegation_consent_gate.sql` (+`.down.sql`): `CREATE OR REPLACE resolve_byok_key_owner` + `AND EXISTS(current-version acceptance)`; re-assert REVOKE/GRANT; default-priv audit.
- [ ] 2.2 RED→GREEN: no-acceptance → `MissingByokKeyError` (distinct from `ByokDelegationRevokedError`); stale-version → fail-closed; current-version → grantor key; own-key → unaffected.

## Phase 3 — Withdrawal (mig 084 + resolver clause + per-turn re-gate + route + UI)
- [ ] 3.1 Create `084_byok_delegation_withdrawals.sql` (+`.down.sql`): append-only WORM table mirroring 074 but **NO `UNIQUE(user_id, delegation_id)`** (non-terminal + Art. 17 anonymise collision); `no_update`/`no_delete` triggers; `anonymise_byok_delegation_withdrawals` RPC that sets `SET LOCAL session_replication_role='replica'` in its own body; RLS select `user_id=auth.uid()` + insert `WITH CHECK (user_id=auth.uid() AND delegation_id IN (SELECT id FROM byok_delegations WHERE grantee_user_id=auth.uid()))`.
- [ ] 3.2 Create SECURITY DEFINER `withdraw_byok_delegation_consent(p_delegation_id)` — **NO `p_user_id`** (derive `auth.uid()`); grantee-only `RAISE EXCEPTION`; INSERT withdrawal row only (NO `revoked_at`); idempotent; `GRANT EXECUTE TO authenticated`.
- [ ] 3.3 In mig 084, `CREATE OR REPLACE resolve_byok_key_owner` adding `AND NOT EXISTS(withdrawal ... withdrawn_at >= COALESCE(max(acceptance.accepted_at), withdrawn_at))` — version-agnostic, COALESCE, `>=`; re-assert REVOKE/GRANT; default-priv audit.
- [ ] 3.4 In mig 084, `CREATE OR REPLACE check_and_record_byok_delegation_use` (064:665): per-turn consent re-gate (row already FOR UPDATE) — withdrawal newer than latest acceptance → raise + debit grantee with new `attribution_shift_reason` (extend enum if CHECK-constrained).
- [ ] 3.5 Create `POST /api/workspace/delegations/withdraw` route (auth, CSRF, flag-gated; passes only delegationId).
- [ ] 3.6 Edit `account-delete.ts`: anonymise withdrawals BEFORE `deleteUser` (FK ON DELETE RESTRICT).
- [ ] 3.7 Edit `dsar-export.ts` + `dsar-export-allowlist.ts`: add `byok_delegation_withdrawals`.
- [ ] 3.8 RED→GREEN: withdrawal blocks new leases AND stops in-flight billing within one turn (debits grantee); NULL-COALESCE + tie (`>=`) block; re-accept reactivates; multiple withdrawals recorded (no UNIQUE); WORM enforced; cross-tenant/forged rejected; resolver RPC-error never leases grantor key (AC12); account-delete succeeds with ≥1 withdrawal row.

## Phase 4 — Consent text + mig 074 header (legal)
- [ ] 4.1 `legal-document-generator`: rewrite `delegation-consent-side-letter-template.md` as versioned in-app text embodying Art. 26 arrangement + Art. 6 basis; grantor bound to same version.
- [ ] 4.2 Edit mig 074 header comment: state Art. 6 + Art. 26 coherently (drop the "6(1)(b) — grantee consents" conflation).
- [ ] 4.3 Retain DPD §2.3 + AUP §5.6 (public disclosure half).

## Phase 5 — Pending-consent UX (ADVISORY)
- [ ] 5.1 Grantor not-live state (no spend/cap banner pre-acceptance).
- [ ] 5.2 Grantee accept flow: inline telemetry-visibility acknowledgment (CLO-required) + withdraw affordance on the same surface.

## Phase 6 — Flag flip (CLO sign-off gate)
- [ ] 6.1 (Post-merge) CLO confirms consent text satisfies Art. 26 (sign-off on #4625).
- [ ] 6.2 (Post-merge) Flip `FLAG_BYOK_DELEGATIONS` via `/soleur:flag-set-role` (Flagsmith + Doppler); `Ref #4625`; `gh issue close 4625`.

## Pre-merge gates
- [ ] `/soleur:gdpr-gate` against the diff (TR6); ADR via `/soleur:architecture create` (withdrawal model + version ownership) before the gate PR merges; deepen-plan triad (data-integrity-guardian + security-sentinel + architecture-strategist) — mandated at single-user-incident threshold.
