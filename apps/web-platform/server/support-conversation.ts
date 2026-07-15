// B2 repo-less support-conversation resolve-or-create (feat-wire-concierge-support-
// chat, ADR-113). Used by the SSE support route (POST /api/support) — the CTO's
// Option-D transport does NOT go through ws-handler's start_session, so support
// conversation materialization lives here.
//
// A support conversation carries `kind='support'` + `repo_url=null` (migration
// 128), so `dispatchSoleurGo`'s persisted-row requirements (ownership probe,
// workspace_id read, messages FK) are satisfied without any repo. It resolves the
// user's existing support thread (idx_conversations_user_support) or creates one.

import { randomUUID } from "crypto";

import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";

/**
 * Resolve the caller's existing support conversation, or create a fresh
 * repo-less one. Returns the conversation id. Throws on a create failure so the
 * route can fall back to the honest canned reply (never proceed with a
 * non-existent conversation id — dispatchSoleurGo would throw "Conversation not
 * found" downstream).
 */
export async function resolveOrCreateSupportConversation(
  userId: string,
): Promise<string> {
  // biome-ignore lint/suspicious/noExplicitAny: tenant client is an untyped supabase-js chain
  const tenant = (await getFreshTenantClient(userId)) as any;

  // Reuse the caller's most-recent support thread so the conversation (and its
  // history) persists across panel close/reopen — the reconnect-replay cliff B2
  // resolves. RLS already scopes to the caller; the kind filter picks support.
  const existing = await tenant
    .from("conversations")
    .select("id")
    .eq("user_id", userId)
    .eq("kind", "support")
    .order("last_active", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing?.data?.id) {
    return existing.data.id as string;
  }

  const id = randomUUID();
  const workspaceId = await resolveCurrentWorkspaceId(userId, tenant);

  const { error } = await tenant.from("conversations").insert({
    id,
    user_id: userId,
    workspace_id: workspaceId,
    repo_url: null,
    kind: "support",
    domain_leader: null,
    status: "active",
    last_active: new Date().toISOString(),
    context_path: null,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "support",
      op: "resolveOrCreateSupportConversation.insert",
      extra: { userId },
    });
    throw new Error(
      `Failed to create support conversation: ${(error as { message?: string })?.message ?? "unknown"}`,
    );
  }

  return id;
}
