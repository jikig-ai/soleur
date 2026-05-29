---
title: "Signature-authed internal routes need PUBLIC_PATHS + the app.* host, not the apex"
date: 2026-05-29
category: integration-issues
module: web-platform/middleware, infra
tags: [middleware, public-paths, hmac, cron, cloudflare, host, kb-drift, "4017"]
---

# Learning: signature-authed routes must bypass the session redirect AND target the app host

## Problem

The nightly **KB-drift walker** GitHub Actions cron failed every run (405 from the
ingest POST). Two independent bugs, both invisible to unit tests and CI:

1. **Wrong host.** `KB_DRIFT_INGEST_URL` pointed at the apex `https://soleur.ai/...`.
   The apex is the **Cloudflare-fronted static marketing site** and returns
   `405 Not Allowed` for any POST — the request never reaches the Next.js app.
   The app lives at `app.soleur.ai` (the canonical host for every `/api/*` route).
2. **Middleware session gate.** The HMAC-authed route `/api/internal/kb-drift-ingest`
   was not in `PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts`). The Supabase auth
   middleware 307-redirects any unauthenticated (no session cookie) request to
   `/login` before the route's own HMAC gate runs — so even after fixing the host,
   the POST got a 307, still failing the workflow's `2xx` assertion.

## Solution

- Added the **narrow exact path** `/api/internal/kb-drift-ingest` to `PUBLIC_PATHS`
  (NOT the broad `/api/internal` prefix — the matcher `pathname === p ||
  pathname.startsWith(p + "/")` would session-bypass every future internal route).
- Corrected the Terraform default host in `apps/web-platform/infra/kb-drift.tf`
  apex → `app.soleur.ai` (kept `lifecycle { ignore_changes = [value] }`; the live
  Doppler value was corrected out of band).
- The route's HMAC-SHA256 gate stays the sole, load-bearing auth — removing the
  redirect does not weaken it; bad/absent signature still 401s before any DB write.

## Key Insight

This is the **exact recurrence of #4017** (`/api/inngest`): a route authenticated by
a request signature carries no session cookie, so Supabase middleware bounces it to
`/login` before its own gate runs. **Any new signature/HMAC-authed route (webhooks,
SDK callbacks, cron ingest) must be added to `PUBLIC_PATHS`** — and must target the
`app.*` host, never the apex (which is the static CF marketing site that 405s POST).

A clean diagnostic tell: an **nginx/Cloudflare-styled** `405 Not Allowed` HTML page
(vs. a Next.js/JSON 405) means the request never reached the app — suspect the host,
not the route handler.

## Session Errors

1. **`doppler secrets set` blocked by hook** — the CLI echoes all remaining secrets to stdout. Recovery: re-ran with `> /dev/null` and verified via a separate `doppler secrets get`. Prevention: already hook-enforced (`BLOCKED: doppler secrets set without > /dev/null`); the deny fired correctly.
2. **Parallel Bash calls failed with `cd: apps/web-platform: No such file or directory`** — relied on shell CWD persisting from a prior `cd`. Recovery: used absolute `cd <worktree-abs>/apps/web-platform` in each call. Prevention: already documented in the work skill ("Bash tool does NOT persist CWD across calls").
3. **Transient write-hook block on the IaC-routing gate** (plan phase, forwarded via session-state.md) — resolved by adding the `iac-routing-ack` comment after confirming no manual provisioning was prescribed. Prevention: existing gate working as intended.
