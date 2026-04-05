# Learning: Supabase ReturnType<typeof createClient> resolves query results to `never`

## Problem

After converting `session-sync.ts` to use a lazy getter typed as `ReturnType<typeof createClient>`, TypeScript CI failed with:

```
error TS2339: Property 'github_installation_id' does not exist on type 'never'.
error TS2345: Argument of type '{ repo_last_synced_at: string; }' is not assignable to parameter of type 'never'.
```

The `.from("users").select(...).single()` call returned `data` typed as `never`, making all property access and `.update()` payloads fail type checks.

## Solution

Replace `ReturnType<typeof createClient>` with the explicit `SupabaseClient` type import:

```typescript
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let _supabase: SupabaseClient | null = null;

function getSupabase(): SupabaseClient | null {
  // ...
}
```

`SupabaseClient` (without generic DB type params) correctly resolves query data to `Record<string, unknown>`, while `ReturnType<typeof createClient>` collapses to `never` for query builder generics in `@supabase/supabase-js` v2.49+.

## Key Insight

When wrapping `createClient` in a lazy getter, always use the explicit `SupabaseClient` type rather than `ReturnType<typeof createClient>`. The `ReturnType` utility type does not preserve the generic parameter defaults that `SupabaseClient` carries, causing downstream query types to collapse. This only surfaces in projects without generated database types (where untyped `from()` calls rely on the client's default generics).

## Session Errors

**`git stash` used in worktree** — Used `git stash` to temporarily revert staged changes for testing original vs fixed code. Violated AGENTS.md hard rule "Never `git stash` in worktrees." Recovery: popped stash immediately. Prevention: use `git show <commit>:<path>` or `git diff --cached` to inspect original code without modifying working tree state.

## Tags

category: build-errors
module: web-platform/session-sync
