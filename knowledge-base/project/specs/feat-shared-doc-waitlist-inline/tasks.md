---
feature: shared-doc-waitlist-inline
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-06-08-feat-shared-doc-waitlist-inline-capture-plan.md
spec: knowledge-base/project/specs/feat-shared-doc-waitlist-inline/spec.md
issue: 5037
pr: 5035
---

# Tasks: Inline waitlist email capture on the shared-document banner

Derived from the finalized (post-review) plan. TDD: write the failing test
before the implementation for each route/component task.

## Phase 0 — Preconditions

- [x] 0.1 Confirm template `app/api/analytics/track/{route,throttle}.ts` and
  helpers (`validateOrigin`/`rejectCsrf` `lib/auth/validate-origin.ts`,
  `SlidingWindowCounter` `server/rate-limiter.ts`, `warnSilentFallback`
  `server/observability.ts`) exist and signatures match the plan.
- [x] 0.2 Confirm `PRODUCTION_ORIGINS = {"https://app.soleur.ai"}` and that
  `validateOrigin` returns `{valid:true, origin:null}` for no-Origin clients
  (drives the `!valid || !origin` guard).

## Phase 1 — Server route (proxy to Buttondown)

- [x] 1.1 RED: `test/api-waitlist-subscribe.test.ts` (node project) — success,
  invalid email, honeypot drop, rate-limit 429, CSRF 403 (incl. null-origin),
  Buttondown-5xx → 502 + `warnSilentFallback` spy, already-subscribed → 200. (AC13)
- [x] 1.2 GREEN: `app/api/waitlist/waitlist.ts` — `WAITLIST_USERNAME="soleur"`,
  `WAITLIST_TAG="pricing-waitlist"`, `HONEYPOT_FIELD="url"`, `MAX_PER_WINDOW=5`
  / `windowMs=60_000` `SlidingWindowCounter` singleton + `startPruneInterval` +
  `__resetForTest`, `subscribeToWaitlist(email)` posting urlencoded
  `email`/`tag`/`embed=1` to `…/embed-subscribe/${WAITLIST_USERNAME}`, mapping
  "already subscribed" → `{ok:true}`, logging raw error server-side. (AC4, AC6)
- [x] 1.3 GREEN: `app/api/waitlist/route.ts` — HTTP-only exports; order:
  `validateOrigin` reject `!valid||!origin` → rate-limit 429 → `req.json()` 400 →
  email-validate 400 → honeypot silent-200 → `subscribeToWaitlist` → 200/502.
  Unexpected failure → `warnSilentFallback(feature:"waitlist-subscribe")`. (AC2, AC3, AC5, AC7)
- [x] 1.4 Verify `csrf-coverage.test.ts` passes; `next build` passes (HTTP-only export rule).

## Phase 2 — Banner component

- [x] 2.1 RED: `test/shared-cta-banner-waitlist.test.tsx` (component project),
  manual-trigger timing pattern — aria-live region present in idle; `fetch`
  rejection → error + re-enabled form; success shows confirm-inbox copy; privacy
  link present. (AC14)
- [x] 2.2 GREEN: rewrite `components/shared/cta-banner.tsx` — replace `<Link>` with
  inline form + `idle→submitting→success|error` state machine; "Joining…"
  affordance; honeypot `name="url"` (`autocomplete=off tabindex=-1 aria-hidden`);
  success "You're on the list ✓ — check your inbox to confirm."; persistent
  aria-live `role="status"`; fetch-rejection/non-2xx → error + re-enable + retain
  email; generic error copy (429 included). (AC1, AC8, AC9)
- [x] 2.3 GREEN: two-tier desktop / stacked mobile layout per wireframes; privacy
  line + PP link (`https://soleur.ai/pages/legal/privacy-policy.html`), one string
  both breakpoints; mobile keyboard keeps Join reachable. (AC10, AC11)
- [x] 2.4 Verify dismiss/session-storage preserved; `shared-cta-banner-close.test.tsx` passes. (AC12)

## Phase 3 — Legal register (GDPR gate fold-in)

- [x] 3.1 Update `knowledge-base/legal/article-30-register.md` PA6: broaden purpose
  (b) to include early-access/waitlist notification; list the shared-document
  banner as a collection surface alongside the pricing page. No new Vendor-DPA
  row (Buttondown already at `:429`). (AC15)

## Phase 4 — Verification

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` passes.
- [ ] 4.3 QA: scenarios 1–12 in the plan (happy/already-subscribed/honeypot/
  rate-limit/offline/mobile-keyboard/wrong-email-reload/honeypot-autofill).
  Unit-covered; browser scenarios (9 keyboard, 10 offline, 11 reload) deferred to
  the `/soleur:qa` step before ship.
- [ ] 4.4 Post-merge (operator, once): discoverability curl probe → 400 invalid_email. (AC16)
