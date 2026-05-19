// Import from `@/lib/supabase/tenant`, NOT from `@/lib/supabase/server` —
// the latter pulls in `next/headers` at module load, which breaks the
// non-Next dev-server bundle (esbuild-built server/index.ts → ws-handler
// → agent-runner → conversations-tools → this module).
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";

/**
 * Shared helper for looking up the conversation row bound to a
 * `(user_id, context_path)` pair and counting its messages. Used by
 * `app/api/chat/thread-info/route.ts`, `app/api/conversations/route.ts`,
 * and the `conversations_lookup` MCP tool.
 *
 * Single round-trip: a PostgREST embedded-resource aggregate combines the
 * SELECT and the message COUNT into one call. The embed is returned as
 * `messages: [{ count: N }]` (always a one-element array, even when N is 0,
 * per PostgREST 12). postgrest-js 2.99 generics sometimes type the embed as
 * nullable — the `?? 0` on the extracted count covers that TS-level case.
 *
 * Returns a discriminated union so routes can distinguish:
 *   - `{ ok: true, row: null }` — no conversation for this path (not an error)
 *   - `{ ok: true, row: ConversationRow }` — hit
 *   - `{ ok: false, error: "lookup_failed" }` — Supabase error. Caller decides.
 *
 * PR-C §2.5 (#3244): migrated to `getFreshTenantClient(userId)` —
 * RLS on `conversations` enforces `auth.uid() = user_id` underneath
 * the explicit `.eq("user_id", userId)` filter. The embedded
 * `messages(count)` aggregate is RLS-filtered through the FK-join,
 * so a cross-tenant lookup returns `{ row: null }` (the maybeSingle
 * result of a 0-row SELECT is null) without leaking any state.
 */
export interface ConversationRow {
  id: string;
  context_path: string;
  last_active: string;
  message_count: number;
}

export type LookupConversationResult =
  | { ok: true; row: ConversationRow | null }
  | { ok: false; error: "lookup_failed" };

export async function lookupConversationForPath(
  userId: string,
  contextPath: string,
  repoUrl: string | null,
): Promise<LookupConversationResult> {
  // Disconnected user (no connected repo) -> no resumable thread.
  // Short-circuit before hitting the DB so orphaned rows from a prior
  // repo cannot leak back into a freshly-connected project.
  if (!repoUrl) return { ok: true, row: null };

  // PR-C §2.5 (#3244): tenant client + per-handler auth probe.
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
    const { error: probeErr } = await tenant
      .from("users")
      .select("id")
      .eq("id", userId)
      .maybeSingle();
    if (probeErr) {
      reportSilentFallback(probeErr, {
        feature: "kb-chat",
        op: "conversation-lookup.auth-probe",
        extra: { contextPath, userId },
      });
      return { ok: false, error: "lookup_failed" };
    }
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "kb-chat",
        op: "conversation-lookup.auth-probe",
        extra: { contextPath, userId },
      });
      return { ok: false, error: "lookup_failed" };
    }
    throw err;
  }

  const { data, error } = await tenant
    .from("conversations")
    .select("id, context_path, last_active, messages(count)")
    .eq("user_id", userId)
    .eq("repo_url", repoUrl)
    .eq("context_path", contextPath)
    .is("archived_at", null)
    .order("last_active", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "kb-chat",
      op: "conversation-lookup",
      extra: { contextPath },
    });
    return { ok: false, error: "lookup_failed" };
  }
  if (!data) return { ok: true, row: null };

  const messagesEmbed = data.messages as
    | Array<{ count: number }>
    | null
    | undefined;
  const messageCount = messagesEmbed?.[0]?.count ?? 0;

  return {
    ok: true,
    row: {
      id: data.id,
      context_path: data.context_path,
      last_active: data.last_active,
      message_count: messageCount,
    },
  };
}
