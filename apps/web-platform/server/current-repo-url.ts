import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { reportSilentFallback } from "@/server/observability";

/**
 * Read the authenticated user's CURRENT `users.repo_url`.
 *
 * Collapses the pattern that otherwise repeats across every caller of
 * `lookupConversationForPath` + `ws-handler.createConversation` +
 * Command Center consumers. Centralizing the read keeps three things
 * consistent:
 *
 *   - Error handling: transient DB errors are mirrored to Sentry via
 *     `reportSilentFallback` (rule `cq-silent-fallback-must-mirror-to-sentry`)
 *     rather than silently degrading to "disconnected".
 *   - Coercion: Postgrest's nullable-row return is flattened to
 *     `string | null` with no `as` casts at call sites.
 *   - Single seam for future URL normalization or `projects.id` migration.
 *
 * Returns `null` when the user is disconnected OR on transient error —
 * callers treat both identically (disconnect semantics fail-closed).
 */
export async function getCurrentRepoUrl(userId: string): Promise<string | null> {
  // PR-C §2.6 (#3244): tenant client. RLS on `users` enforces
  // `auth.uid() = id`. Auth probe is the `.maybeSingle()` SELECT itself
  // — this function reads ONLY the caller's own row, no other table is
  // touched, so a separate probe would be redundant. RuntimeAuthError
  // from `getFreshTenantClient` is the load-bearing distinction
  // between "no row" and "JWT-mint failed."
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "repo-scope",
        op: "read-current-repo-url.tenant-mint",
        extra: { userId },
      });
      return null;
    }
    throw err;
  }

  const { data, error } = await tenant
    .from("users")
    .select("repo_url")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "repo-scope",
      op: "read-current-repo-url",
      extra: { userId },
    });
    return null;
  }

  // Normalize on return — the choke point for every server consumer
  // (MCP tools, WS handler, agent-runner, lookup helper). Post-backfill
  // this is a no-op on at-rest data; pre-backfill it's the safety net
  // for any row the migration couldn't normalize (or a future direct-DB
  // insert that bypasses `/api/repo/setup`).
  const raw = (data?.repo_url as string | null | undefined) ?? null;
  const normalized = normalizeRepoUrl(raw);
  return normalized.length > 0 ? normalized : null;
}
