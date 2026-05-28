// Client-safe readers for JWT-hook session claims (ADR-044, migration 060/079).
//
// These are pure functions over a decoded Supabase session — NO server
// dependencies. They live in `lib/` (not `server/workspace-resolver.ts`) so
// `"use client"` components (e.g. the workspace switcher) can read the active
// workspace/org claim WITHOUT pulling the server observability/pino module into
// the browser bundle (serverExternalPackages only externalizes the server
// chunk; a transitive pino import would bundle client-side). See
// 2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries.md.
//
// `server/workspace-resolver.ts` re-exports these for server callers.

export interface SessionLike {
  user?: {
    id?: string;
    app_metadata?: {
      current_organization_id?: string;
      current_workspace_id?: string;
    } & Record<string, unknown>;
  };
}

/**
 * @deprecated Reads from `getUser().app_metadata` which returns the stored
 * `raw_app_meta_data` — the JWT hook's `current_organization_id` claim is
 * NOT persisted there. Use `resolveCurrentOrganizationId` instead.
 */
export function getCurrentOrganizationId(
  session: SessionLike | null | undefined,
): string | null {
  return session?.user?.app_metadata?.current_organization_id ?? null;
}

/**
 * Reads the JWT hook's `current_workspace_id` claim from a session ACCESS
 * TOKEN (ADR-044, migration 079). Unlike `getUser().app_metadata`
 * (`raw_app_meta_data`, no hook claims), the decoded access-token claims DO
 * carry hook injections — so the switcher reads the claim from the session
 * JWT, not `getUser()` (AC9). Returns null when the claim is absent (the
 * caller then falls back to the solo workspace via `resolveCurrentWorkspaceId`).
 */
export function getCurrentWorkspaceId(
  session: SessionLike | null | undefined,
): string | null {
  return session?.user?.app_metadata?.current_workspace_id ?? null;
}
