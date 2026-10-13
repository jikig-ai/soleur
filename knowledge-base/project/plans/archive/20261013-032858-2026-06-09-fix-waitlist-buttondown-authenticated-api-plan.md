---
title: "Fix broken waitlist signup — migrate to Buttondown authenticated v1 API"
date: 2026-06-09
type: fix
branch: feat-one-shot-waitlist-buttondown-api
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
status: planned
---

# 🐛 Fix: Waitlist signup returns gateway 502 — migrate to Buttondown authenticated v1 API

## Enhancement Summary

**Deepened on:** 2026-06-09
**Sections enhanced:** Overview (verified-claims block), Implementation Phase 1/3, Risks
**Verification performed inline** (the deepen-plan parallel skill/learning/review subagents
require the Task tool, which is unavailable in this environment; the equivalent checks were
run directly):

### Key Improvements (all live-verified this pass)
1. **Buttondown v1 API contract confirmed from two independent sources** (Context7
   `/buttondown/docs` + WebFetch of docs.buttondown.com): `email_address` (required),
   `tags` (JSON array), `type: "regular"` BYPASSES double opt-in, `Authorization: Token`,
   201 success, 400 collision.
2. **Precedent-diff (Phase 4.4):** the `Authorization: Token ${token}` header AND
   `AbortSignal.timeout(VALIDATION_TIMEOUT_MS)` (5_000) pattern already exist verbatim at
   `token-validators.ts:59,74,3` for the buttondown provider. The plan mirrors the
   established codebase form exactly — no novel pattern.
3. **`AbortSignal.timeout` rejection shape confirmed:** `name: "TimeoutError"`,
   `msg: "The operation was aborted due to timeout"` (Node runtime, live `node -e` probe).
   The Phase 3 timeout-test mock is correct.
4. **Verify-the-negative pass — all negative claims confirmed, zero contradictions:**
   `BUTTONDOWN_API_KEY` has no `NEXT_PUBLIC_` form (server-only, never client-exposed);
   `WAITLIST_USERNAME` has no consumer outside the lines being removed (safe to delete);
   no env-validation framework exists (`envalid`/`createEnv`/`@t3-oss/env`/`env.ts` all
   absent) → confirms the "no boot-schema edit; runtime fail-closed guard" decision.

### New Considerations Discovered
- **Double opt-in is the highest-risk drift surface** (already a Sharp Edge): the v1 API
  silently activates the subscriber if `type: "regular"` is sent. The original feature
  (`2026-03-25-feat-waitlist-signup-form-plan.md`) and the live `cta-banner.tsx:102-103`
  copy ("check your inbox to confirm") both depend on the confirmation email. Omitting
  `type` is load-bearing — promoted to AC and test assertion.
- **The v1 duplicate-400 body differs from the embed body** (already a Sharp Edge): the
  `/already/i` heuristic must be re-derived against a real v1 collision response at /work
  time, not copied. Left as a /work-time read because no synthetic collision can be
  exercised without writing a real subscriber to prod.

## Overview

The waitlist banner (`CtaBanner`, rendered on the pricing page and shared docs) is
broken for every visitor: `POST /api/waitlist` with a valid email returns a
**Cloudflare-synthesized gateway 502** (`server: cloudflare`, `content-type: text/plain`,
body `error code: 502`), and the banner shows "Something went wrong. Please try again."

The root cause is upstream, not in our code: `subscribeToWaitlist`
(`apps/web-platform/app/api/waitlist/waitlist.ts:53`) proxies Buttondown's **keyless
public embed-subscribe endpoint** (`https://buttondown.com/api/emails/embed-subscribe/soleur`).
Buttondown has moved that public endpoint behind **Cloudflare Turnstile** — a direct
POST now returns HTTP 400 + an HTML "Verify Your Subscription" page that loads
`challenges.cloudflare.com/turnstile`, which a server-side proxy cannot solve. The
outbound request either gets the 400/challenge or hangs on egress until the origin
dies, which Cloudflare reports to the browser as a gateway 502.

**The fix:** rewrite `subscribeToWaitlist` to call Buttondown's **authenticated REST
API** (`POST https://api.buttondown.com/v1/subscribers`, `Authorization: Token
${BUTTONDOWN_API_KEY}`), which is **not** behind Turnstile. Add a request timeout so a
future upstream stall degrades to the app's own JSON 502 rather than a gateway hang.
Wire the already-registered `BUTTONDOWN_API_KEY` secret. Update the existing test.

This is a single-file behavioral fix to an already-built, already-broken route. No
client change, no route-handler change, no new infrastructure, no new vendor.

### Confirmed root cause (verified by direct prod + Buttondown probing, 2026-06-09)

- `GET /` healthy (307, 0.2s); `GET /api/waitlist` → 405; POST with bad origin → app's
  clean `{"error":"Forbidden"}` JSON. The route module loads and the handler runs.
- POST with a valid email → 502 with `server: cloudflare`, `cf-ray`,
  `content-type: text/plain`, body `error code: 502` — Cloudflare-synthesized, NOT the
  app's own `{"error":"upstream_unavailable"}` JSON. The request dies at the origin
  during the upstream call.
- Direct POST to `https://buttondown.com/api/emails/embed-subscribe/soleur` → HTTP 400 +
  HTML "Verify Your Subscription" page loading Cloudflare Turnstile.
- The error handler (`warnSilentFallback` wraps Sentry in try/catch) and the client
  (`cta-banner.tsx`) are both fine — no change needed there.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task framing) | Reality (verified this session) | Plan response |
| --- | --- | --- |
| `subscribeToWaitlist` proxies the keyless public embed endpoint | Confirmed: `waitlist.ts:31,60` POSTs `BUTTONDOWN_EMBED_URL` urlencoded, no auth header | Rewrite to authenticated v1 JSON API |
| `BUTTONDOWN_API_KEY` is a registered provider | Confirmed: `providers.ts:23` (`category: "social"`, `envVar: "BUTTONDOWN_API_KEY"`), validated `token-validators.ts:57-60` against `api.buttondown.com/v1` with `Authorization: Token ${token}` | Read `process.env.BUTTONDOWN_API_KEY` |
| Key is present in web-platform Doppler config | Confirmed live: `doppler secrets get BUTTONDOWN_API_KEY -p soleur -c prd --plain` → PRESENT | No provisioning step needed |
| `AbortSignal.timeout(...)` pattern exists to follow | Confirmed: `token-validators.ts:3,74` uses `AbortSignal.timeout(VALIDATION_TIMEOUT_MS)` (5_000) | Mirror the pattern with a `WAITLIST_TIMEOUT_MS` |
| web-platform validates env at boot | **False** — no `envalid`/`createEnv`/zod-env/`env.ts` exists; convention is plain `process.env.<VAR>` | No boot-schema edit; runtime fail-closed guard instead (see Phase 2) |
| `.env.example` exists at `apps/web-platform/.env.example` | Confirmed (9.9KB, `# --- Section ---` headers); has **no** `BUTTONDOWN_API_KEY` line | Add a `# --- Buttondown (waitlist) ---` section |
| Existing test mocks the embed endpoint | Confirmed: `api-waitlist-subscribe.test.ts:100` asserts `buttondown.com/api/emails/embed-subscribe/soleur` + urlencoded body | Rewrite mock to the v1 JSON endpoint |
| Already-subscribed handling: HTTP 400 + `/already/i` body | Current code at `waitlist.ts:70-72`. **v1 API duplicate semantics differ** — see Sharp Edges | Re-derive duplicate handling for v1 (see Phase 1) |

### Buttondown v1 API contract (verified 2026-06-09 via Context7 `/buttondown/docs` + WebFetch of docs.buttondown.com)

`POST https://api.buttondown.com/v1/subscribers`
- Header: `Authorization: Token ${BUTTONDOWN_API_KEY}` (verbatim — same form as `token-validators.ts:59`)
- Header: `Content-Type: application/json`
- Body (JSON): `email_address` (string, **required**), `tags` (array of strings, optional),
  `type` (string, optional — `"regular"` BYPASSES double opt-in), `metadata` (object, optional),
  `utm_source` / `utm_campaign` (optional).
- Success: **201** (created). Response carries `id`, `email_address`, `type`, `tags`, `creation_date`, `source`.
- Duplicate email: **400** (collision). Collision behavior is governed by the
  `X-Buttondown-Collision-Behavior` header (`overwrite` | `add`); default is to reject.
- The field is `email_address`, NOT `email`. Tags are a JSON array, NOT a urlencoded `tag` field.

## User-Brand Impact

**If this lands broken, the user experiences:** the waitlist banner on the pricing
page and every shared doc continues to show "Something went wrong. Please try again."
on submit — the single top-of-funnel conversion surface stays dead, and any visitor
who tries to join silently bounces.

**If this leaks, the user's data is exposed via:** the route forwards a visitor's email
address (PII) to Buttondown (US processor, SCCs Module 2 — see
`knowledge-base/project/learnings/2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`).
The only new exposure vector is the `BUTTONDOWN_API_KEY` itself: it must never be logged,
never be returned in a response body, and never reach the client. The existing handler
already logs status-only (never the raw Buttondown body); the rewrite preserves that.

**Brand-survival threshold:** aggregate pattern. (Marketing waitlist relay; a single
failed signup is a lost lead, not a brand-survival incident. No per-PR CPO sign-off.)

## Implementation Phases

### Phase 1 — Rewrite `subscribeToWaitlist` to the authenticated v1 API

File: `apps/web-platform/app/api/waitlist/waitlist.ts`

1. Replace the `BUTTONDOWN_EMBED_URL` constant with the authenticated endpoint:
   ```ts
   const BUTTONDOWN_SUBSCRIBE_URL = "https://api.buttondown.com/v1/subscribers";
   ```
   Keep `WAITLIST_TAG = "pricing-waitlist"` unchanged (same bucket). The
   `WAITLIST_USERNAME = "soleur"` constant becomes dead once the embed URL is gone —
   `git grep -n "WAITLIST_USERNAME" apps/web-platform` to confirm it has no other
   consumer, then remove it (and its comment) in the same commit per
   `cq-ref-removal-sweep-cleanup-closures`. (Verified this session: zero other consumers.)

2. Add a timeout constant mirroring `token-validators.ts:3`:
   ```ts
   const WAITLIST_TIMEOUT_MS = 5_000;
   ```

3. Read the key fail-closed at call time (NOT module load — a missing key must not crash
   the worker per the acceptance criterion; the route's try/catch maps a throw to a
   graceful JSON 502):
   ```ts
   const apiKey = process.env.BUTTONDOWN_API_KEY;
   if (!apiKey) {
     log.warn("BUTTONDOWN_API_KEY missing — waitlist subscribe disabled");
     throw new Error("waitlist subscribe unconfigured");
   }
   ```
   (Plain `process.env` is the codebase convention — no env wrapper exists. The throw is
   caught by `route.ts:72` → `warnSilentFallback` + `{error:"upstream_unavailable"}` 502.)

4. Issue the authenticated POST with a JSON body, the `Authorization: Token` header, and
   the abort timeout:
   ```ts
   const res = await fetch(BUTTONDOWN_SUBSCRIBE_URL, {
     method: "POST",
     headers: {
       Authorization: `Token ${apiKey}`,
       "content-type": "application/json",
     },
     body: JSON.stringify({ email_address: email, tags: [WAITLIST_TAG] }),
     signal: AbortSignal.timeout(WAITLIST_TIMEOUT_MS),
   });
   ```
   **Do NOT set `type: "regular"`.** Omitting `type` preserves Buttondown's default
   **double opt-in** — the visitor receives a confirmation email, which the existing
   success copy promises ("You're on the list ✓ — check your inbox to confirm.",
   `cta-banner.tsx:102-103`) and which is the documented GDPR Art. 6(1)(a) consent step
   (original plan `2026-03-25-feat-waitlist-signup-form-plan.md:273,293-295`). Setting
   `type: "regular"` would silently strip the confirmation email and the consent step.
   See Sharp Edges.

5. Map responses (mirror the current idempotent-success contract):
   - `res.ok` (200/201) → `return { ok: true }`.
   - `400` → read body (`.text().catch(() => "")`); treat duplicate/already-subscribed
     as **idempotent success** (`return { ok: true }`). **Re-derive the match** against
     the v1 body shape rather than copying `/already/i` blindly — the v1 collision 400
     body differs from the old embed body. Prefer a tolerant predicate that matches the
     v1 collision signal (e.g. `/already|subscrib|exists|duplicate/i`, OR parse the JSON
     and check for a collision `code`). Confirm the exact v1 400 body during /work by
     reading a real collision response (or the Context7 schema) before freezing the regex.
   - Any other status → `log.warn({ status }, "...")` and `throw` (route → 502). Status
     only ever reaches logs; never the raw body, never the key.

6. Update the function's doc comment to describe the authenticated v1 API.

#### Research Insights (Phase 1)

**Precedent-diff — the canonical form already exists in-repo** (`token-validators.ts`,
verified this pass):
```ts
// token-validators.ts:3,59,74 — the buttondown validator already does exactly this:
const VALIDATION_TIMEOUT_MS = 5_000;
headers: (token) => ({ Authorization: `Token ${token}` }),   // buttondown @ api.buttondown.com/v1
signal: AbortSignal.timeout(VALIDATION_TIMEOUT_MS),
```
The rewrite is a 1:1 mirror of this established pattern (header form, timeout primitive,
5s window) applied to the subscribe endpoint. No novel pattern; nothing for reviewers to
scrutinize on shape.

**AbortSignal.timeout rejection shape** (live `node -e` probe): rejects with a `DOMException`
whose `name === "TimeoutError"` and `message === "The operation was aborted due to timeout"`.
The Phase 3 timeout test mocks exactly this. The fetch throw is caught by `route.ts:72`.

**Edge case — fail-closed key read at call time, not module load.** Reading
`process.env.BUTTONDOWN_API_KEY` at module-evaluation time would make a missing key a
module-load crash (the worker dies), violating the "never crash the worker" requirement.
Reading inside `subscribeToWaitlist` lets the throw be caught by the route's try/catch →
graceful JSON 502. This matches `token-validators.ts` reading `token` per-call.

### Phase 2 — Wire the secret into `.env.example`

File: `apps/web-platform/.env.example`

Add a section (the file uses `# --- Section ---` headers; Buttondown is the only
`category: "social"` provider with a server-side consumer). Place it near the other
infrastructure/social secrets:
```
# --- Buttondown (waitlist) ---
# Authenticated REST API key for the marketing waitlist relay (/api/waitlist →
# api.buttondown.com/v1/subscribers). Token-format key from
# buttondown.com/settings/api. Without it, /api/waitlist fails closed to a graceful
# 502 (the worker never crashes). Present in Doppler soleur/prd.
BUTTONDOWN_API_KEY=
```

**No boot-time env-schema edit** — web-platform has no env-validation framework
(verified: no `envalid`/`createEnv`/zod-env/`env.ts`). The Phase 1 fail-closed guard is
the runtime validation. Document this decision in the PR body.

### Phase 3 — Update the test

File: `apps/web-platform/test/api-waitlist-subscribe.test.ts`

The test already stubs global `fetch` and mocks observability + logger. Rewrite the
upstream-shape assertions:

1. **Header comment** (lines 2-9): change "proxy to Buttondown's embed-subscribe" to the
   authenticated v1 API description.
2. **`valid email ... returns 200` test** (lines 90-105):
   - Mock `mockFetch.mockResolvedValue(new Response("", { status: 201 }))`.
   - Assert `String(url)` contains `api.buttondown.com/v1/subscribers`.
   - Assert the request `init` headers include `Authorization: Token <...>` and
     `content-type: application/json`.
   - Parse `init.body` as JSON; assert `email_address === "user@company.com"` and
     `tags` deep-equals `["pricing-waitlist"]`. Assert **no** `type` field is sent
     (double-opt-in preservation guard).
   - Set `process.env.BUTTONDOWN_API_KEY` in `beforeEach` and delete it in `afterEach`.
3. **already-subscribed test** (lines 107-118): mock the v1 collision 400 body shape
   (use the exact body the Phase 1 predicate matches); assert 200 `{ok:true}` and
   `warnSilentFallback` NOT called.
4. **unexpected-status test** (lines 198-210): keep the 503 → 502 + `warnSilentFallback`
   assertion (status mapping unchanged).
5. **NEW: timeout → 502 test.** `mockFetch.mockRejectedValue(Object.assign(new Error("The operation was aborted due to timeout"), { name: "TimeoutError" }))`
   (or `new DOMException("aborted", "TimeoutError")`); assert 502 + `warnSilentFallback`
   called once. (`AbortSignal.timeout` rejects the fetch with a `TimeoutError`; mocking
   the rejection is the deterministic way to exercise the path without a real timer.)
6. **NEW: missing-key → 502 test.** `delete process.env.BUTTONDOWN_API_KEY` before the
   call; assert 502 + `warnSilentFallback` called, and `mockFetch` NOT called (fail-closed
   before any upstream call).
7. The rate-limit, honeypot, origin, and invalid-email tests are unaffected — keep them
   (but ensure they don't depend on a real upstream call; the rate-limit test mocks a
   200, which should become a 201).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `subscribeToWaitlist` POSTs `https://api.buttondown.com/v1/subscribers` with header
      `Authorization: Token ${process.env.BUTTONDOWN_API_KEY}` and JSON body
      `{ email_address, tags: ["pricing-waitlist"] }` — verified by
      `git grep -n "api.buttondown.com/v1/subscribers" apps/web-platform/app/api/waitlist/waitlist.ts` returning 1.
- [ ] The body sends **no** `type` field (double opt-in preserved) — verified by a test
      assertion that the parsed request body has no `type` key.
- [ ] The fetch carries `signal: AbortSignal.timeout(WAITLIST_TIMEOUT_MS)` — verified by
      `git grep -n "AbortSignal.timeout" apps/web-platform/app/api/waitlist/waitlist.ts`.
- [ ] A missing `BUTTONDOWN_API_KEY` throws before any fetch (fail-closed) → route returns
      `{error:"upstream_unavailable"}` 502, worker does not crash — covered by the
      missing-key test.
- [ ] `apps/web-platform/.env.example` contains a `BUTTONDOWN_API_KEY=` line under a
      Buttondown section — verified by `grep -c "^BUTTONDOWN_API_KEY=" apps/web-platform/.env.example` returning 1.
- [ ] The old embed endpoint and `WAITLIST_USERNAME` are gone — verified by
      `git grep -n "embed-subscribe\|WAITLIST_USERNAME" apps/web-platform` returning 0.
- [ ] Test suite covers: success (201), already-subscribed idempotent (400) success,
      unexpected status → 502, timeout → 502, missing-key → 502.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.

### Post-merge (operator)

- [ ] After deploy, a valid email POST to prod `/api/waitlist` (via the banner or curl
      with a valid Origin + cf-connecting-ip) returns `200 {ok:true}` and the subscriber
      appears (status: unconfirmed, pending double opt-in) in Buttondown under the
      `pricing-waitlist` tag. Automation: Playwright MCP can drive the banner submit on
      the live pricing page to confirm the success state renders; Buttondown subscriber
      presence is confirmed via `GET api.buttondown.com/v1/subscribers?tag=pricing-waitlist`
      with the Doppler key (read-only). `Ref` the tracking issue; do not `Closes`-auto-close
      until prod is verified.

## Domain Review

**Domains relevant:** Legal/Compliance (email PII → US processor), Product (top-of-funnel
conversion surface), Engineering.

(Note: the plan skill's domain-leader subagents and Product/UX Gate specialists could not
be spawned in this environment — the Task tool is unavailable. The Product/UX Gate is
**NONE** by the mechanical UI-surface override: this plan's Files-to-Edit contains NO
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` — it only edits a server
helper, an env example, and a test. The client `cta-banner.tsx` is explicitly NOT changed.
A `.pen` wireframe already exists at
`knowledge-base/product/design/shared-document/cta-banner-waitlist.pen`; no new UI surface
is introduced.)

### Legal/Compliance

**Status:** reviewed (carry-forward from existing artifacts)
**Assessment:** Email is PII forwarded to Buttondown (US processor, SCCs Module 2 — see
learning `2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`). No new processor,
no new data type, no new purpose: this is the **same** Art. 6(1)(a) consent basis, the
**same** `pricing-waitlist` Art. 30 PA6 bucket, and the **same** double opt-in consent
step as the already-shipped waitlist. The fix changes only the transport (keyless embed →
authenticated REST), not the data flow, the lawful basis, or the consent mechanism. The
critical compliance guard is **preserving double opt-in** (Phase 1 step 4) — omitting
`type: "regular"`. Phase 2.7 GDPR gate fires (email PII → external API on a regulated
surface) but produces no new fold-in: the privacy posture is unchanged from the current
shipped state.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline) — no UI surface in Files-to-Edit; mechanical
override did not fire.

## Observability

```yaml
liveness_signal:
  what: "Buttondown subscriber count under the pricing-waitlist tag increments on real signups"
  cadence: "on-demand (low-volume marketing funnel; no scheduled probe warranted)"
  alert_target: "none (aggregate-pattern threshold; not a paged surface)"
  configured_in: "Buttondown dashboard / GET api.buttondown.com/v1/subscribers?tag=pricing-waitlist"
error_reporting:
  destination: "Sentry via warnSilentFallback({ feature: 'waitlist-subscribe', op: 'subscribe' }) at route.ts:76 (unchanged)"
  fail_loud: "warn-level (best-effort marketing forward; the route returns a graceful JSON 502, never a crash)"
failure_modes:
  - mode: "BUTTONDOWN_API_KEY missing/unset at runtime"
    detection: "log.warn 'BUTTONDOWN_API_KEY missing' + Sentry warn via route catch → JSON 502"
    alert_route: "Sentry (warn), surfaced as the app's {error:'upstream_unavailable'} 502 (NOT a gateway 502)"
  - mode: "Buttondown upstream non-ok status (e.g. 401 bad key, 5xx)"
    detection: "log.warn({ status }) in waitlist.ts + throw → route catch → Sentry warn"
    alert_route: "Sentry (warn)"
  - mode: "Buttondown upstream stall / hang"
    detection: "AbortSignal.timeout(5s) rejects → route catch → Sentry warn → JSON 502"
    alert_route: "Sentry (warn); the timeout converts a would-be gateway 502 into the app's JSON 502"
logs:
  where: "createChildLogger('waitlist-subscribe') — status-only, never the raw upstream body, never the key"
  retention: "platform log retention (unchanged)"
discoverability_test:
  command: "curl -sS -X POST https://app.soleur.ai/api/waitlist -H 'origin: https://app.soleur.ai' -H 'content-type: application/json' -d '{\"email\":\"probe@example.com\"}' -w '%{http_code}'"
  expected_output: "200 with body {\"ok\":true} (NOT 'error code: 502' text/plain from Cloudflare)"
```

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue references
`apps/web-platform/app/api/waitlist/waitlist.ts` or the waitlist test. Verified via the
two-stage `gh issue list --json` + standalone `jq --arg` pattern at plan time; the
GitHub query surfaced no matches against the planned file paths. If `gh` is offline at
/work time, re-run the check before finalizing.)

## Test Scenarios

| Scenario | Mock | Expected |
| --- | --- | --- |
| Valid email, key present | fetch → 201 | 200 `{ok:true}`; body `{email_address, tags:["pricing-waitlist"]}`, no `type`; `Authorization: Token` header |
| Already subscribed | fetch → 400 (v1 collision body) | 200 `{ok:true}`; `warnSilentFallback` NOT called |
| Bad key / unexpected status | fetch → 401/503 | 502 `{error:"upstream_unavailable"}`; `warnSilentFallback` once |
| Upstream timeout | fetch → reject `TimeoutError` | 502; `warnSilentFallback` once |
| Missing key | `delete process.env.BUTTONDOWN_API_KEY` | 502; `warnSilentFallback` once; fetch NOT called |
| Honeypot / bad origin / invalid email / rate limit | (unchanged) | unchanged (no upstream call) |

## Sharp Edges

- **Double opt-in must be preserved — do NOT send `type: "regular"`.** The v1 API defaults
  to double opt-in (visitor gets a confirmation email) ONLY when `type` is omitted; sending
  `type: "regular"` activates the subscriber immediately and skips the confirmation email.
  The existing success copy (`cta-banner.tsx:102-103`: "check your inbox to confirm") and
  the documented GDPR Art. 6(1)(a) consent step (original plan
  `2026-03-25-feat-waitlist-signup-form-plan.md:273,293-295,323`) both depend on the
  confirmation email being sent. Omitting `type` is load-bearing, not an oversight.
- **The v1 duplicate-400 body differs from the old embed body.** The current
  `/already/i.test(text)` heuristic was written against the embed endpoint's plaintext
  response. The v1 collision-400 body shape is different (JSON with a collision code, or
  a different message). Re-read a real v1 400 collision body (or the Context7 schema)
  during /work and widen the predicate accordingly — do NOT copy `/already/i` blindly, or
  a genuine duplicate could fall through to a 502.
- **The field is `email_address`, not `email`; tags are a JSON array, not a urlencoded
  `tag`.** The embed endpoint took `email`+`tag` urlencoded; the v1 API takes
  `email_address`+`tags:[...]` as JSON. Mixing the two shapes silently produces a 400.
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` has
  `[test] pathIgnorePatterns = ["**"]` — `bun test` discovers nothing. Use
  `./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts`. Typecheck is
  `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the repo root has no
  `workspaces` field, so `npm run -w` fails).
- **The test file path must match the vitest `node` project glob** (`test/**/*.test.ts`).
  The existing file already lives at `apps/web-platform/test/api-waitlist-subscribe.test.ts`
  — keep it there; do not co-locate.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled; threshold = aggregate pattern.)

## Infrastructure (IaC)

None. This plan introduces no new server, service, cron, vendor account, DNS record, TLS
cert, or firewall rule. `BUTTONDOWN_API_KEY` is an **already-provisioned** Doppler secret
(verified present in `soleur/prd`) and an already-registered provider (`providers.ts:23`)
— no new secret is created. The change edits only `apps/web-platform/app/`,
`apps/web-platform/.env.example`, and `apps/web-platform/test/`. Phase 2.8 gate skipped
(pure code change against an already-provisioned surface).

## Files to Edit

- `apps/web-platform/app/api/waitlist/waitlist.ts` — rewrite `subscribeToWaitlist` to the
  authenticated v1 API; add timeout; fail-closed key read; remove embed URL + `WAITLIST_USERNAME`.
- `apps/web-platform/.env.example` — add `# --- Buttondown (waitlist) ---` + `BUTTONDOWN_API_KEY=`.
- `apps/web-platform/test/api-waitlist-subscribe.test.ts` — re-mock to the v1 endpoint;
  add timeout + missing-key cases; assert no `type` field.

## Files to Create

None.
