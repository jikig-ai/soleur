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

// Module-scoped lazy singleton mirroring `agent-runner.ts` and
// `ws-handler.ts`. Tests that need to drive the wrapper without hitting a
// real client mock at the module boundary via
// `vi.mock("@supabase/supabase-js", () => ({ createClient: ... }))`.
let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  if (!_supabase) _supabase = createServiceClient();
  return _supabase;
}

/**
 * Per-(feature, op, kind) Sentry-mirror dedup window. Caps the
 * `reportSilentFallback` rate to one mirror per minute per call class
 * during error storms (Supabase outage, sustained 0-rows-affected
 * loop). The first occurrence in each window is always reported so
 * outages are observable; suppressed events still hit the pino log.
 *
 * Module-scoped Map; survives across calls but resets on process
 * restart. Acceptable: Sentry already tracks event groups and
 * volume-spikes via its own dedup, this is just a local-process
 * blast-cap.
 */
const SENTRY_DEDUP_WINDOW_MS = 60_000;
const recentReports = new Map<string, number>();

function shouldReportToSentry(feature: string, op: string, kind: string): boolean {
  const key = `${feature}:${op}:${kind}`;
  const now = Date.now();
  const last = recentReports.get(key);
  if (last !== undefined && now - last < SENTRY_DEDUP_WINDOW_MS) {
    return false;
  }
  recentReports.set(key, now);
  // Best-effort GC of stale entries to bound memory.
  if (recentReports.size > 100) {
    for (const [k, t] of recentReports) {
      if (now - t > SENTRY_DEDUP_WINDOW_MS) recentReports.delete(k);
    }
  }
  return true;
}

/** Test-only — clears the per-process Sentry dedup map. */
export function __resetSentryDedupForTests(): void {
  recentReports.clear();
}

/**
 * Allowed columns for a single-conversation targeted update.
 *
 * Hand-written rather than `Pick<Database["public"]["Tables"]["conversations"]["Update"], …>`
 * because the rest of `apps/web-platform/server/` imports `Conversation`
 * from `@/lib/types`, not the Supabase generated types. Adding a new column
 * here is a one-line edit at the migration call site that surfaces via
 * TS error.
 *
 * Scoped to fields the migrated callers actively write. Archive/repo_url
 * flows live in `conversations-tools.ts` (3-column composite key
 * `id, user_id, repo_url`) and are intentionally outside this wrapper —
 * see `scripts/lint-conversations-update-callsites.sh` allowlist.
 */
export interface ConversationPatch {
  status?: Conversation["status"];
  last_active?: string;
  session_id?: string | null;
  active_workflow?: string | null;
  workflow_ended_at?: string | null;
  domain_leader?: Conversation["domain_leader"];
}

export interface UpdateConversationOptions {
  /** Sentry tag — typically the route or module short name. */
  feature?: string;
  /** Sentry sub-tag — the specific operation. */
  op?: string;
  /** Caller-supplied extra context merged into the Sentry `extra` payload. */
  extra?: Record<string, unknown>;
  /**
   * When `true`, treat a 0-rows-affected outcome as failure: the wrapper
   * issues `.select("id")` on the update and returns `{ ok: false }` if
   * no row matched the composite key. Use for paths whose downstream
   * effects (slot release, `session_ended` emission, `waiting_for_user`
   * prompt) would otherwise act on a stale or missing DB row. Default
   * `false` — see module docstring on why silent-success is the
   * baseline contract.
   */
  expectMatch?: boolean;
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
  const baseQuery = supabase()
    .from("conversations")
    .update(patch)
    .eq("id", conversationId)
    .eq("user_id", userId);

  const result = options.expectMatch
    ? await baseQuery.select("id")
    : await baseQuery;
  const error = result.error;
  const data = options.expectMatch
    ? (result as { data: { id: string }[] | null }).data
    : undefined;

  if (error) {
    const feature = options.feature ?? "conversation-writer";
    const op = options.op ?? "update";
    if (shouldReportToSentry(feature, op, "error")) {
      reportSilentFallback(error, {
        feature,
        op,
        extra: {
          userId,
          conversationId,
          patchKeys: Object.keys(patch),
          ...options.extra,
        },
      });
    }
    return {
      ok: false,
      error: new Error(error.message, { cause: error }),
    };
  }

  if (options.expectMatch && (!data || data.length === 0)) {
    // 0-rows-affected with expectMatch: surface as failure. Mirror to
    // Sentry via reportSilentFallback so the downstream caller's
    // degraded path is observable. The composite key (id, user_id)
    // didn't match — caller should treat this as "row no longer
    // eligible" (deleted, archived, owned by someone else after a
    // tenant migration).
    const feature = options.feature ?? "conversation-writer";
    const op = options.op ?? "update";
    if (shouldReportToSentry(feature, op, "0rows")) {
      reportSilentFallback(null, {
        feature,
        op,
        message: "conversation update affected 0 rows (expectMatch)",
        extra: {
          userId,
          conversationId,
          patchKeys: Object.keys(patch),
          ...options.extra,
        },
      });
    }
    return {
      ok: false,
      error: new Error("conversation update affected 0 rows"),
    };
  }

  return { ok: true };
}
