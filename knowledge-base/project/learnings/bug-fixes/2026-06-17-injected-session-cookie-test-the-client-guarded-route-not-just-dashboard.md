---
title: "Injected-session auth repro must exercise the client-guarded route, not a server-rendered one"
date: 2026-06-17
category: bug-fixes
module: live-verify
issue: 5485
tags: [supabase-ssr, playwright, cookie-injection, httpOnly, auth, live-verify, repro-methodology]
---

# Learning: an injected-session auth repro on a server-rendered route falsely clears a client-hydration auth bug

## Problem

The live-verify harness (`apps/web-platform/scripts/live-verify/run.ts`) mints a
synthetic Supabase session, injects the cookie into a headless browser via
Playwright `addCookies`, and drives the deployed app. Issue #5485 reported "the
injected cookie does not authenticate (lands on /login)". Two facts had to be
pinned by live repro before a fix.

First repro (WRONG conclusion): I injected the cookie and navigated to
`/dashboard`, observed an authenticated render for all cookie shapes (including
the harness's `httpOnly: true`), and concluded "auth works; httpOnly is a red
herring." That cleared the plan's primary suspect — incorrectly.

## Root cause

`/dashboard` is **server-rendered**: the Next.js middleware reads the auth cookie
**server-side**, where `httpOnly` is irrelevant (the server can always read the
cookie). So a server-rendered route authenticates even with an `httpOnly: true`
injected cookie.

The actual gate route, `/dashboard/chat/new`, is **client-guarded**: it hydrates
its session via the `@supabase/ssr` BROWSER client, which reads the auth-token
from `document.cookie` — a path `httpOnly` **blocks**. With `httpOnly: true`, the
browser client sees no session and the client-side guard races to `/login`
(~20% of runs, measured over 5 iterations). With `httpOnly: false` it was 5/5
clean. The deployed app's own `Set-Cookie` is server-set (and may be httpOnly),
but the harness must inject a **browser-readable** cookie because it has to
satisfy the client hydration path too.

## Solution

- Inject the cookie with `httpOnly: false` (matches the two proven-working
  references `bot-signin.ts` and `e2e/global-setup.ts`; both write non-httpOnly).
- Independently, the harness's bundled `@playwright/test` chromium could not
  launch on the runner (OS-unsupported) — added optional
  `LIVE_VERIFY_BROWSER_CHANNEL` / `LIVE_VERIFY_BROWSER_PATH` overrides
  (default byte-identical to bundled; fail-loud `CANT-RUN:browser-launch:<name>`).
- Fixed the `--dry-run` branch to assert the rail on `/dashboard/chat/new` (where
  it exists for the org-less synthetic principal), not `/dashboard` (rail-less
  onboarding command-center).

## Key Insight

**When reproing an injected-session auth bug, navigate to a CLIENT-GUARDED route
(one that hydrates via the browser SDK from `document.cookie`), never only a
server-rendered route.** A server-rendered route reads the cookie server-side and
authenticates even when the injected cookie is mis-shaped for the browser client
(`httpOnly: true`, wrong domain visibility, missing chunk) — so it silently
clears bugs that only manifest on the client path. The gate's true assertion
target is the strongest repro surface; pick it deliberately.

Corollary: `httpOnly: true` on a Playwright-injected Supabase session cookie
breaks `@supabase/ssr` browser-client hydration on client-guarded routes, even
though it transmits fine on HTTP navigations.

## Session Errors

1. **Server-route-only repro falsely cleared the httpOnly suspect.** Recovery:
   re-ran the repro against the actual client-guarded gate route
   (`/dashboard/chat/new`) and measured flakiness across 5 iterations.
   **Prevention:** this learning + a sharp-edge bullet routed to the
   browser-test skills; always repro injected-session auth on a client-guarded
   route.
2. **`bun` resolved `@supabase/ssr` from its global cache (0.12.0) instead of the
   project's pinned 0.6.1** when the repro script lived in `/tmp`. Recovery:
   moved the script inside `apps/web-platform/` so node_modules resolution wins.
   **Prevention:** run throwaway repro scripts that import project deps from
   inside the app package tree, never `/tmp`.
3. **`git commit -m` with embedded double-quotes broke shell word-splitting.**
   Recovery: `git commit -F -` heredoc. **Prevention:** already-documented
   pattern; use `-F -`/`--body-file` for any multi-line/quoted commit body.
4. **The Explore root-cause agent flip-flopped on an unconfirmed guess** (domain
   scoping). One-off — correctly not trusted; the binding live repro overrode it.
