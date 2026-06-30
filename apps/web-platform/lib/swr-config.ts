import type { ScopedMutator } from "swr";
import type { SWRConfiguration } from "swr";

/**
 * Global SWR configuration for the dashboard client-data cache (ADR-067).
 *
 * The cache is **in-memory / session-only** — SWR's default Map provider, NO
 * localStorage/sessionStorage/persistent provider (CPO condition C1). It holds
 * data the user already has access to; the single load-bearing safeguard is
 * that it is CLEARED on sign-out and workspace switch so one (user, workspace)
 * never sees another's cached content (FR4, brand-survival threshold =
 * single-user incident). See `clearSwrCache` below and its two call sites:
 * `components/auth/use-sign-out.ts` (GAP A / C2) and
 * `components/dashboard/org-switcher-container.tsx` (GAP B).
 *
 * `revalidateOnReconnect: false` is deliberate (GAP B): a workspace switch does
 * a hard navigation through an offline-park window; reconnect-revalidation in
 * that window could write workspace-A keys after the user committed to
 * workspace B. We revalidate on focus (cheap, scoped to the mounted view) but
 * never on reconnect for content keys.
 */
export const swrConfig: SWRConfiguration = {
  revalidateOnFocus: true,
  revalidateOnReconnect: false,
  // Coalesce duplicate requests for the same key fired within this window
  // (e.g. Dashboard + Inbox both keying `/api/inbox/emails` — free dedup).
  dedupingInterval: 2000,
};

/**
 * Clear the entire in-memory SWR cache without triggering revalidation.
 *
 * `mutate(() => true, undefined, { revalidate: false })` matches every key
 * (the `() => true` filter), sets each to `undefined`, and suppresses the
 * background refetch SWR would otherwise schedule. Awaiting it guarantees the
 * cache is empty BEFORE the caller navigates, closing the cross-principal leak
 * window (a soft `router.push` would otherwise let the module-singleton cache
 * survive into the next principal's first paint).
 *
 * Pass the `mutate` from `useSWRConfig()` — the bound, cache-scoped mutator.
 */
export async function clearSwrCache(mutate: ScopedMutator): Promise<void> {
  await mutate(() => true, undefined, { revalidate: false });
}

/**
 * Typed cache-key builders (TR4 / FR5).
 *
 * Keys are tuples `[endpoint, ...params]` so a view with filters caches each
 * distinct filter state under its own key without collisions (e.g. Inbox
 * active vs archived). Co-locating them here keeps the convention consistent
 * and lets the Dashboard share a key with Inbox for `/api/inbox/emails` (free
 * dedup). A `null`/`undefined` key short-circuits the fetch (SWR convention),
 * used to gate a request until a precondition (e.g. a contextPath) is known.
 */
export const swrKeys = {
  inboxEmails: (status: string) => ["/api/inbox/emails", status] as const,
  kbTree: () => ["/api/kb/tree"] as const,
  chatThreadInfo: (contextPath: string | null) =>
    contextPath ? (["/api/chat/thread-info", contextPath] as const) : null,
  dashboardToday: () => ["/api/dashboard/today"] as const,
  workspaceActiveRepo: () => ["/api/workspace/active-repo"] as const,
  // Not an HTTP endpoint — the fetcher runs a Supabase count query. Key is a
  // plain sentinel (no URL shape) so it can't be mistaken for a route.
  dashboardOrphanCount: () => ["dashboard:orphan-conversation-count"] as const,
  routinesList: () => ["/api/dashboard/routines"] as const,
  workstreamIssues: () => ["/api/workstream/issues"] as const,
  conversations: (filters: {
    statusFilter?: string;
    domainFilter?: string;
    archiveFilter?: string;
    limit?: number;
  }) => ["conversations", filters] as const,
} as const;

/**
 * Default JSON fetcher for HTTP `useSWR` keys. Throws on non-2xx so SWR routes
 * the response into `error` (powering the stale-failure retry bar) rather than
 * caching an error body as data. The first tuple element is always the URL.
 */
export async function jsonFetcher<T = unknown>(
  key: readonly [string, ...unknown[]] | string,
): Promise<T> {
  const url = Array.isArray(key) ? key[0] : key;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Request failed: ${res.status} ${url}`);
  }
  return (await res.json()) as T;
}
