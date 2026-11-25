# Tasks — fix-linkedin-token-validator-userinfo (#9188)

Plan: `knowledge-base/project/plans/2026-09-29-fix-linkedin-token-validator-userinfo-plan.md`

## Phase 1 — Capability-aware probe chain (TDD)

- [ ] 1.1 Update `apps/web-platform/test/token-validators.test.ts` first (failing tests). Fetch mocks keyed per URL via `mockFetch.mockImplementation((url) => …)` returning `{ok, status}` shapes:
  - [ ] 1.1.1 Community-shaped token: userinfo `403` → `/v2/me` `200` ⇒ `true`; assert fetch order `[userinfo, me]` and callCount 2.
  - [ ] 1.1.2 Org-capable member-denied shape: userinfo `403` → `/v2/me` `403` → `organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED` `200` ⇒ `true`; assert all three URLs in order.
  - [ ] 1.1.3 Scope-empty token: `403` on all three probes ⇒ `false`.
  - [ ] 1.1.4 Dead token: userinfo `401` ⇒ `false` AND callCount 1 (short-circuit — no fallback burn).
  - [ ] 1.1.5 OIDC regression guard: userinfo `200` ⇒ `true` AND callCount 1 (extend the existing L93-96 linkedin test).
  - [ ] 1.1.6 Unexpected status: userinfo `500` (and/or `429`) ⇒ `false` AND callCount 1 — only `403` triggers fallback.
  - [ ] 1.1.7 Transport: fetch throws on userinfo ⇒ `false` AND callCount 1 (unchanged semantics).
  - [ ] 1.1.8 `redirect: "manual"` present in the fetch init on every linkedin probe.
  - [ ] 1.1.9 Non-linkedin pin: `github` `403` ⇒ `false` callCount 1 (providers without `fallbackUrls` identical — P5).
  - [ ] 1.1.10 Confirm the new tests are RED against current code.
- [ ] 1.2 Edit `apps/web-platform/server/token-validators.ts`:
  - [ ] 1.2.1 `ValidatorConfig` gains `fallbackUrls?: string[]` (consulted only after a `403`) and `redirect?: "manual"`.
  - [ ] 1.2.2 `linkedin` entry: `url` stays `v2/userinfo`; `fallbackUrls: ["https://api.linkedin.com/v2/me", "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED"]`; `redirect: "manual"`; comment names both developer apps and the unknowable-minting-app rationale.
  - [ ] 1.2.3 `validateToken` loops `[primary, ...fallbackUrls]`: `res.ok` → `true`; `401` → `false` (stop); `403` → next probe / `false` when exhausted; other non-2xx → `false` (stop); throw → `false` (stop).
  - [ ] 1.2.4 One shared `AbortSignal.timeout(VALIDATION_TIMEOUT_MS)` for the whole chain (5s total budget, not per-probe).
  - [ ] 1.2.5 `logger.warn` on inconclusive linkedin outcomes only (transport/unexpected status) — `{fn, provider, status}` — never the token; no `reportSilentFallback`; other providers untouched.
- [ ] 1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/token-validators.test.ts` — GREEN (NOT `bun test`; bunfig blocks discovery). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 2 — Closeout wiring

- [ ] 2.1 PR body: `Closes #9188`. Do not touch the cron (`cron-linkedin-token-check.ts`), `bootstrap.sh`, or `providers.ts` — sibling #9183 covered them.
- [ ] 2.2 Grep sweep: `organizationalEntityAcls` appears in `token-validators.ts` exactly once (the fallback entry); no stray `userinfo` single-probe remnants for linkedin.

## Testing

- [ ] T1 Scoped vitest run for `token-validators.test.ts` green — including per-URL mocks and order/callCount assertions (a verdict-only suite is insufficient).
- [ ] T2 `./node_modules/.bin/tsc --noEmit` clean in `apps/web-platform`.
- [ ] T3 Confirm `app/api/services/route.ts` needs no diff — `validateToken` signature and boolean contract unchanged.
