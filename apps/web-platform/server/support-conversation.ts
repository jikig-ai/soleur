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
import { AgentEnginePersistenceRepository, type PersistenceClient } from "@/server/agent-engine-persistence";
import { assertLegacyEngineBinding } from "@/server/agent-engine-route-guard";

/**
 * Bind the conversation's engine run before dispatch (#11591): the credential lease reads the binding's
 * auth mode, and a `pending`/`legacy` conversation with no run fails closed (or serves `managed`) for an
 * owner who holds a subscription row. A failed bind is non-fatal and Sentry-mirrored: the lease already
 * fails closed for a subscription holder and every other user is unaffected. A duplicate-key failure
 * means a concurrent first message already bound the row, which is the desired state, so it is not
 * mirrored. A successful bind is checked with `assertLegacyEngineBinding` (as ws-handler does): a
 * non-Claude workspace default must not bind a conversation the Claude runner will execute.
 */
async function bindSupportConversation(
  // biome-ignore lint/suspicious/noExplicitAny: tenant client is an untyped supabase-js chain
  tenant: any,
  userId: string,
  conversationId: string,
  workspaceId: string,
): Promise<void> {
  let binding: unknown;
  try {
    binding = await new AgentEnginePersistenceRepository(tenant as PersistenceClient).bind({
      workspaceId,
      executionKind: "conversation",
      conversationId,
      createdBy: userId,
    });
  } catch (err) {
    if (err instanceof Error && err.message.includes("duplicate key")) return;
    reportSilentFallback(err, { feature: "support", op: "bind", extra: { conversationId } });
    return;
  }
  assertLegacyEngineBinding(binding);
}

/**
 * Resolve the caller's existing support conversation, or create a fresh
 * repo-less one. Returns the conversation id. Throws on a create failure so the
 * route can fall back to the honest canned reply (never proceed with a
 * non-existent conversation id — dispatchSoleurGo would throw "Conversation not
 * found" downstream).
 *
 * @param opts.forceNew When true, SKIP the reuse SELECT and always insert a
 *   fresh thread. The "start a new conversation" affordance (support panel +
 *   the per-workflow cost-cap error's own instruction) — without it a caller
 *   whose most-recent thread is wedged (cost-capped, or a stale pre-corpus
 *   session) can never escape it, since the resolve path always returns that
 *   same newest row. The newly-inserted row becomes the newest, so subsequent
 *   (forceNew=false) sends reuse IT.
 */
export async function resolveOrCreateSupportConversation(
  userId: string,
  opts?: { forceNew?: boolean },
): Promise<string> {
  // biome-ignore lint/suspicious/noExplicitAny: tenant client is an untyped supabase-js chain
  const tenant = (await getFreshTenantClient(userId)) as any;

  // Reuse the caller's most-recent support thread so the conversation (and its
  // history) persists across panel close/reopen — the reconnect-replay cliff B2
  // resolves. RLS already scopes to the caller; the kind filter picks support.
  // `forceNew` bypasses reuse to mint a deliberate fresh thread.
  if (!opts?.forceNew) {
    const existing = await tenant
      .from("conversations")
      .select("id, engine_binding_state, workspace_id")
      .eq("user_id", userId)
      .eq("kind", "support")
      .order("last_active", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existing?.data?.id) {
      // A sticky row is `legacy` when it predates engine binding (migration 141 backfilled every unbound
      // pre-existing conversation to `legacy`) and `pending` when a post-141 create-time bind failed.
      // Both are bound at the next message (the RPC accepts either when no run exists), so an owner
      // who chose "My API key" is not served the subscription on this thread forever (CTO ruling,
      // #11591). It snapshots the then-current workspace default. A `bound` row keeps its snapshot.
      // No extra read per message: the state came with the select above.
      const state = existing.data.engine_binding_state;
      if ((state === "pending" || state === "legacy") && typeof existing.data.workspace_id === "string") {
        await bindSupportConversation(tenant, userId, existing.data.id as string, existing.data.workspace_id);
      }
      return existing.data.id as string;
    }
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

  await bindSupportConversation(tenant, userId, id, workspaceId);
  return id;
}
