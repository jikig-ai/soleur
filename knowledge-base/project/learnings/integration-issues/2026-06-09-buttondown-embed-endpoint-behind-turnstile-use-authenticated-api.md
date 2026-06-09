# Learning: Buttondown's public embed-subscribe endpoint moved behind Cloudflare Turnstile — proxy the authenticated API instead

## Problem

The waitlist banner (`CtaBanner`, pricing page + shared docs) showed "Something
went wrong. Please try again." on every email submit. `POST /api/waitlist`
returned a **502** in ~2–4s.

The 502 was a **Cloudflare-synthesized gateway 502** (`server: cloudflare`,
`cf-ray`, `content-type: text/plain`, body `error code: 502`), NOT the app's own
`{"error":"upstream_unavailable"}` JSON 502. That distinction localized the
fault to the origin failing to return a clean response during the upstream call,
not the route handler.

Root cause: `subscribeToWaitlist` (`apps/web-platform/app/api/waitlist/waitlist.ts`)
proxied Buttondown's **keyless public embed-subscribe endpoint**
(`https://buttondown.com/api/emails/embed-subscribe/<user>`). Buttondown moved
that public endpoint **behind Cloudflare Turnstile** — a direct server-side POST
now returns `400` + an HTML "Verify Your Subscription" page that loads
`challenges.cloudflare.com/turnstile`. A same-origin server-side proxy can never
solve a Turnstile challenge, so every submission failed (400/challenge, or an
egress stall that collapsed into the gateway 502).

## Solution

Rewrite `subscribeToWaitlist` to call Buttondown's **authenticated v1 REST API**
(`POST https://api.buttondown.com/v1/subscribers`, header
`Authorization: Token ${BUTTONDOWN_API_KEY}`, JSON body
`{ email_address, tags: [...] }`), which is **not** behind Turnstile. Supporting
changes:

- Add `AbortSignal.timeout(5_000)` so a future upstream stall degrades to the
  app's own JSON 502 instead of hanging the worker into a gateway 502 (mirrors
  the existing `token-validators.ts` buttondown validator pattern).
- Read `BUTTONDOWN_API_KEY` **fail-closed at call time** (throw inside the
  function → route try/catch → graceful JSON 502), never at module load — a
  missing key must not crash the worker at boot.
- **Omit `type: "regular"`** from the body to preserve Buttondown's default
  double opt-in (the confirmation email is the GDPR Art. 6(1)(a) consent step
  the success copy promises).
- Match the v1 duplicate signal on the machine code `email_already_exists` (and
  a narrow `/already (subscribed|exists)/i` detail/plaintext phrase) — NOT a
  broad `exists`/`subscrib`/`duplicate` token, which misclassifies genuine
  validation 400s as success and silently drops the signup.

## Key Insight

Two generalizable lessons:

1. **A server-side proxy of a vendor's *public embed/form* endpoint is fragile.**
   Public form endpoints are designed for a real browser and can sprout bot
   defenses (Turnstile/reCAPTCHA) at any time, silently breaking a server
   relay. When a vendor offers an authenticated REST API for the same action,
   proxy that instead — it is the supported server-to-server path and is not
   gated by browser challenges.

2. **A Cloudflare-synthesized 5xx (`server: cloudflare`, `cf-ray`, `text/plain`
   `error code: NNN`) is NOT the app's own error response.** When debugging a
   5xx behind Cloudflare, compare the captured body/headers against what the
   app's handler is coded to return. If the app returns JSON but you see CF's
   HTML/text error page, the origin never returned a clean response — the fault
   is at the origin/upstream layer, not in the handler's error branch. Probe the
   route's early-exit paths (bad origin → app JSON 403, etc.) to confirm the
   handler is reachable, then bisect to the specific upstream call.

## Session Errors

- **Task tool unavailable in the planning subagent's environment** (forwarded
  from session-state.md) — the deepen-plan research/review fan-out ran inline
  instead of via parallel subagents. One-off environment constraint; the inline
  verification (Context7 + WebFetch + live prod probes) covered the same ground.
  Prevention: none needed — graceful inline fallback already exists.
- **`curl -H origin:https://...` (unquoted) returned a spurious 403** during prod
  probing — the malformed Origin header failed `validateOrigin`. Recovery: use
  quoted `-H "origin: https://..."`. Prevention: always quote `curl -H` header
  args.
- **`git grep ... -- ':!*.md'` errored `fatal: unable to resolve revision`** —
  mixing a revision-less grep with a pathspec exclusion. Recovery: fell back to a
  plain `git grep <pattern> <path>` + post-filter. One-off.

## Tags
category: integration-issues
module: web-platform/api/waitlist
