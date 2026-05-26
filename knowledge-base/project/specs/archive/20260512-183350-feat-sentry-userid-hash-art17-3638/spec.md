---
title: "Hash userId in Sentry mirror + Art. 17 erasure hooks"
issue: 3638
related: [3603, 3623, 3649]
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: feat-sentry-userid-hash-art17-3638

## Problem Statement

`mirrorP0Deduped` (`apps/web-platform/server/observability.ts:322-357`) sends raw `userId` + `conversationId` to Sentry `extra` AND to pino → Better Stack. Under GDPR Art. 4(1) these are personal-data identifiers. Two compounding issues from the PR-A2 #3603 8-agent review (security-sentinel H6 + H7):

1. **Art. 17 (right to erasure) failure**: FK CASCADE wipes DB rows on user delete; Sentry retention (30–90d) and Better Stack retention still hold the user's identifiers. A DSAR following erasure would reveal residual PII.
2. **Art. 5(1)(c) data minimization**: raw `userId` forwarded to two external processors when a pseudonymous form would suffice for triage.

Brand-survival threshold: **single-user incident**. One user discovering residual PII post-deletion is a documented compliance failure with regulator-complaint and brand-trust risk.

## Goals

1. Eliminate raw `userId` from Sentry payload via HMAC-SHA256 pseudonymization (Recital 26).
2. Provide active Art. 17 erasure for both processors (Sentry purge-by-tag, Better Stack log purge) on `account-delete.ts` invocation.
3. Document the breach-attempt observability mirror as a processing activity in `knowledge-base/legal/article-30-register.md`.
4. Preserve operational triage utility — `userIdHash` must be stable enough for cross-event correlation within a pepper-rotation window.

## Non-Goals

- `security_events` durable audit-log table (Art. 33(5) 6-year retention) — deferred to a separate D-durable-audit-log issue; different legal basis, different schema design.
- Privacy-policy text changes — Sentry + Better Stack are already disclosed as sub-processors via #1048.
- Changes to pino's in-container log shape — pino retains raw `userId` for operator debugging; erasure happens at the Better Stack boundary.
- Replacing the in-process dedup-map key (stays raw `userId` for debounce correctness).

## Functional Requirements

- **FR1.** `mirrorP0Deduped` forwards `userIdHash` (HMAC-SHA256 with server pepper) and `conversationId` to Sentry `extra` and `tags`. Raw `userId` is NOT included in any Sentry payload.
- **FR2.** `reportSilentFallback` extras pipeline transforms any caller-supplied `userId` extra to `userIdHash` before Sentry forward.
- **FR3.** Pepper rotation: support a `PEPPER_PREVIOUS` overlap value so erasure across the Sentry retention window covers events hashed with the prior pepper.
- **FR4.** `account-delete.ts` (post-cascade, after line 125) calls `DELETE /api/0/organizations/{slug}/issues/?query=userIdHash:<hash>` against Sentry for both current and previous peppers. Failure is mirrored via `reportSilentFallback` but does NOT regress account-delete success status.
- **FR5.** `account-delete.ts` submits a Better Stack log-purge job keyed on raw `userId` for the deleting user's pino events. Failure mirrored, non-blocking.
- **FR6.** New entry in `knowledge-base/legal/article-30-register.md` documenting: breach-attempt observability mirror processing activity, the two processors (Sentry pseudonymous + Better Stack raw), retention periods, erasure mechanism, legal basis (Art. 6(1)(f) legitimate interest in security monitoring).
- **FR7.** Dedup-map key (`${userId}:${op}:${conversationId}` in `mirrorP0Deduped`; `${userId}:${errorClass}` in `mirrorWithDebounce`) is unchanged — raw `userId` stays in-process for debounce correctness.

## Technical Requirements

- **TR1.** Pepper stored as Doppler secret `SENTRY_USERID_PEPPER` (and optional `SENTRY_USERID_PEPPER_PREVIOUS` during rotation). Both peppers loaded at module init in `observability.ts`; absence of the previous pepper is non-fatal.
- **TR2.** Hash output: hex-encoded HMAC-SHA256 first 16 bytes (32 hex chars) — sufficient collision resistance for tag lookup, compact enough for Sentry tag value limits.
- **TR3.** Sentry token: `event:admin` scope on a dedicated `SENTRY_ERASURE_TOKEN` Doppler secret. Separate from the existing `SENTRY_AUTH_TOKEN` so least-privilege is preserved for non-erasure surfaces.
- **TR4.** Better Stack purge: research the exact API surface during plan phase. If a per-tenant log-purge-by-query endpoint exists, call it from `account-delete.ts`. If not, document the residual retention in the Art. 30 entry and downgrade FR5 to a documented expiry.
- **TR5.** Tests: unit tests for `hashUserId(userId, pepper)` determinism + cross-pepper distinctness. Integration test for `mirrorP0Deduped` asserting no raw `userId` in Sentry payload. Integration test for `deleteAccount` asserting the Sentry DELETE + Better Stack purge are invoked.
- **TR6.** No regression in W4-orphan drop observability — `cc-dispatcher.ts:1476` continues to fire `mirrorP0Deduped` with the same signature. Only the emitted payload changes shape.

## Acceptance Criteria

- [ ] **AC1.** Pepper-hashed `userId` in Sentry payload; raw `userId` retained only in pino (container-internal) and in the in-process dedup map.
- [ ] **AC2.** `account-delete.ts` calls Sentry purge-by-tag API for current + previous pepper hashes; failures non-blocking + mirrored.
- [ ] **AC3.** `account-delete.ts` calls Better Stack log purge for the deleting user (or, if API not available, Art. 30 documents the residual retention with explicit retention-period disclosure).
- [ ] **AC4.** New `article-30-register.md` entry covering the breach-attempt mirror as a processing activity (per FR6).
- [ ] **AC5.** Coordinated with PR-C: this PR lands FIRST; the Art. 30 entry here is consumed by PR-C's downstream work.
- [ ] **AC6.** D-durable-audit-log filed as a separate issue with the `security_events` table scope.
- [ ] **AC7.** Tests per TR5 pass; `cc-dispatcher.test.ts` W4-orphan test asserts hashed `userIdHash` in mirrored payload.

## Risks & Open Questions

- **R1.** Better Stack log-purge API surface is unverified. If the API doesn't exist, FR5 downgrades to documented retention. Plan skill must resolve before implementation.
- **R2.** Pepper rotation logistics — when `SENTRY_USERID_PEPPER` rotates, all at-rest events in Sentry's retention window were hashed with the prior pepper. The erasure call must compute BOTH hashes (FR4). Rotation cadence should align with Sentry's retention setting so `PEPPER_PREVIOUS` is always sufficient.
- **R3.** Sentry tag value length limits (200 chars typical) — verify 32-char hex fits well within budget.
- **R4.** D-art30 PR-C dependency: search returned no open D-art30 issue; the register file exists. Confirm whether the PR-A2 plan's "D-art30 PR-C blocker" refers to this PR's new entry or a separate file. Plan skill to confirm scope.

## References

- Issue #3638 (this work)
- Issue #3603 (PR-A2, closed) — source 8-agent review
- `knowledge-base/project/plans/2026-05-12-feat-cc-soleur-go-transcript-hardening-pr-a2-plan.md` — D-durable-audit-log deferral context
- `knowledge-base/project/learnings/2026-04-28-sentry-payload-pii-and-client-observability-shim.md` — typed-only extras rule
- `knowledge-base/project/learnings/2026-04-17-pii-regex-scrubber-three-invariants.md` — PII scrubber invariants
- `knowledge-base/legal/article-30-register.md` — destination for FR6 entry
- `apps/web-platform/server/observability.ts` — primary code surface
- `apps/web-platform/server/account-delete.ts` — Art. 17 hook extension point
- `apps/web-platform/server/cc-dispatcher.ts:1476` — sole P0 call site
