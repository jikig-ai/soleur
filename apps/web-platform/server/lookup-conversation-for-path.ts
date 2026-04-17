import { createServiceClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";

/**
 * Shared helper for looking up the conversation row bound to a
 * `(user_id, context_path)` pair and counting its messages. Used by both
 * `app/api/chat/thread-info/route.ts` and `app/api/conversations/route.ts`
 * to keep the query vocabulary in a single place (issue #2388 task 8C).
 *
 * Returns a discriminated union so routes can distinguish:
 *   - `{ ok: true, row: null }` — no conversation for this path (not an error)
 *   - `{ ok: true, row: ConversationRow }` — hit
 *   - `{ ok: false, error: ... }` — Supabase error. Caller decides 500 vs. fallback.
 *
 * Internally uses the service client (RLS bypassed) because callers have
 * already authenticated the user and validated the path.
 */
export interface ConversationRow {
  id: string;
  context_path: string;
  last_active: string;
  message_count: number;
}

export type LookupConversationResult =
  | { ok: true; row: ConversationRow | null }
  | { ok: false; error: "lookup_failed" | "count_failed" };

export async function lookupConversationForPath(
  userId: string,
  contextPath: string,
): Promise<LookupConversationResult> {
  const service = createServiceClient();
  const { data: existing, error: lookupErr } = await service
    .from("conversations")
    .select("id, context_path, last_active")
    .eq("user_id", userId)
    .eq("context_path", contextPath)
    .is("archived_at", null)
    .order("last_active", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lookupErr) {
    reportSilentFallback(lookupErr, {
      feature: "kb-chat",
      op: "conversation-lookup",
      extra: { contextPath },
    });
    return { ok: false, error: "lookup_failed" };
  }
  if (!existing) {
    return { ok: true, row: null };
  }

  const { count, error: countErr } = await service
    .from("messages")
    .select("id", { count: "exact", head: true })
    .eq("conversation_id", existing.id);

  if (countErr) {
    reportSilentFallback(countErr, {
      feature: "kb-chat",
      op: "conversation-count",
      extra: { conversationId: existing.id },
    });
    return { ok: false, error: "count_failed" };
  }

  return {
    ok: true,
    row: {
      id: existing.id,
      context_path: existing.context_path,
      last_active: existing.last_active,
      message_count: count ?? 0,
    },
  };
}
