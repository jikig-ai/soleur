---
feature: feat-one-shot-3696-pseudonymize-client-userid-sentry
issue: 3696
plan: knowledge-base/project/plans/2026-05-12-feat-pseudonymize-client-userid-sentry-plan.md
lane: cross-domain
last_updated: 2026-05-12
---

# Tasks: feat-one-shot-3696-pseudonymize-client-userid-sentry

Derived from `knowledge-base/project/plans/2026-05-12-feat-pseudonymize-client-userid-sentry-plan.md`.

## 1. Setup — Preflight & Sweep

- [ ] 1.1 Run `grep -rn "@/lib/client-observability" apps/web-platform/ --include="*.ts" --include="*.tsx" | grep -v "/test/" | sort -u` and confirm count matches plan inventory (≥ 18 sites). Halt if divergence ≥ 2 sites.
- [ ] 1.2 Run `grep -rnE "Sentry\.(captureException|captureMessage)\(" apps/web-platform/lib apps/web-platform/components apps/web-platform/app --include="*.ts" --include="*.tsx" | grep -v "/api/" | grep -v "client-observability.ts" | grep -v "/test/"` — enumerate every direct Sentry call site in browser-importable code. Confirm none currently passes `userId` / `user_id` / `email` in `extra`.
- [ ] 1.3 Confirm `Sentry.setUser` is NOT called anywhere (`grep -rn "Sentry\.setUser" apps/web-platform/` returns no production matches).

## 2. Core Implementation

### 2.1 `lib/client-observability.ts` — runtime strip + TS brand

- [ ] 2.1.1 Add `PII_KEY_RE = /^user_?id$|^email$/i` constant + `PiiKey` type + `ClientExtra` branded type. See plan Phase 1.
- [ ] 2.1.2 Add `stripPiiKeys(extra)` helper with dev-only `console.warn`, prod-silent, `piiStripped` sentinel return shape.
- [ ] 2.1.3 Widen `SilentFallbackOptions.extra` from `Record<string, unknown>` to `ClientExtra`.
- [ ] 2.1.4 Route `extra` through `stripPiiKeys` inside both `reportSilentFallback` and `warnSilentFallback` bodies before passing to Sentry.

### 2.2 `sentry.client.config.ts` — Sentry `beforeSend` backstop

- [ ] 2.2.1 Add `PII_KEY_RE` + `stripPiiFromRecord` private helper.
- [ ] 2.2.2 Add exported `stripUserContextFromEvent<T extends Sentry.ErrorEvent>(event: T): T` that scrubs `event.user.{id,email,username,ip_address}`, `event.extra`, `event.contexts.*`, `event.breadcrumbs[*].data`.
- [ ] 2.2.3 Chain `stripUserContextFromEvent(scrubJwtFromEvent(event))` inside the existing `beforeSend(event)`.

### 2.3 PA8 §(c)(i) narrow-disclosure update

- [ ] 2.3.1 In `knowledge-base/legal/article-30-register.md`, append the one-sentence client-side strip + `beforeSend` backstop disclosure to §(c)(i). See plan Phase 4 for exact wording.
- [ ] 2.3.2 Bump `last_reviewed` frontmatter to merge date.

## 3. Testing

### 3.1 `test/client-observability.test.ts` (new file)

- [ ] 3.1.1 Mock `@sentry/nextjs` via `vi.hoisted` + `vi.mock`. Import `reportSilentFallback`, `warnSilentFallback` from `@/lib/client-observability`.
- [ ] 3.1.2 Test: `userId` stripped from extra on `reportSilentFallback` (Error path). `@ts-expect-error` directive proves brand catches the literal at compile time.
- [ ] 3.1.3 Test: `user_id` (snake) + `email` stripped together.
- [ ] 3.1.4 Test: `userId` stripped from extra on `warnSilentFallback` (non-Error path).
- [ ] 3.1.5 Test: non-PII keys (`segment`, `digest`) pass through unchanged; no `piiStripped` sentinel.
- [ ] 3.1.6 Test: undefined `extra` does not throw.
- [ ] 3.1.7 Test: dev-only `console.warn` fires when `NODE_ENV !== "production"`; silent in production.
- [ ] 3.1.8 Test: case-insensitive variants (`UserID`, `USERID`) stripped.

### 3.2 `test/sentry-client-strip-user-context.test.ts` (new file)

- [ ] 3.2.1 Import `stripUserContextFromEvent` from `@/sentry.client.config`. Mirror `test/sentry-client-jwt-scrub.test.ts` shape.
- [ ] 3.2.2 Test: `event.user.{id,email,username,ip_address}` all zeroed.
- [ ] 3.2.3 Test: `event.extra.{userId,user_id,email}` stripped; non-PII kept.
- [ ] 3.2.4 Test: `event.contexts.<any>.{userId,user_id,email}` stripped.
- [ ] 3.2.5 Test: `event.breadcrumbs[*].data.{userId,email}` stripped.
- [ ] 3.2.6 Test: no-PII events unchanged.
- [ ] 3.2.7 Test: all-undefined optional fields handled without throw.

### 3.3 Existing regression

- [ ] 3.3.1 `test/sentry-client-jwt-scrub.test.ts` still passes 3/3 (chain ordering verified).

## 4. Gates

- [ ] 4.1 `tsc --noEmit` passes. `@ts-expect-error` directives in `test/client-observability.test.ts` are not flagged as `TS2578 Unused` (the brand is load-bearing).
- [ ] 4.2 `vitest run apps/web-platform/test/client-observability.test.ts apps/web-platform/test/sentry-client-strip-user-context.test.ts apps/web-platform/test/sentry-client-jwt-scrub.test.ts` — all suites green.
- [ ] 4.3 `bash scripts/test-all.sh` — full suite green; no cross-suite regression vs. predecessor baseline.
- [ ] 4.4 `/soleur:gdpr-gate` invoked at work Phase 2 exit per AGENTS.md `hr-gdpr-gate-on-regulated-data-surfaces` + `wg-plan-prescribed-skills-must-run-inline`. Advisory pass expected (PR reduces PII exposure).
- [ ] 4.5 Multi-agent `/review` at PR time with `user-impact-reviewer` ENABLED (per `requires_cpo_signoff: true` plan frontmatter).

## 5. Acceptance Criteria Pointers

- AC1–AC9 enumerated in plan §Acceptance Criteria — each task above maps to one or more AC. Verification commands inline in the plan AC text.
- Post-merge operator action: **none** (no Doppler change, no SSR-inject change, no migration).

## 6. Sharp Edges Reminders

- The three defense layers (TS brand, runtime strip, `beforeSend` backstop) are independent. Do not collapse "for simplicity."
- `event.user` mutation pattern depends on `@sentry/nextjs` types at the installed version. If `tsc --noEmit` flags the `= undefined` assignment, switch to `delete`.
- `@ts-expect-error` directives are load-bearing; do not remove them when refactoring tests.
- PA8 §(c)(i) phrasing scopes the claim to (a) helper boundary AND (b) `beforeSend` backstop — do NOT over-claim "no PII ever reaches Sentry from the client."

## 7. References

- Plan: `knowledge-base/project/plans/2026-05-12-feat-pseudonymize-client-userid-sentry-plan.md`
- Predecessor: PR #3685 (server-side pseudonymization), PR #3638 (issue), #3698 (pino direct-emit migration follow-up)
- Constitution: `knowledge-base/overview/constitution.md`
- Learnings:
  - `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`
  - `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`
