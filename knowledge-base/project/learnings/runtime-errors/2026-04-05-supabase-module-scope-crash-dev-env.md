# Learning: Supabase client created at module scope crashes dev server when env vars absent

## Problem

`apps/web-platform/server/session-sync.ts` called `createClient(url, key)` at module scope (line 17). When `NEXT_PUBLIC_SUPABASE_URL` or `SUPABASE_SERVICE_ROLE_KEY` were absent (Doppler `dev` config has neither), the dev server crashed on startup with a module-load error, blocking all local development and QA browser testing.

## Solution

Replace module-level client instantiation with a lazy getter that returns `null` when env vars are absent:

```typescript
let _supabase: ReturnType<typeof createClient> | null = null;

function getSupabase(): ReturnType<typeof createClient> | null {
  if (_supabase) return _supabase;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    log.warn("Supabase env vars not set — session sync disabled");
    return null;
  }
  _supabase = createClient(url, key);
  return _supabase;
}
```

Callers (`getInstallationId`, `updateLastSynced`) then guard with `if (!supabase) return null/undefined`.

## Key Insight

Services that use external credentials should never initialize those clients at module scope. Lazy initialization with null-guard lets the server start and function partially when optional integrations are unconfigured. This is especially important for best-effort features (like session sync, which explicitly logs but never throws).

## Session Errors

**`worktree-manager.sh --yes create` exited 128 (bare repo `git pull`)** — Recovery: called `git worktree add` directly — Prevention: The fix-issue skill should note that `worktree-manager.sh` may fail on bare repos; fall back to `git worktree add` when the script fails.

**`bun test` crashes with Floating Point Error (Bun v1.3.6 bug)** — Recovery: treated as pre-existing baseline (same crash before and after fix) — Prevention: file a GitHub issue to track the Bun crash so it is not silently ignored.

## Tags

category: runtime-errors
module: web-platform/session-sync
