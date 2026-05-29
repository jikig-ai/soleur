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

## Phase 3 — Withdrawal (mig 084 + resolver clause + route + UI)
- [ ] 3.1 Create `084_byok_delegation_withdrawals.sql` (+`.down.sql`): WORM table mirroring 074 + `no_update`/`no_delete` triggers + `anonymise_byok_delegation_withdrawals` RPC + RLS.
- [ ] 3.2 Create SECURITY DEFINER `withdraw_byok_delegation_consent` — INSERT withdrawal row only (NO `revoked_at` write); idempotent; grantee-only.
- [ ] 3.3 In mig 084, `CREATE OR REPLACE resolve_byok_key_owner` adding `AND NOT EXISTS(withdrawal newer than latest current-version acceptance)`; re-assert REVOKE/GRANT; default-priv audit.
- [ ] 3.4 Create `POST /api/workspace/delegations/withdraw` route (auth, CSRF, flag-gated, grantee-only).
- [ ] 3.5 Edit `account-delete.ts`: anonymise withdrawals BEFORE `deleteUser` (FK ON DELETE RESTRICT).
- [ ] 3.6 Edit `dsar-export.ts` + `dsar-export-allowlist.ts`: add `byok_delegation_withdrawals`.
- [ ] 3.7 RED→GREEN: withdrawal blocks new leases; in-flight unaffected; re-accept reactivates; WORM enforced; cross-tenant rejected; account-delete succeeds with withdrawal row (FK-block regression).

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
