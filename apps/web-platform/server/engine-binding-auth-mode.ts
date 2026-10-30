// Reads the auth mode of a conversation's immutable engine binding (ADR-233). Two consumers:
//   - `readConversationBindingAuthMode`: the temporary auth-failure diagnostic (agent-auth-mode.ts),
//     which reports "no run" as `unbound`;
//   - `makeConversationAuthModeResolver`: the credential lease (byok-lease.ts, #11591), which must
//     decide, so it fails closed on everything it cannot positively resolve.
//
// No Sentry or logger import here: the lease owns the single event, and it learns the reason from the
// closed `ConversationAuthModeError` set only (never a row, a database message or an id).
// Both reads are scoped to the caller (`created_by` on the run, `user_id` on the conversation). The
// `agent_engine_runs` select policy is workspace-member-wide, so an unscoped run read would let a
// co-member's conversation id lend the caller another member's mode; the `user_id` scope on the
// conversation read is the same principle (`conversations` rows are member-readable only when shared).

import { getFreshTenantClient } from "@/lib/supabase/tenant";

import { AgentEnginePersistenceRepository, type PersistenceClient } from "./agent-engine-persistence";
import { ConversationAuthModeError } from "./auth-mode-error";

async function repositoryFor(userId: string): Promise<AgentEnginePersistenceRepository> {
  const tenant = await getFreshTenantClient(userId);
  return new AgentEnginePersistenceRepository(tenant as unknown as PersistenceClient);
}

/** The run's raw `authMode` bound by `userId`, or `null` when there is no such run. One read path for both consumers. */
async function readRunAuthMode(
  repo: AgentEnginePersistenceRepository,
  userId: string,
  conversationId: string,
): Promise<string | null> {
  const run = (await repo.getConversationRun(conversationId, userId)) as { binding?: { authMode?: unknown } } | null;
  const mode = run?.binding?.authMode;
  return typeof mode === "string" ? mode : null;
}

/** The binding's raw `authMode`, or `null` when the conversation has no run bound by `userId`. Rejects on a read error. */
export async function readConversationBindingAuthMode(
  userId: string,
  conversationId: string,
): Promise<string | null> {
  return readRunAuthMode(await repositoryFor(userId), userId, conversationId);
}

/**
 * The lease-facing resolver for one conversation. A run found: its `authMode` (the lease validates the
 * value; `normalizeRun` stringifies a missing value, which the lease rejects as `invalid_value`). No run:
 * a `legacy` conversation (created before engine binding) resolves to `managed`, matching
 * `assertLegacyConversationEngineBinding`; any other state, including no conversation row, throws
 * `unbound`. A read error throws `read_failed`. An empty id can never name a caller's own row, so it is
 * `unbound` before any read (the scope arguments of the repository reads are optional by design).
 */
export function makeConversationAuthModeResolver(userId: string, conversationId: string): () => Promise<string> {
  return async () => {
    if (!userId || !conversationId) throw new ConversationAuthModeError("unbound");
    try {
      const repo = await repositoryFor(userId);
      const mode = await readRunAuthMode(repo, userId, conversationId);
      if (mode !== null) return mode;
      const state = await repo.getConversationBindingState(conversationId, userId);
      if (state === "legacy") return "managed";
      throw new ConversationAuthModeError("unbound");
    } catch (err) {
      if (err instanceof ConversationAuthModeError) throw err;
      throw new ConversationAuthModeError("read_failed");
    }
  };
}
