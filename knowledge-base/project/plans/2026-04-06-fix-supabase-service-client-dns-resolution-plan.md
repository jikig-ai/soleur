---
title: "fix: use direct Supabase URL for server-side service client"
type: fix
date: 2026-04-06
issue: "#1679"
---

# fix: use direct Supabase URL for server-side service client

## Overview

The production Docker container cannot reach `https://api.soleur.ai` (Supabase custom domain) for server-side REST/admin API calls. This causes three cascading failures: `/health` reports `supabase: "error"`, `/api/repo/install` returns 403, and `/api/repo/create` returns 400. Client-side auth works because the browser resolves DNS directly. The server container has DNS resolution issues with the custom domain CNAME (`api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co`).

## Problem Statement

The `createServiceClient()` function and all server-side Supabase clients use `NEXT_PUBLIC_SUPABASE_URL` (`https://api.soleur.ai`) for both client and server contexts. This is a custom domain configured as a CNAME in Cloudflare DNS (non-proxied) pointing to the Supabase project URL (`ifsccnjhymdmidffkzhl.supabase.co`).

The Docker container running on Hetzner cannot resolve this CNAME, likely due to:

- Docker's default DNS resolver not handling the CNAME chain
- The Hetzner server's `/etc/resolv.conf` using a resolver that cannot follow the CNAME
- Network path differences between the container network and the host

The Supabase documentation confirms that the original project URL (`ifsccnjhymdmidffkzhl.supabase.co`) continues to work alongside the custom domain. Server-side code does not need the custom domain -- only client-side code benefits from branded URLs.

### Evidence

- `/health` returns `{"supabase":"error","sentry":"configured"}` -- the health check fetches `${NEXT_PUBLIC_SUPABASE_URL}/rest/v1/` and fails with a 2s timeout
- `/api/repo/install` returns 403 -- `auth.admin.getUserById()` returns no identities because the admin API call to `api.soleur.ai` fails silently
- `/api/repo/create` returns 400 -- `serviceClient.from("users").select()` fails, returning no data
- CLI admin API call with the same service role key against `ifsccnjhymdmidffkzhl.supabase.co` returns all 3 identities correctly

## Proposed Solution

Introduce a new environment variable `SUPABASE_URL` (server-side only, no `NEXT_PUBLIC_` prefix) that points to the direct Supabase project URL. Use this for all server-side Supabase clients. Fall back to `NEXT_PUBLIC_SUPABASE_URL` if `SUPABASE_URL` is not set (backward compatibility for local dev).

### Files to Modify

#### 1. `apps/web-platform/lib/supabase/server.ts`

- `createServiceClient()`: use `SUPABASE_URL` (falling back to `NEXT_PUBLIC_SUPABASE_URL`)

#### 2. `apps/web-platform/server/health.ts`

- `checkSupabase()`: use `SUPABASE_URL` (falling back to `NEXT_PUBLIC_SUPABASE_URL`) for the REST ping

#### 3. `apps/web-platform/server/ws-handler.ts`

- Module-level `createClient()` call at line 35-38: use `SUPABASE_URL`

#### 4. `apps/web-platform/server/agent-runner.ts`

- Module-level `createClient()` call at line 26-29: use `SUPABASE_URL`

#### 5. `apps/web-platform/server/api-messages.ts`

- Module-level `createClient()` call at line 4-7: use `SUPABASE_URL`

#### 6. `apps/web-platform/server/session-sync.ts`

- `getSupabase()` function at line 21: use `SUPABASE_URL`

#### 7. Doppler `prd` config

- Add `SUPABASE_URL=https://ifsccnjhymdmidffkzhl.supabase.co` to the `prd` config

### Implementation Pattern

Extract a helper to centralize the URL resolution:

```typescript
// apps/web-platform/lib/supabase/server.ts

/** Server-side Supabase URL: prefer direct project URL over custom domain. */
function serverUrl(): string {
  return process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL!;
}
```

Use `serverUrl()` in `createServiceClient()` and export it for use by other server modules (`health.ts`, `ws-handler.ts`, `agent-runner.ts`, `api-messages.ts`, `session-sync.ts`).

### What NOT to Change

- `NEXT_PUBLIC_SUPABASE_URL` build arg in Dockerfile -- still needed for client-side code inlining
- `createClient()` (cookie-based server client) in `lib/supabase/server.ts` -- this is used by Next.js API routes for user-authenticated requests where the custom domain matches the cookie domain. Changing this could break auth cookie resolution
- Client-side Supabase client in `lib/supabase/client.ts` -- must use custom domain for branded auth flows
- Middleware Supabase client in `middleware.ts` -- runs in edge runtime, resolves DNS independently

## Technical Considerations

### Cookie Domain Alignment

The cookie-based `createClient()` (used by API routes for user auth) must continue using `NEXT_PUBLIC_SUPABASE_URL` because Supabase auth cookies are scoped to the custom domain. The service client does not use cookies -- it authenticates via the service role key in the Authorization header.

### Backward Compatibility

The `serverUrl()` helper falls back to `NEXT_PUBLIC_SUPABASE_URL` when `SUPABASE_URL` is not set. This means:

- Local development continues working without adding `SUPABASE_URL` to `.env.local`
- CI/test environments that only set `NEXT_PUBLIC_SUPABASE_URL` continue working
- Only production needs the new variable (via Doppler `prd` config)

### DNS Root Cause

The root cause (Docker DNS resolution failure for the CNAME) is not directly fixed by this change. Instead, we sidestep the issue by using the direct Supabase URL for server-side calls. This is actually the more correct architecture -- server-side code should use the stable project URL, while only client-facing code needs the branded custom domain.

## Acceptance Criteria

- [ ] `/health` endpoint returns `supabase: "connected"` in production
- [ ] `/api/repo/install` successfully resolves GitHub identities via `auth.admin.getUserById()`
- [ ] `/api/repo/create` successfully reads the `users` table via service client
- [ ] `SUPABASE_URL` is set in Doppler `prd` config
- [ ] Local development works without setting `SUPABASE_URL` (fallback to `NEXT_PUBLIC_SUPABASE_URL`)
- [ ] All existing server-side Supabase clients use the direct URL
- [ ] WebSocket handler, agent runner, api-messages, and session-sync all use the direct URL

## Test Scenarios

- Given `SUPABASE_URL` is set, when `createServiceClient()` is called, then it uses `SUPABASE_URL`
- Given `SUPABASE_URL` is not set, when `createServiceClient()` is called, then it falls back to `NEXT_PUBLIC_SUPABASE_URL`
- Given `SUPABASE_URL` is set, when `/health` is called, then the Supabase ping uses the direct URL
- Given the Docker container is running with `SUPABASE_URL=https://ifsccnjhymdmidffkzhl.supabase.co`, when `/api/repo/install` is called with a valid user, then `auth.admin.getUserById()` returns identities
- Given the Docker container is running with `SUPABASE_URL`, when `/api/repo/create` is called, then `serviceClient.from("users").select()` returns user data

### Integration Verification

- **API verify (health):** `curl -s https://app.soleur.ai/health | jq '.supabase'` expects `"connected"`
- **API verify (install):** POST to `/api/repo/install` with valid auth returns 200, not 403
- **Doppler verify:** `doppler secrets get SUPABASE_URL -p soleur -c prd --plain` expects `https://ifsccnjhymdmidffkzhl.supabase.co`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/runtime bug fix with no user-facing, marketing, legal, or product impact.

## Context

Discovered during E2E verification of #1673 (follow-through from PR #1671). The `createRepo` function itself works correctly when called directly, but the surrounding auth and data-fetching flows fail because the server-side Supabase client cannot reach the custom domain.

## References

- Issue: #1679
- DNS config: `apps/web-platform/infra/dns.tf:84-91` (CNAME `api` -> `ifsccnjhymdmidffkzhl.supabase.co`)
- Service client: `apps/web-platform/lib/supabase/server.ts:41-52`
- Health check: `apps/web-platform/server/health.ts:1-14`
- Deploy script: `apps/web-platform/infra/ci-deploy.sh` (Doppler env download)
- Supabase docs: custom domains continue to serve alongside the original project URL
