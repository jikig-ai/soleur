---
date: 2026-06-08
type: feat
feature: shared-doc-waitlist-inline
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-shared-doc-waitlist-inline
pr: 5035
issue: 5037
brainstorm: knowledge-base/project/brainstorms/2026-06-08-shared-doc-waitlist-inline-brainstorm.md
spec: knowledge-base/project/specs/feat-shared-doc-waitlist-inline/spec.md
wireframes: knowledge-base/product/design/shared-document/cta-banner-waitlist.pen
---

# ✨ feat(shared): inline waitlist email capture on the shared-document banner

## Overview

The shared-document CTA banner (`apps/web-platform/components/shared/cta-banner.tsx:31`)
says "Sign up for the waitlist" but links to `<Link href="/signup">`, opening the
account-creation page instead of joining a waitlist. Replace the link with an
**inline email-capture form** that POSTs to a new **same-origin Next.js route handler**
(`app/api/waitlist/route.ts`) which proxies to Buttondown's public embed-subscribe
endpoint (`tag=pricing-waitlist`). On success the form is replaced by an inline
"You're on the list ✓" confirmation. Banner is rearranged: two-tier on desktop,
stacked on mobile.

**Why a server proxy (not a direct client POST):** prod CSP `connect-src`
(`lib/csp.ts:99`) excludes `buttondown.com`, and `form-action 'self'`
(`lib/csp.ts:32-45`) would also block a native cross-origin `<form action>`. A
client `fetch()` to a same-origin route needs **no CSP change** and lets the
honeypot + rate-limit be enforced server-side (a client-only honeypot in a
hydrated React component is bypassable).

**Effort:** small (hours). No DB, no migration, no new infra/secret, no ADR.

## Premise Validation (Phase 0.6)

- `cta-banner.tsx:31` → `href="/signup"` — **confirmed** (the bug).
- `lib/csp.ts:99` `connect-src` excludes `buttondown.com` — **confirmed**.
- Issue #5037 open, draft PR #5035 open — **confirmed**.
- Wireframes `cta-banner-waitlist.pen` exist on disk — **confirmed**.
- No stale premises.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "reuse Buttondown … no backend route needed" (docs-site pattern) | Docs-site form is vanilla JS + native `<form action>`; web-platform CSP `form-action 'self'` blocks that. Not importable React. | Re-implement as React client component + same-origin proxy route. |
| Open Q: rate-limit helper availability | **Exists**: `SlidingWindowCounter` (`server/rate-limiter.ts`), pattern at `app/api/analytics/track/throttle.ts`. | Reuse; singleton in sibling `waitlist.ts`. |
| Open Q: canonical Privacy Policy URL | web-platform has no public privacy page; convention is absolute marketing URL. | Link `https://soleur.ai/pages/legal/privacy-policy.html` (per `signup/page.tsx:146`). |
| Open Q: Plausible parity | No Plausible wired in web-platform. | Drop the analytics event for v1 (recorded; no follow-up needed). |
| Buttondown username source | `"soleur"` at `plugins/soleur/docs/_data/site.json:13`; web-platform has none (the existing `BUTTONDOWN_API_KEY` is the unrelated social-accounts feature). | Hardcoded module constant `const WAITLIST_USERNAME = "soleur"` (public handle, already public in `site.json`, no env var — YAGNI per plan-review). |
| (not in spec) CSRF protection | `csrf-coverage.test.ts` negative-space gate **fails CI** for any new POST route not calling `validateOrigin`/`rejectCsrf` or in `EXEMPT_ROUTES`. | New scope: route calls `validateOrigin`/`rejectCsrf`. |
| (not in spec) route.ts export rule | `cq-nextjs-route-files-http-only-exports` — `next build` fails if route.ts exports non-handlers. | New scope: throttle singleton, Buttondown client, honeypot constant in sibling modules. |

## User-Brand Impact

**If this lands broken, the user experiences:** an anonymous visitor on a shared
document submits their email and either nothing happens (silent failure) or they
are again bounced to account creation — the exact bug, unfixed, at a high-value
first brand contact.

**If this leaks, the user's data is exposed via:** the visitor's email (personal
data) is forwarded to a third party (Buttondown, SCCs Module 2 — not DPF). Risk
vectors: mis-tagging, capture without a visible privacy notice/consent, or a raw
upstream error body surfaced to the client.

**Brand-survival threshold:** single-user incident. One mishandled email, or one
misleading-context capture, is a brand-survival event on this public surface.
`requires_cpo_signoff: true` (CPO reviewed at brainstorm). `user-impact-reviewer`
runs at PR review.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `cta-banner.tsx` no longer links to signup: `grep -nE 'signup|next/link'
  apps/web-platform/components/shared/cta-banner.tsx` returns nothing (the word
  "signup" and the `next/link` import are both gone — catches `href={...}`
  template-literal forms a `href="/signup"`-only grep would miss).
- [ ] **AC2** New `app/api/waitlist/route.ts` exports **only** HTTP handlers (`POST`).
  The throttle singleton, Buttondown client, honeypot + username + tag constants
  live in one sibling module `waitlist.ts` (`cq-nextjs-route-files-http-only-exports`).
  `next build` passes.
- [ ] **AC3** Route calls `validateOrigin` and rejects when `!valid || !origin`
  (null-origin rejected — browser-only form); `csrf-coverage.test.ts` passes
  (route covered, not added to `EXEMPT_ROUTES`).
- [ ] **AC4** Route POSTs `email`, `tag=pricing-waitlist`, `embed=1` as
  `application/x-www-form-urlencoded` to
  `https://buttondown.com/api/emails/embed-subscribe/${WAITLIST_USERNAME}` server-side.
- [ ] **AC5** Honeypot input `name="url"` (`autocomplete="off" tabindex="-1" aria-hidden`);
  enforced server-side — a filled honeypot returns `200 {ok:true}` WITHOUT forwarding
  (silent drop; a 400 would teach a bot which field is the trap).
- [ ] **AC6** Per-IP rate limit via `SlidingWindowCounter` (`MAX_PER_WINDOW = 5`,
  `windowMs = 60_000`, hardcoded constants); over-limit returns `429
  {error:"rate_limited"}` + `Retry-After`; `logRateLimitRejection` called.
- [ ] **AC7** Response contract (single `{error:"snake_case"}` shape for all errors):
  `200 {ok:true}` on success / already-subscribed / honeypot-drop **(explicitly 200+JSON,
  NOT the template's 204 — client needs a parseable body)**; `400 {error:"invalid_json"}`
  / `{error:"invalid_email"}`; `403 {error:"Forbidden"}` (CSRF / null-origin);
  `429 {error:"rate_limited"}`; `502 {error:"upstream_unavailable"}` on unexpected
  Buttondown failure. Raw Buttondown error bodies are never returned to the client.
  Unexpected Buttondown failure (network throw / 5xx) is mirrored to Sentry via
  `warnSilentFallback` (`feature: "waitlist-subscribe"`); expected errors
  (CSRF / rate-limit / 400 / already-subscribed) are NOT mirrored.
- [ ] **AC8** Banner client component implements `idle → submitting → success | error`:
  submit disabled in-flight with a visible affordance (button "Joining…", not a bare
  disabled button) **(P1-5)**; native `type="email"` + `required` in the markup;
  success replaces the form with **"You're on the list ✓ — check your inbox to
  confirm."** (double opt-in is honest only if the user is told to confirm) **(P0-2)**;
  the aria-live `role="status"` region is **rendered (empty) in idle** and text
  swapped in on error **(P1-4)**.
- [ ] **AC9** **Client failure handling (P0-3):** any `fetch` rejection (offline /
  DNS / abort) OR non-2xx routes to `error` with the **form re-enabled** (never a
  permanent disabled `submitting` freeze) and the email retained in the field;
  error copy is the generic "Something went wrong. Please try again." (429 uses
  this same generic path — no bespoke copy).
- [ ] **AC10** Visible privacy line ("No spam. We email you once when early access
  opens.") + Privacy Policy link (`https://soleur.ai/pages/legal/privacy-policy.html`,
  the web-platform convention) present in the idle banner — **one string for BOTH
  desktop and mobile** (drop the mobile short variant in the `.pen`) **(P2-9)**.
  Not behind hover/tooltip.
- [ ] **AC11** Two-tier desktop + stacked mobile layouts match the wireframes
  (`cta-banner-waitlist.pen` frames 01/03), input comfortably wide (per wireframe).
  On mobile, focusing the input keeps the Join button reachable above the soft
  keyboard (`fixed bottom-0`) — verify in QA scenario 9 **(P1-7)**.
- [ ] **AC12** Dismiss preserved: `data-testid="cta-banner-dismiss"`,
  `aria-label="Dismiss signup banner"`, `STORAGE_KEY="soleur:shared:cta-dismissed"`
  via `safeSession`. Existing `shared-cta-banner-close.test.tsx` still passes.
- [ ] **AC13** Route test (`test/api-waitlist-subscribe.test.ts`, node project)
  covers: success, invalid email, honeypot drop, rate-limit 429, CSRF 403
  (incl. null-origin), Buttondown-5xx → 502 + `warnSilentFallback` mirror (spy),
  already-subscribed → 200.
- [ ] **AC14** Component test (`test/shared-cta-banner-waitlist.test.tsx`, component
  project) using the manual-trigger timing pattern
  (`2026-04-12-testing-transient-react-state-in-async-flows.md`); asserts the
  server-driven paths (not native validation): aria-live region exists in idle
  (empty); a `fetch` rejection → error + re-enabled form; success shows the
  confirm-inbox copy; privacy link present.
- [ ] **AC15** **(GDPR gate)** `article-30-register.md` PA6 updated: purpose (b)
  includes early-access/waitlist notification; collection surfaces list the
  shared-document banner alongside the pricing page. No new Vendor-DPA row
  (Buttondown already registered, `:429`).

### Post-merge (operator)

- [ ] **AC16** Discoverability probe (NO ssh), run once post-merge by hand:
  `curl -sS -X POST https://app.soleur.ai/api/waitlist -H 'Content-Type: application/json' -H 'Origin: https://app.soleur.ai' -d '{}' -i`
  → `400 {"error":"invalid_email"}` (route wired; no Buttondown write). Note: the
  app host is `app.soleur.ai` (= `PRODUCTION_ORIGINS`); `soleur.ai` is the
  separate marketing host where the Privacy Policy lives.

_(`tsc`/`vitest` green is definition-of-done, not a separate AC — exact commands in Sharp Edges.)_

## Files to Create

- `apps/web-platform/app/api/waitlist/route.ts` — POST handler, HTTP exports only.
  Order (modeled on `app/api/analytics/track/route.ts`, but note divergences below):
  `validateOrigin`→reject when **`!valid || !origin`** (null-origin rejected — this is
  a browser-only form; clones the template's `!origin` guard); IP rate-limit→429
  `{error:"rate_limited"}`+`Retry-After`; `req.json()` in try/catch→400
  `{error:"invalid_json"}`; email validate→400 `{error:"invalid_email"}`; honeypot
  filled→silent `200 {ok:true}` (no forward); `subscribeToWaitlist()`→`200 {ok:true}`
  on ok (success **or** already-subscribed) / `502 {error:"upstream_unavailable"}` on
  unexpected failure. Omit `GET` (Next.js returns 405 by default; add an explicit
  stub only if a JSON 405 body is wanted). **Success is `200 {ok:true}`, NOT the
  template's `204`** — the client needs a parseable body to drive the state machine.
- `apps/web-platform/app/api/waitlist/waitlist.ts` — single sibling helper (collapsed
  per plan-review): `WAITLIST_USERNAME = "soleur"` const, `WAITLIST_TAG = "pricing-waitlist"`
  const, `HONEYPOT_FIELD = "url"` const, the `SlidingWindowCounter` singleton
  (`MAX_PER_WINDOW = 5`, `windowMs = 60_000`) + `startPruneInterval` + `__resetForTest`,
  and `subscribeToWaitlist(email): Promise<{ok:true} | {ok:false}>` posting
  `email`,`tag`,`embed=1` urlencoded to `…/embed-subscribe/${WAITLIST_USERNAME}`,
  mapping "already subscribed" → `{ok:true}`, logging raw error server-side.
- `apps/web-platform/test/api-waitlist-subscribe.test.ts` — route test (AC13).
- `apps/web-platform/test/shared-cta-banner-waitlist.test.tsx` — component test (AC14).

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx` — replace the `<Link>`
  (lines 30-35) with the inline form + state machine + privacy line; keep the
  dismiss button, test id, aria-label, `safeSession` logic, and container classes;
  re-layout to two-tier (desktop) / stacked (mobile) per wireframes. Honeypot input
  `name="url"` with `autocomplete="off" tabindex="-1" aria-hidden` (matches docs-site
  precedent; avoids tripping a real user's password-manager/email autofill, which
  would silently drop a real signup). Reuse tokens: `bg-soleur-accent-gold-fill`,
  `text-soleur-text-on-accent`, `text-soleur-text-secondary`, `text-soleur-text-muted`,
  `border-soleur-border-default`, `rounded-lg`.
- `knowledge-base/legal/article-30-register.md` — **(GDPR gate fold-in)** update
  Processing Activity 6 (Newsletter Subscription, line 120): broaden purpose (b)
  to include early-access/waitlist notification, and add the shared-document
  banner alongside the pricing page as a collection surface for the
  `pricing-waitlist` tag. Buttondown Vendor-DPA row (`:429`, SCCs M2) already
  covers the transfer — no new vendor row. Keeps Art. 5(1)(b) consent scoping
  honest; cheap doc edit at single-user-incident threshold.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried against the planned
file list — no open scope-outs touch `cta-banner.tsx` or `app/api/waitlist/*`.)

## Infrastructure (IaC)

None. The proxy uses a **hardcoded public constant** (`WAITLIST_USERNAME = "soleur"`,
already public in `site.json`); the Buttondown embed endpoint requires no API key.
No env var, server, secret, DNS, cron, or vendor account is introduced — Phase 2.8
IaC gate does not fire.

## Observability

```yaml
liveness_signal:
  what: POST /api/waitlist returns 2xx; request-scoped route, health implied by existing web-platform uptime monitor (no new background job → no new probe)
  cadence: on-demand (per visitor submit)
  alert_target: existing app uptime / Sentry
  configured_in: infra/sentry (existing) — no new monitor
error_reporting:
  destination: Sentry via warnSilentFallback / reportSilentFallback (server/observability.ts)
  fail_loud: unexpected Buttondown network-throw or 5xx mirrored to Sentry (feature="waitlist-subscribe"); expected errors (CSRF 403, rate-limit 429, invalid_email 400, already-subscribed) NOT mirrored per observability.ts docblock
failure_modes:
  - mode: Buttondown unreachable/5xx; detection: catch + warnSilentFallback; alert_route: Sentry
  - mode: rate-limit abuse; detection: SlidingWindowCounter 429 + logRateLimitRejection; alert_route: pino warn + Sentry breadcrumb
  - mode: invalid origin / CSRF; detection: validateOrigin → rejectCsrf 403; alert_route: pino (expected, no Sentry)
logs:
  where: pino structured logs (existing web-platform logger); Sentry for unexpected failures
  retention: existing platform retention (Sentry / Better Stack defaults)
discoverability_test:
  command: "curl -sS -X POST https://app.soleur.ai/api/waitlist -H 'Content-Type: application/json' -H 'Origin: https://app.soleur.ai' -d '{}' -i"
  expected_output: "HTTP/2 400 with body {\"error\":\"invalid_email\"} — route wired, no Buttondown write (app host is app.soleur.ai, = PRODUCTION_ORIGINS)"
```

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + Phase 1 research).
**Assessment:** Same-origin proxy is dictated by CSP, not preference. Re-implement
docs-site pattern as React client component + sibling-module route. New scope from
research: CSRF gate (csrf-coverage.test.ts), HTTP-only route exports, friendly
error mapping. Small effort, no ADR.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Visible privacy notice + Privacy Policy link mandatory; copy must
read as a product marketing waitlist (not document access). Buttondown double
opt-in = consent record (no checkbox). Buttondown transfers via SCCs Module 2
(not DPF) — relevant only if copy names the transfer mechanism (it does not).
Article 30 coverage check delegated to GDPR gate below.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override: `cta-banner.tsx` is a component).
**Decision:** reviewed.
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55 — `.pen` committed), spec-flow-analyzer (this phase), cpo (brainstorm carry-forward).
**Skipped specialists:** none.
**Pencil available:** yes (`cta-banner-waitlist.pen`, 5 frames, referenced in spec FR2-FR5 + AC11).

#### Findings

spec-flow-analyzer (single-user-incident lens) confirmed the happy / honeypot /
already-subscribed / CSRF / dismiss flows are complete and honest. Three
legitimate-human paths were left silent or dead-ended and are now folded into the
AC set:

- **P0-3 → AC9:** offline/`fetch` rejection could freeze the UI in `submitting`
  forever → route any rejection/non-2xx to `error` with the form re-enabled, email retained.
- **P0-2 → AC8 (partial):** wrong-email-after-success was a silent dead end (double
  opt-in means a typo never produces a confirmation). Resolved with the honest floor
  — **"check your inbox to confirm"** copy makes the typo diagnosable; the recovery
  path already exists via reload (success isn't persisted → banner returns to idle,
  P2-8). The heavier "Use a different email" affordance was **cut** at plan-review
  (DHH) as gold-plating the reload path already covers.
- **P0-1 → AC9 (folded to generic):** rate-limited real user behind the error path.
  Server-side 429 + `Retry-After` kept; the bespoke client copy was **cut** (DHH) —
  the generic error path is honest, and the shared-NAT-retry-loop is hypothetical on
  a new low-traffic banner. Email retained on error.
- **P1-4 → AC8:** persistent aria-live region in idle (assistive-tech announce).
- **P1-5 → AC8:** defined in-flight affordance ("Joining…").
- **P1-7 → AC11 + QA scenario 9:** mobile soft-keyboard occlusion of the `fixed bottom-0` bar.
- **P2-9 → AC10:** unify the desktop/mobile privacy string (drop unreviewed mobile variant).
- **P2-8 (known behavior, not an AC):** success state does not persist across reload
  (banner returns to idle; re-submit is a harmless already-subscribed→200) — this is
  also the wrong-email recovery path above. Revisit only if support friction appears.

## GDPR / Compliance Gate (Phase 2.7)

Advisory; not legal review. Regulated surface = anonymous-visitor email PII →
Buttondown (US, SCCs Module 2).

- **No Critical (Art. 9) findings.** Email is not special-category; no DB table,
  no FK to `users`.
- **Chapter V (cross-border):** covered — Buttondown is in the Art. 30 register
  (PA6 recipient) + Vendor-DPA table (`:429`, SCCs M2). No new vendor row.
- **Art. 30 / Art. 6 (Important):** PA6 purpose is scoped to "periodic newsletter";
  the early-access waitlist purpose + the new shared-document collection surface
  are not reflected → folded into AC15 (PA6 doc edit in this PR).
- **Consent (Suggestion, satisfied):** affirmative submit + Buttondown double
  opt-in = valid Art. 6(1)(a) basis; no checkbox required. AC10 notice satisfies
  Art. 13/14.
- **DSAR (no new gap):** erasure/access via Buttondown, same as existing newsletter.

`user-impact-reviewer` runs at PR review (single-user-incident threshold).

## Test Scenarios

1. Happy path: valid email → 200 → "You're on the list ✓".
2. Already-subscribed email → 200 (treated as success, no error shown).
3. Invalid email → native validation blocks submit; server 400 if bypassed.
4. Honeypot filled (bot) → server silent-drop 200, no Buttondown call.
5. Rate-limit: N+1 rapid submits from one IP → 429.
6. Buttondown 5xx → client shows generic error; Sentry receives `warnSilentFallback`.
7. Dismiss still works; re-render after dismiss = null (session-storage).
8. Mobile breakpoint: stacked full-width input + button; privacy line present.
9. Mobile keyboard: focusing the email input keeps the Join button reachable
   above the soft keyboard on the fixed bottom bar (spec-flow P1-7).
10. Offline: with network disabled, Join → error state, form re-enabled (not a
    frozen `submitting`); re-enabling network + retry succeeds (spec-flow P0-3).
11. Wrong-email recovery: success shows "check your inbox to confirm"; reload →
    banner returns to idle (success not persisted) → re-enter correct email
    (spec-flow P0-2, resolved via reload not a bespoke affordance).
12. Honeypot autofill safety: a password-manager / browser autofill does not
    populate the hidden `name="url"` field (`autocomplete="off" tabindex="-1"`),
    so a real signup is never silently dropped (Kieran P1-3).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this one is filled (single-user incident).
- `route.ts` must export ONLY HTTP handlers (`cq-nextjs-route-files-http-only-exports`);
  `tsc`/vitest stay green but `next build` fails on a stray export. Sibling modules.
- New POST route MUST call `validateOrigin`/`rejectCsrf` or `csrf-coverage.test.ts`
  fails CI — easy to forget; it's not in the original spec. **Reject `!valid || !origin`**
  (not just `!valid`): `validateOrigin` returns `{valid:true, origin:null}` for
  no-Origin clients (`validate-origin.ts:62`), so a null-origin curl would otherwise
  sail past CSRF. A same-origin browser POST sends `Origin: https://app.soleur.ai`
  (the prod allowlist, `validate-origin.ts:9`) → passes.
- Honeypot field is `name="url"` with `autocomplete="off" tabindex="-1" aria-hidden`
  (docs-site precedent). Do NOT name it `email_confirm`/`website`-without-`autocomplete=off`
  — a real password-manager autofill into the honeypot silently drops a real signup
  (the single-user-incident brand event).
- Prod success contract is `200 {ok:true}`, NOT the template's `204` — the client
  parses the body. All errors share `{error:"snake_case"}` (success is the only
  `{ok:...}` shape).
- Never return raw Buttondown error bodies to the client; map + log raw server-side;
  "already subscribed" is success, not error.
- Component test `.tsx` MUST live under `test/` (vitest component project glob
  `test/**/*.test.tsx`) — a co-located `components/**/*.test.tsx` is silently never run.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w` (repo root has no `workspaces` field).
