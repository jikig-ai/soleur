---
module: Web Platform
date: 2026-04-06
problem_type: runtime_error
component: authentication
symptoms:
  - "/health returns supabase: error with 2s timeout"
  - "/api/repo/install returns 403 — getUserById returns no GitHub identity"
  - "/api/repo/create returns 400 — service client cannot read users table"
root_cause: config_error
resolution_type: config_change
severity: critical
tags: [docker, dns, supabase, custom-domain, cname, env-var]
---

# Troubleshooting: Docker container cannot resolve Supabase custom domain CNAME

## Problem

Production Docker container's server-side Supabase service client calls fail silently because Docker's DNS resolver cannot follow the CNAME chain for the custom domain (`api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co`). Client-side auth works because the browser resolves DNS directly.

## Environment

- Module: Web Platform (apps/web-platform)
- Affected Component: Server-side Supabase service client (lib/supabase/server.ts)
- Infrastructure: Hetzner Cloud server running Docker
- Date: 2026-04-06

## Symptoms

- `/health` endpoint returns `{"supabase":"error","sentry":"configured"}` — the REST API ping to `NEXT_PUBLIC_SUPABASE_URL/rest/v1/` fails with a 2s timeout
- `/api/repo/install` returns 403 — `auth.admin.getUserById()` fails to retrieve user identities, making `githubLogin` undefined
- `/api/repo/create` returns 400 — `serviceClient.from("users").select()` fails to read the users table
- CLI admin API call with the same service role key against the direct Supabase URL returns all 3 identities correctly

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The issue was diagnosed from the pattern: client-side auth works (browser resolves DNS), server-side fails (Docker DNS can't resolve CNAME). The fix was to bypass the custom domain for server-side calls.

## Session Errors

**setup-ralph-loop.sh not found**

- **Recovery:** Skipped — script path was wrong in one-shot skill template
- **Prevention:** Verify script paths exist before referencing them in skill templates

**Plan subagent hit usage limit before running deepen-plan**

- **Recovery:** Proceeded with the plan as-is — it was complete and sufficient for a focused bug fix
- **Prevention:** Budget awareness when spawning subagents for multi-step workflows; consider splitting plan and deepen into separate subagent calls

**cd apps/web-platform failed in worktree context**

- **Recovery:** Used the correct path without cd (commands run from worktree root)
- **Prevention:** In worktrees, run commands from the worktree root using relative paths or avoid cd to subdirectories

## Solution

Introduced a `SUPABASE_URL` environment variable (server-side only, no `NEXT_PUBLIC_` prefix) pointing to the direct Supabase project URL. Server-side code uses this instead of the custom domain.

**Code changes:**

```typescript
// Before (broken — custom domain unreachable from Docker):
export function createServiceClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,  // https://api.soleur.ai
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );
}

// After (fixed — direct URL bypasses DNS issue):
export function serverUrl(): string {
  return process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL!;
}

export function createServiceClient() {
  return createSupabaseClient(
    serverUrl(),  // https://ifsccnjhymdmidffkzhl.supabase.co in production
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );
}
```

Additionally consolidated 4 duplicate inline `createClient()` calls in `ws-handler.ts`, `agent-runner.ts`, `api-messages.ts`, and `session-sync.ts` into imports from the centralized `lib/supabase/server.ts` module.

**Environment change:**

```bash
doppler secrets set SUPABASE_URL "https://ifsccnjhymdmidffkzhl.supabase.co" -p soleur -c prd
```

## Why This Works

1. **Root cause:** Docker's default DNS resolver on the Hetzner server cannot follow the CNAME chain from `api.soleur.ai` to `ifsccnjhymdmidffkzhl.supabase.co`. The exact failure mode is a timeout, not a resolution error, suggesting the resolver may be hitting a firewall or rate limit on CNAME resolution.

2. **Why the fix works:** The direct Supabase project URL (`ifsccnjhymdmidffkzhl.supabase.co`) resolves to an A record, which Docker's DNS handles without issue. Server-side code doesn't need the branded custom domain — only client-facing code benefits from it.

3. **Why the cookie-based client is untouched:** Supabase auth cookies are scoped to the custom domain. The `createClient()` function (used by Next.js API routes for user-authenticated requests) must continue using `NEXT_PUBLIC_SUPABASE_URL` to match the cookie domain. The service client authenticates via the service role key in the Authorization header, so cookie domain doesn't matter.

## Prevention

- Use direct service URLs (not custom domain CNAMEs) for server-side calls in Docker containers
- Keep custom domains for client-facing code only (auth flows, branded URLs)
- When adding a custom domain to a service, always add a separate env var for the direct URL and use it for server-side calls
- Test health endpoints after deploying Docker configuration changes

## Related Issues

No related issues documented yet.
