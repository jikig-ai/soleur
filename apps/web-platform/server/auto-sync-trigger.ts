import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { userHasEffectiveByokKey as defaultUserHasEffectiveByokKey } from "@/server/byok-resolver";
import { RuntimeAuthError } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";
import logger from "@/server/logger";

/**
 * Fire-and-forget headless sync trigger, extracted from
 * `/api/repo/setup` (route.ts:222-281) so the lease/auth resilience is
 * unit-testable without the agent SDK.
 *
 * FIX 3 (BUG 3): the post-clone sync fires immediately after the clone
 * resolves, racing the BYOK lease / tenant-JWT mint. Both `RuntimeAuthError`
 * (tenant.ts) and `ByokLeaseError("escape")` (byok-lease.ts) carry the same
 * user-facing copy ("Authentication unavailable; retry shortly") and are raised
 * at lease-bind time BEFORE any agent work — so retrying `startAgentSession`
 * with the SAME pre-created conversation is idempotent. We bound-retry ONLY
 * those classes; on exhaustion we mirror to Sentry and RETURN (never rethrow
 * into the setup `.then()`, never touch `repo_status` — the clone succeeded,
 * only the convenience auto-sync is degraded). `getUserApiKey` (agent-runner)
 * stays the authoritative chat-time backstop.
 *
 * Architecture P0-3: the `conversations` INSERT happens ONCE, OUTSIDE the retry
 * boundary (single `crypto.randomUUID()` id + `session_id`); only
 * `startAgentSession` is retried, reusing the SAME conversationId every attempt.
 * Re-INSERTing per attempt would mint orphan "active" conversations behind the
 * ready screen — the exact orphan the `userHasEffectiveByokKey` gate prevents.
 *
 * Observability note (AC10): the `op auto-sync-degraded` slug (GH013
 * committed-locally-but-could-not-push) is intentionally NOT emitted here.
 * `startAgentSession` is `Promise<void>` (fire-and-forget) — its result surfaces
 * only via `conversations.status` + the WS stream, never a return value. A
 * read-back marker is descoped for this slice, so per AC10 (no emit-less op
 * slug) GH013-degraded is observed via the existing `conversations.status =
 * "failed"` + chat-failure alert path, NOT a dedicated `auto-sync-degraded` op.
 */

/** `startAgentSession` from `@/server/agent-runner`, narrowed to the args used. */
export type StartAgentSessionFn = (
  userId: string,
  conversationId: string,
  arg3: undefined,
  arg4: undefined,
  prompt: string,
) => Promise<void>;

export interface TriggerHeadlessSyncSeams {
  /** Injected so the resilience is testable without the agent SDK. */
  startAgentSession: StartAgentSessionFn;
  /** Service-role Supabase client (conversation INSERT). */
  serviceClient?: ReturnType<typeof createServiceClient>;
  /** Resolve the active workspace_id (solo fallback = userId). */
  resolveWorkspaceId?: (
    userId: string,
    serviceClient: ReturnType<typeof createServiceClient>,
  ) => Promise<string>;
  /** Presence-gate: skip sync entirely for keyless users (#4642). */
  userHasEffectiveByokKey?: (
    userId: string,
    opts: { onErrorReturn: boolean },
  ) => Promise<boolean>;
}

const HEADLESS_SYNC_PROMPT = "/soleur:sync --headless";

// Bounded retry: 1 initial attempt + MAX_RETRIES backed-off retries.
const MAX_RETRIES = 3;
// Exponential backoff (lease/JWT-mint blip is short): 1s / 3s / 9s.
const BACKOFF_MS = [1_000, 3_000, 9_000];

const LEASE_RETRY_MESSAGE = "Authentication unavailable; retry shortly";

/**
 * True when the error is a transient lease/auth-unavailable class worth
 * retrying. Matches the two typed classes plus the shared user-facing message
 * as a defensive substring (a future wrapper that loses the type but keeps the
 * copy still retries).
 */
function isLeaseRetryable(err: unknown): boolean {
  if (err instanceof RuntimeAuthError) return true;
  // Duck-type `ByokLeaseError("escape")` by name + cause instead of importing
  // the heavy `byok-lease` module graph (its module-init `createChildLogger` +
  // tenant client) into the `/api/repo/setup` route's STATIC import graph. The
  // constructor pins `this.name = "ByokLeaseError"` (byok-lease.ts:175), so the
  // structural check is exact for the typed instance.
  if (
    err instanceof Error &&
    (err as { name?: unknown }).name === "ByokLeaseError" &&
    (err as { cause?: unknown }).cause === "escape"
  ) {
    return true;
  }
  if (err instanceof Error && err.message.includes(LEASE_RETRY_MESSAGE)) {
    return true;
  }
  return false;
}

function delay(ms: number): Promise<void> {
  return new Promise((res) => setTimeout(res, ms));
}

export async function triggerHeadlessSync(
  userId: string,
  repoUrl: string,
  seams: TriggerHeadlessSyncSeams,
): Promise<void> {
  const serviceClient = seams.serviceClient ?? createServiceClient();
  const resolveWorkspaceId = seams.resolveWorkspaceId ?? resolveCurrentWorkspaceId;
  const userHasEffectiveByokKey =
    seams.userHasEffectiveByokKey ?? defaultUserHasEffectiveByokKey;

  // Presence-gate: skip entirely for users without a usable key (#4642). The
  // sync agent rejects at getUserApiKey enforcement otherwise, leaving an
  // orphaned "active" conversation behind a "ready" screen. Fail-open
  // (onErrorReturn:true) so keyed/delegated users are never blocked —
  // getUserApiKey stays the authoritative backstop.
  const hasEffectiveKey = await userHasEffectiveByokKey(userId, {
    onErrorReturn: true,
  });
  if (!hasEffectiveKey) return;

  // --- Conversation INSERT: ONCE, OUTSIDE the retry boundary (P0-3) ---
  const conversationId = crypto.randomUUID();
  // conversations.workspace_id is NOT NULL (migration 059); resolve the active
  // workspace (solo fallback = userId) or the INSERT 23502s and the sync
  // conversation is never created.
  const conversationWorkspaceId = await resolveWorkspaceId(userId, serviceClient);
  const { error: convError } = await serviceClient.from("conversations").insert({
    id: conversationId,
    user_id: userId,
    workspace_id: conversationWorkspaceId,
    repo_url: repoUrl,
    domain_leader: "system",
    status: "active",
    session_id: crypto.randomUUID(),
  });

  if (convError) {
    Sentry.withIsolationScope(() => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(userId) });
      reportSilentFallback(convError, {
        feature: "repo-setup",
        op: "auto-sync-trigger",
        message: "Failed to create sync conversation",
        extra: { userId, repoUrl },
      });
    });
    return;
  }

  // --- Retry wraps ONLY startAgentSession, reusing the SAME conversationId ---
  let lastErr: unknown;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      await seams.startAgentSession(
        userId,
        conversationId,
        undefined,
        undefined,
        HEADLESS_SYNC_PROMPT,
      );
      return; // success
    } catch (err) {
      lastErr = err;
      // Only the lease/auth-unavailable classes are retried; everything else
      // (and the final exhausted attempt) falls loud below.
      if (attempt < MAX_RETRIES && isLeaseRetryable(err)) {
        logger.warn(
          { userId, attempt: attempt + 1 },
          "Auto-sync lease/auth unavailable — backing off before retry",
        );
        await delay(BACKOFF_MS[attempt] ?? BACKOFF_MS[BACKOFF_MS.length - 1]);
        continue;
      }
      break;
    }
  }

  // Exhausted (or non-retryable): mirror to Sentry, never rethrow, never touch
  // repo_status (stays "ready" — the clone succeeded; only auto-sync degraded).
  Sentry.withIsolationScope(() => {
    Sentry.getCurrentScope().setUser({ id: hashUserIdValue(userId) });
    reportSilentFallback(lastErr, {
      feature: "repo-setup",
      op: "auto-sync-trigger",
      message: "Auto-triggered sync failed (lease/auth unavailable after retries)",
      extra: { userId, repoUrl },
    });
  });
}
