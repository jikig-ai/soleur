import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import type { Conversation } from "@/lib/types";

/**
 * Single-conversation targeted-write wrapper enforcing the R8 composite-key
 * invariant (`.eq("id", conversationId).eq("user_id", userId)`) for every
 * update against the `conversations` table from `apps/web-platform/server/`.
 *
 * Generalizes the pattern introduced in PR #2954 at `cc-dispatcher.ts`'s
 * `updateConversationStatus` closure. See issue #2956 for the audit and
 * `scripts/lint-conversations-update-callsites.sh` for the CI detector that
 * enforces single-source ownership of direct `.from("conversations").update`
 * calls.
 *
 * Bulk updates (status sweeps with `.in(...)` + `.lt(...)` filters and no
 * per-user dimension) MUST NOT use this wrapper — they have no composite
 * key. Mark such sites with `// allow-direct-conversation-update: <reason>`
 * on the line above the `.from("conversations")` call so the linter accepts
 * them.
 *
 * 0-rows-affected is silent success: every migrated caller derives both
 * `userId` and `conversationId` server-side, so a 0-row outcome means the
 * conversation no longer matches the composite key (legitimate
 * concurrent-close race), not an attacker probing a foreign id.
 */

let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  if (!_supabase) _supabase = createServiceClient();
  return _supabase;
}

/**
 * Allowed columns for a single-conversation targeted update.
 *
 * Hand-written rather than `Pick<Database["public"]["Tables"]["conversations"]["Update"], …>`
 * because the rest of `apps/web-platform/server/` imports `Conversation`
 * from `@/lib/types`, not the Supabase generated types. Adding a new column
 * here is a one-line edit at the migration call site that surfaces via
 * TS error.
 */
export interface ConversationPatch {
  status?: Conversation["status"];
  last_active?: string;
  session_id?: string | null;
  active_workflow?: string | null;
  workflow_ended_at?: string | null;
  domain_leader?: Conversation["domain_leader"];
  archived_at?: string | null;
  context_path?: string | null;
}

export interface UpdateConversationOptions {
  /** Sentry tag — typically the route or module short name. */
  feature?: string;
  /** Sentry sub-tag — the specific operation. */
  op?: string;
  /** Caller-supplied extra context merged into the Sentry `extra` payload. */
  extra?: Record<string, unknown>;
}

export interface UpdateConversationResult {
  ok: boolean;
  /** Underlying Supabase error if the update failed. */
  error?: Error;
}

/**
 * Update a single conversation row scoped to `(id, user_id)`.
 *
 * Returns `{ ok }` rather than throwing. Errors are mirrored to Sentry via
 * `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` so
 * call sites do not each have to remember; callers decide whether the
 * failure is fatal (close-conversation handler) or degraded (session_id
 * persist).
 */
export async function updateConversationFor(
  userId: string,
  conversationId: string,
  patch: ConversationPatch,
  options: UpdateConversationOptions = {},
): Promise<UpdateConversationResult> {
  const { error } = await supabase()
    .from("conversations")
    .update(patch)
    .eq("id", conversationId)
    .eq("user_id", userId);

  if (error) {
    reportSilentFallback(error, {
      feature: options.feature ?? "conversation-writer",
      op: options.op ?? "update",
      extra: {
        userId,
        conversationId,
        patchKeys: Object.keys(patch),
        ...options.extra,
      },
    });
    return { ok: false, error: new Error(error.message) };
  }

  return { ok: true };
}
