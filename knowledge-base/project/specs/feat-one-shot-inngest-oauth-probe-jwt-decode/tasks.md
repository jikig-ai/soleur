---
title: "Tasks: fix probe-octokit App-JWT decode — PKCS#8 canonicalization"
feature: feat-one-shot-inngest-oauth-probe-jwt-decode
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-probe-octokit-jwt-decode-pkcs8-canonicalization-plan.md
date: 2026-05-29
---

# Tasks

## Phase 0 — Preconditions
- [ ] 0.1 Verify installed lib versions (`@octokit/app@16.1.2`, `universal-github-app-jwt@2.2.2`) in `apps/web-platform/package-lock.json`; re-verify lib source if drifted.
- [ ] 0.2 Grep `probe-octokit.ts` for secret/JWT references — confirm only `readEnv` + the new local const reach `new App()`.
- [ ] 0.3 Enumerate all `createProbeOctokit`/`createAppJwtOctokit` callers (blast radius: cron-bug-fixer, _cron-shared, roadmap/strategy crons).
- [ ] 0.4 Confirm vitest runner; run existing `probe-octokit-retry.test.ts` GREEN before edits.
- [ ] 0.5 Decide helper home (`normalizeAppPrivateKey` exported from `probe-octokit.ts`, used by both factories).

## Phase 1 — RED: PEM canonicalization tests
- [ ] 1.1 Test: PKCS#1 PEM → PKCS#8 (synthesized `generateKeyPairSync` fixture).
- [ ] 1.2 Test: CRLF PEM → `\r`-free PKCS#8 whose body base64 decodes.
- [ ] 1.3 Test: escaped `\n` env-shaped key expands to real newlines.
- [ ] 1.4 Test: clean PKCS#8 LF PEM idempotent.
- [ ] 1.5 Test: empty/whitespace env value still throws `readEnv` error.
- [ ] 1.6 Confirm RED against current raw-passthrough; existing retry/diagnostics tests still pass.

## Phase 2 — GREEN: add normalizeAppPrivateKey + route both factories
- [ ] 2.1 Add `createPrivateKey` import.
- [ ] 2.2 Add `normalizeAppPrivateKey(raw)` helper (expand `\n` → `createPrivateKey().export({type:"pkcs8",format:"pem"})`).
- [ ] 2.3 Wrap BOTH `new App({ privateKey })` sites (`attempt()` + `createAppJwtOctokit`) in `normalizeAppPrivateKey(readEnv(...))`.
- [ ] 2.4 Run `vitest run test/server/github/` GREEN.

## Phase 3 — REFACTOR + typecheck + scope guard
- [ ] 3.1 `tsc --noEmit` clean (keep `.toString()` for the `string|Buffer` union).
- [ ] 3.2 Scope guard: no `github-app.ts` margin change, no `exp`/`iat` edit, #4568 diagnostics/retry preserved.
- [ ] 3.3 Full `test/server/github/` slice green (no sibling regression).

## Phase 4 — Runbook
- [ ] 4.1 Add `probe_app_jwt_decode` failure-mode subsection to `oauth-probe-failure.md` with non-SSH verification recipe.
- [ ] 4.2 Cross-link Sentry id `4e6a3003d19d47809616d521df3c795b` + this PR.

## Acceptance Criteria (gate before PR-ready)
- [ ] AC1-AC4 canonicalization tests pass; AC5 both factories routed; AC6 no secret leak; AC7 scope guard; AC8 suite+tsc green; AC9 runbook entry.
- [ ] Post-merge: AC10 manual probe trigger recovers (`?status=ok` check-in); AC11 `4e6a3003…` class quiets.
