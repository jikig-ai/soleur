---
title: "Next.js metadata route files all need PUBLIC_PATHS allowlist entries or auth middleware shadows them"
date: 2026-05-29
category: integration-issues
module: apps/web-platform/middleware
issue: 4587
pr: 4588
tags: [nextjs, middleware, auth, robots, metadata-routes, supabase, public-paths]
related:
  - 2026-03-29-pwa-manifest-auth-middleware-and-icon-purpose-types.md
---

# Learning: Next.js metadata route files need `PUBLIC_PATHS` allowlist entries

## Problem

`apps/web-platform/app/robots.ts` (added by #4573) returns `User-agent: *\nDisallow: /`
to keep the `app.soleur.ai` subdomain out of search indexes. A live probe showed it was
shadowed:

```
$ curl -sI https://app.soleur.ai/robots.txt
HTTP/2 307
location: /login
```

The Supabase auth middleware 307-redirected `/robots.txt` to `/login` **before** the
Next.js `robots.ts` route handler could run, because `/robots.txt` was absent from
`PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts`) — the allowlist consulted at
`middleware.ts:129`. Crawlers never received the `Disallow: /` body. The route file
existed and was correct; it was simply unreachable.

## Solution

Add the metadata route's served path to `PUBLIC_PATHS`, adjacent to the existing
`/manifest.webmanifest` entry (same class):

```ts
// apps/web-platform/lib/routes.ts
"/manifest.webmanifest",
"/robots.txt",   // Next.js robots.ts metadata route (Disallow: /). Public-by-design.
```

Use `PUBLIC_PATHS`, **not** the matcher-exclusion regex (`middleware.ts:351`): the
`PUBLIC_PATHS` branch still applies `withCspHeaders`, so CSP coverage is preserved
(matcher exclusion would drop it). Regression tests pin both arms: positive
(`isPublicPath("/robots.txt") === true`) and prefix-collision negative
(`isPublicPath("/robots.txtx") === false`, exercising the `startsWith(p + "/")` boundary).

## Key Insight

**This is the same middleware-shadow class as `/manifest.webmanifest`
([[2026-03-29-pwa-manifest-auth-middleware-and-icon-purpose-types]]) — the SECOND
instance.** Generalizable rule: **every Next.js metadata route file
(`app/robots.ts`, `app/manifest.ts`, `app/sitemap.ts`, future `app/*.ts` metadata
handlers) serves a public-by-design, cookieless, crawler-fetched path that the
Supabase auth middleware will 307→/login unless its served path is in `PUBLIC_PATHS`.**
When adding any such file, allowlist its path in the same PR. The matcher regex only
excludes `_next/*`, `favicon.ico`, `sw.js`, and image extensions — metadata routes
DO reach middleware. Allowlisting them does not widen the auth boundary (no auth, no
PII, no DB read) and is exact-match, so siblings like `/robots.txtx` stay protected.

## Session Errors

1. **Stale local `origin/main` ref produced a false scope-breach signal.** At the
   one-shot scope-verification step, `git diff origin/main...HEAD --name-only` listed
   files from an unrelated feature branch (`feat-one-shot-reconcile-cf-sentry-iac-apex-canonical`),
   momentarily resembling a planning-subagent scope breach. Root cause: the bare repo's
   local `origin/main` ref lagged the actual main HEAD (`a0bcbcfd`), so the three-dot
   merge-base was computed against stale state. **Recovery:** re-diffed against the
   verified HEAD commit SHA directly (`git diff a0bcbcfd..HEAD --name-only`), confirming
   the branch's only delta was the empty initialize commit. **Prevention:** verify
   one-shot scope against the worktree's actual base commit SHA (from
   `git log --oneline -1` on the freshly-created branch's parent) or run
   `git fetch origin main` before the three-dot diff — never trust a bare repo's local
   `origin/main` ref for scope checks without a fetch.

## Tags
category: integration-issues
module: apps/web-platform/middleware
