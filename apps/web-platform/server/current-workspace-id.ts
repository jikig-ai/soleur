// Filesystem-free sibling of `workspace-resolver.ts` holding the pure-DB
// `resolveCurrentWorkspaceId` (plus the `SupabaseLike`/`awaitChain`
// primitives it shares with that module). Extracted for #9137: the
// EXECUTION_PLACEMENT manifest pins `cfo-on-payment-failed` and
// `github-on-event` as `volume-bound` ONLY because they reach
// `workspace-resolver.ts` (WORKSPACES_ROOT) through this helper — the
// function itself is a Supabase lookup with no filesystem access.
// `workspace-resolver.ts` re-exports `resolveCurrentWorkspaceId` so
// existing import sites stay stable; placement-aware consumers (e.g.
// `byok-resolver.ts`) import from THIS leaf so their import closure never
// reaches the filesystem-bearing module.

import { reportSilentFallback } from "@/server/observability";

// `.from(table)` returning a thenable query chain. This avoids dragging the
// full `SupabaseClient<Database>` generic into the resolver signature.
export interface SupabaseLike {
  from: (table: string) => unknown;
}

export async function awaitChain<T>(chain: unknown): Promise<T> {
  // The chain is a thenable; await coerces it without explicit .then chaining.
  return (await (chain as PromiseLike<T>)) as T;
}

/**
 * Resolve the user's CURRENT workspace id from `user_session_state`
 * (ADR-044). Source-of-truth read (preferred over the JWT claim, which can
 * be stale on an un-refreshed session). Falls back to the user's SOLO
 * workspace (`= userId` per ADR-038 N2) when the claim is null/absent or on
 * transient error — NEVER an arbitrary sibling workspace (the cross-tenant
 * read this whole feature is designed to prevent). Always returns a
 * workspace id; never null.
 *
 * RLS: `user_session_state_owner_select` allows `auth.uid() = user_id`, so a
 * tenant client reads only its own row.
 */
export async function resolveCurrentWorkspaceId(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    maybeSingle: () => ChainShape;
  } & PromiseLike<{
    data: { current_workspace_id: string | null } | null;
    error: unknown;
  }>;

  const chain = supabase.from("user_session_state") as ChainShape;
  const result = await awaitChain<{
    data: { current_workspace_id: string | null } | null;
    error: unknown;
  }>(chain.select("current_workspace_id").eq("user_id", userId).maybeSingle());

  if (result.error) {
    reportSilentFallback(result.error, {
      feature: "workspace-resolver",
      op: "resolveCurrentWorkspaceId",
      extra: { userId },
    });
    return userId; // fail to solo workspace, never a sibling
  }
  return result.data?.current_workspace_id ?? userId;
}
