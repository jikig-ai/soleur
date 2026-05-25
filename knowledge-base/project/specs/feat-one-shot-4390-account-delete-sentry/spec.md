---
title: "obs: route account-delete.ts anonymise failure paths through Sentry.captureException"
issue: 4390
related: [4356, 4357, 3638, 3685, 3698]
branch: feat-one-shot-4390-account-delete-sentry
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: observability-hygiene
plan: knowledge-base/project/plans/2026-05-25-obs-account-delete-sentry-mirror-plan.md
last_updated: 2026-05-25
---

# Spec: feat-one-shot-4390-account-delete-sentry

## Goal

Route every FATAL anonymise step + the terminal `auth-delete` failure path in `apps/web-platform/server/account-delete.ts` through `reportSilentFallback` / `warnSilentFallback` so the GDPR Art. 17 erasure cascade pages the on-call via Sentry on failure (in addition to the existing pino → Better Stack mirror).

## Functional Requirements

- **FR1** — Every FATAL `log.error` site (steps 3.82, 3.83, 3.84, 3.85, 3.90, 3.905, 3.91, 3.92, 3.93 + auth-delete at line 553) emits via `reportSilentFallback({ feature: "account-delete", op: "<stage-slug>", extra: { userId, err? }, message: "<original literal>" })`. 10 FATAL stages × 2 emit arms (if-error + catch) + 1 auth-delete = 21 emits.
- **FR2** — The non-FATAL step 3.86 (`anonymise_audit_github_token_use`) emits via `warnSilentFallback` (level=warning, not error). The FK is `ON DELETE SET NULL` so the cascade continues regardless.
- **FR3** — Every emit carries an explicit `message:` string matching the pre-PR literal verbatim (per `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`). No reliance on helper-default `"account-delete silent fallback"`.
- **FR4** — No direct `Sentry.captureException` / `Sentry.captureMessage` calls in `account-delete.ts`. ADR-029 boundary preserved — all Sentry routing flows through the helper.
- **FR5** — `extra.userId` field stays raw at the call site; the helper layer pseudonymises to `userIdHash` via `hashExtraUserId` (ADR-029).
- **FR6** — Head-of-cascade non-fatal `log.warn` sites (lines 104, 128, 134, 144, 156, 182, 196, 220) are explicitly scoped OUT and remain as-is — best-effort steps whose failure does not block the cascade.

## Test Strategy

- Mock `@/server/observability` (not `@sentry/nextjs`) per repo precedent — assert on helper-input args (`feature`, `op`, `message`, `extra`). The helper's internal pseudonymisation lives in `observability.test.ts` and is not re-asserted here. Pattern: `apps/web-platform/test/api-accept-terms-ledger.test.ts:50-68`.
- Extend three existing cascade tests with `vi.mock("@/server/observability", { reportSilentFallback, warnSilentFallback, hashUserId })` and per-failure-arm assertions on `mockReportSilentFallback` / `mockWarnSilentFallback`.
- New parametrised test `account-delete-sentry-mirror.test.ts` covering all 11 emit stages + 1 happy-path case (12 tests total).
- Test runner: **vitest**, not bun test (`apps/web-platform/bunfig.toml` sets `pathIgnorePatterns = ["**"]` per #1469). All verification commands use `./node_modules/.bin/vitest run <path>`.

## Risks

See plan `## Risks` section. Highest risks:

1. Sentry mock parity drift — mitigated by canonical 4-primitive mock.
2. `message:` default substitution — mitigated by AC5 grep on count=21.
3. `level: "warning"` for 3.86 — mitigated by parametrised test `warn: true` row.

## Scope

- **In:** `apps/web-platform/server/account-delete.ts`; 3 existing cascade tests; 1 new parametrised test.
- **Out:** Head-of-cascade non-fatal log.warn sites; backfilling Sentry alert rules; `hashUserId()`-at-call-site refactor; direct-bypass sentinel sweep across other server files.

## References

- Plan: `knowledge-base/project/plans/2026-05-25-obs-account-delete-sentry-mirror-plan.md`
- Parent: PR #4357 (MERGED), Issue #4356 (CLOSED)
