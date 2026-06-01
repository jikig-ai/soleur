# Learning: a new non-browser API route is unreachable in prod unless added to PUBLIC_PATHS — unit tests don't catch it

## Problem

PR #4735 (#4734) added `POST /api/internal/trigger-cron`, a secret-authenticated
internal route (Bearer `INNGEST_MANUAL_TRIGGER_SECRET`, length-guarded
`timingSafeEqual`). All 10 route unit tests passed, tsc was clean, and the full
sharded webplat suite was green. But the route was **unreachable in production**:
`apps/web-platform/middleware.ts` runs Supabase auth on every non-public path and
`if (!user) return redirectWithCookies("/login")`. A cookie-less Bearer caller
(the operator/agent, or the plan's own AC4 post-merge `curl`) gets a `307 → /login`
and the route's auth gate never runs — it would return a redirect, not 202.

The plan's `## Files to Create` / `## Files to Edit` never listed
`apps/web-platform/lib/routes.ts` (the `PUBLIC_PATHS` source of truth), and the
route unit tests call `POST(request)` **directly**, bypassing middleware entirely —
so neither the plan, the implementation, nor the unit suite surfaced the defect.
It was caught by `user-impact-reviewer` at the review phase, which reasoned about
the prod request path rather than the unit-test path.

This is a recurring class: `#4017` (`/api/inngest` missed all scheduled fires),
`#4587` (`/robots.txt` 307→/login), and the `kb-drift-ingest` route all hit the
same trap and all carry an explicit `PUBLIC_PATHS` entry as the fix.

## Solution

Add the exact route path to `PUBLIC_PATHS` in `apps/web-platform/lib/routes.ts`
with a NARROW exact-match entry (never broaden to `/api/internal`), plus a
`middleware.test.ts` assertion `expect(isPublicPath("<path>")).toBe(true)` and a
prefix-collision assertion that the bare parent + siblings stay private. The
route's own secret/HMAC gate is then the load-bearing auth — middleware just
stops shadowing it with a session redirect.

## Key Insight

**Any new `app/api/**` route that is authenticated by something OTHER than a
Supabase session cookie (shared secret, HMAC, SDK signature) MUST be registered
in `PUBLIC_PATHS` in the same PR.** The signal is "called by a non-browser client"
(cron, webhook, operator/agent curl, SDK). Route unit tests that import and call
the handler directly CANNOT catch this — they never traverse middleware. The
only pre-merge gates that catch it are (a) a `middleware.test.ts` membership
assertion, and (b) a reviewer who reasons about the prod request path. Plan-phase
defense: when a plan creates an `app/api/**` route reachable by a non-browser
caller, `routes.ts` belongs in `## Files to Edit`.

## Session Errors

1. **Plan-deepen subagent: bare-root write guard blocked one write** — CWD-relative
   path resolved to the synced mirror. Recovery: wrote to the absolute worktree path.
   Prevention: already covered by the one-shot plan subagent's CWD-verification first step.
2. **Review classification `set -uo pipefail` tripped on the shell snapshot**
   (`ZSH_VERSION: unbound variable`, exit 127) — the `-u` flag aborted while the
   harness sourced the bash shell-snapshot (which references unbound vars), and the
   `has_source` grep returned a false "none". Recovery: classified the change manually
   from the file list (clearly code-class). Prevention: in this harness, run the
   review classification predicates WITHOUT `set -u` (the skill's own
   `set -uo pipefail` is incompatible with the sourced shell snapshot); `set -o pipefail`
   alone is sufficient.
3. **CSRF coverage drift-guard failed on the new route** — `lib/auth/csrf-coverage.test.ts`
   requires every state-mutating route to use `validateOrigin` or be exempt. Working
   as designed. Recovery: added the route to `EXEMPT_ROUTES` (secret-auth, no cookies,
   same class as kb-drift-ingest). Prevention: expected — a new POST route always trips
   this gate; decide CSRF posture (origin-validate vs secret-auth-exempt) at plan time.
4. **Pre-existing signature-verify env-leak flakes in the unsharded local full-run** —
   `signature-verify*.test.ts` mutate `process.env.INNGEST_DEV`/`INNGEST_SIGNING_KEY`
   at module top-level; co-location in an unsharded run leaks across the forks pool.
   Recovery: confirmed green via the sharded (CI-equivalent) run + isolation. Prevention:
   run the full-suite exit gate the way CI runs it (`--shard=K/N`); an unsharded local
   full-run surfaces latent co-location env-leaks that CI's shard split hides.
5. **P1 (route unreachable) caught at review, not work** — see Problem/Key Insight above.
   Prevention: route-to-definition below.

## Tags
category: integration-issues
module: web-platform/middleware
related: 2026-05-19 #4017 (/api/inngest), #4587 (/robots.txt), kb-drift-ingest
