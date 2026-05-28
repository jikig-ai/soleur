---
module: github-app
date: 2026-05-28
problem_type: runtime_error
component: auth
symptoms:
  - "GitHub installation token request failed: 401 (intermittent, ~30/day)"
  - "workspace-reconcile-on-push Inngest function fails on POST /api/inngest"
  - "Sentry issue 122537945 unresolved, 90 events over 14 days"
root_cause: jwt_exp_at_github_600s_maximum
severity: high
sentry_issue: 122537945
tags: [github-app, jwt, clock-skew, installation-token, retry-backoff, intermittent-401]
synced_to: []
---

# Learning: GitHub App JWT `exp` at the 600s ceiling causes intermittent installation-token 401s

## Problem

Sentry issue 122537945 (`Error: GitHub installation token request failed: 401`)
fired 90 events over 14 days, 100% from the `workspace-reconcile-on-push` Inngest
function minting an installation token for a **healthy** org installation (not
suspended, all scopes granted). The App-JWT → `POST /app/installations/{id}/access_tokens`
exchange itself was intermittently returning 401 — not a permission or suspension
problem.

The token path already had the standard mitigations and STILL 401'd:
- `createAppJwt()` backdated `iat: now - 60` (clock-skew guard) ✓
- `generateInstallationToken()` retried once on 401 with a 1s delay (added by PR
  #4498) ✓
- Inngest retried the whole run (`retries: 1`) ✓

## Root Cause

`createAppJwt()` set `exp: now + 10 * 60` — **exactly 600 seconds**, which is
GitHub's documented **maximum** App-JWT lifetime. GitHub validates `exp` against
*its own* clock. When the minting server's clock is even slightly **ahead** of
GitHub's (positive skew), GitHub sees `exp > now_github + 600` → "expiration time
too far in the future" → **401**. This is intermittent (only fires while the skew
is positive and near the boundary), which is exactly the observed ~30/day pattern.

The single 1s retry (PR #4498) was insufficient because (a) it re-minted a JWT
that hit the same boundary if the skew persisted, and (b) JWT-replication
transients sometimes outlast 1s. PR #4498 addressed the *retry* symptom but never
the `exp`-boundary *cause* — this incident is its unresolved tail.

## Solution

`apps/web-platform/server/github-app.ts`, two independent edits:

1. **Leave margin below the 600s ceiling.** `exp: now + 10 * 60` → `exp: now + 9 * 60`
   (540s). 60s of headroom absorbs positive server-clock skew. This mirrors the
   battle-tested octokit pattern: `universal-github-app-jwt` computes
   `exp = now - 30 + 60*10 = now + 570`. `iat: now - 60` is retained (more
   conservative than octokit's `now - 30`).

   ```ts
   const payload = {
     iss: getAppId(),
     iat: now - 60,
     exp: now + 9 * 60, // 540s — 60s below GitHub's 600s max
   };
   ```

2. **Widen the mint retry to exponential backoff.** Single 1s 401-retry → a
   bounded loop adopting the canonical in-repo idiom (`server/github-api.ts`):
   `INSTALL_TOKEN_MAX_RETRIES = 2`, `INSTALL_TOKEN_BASE_DELAY_MS = 1_000`, delay
   `* 2 ** attempt` (1s, 2s) → 3 total attempts. **401-only** predicate (any
   non-401 breaks immediately, preserving 403/5xx semantics); fresh JWT per
   attempt; body drained before each sleep (socket-leak guard).

## Key Insight

**A GitHub App JWT `exp` must NOT sit at the 600s maximum.** GitHub's `exp` ≤
10-minute rule is validated against GitHub's clock, so any positive skew on the
minting host turns `exp = now + 600` into an intermittent 401. Always leave
margin (`now + 540` or octokit's `now + 570`). Backdating `iat` guards the *past*
edge; capping `exp` below 600 guards the *future* edge — you need **both**.

Generalizable: when a vendor documents a MAX for a time-bounded credential,
setting the value to exactly the max is a latent intermittent-failure bug under
clock skew. Always subtract a skew budget.

## Scope note (verify the call graph before scoping out latency)

`generateInstallationToken` feeds two distinct App-JWT paths — confirm which one
you're touching:
- **Hand-rolled `createAppJwt()`** (github-app.ts) — git-auth, github-api, KB
  upload/sync, workspace reconcile, ~12 Inngest crons. **This was the bug.**
- **`@octokit/app` via `probe-octokit.ts`** (`universal-github-app-jwt`, `exp =
  now + 570`) — drift-guard, oauth-probe. **Already safe; out of scope.**

## Session Errors

- **Plan scoped out the added-backoff latency by asserting `generateInstallationToken`
  is "not on a hot user-interactive path (cron/reconcile)" — FALSE.** It is reached
  synchronously from `POST /api/kb/upload`, `POST /api/kb/sync`, and the agent
  `pushBranch` tool. Caught at PR review by `user-impact-reviewer`. Recovery:
  corrected the plan and justified the bounded latency (zero on happy path;
  per-installation `tokenCache` collapses a request's repeated mints to one;
  degraded-window retry converts failure→success). **Prevention: when a plan
  scopes out latency or blast-radius by claiming a shared function is "not
  interactive" / "cron-only," grep the call graph (`git grep <fn> apps/web-platform/app/api
  apps/web-platform/server/*tools*`) and enumerate every synchronous HTTP/agent
  caller before asserting it.**

## Cross-references

- `knowledge-base/project/learnings/bug-fixes/2026-05-26-inngest-github-installation-token-401-resilience-gap.md`
  (PR #4498 — added the single 401 retry; this fix is its unresolved tail).
- octokit precedent: `node_modules/universal-github-app-jwt/index.js` (`exp = now + 570`).
- Canonical backoff idiom: `apps/web-platform/server/github-api.ts:21-22,56-95`.
