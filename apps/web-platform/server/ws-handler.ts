import { Server as HTTPServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { parse } from "url";
import { randomUUID } from "crypto";
import { basename as pathBasename } from "path";

import { KeyInvalidError, WS_CLOSE_CODES, type PlanTier, type WSMessage, type Conversation, type WSErrorCode } from "@/lib/types";
import { ByokDelegationError } from "@/server/byok-resolver";
import type { ConversationContext } from "@/lib/types";
import { validateConversationContext } from "./context-validation";
import { createServiceClient } from "@/lib/supabase/service";
import {
  getFreshTenantClient,
  getMyRevocationStatus,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { getCurrentRepoUrl } from "@/server/current-repo-url";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { MAX_SELECTION_LENGTH } from "./review-gate";

// Agent runner stubs -- will be implemented in server/agent-runner.ts
import {
  startAgentSession,
  sendUserMessage,
  resolveReviewGate,
  abortSession,
} from "./agent-runner";
import { updateConversationFor } from "./conversation-writer";
import { WS_CAPABILITIES } from "@/lib/ws-capabilities";
import { reportSilentFallback, warnSilentFallback } from "./observability";
import * as Sentry from "@sentry/nextjs";
import { sanitizeErrorForClient } from "./error-sanitizer";
import { createChildLogger } from "./logger";
import {
  connectionThrottle,
  sessionThrottle,
  pendingConnections,
  extractClientIp,
  logRateLimitRejection,
} from "./rate-limiter";
import { validateContextPath } from "./validate-context-path";
import {
  setUserWorkspace,
  clearUserWorkspace,
  resolveUserWorkspaceBinding,
  getActiveTurnConversation,
  setActiveTurnConversation,
  clearActiveTurnConversation,
  forEachSessionForConversation,
} from "./agent-session-registry";
import {
  streamReplayBuffer,
  isBufferedFrame,
} from "./stream-replay-buffer";
import {
  resolveCurrentOrganizationId,
  getDefaultWorkspaceForUser,
  getWorkspaceForUserInOrganization,
  readWorkspaceIdFromDb,
  workspacePathForWorkspaceId,
  isGitDataStoreEnabled,
} from "./workspace-resolver";
import { resolveHostId } from "./host-identity";
import { resolveSessionRoute } from "./session-router";
import { proxyClientToOwner } from "./session-proxy";
import {
  restoreInflightCheckpoint,
  CHECKPOINT_REFUSED_MESSAGE,
} from "./inflight-checkpoint";
import { effectiveCap, nextTier } from "@/lib/plan-limits";
import { closeWithPreamble } from "@/lib/ws-close-helper";
import { retrieveSubscriptionTier } from "@/lib/stripe";
import {
  acquireSlot,
  releaseSlot,
  touchSlot,
  emitConcurrencyCapHit,
  SLOT_STALENESS_THRESHOLD_SECONDS,
  SLOT_HEARTBEAT_INTERVAL_MS,
} from "./concurrency";
import {
  parseConversationRouting,
  serializeConversationRouting,
  type ConversationRouting,
  type WorkflowName,
} from "./conversation-routing";
import {
  dispatchSoleurGo,
  getCcStartSessionRateLimiter,
  handleInteractivePromptResponseCase,
  hasActiveCcQuery,
  resolveCcBashGate,
  drainAutonomousDisclosureGates,
  markConversationAcked,
  resolveConciergeDocumentContext,
  closeCcConversation,
} from "./cc-dispatcher";
import { fetchUserWorkspacePath } from "./kb-document-resolver";
import { stripAndReportImagePlaceholders } from "./image-paste-strip";
import {
  setAutonomousAck,
  AutonomousAckOwnerDeniedError,
} from "@/server/set-autonomous-ack";
type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;

const log = createChildLogger("ws");

// ---------------------------------------------------------------------------
// Supabase admin client (service role -- server-side only)
//
// Lazy-init: defers createServiceClient() to first property access so this
// module can be imported by app/api/webhooks/stripe/route.ts (for
// forceDisconnectForTierChange) without evaluating serverUrl() at
// `next build` "Collecting page data" time. Mirrors the pattern used by
// server/agent-runner.ts supabase() and server/session-sync.ts getSupabase().
// ---------------------------------------------------------------------------
type ServiceClient = ReturnType<typeof createServiceClient>;
let _supabase: ServiceClient | null = null;
// PR-C §2.10 (#3244): the module-level `supabase` Proxy is RETAINED —
// it's PERMANENT, used only for the `supabase.auth.getUser(token)` HTTP
// Bearer validation at the WS handshake (around `:1812`, after Phase 2.10).
// That call must run BEFORE userId exists (auth-domain bootstrap,
// structurally pre-tenant-JWT). The 13 tenant data sites in this file
// migrate to per-call `getFreshTenantClient(userId)` via the
// `tenantFor(userId)` helper below.
const supabase = new Proxy({} as ServiceClient, {
  get(_target, prop) {
    _supabase ??= createServiceClient();
    const value = Reflect.get(_supabase, prop);
    return typeof value === "function" ? value.bind(_supabase) : value;
  },
});

/**
 * Mint a tenant-scoped Supabase client. Returns `null` on
 * `RuntimeAuthError` (mirrored to Sentry) — callers early-return on
 * `null` to preserve ws-handler's fail-open behavior.
 *
 * Auth probe is IMPLICIT in `getFreshTenantClient`: the
 * `precheck_jwt_mint` RPC throws `RuntimeAuthError` on rate-limit,
 * RPC error, or missing secret. Per `agent-runner.ts:188` precedent
 * ("the auth probe is implicit in getFreshTenantClient — the throw at
 * mint time is the load-bearing distinction") we do NOT layer an
 * additional `SELECT id FROM users` probe on top: every subsequent
 * tenant data read on this client is already RLS-filtered to
 * `auth.uid()`, so a JWT that successfully minted but cannot read its
 * own row is structurally impossible.
 */
async function tenantFor(
  userId: string,
  op: string,
): Promise<ServiceClient | null> {
  try {
    return await getFreshTenantClient(userId);
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "ws-handler",
        op: `tenant-mint.${op}`,
        extra: { userId },
      });
      // #3930 — emit a discriminated `revocation_notice` WS frame
      // BEFORE returning null so the caller's `ws.close(INTERNAL_ERROR)`
      // runs AFTER the send completes. The await is load-bearing:
      // without it, `void emitRevocationNotice(...)` races `ws.close()`
      // and the close usually wins, swallowing the notice. Reachability
      // (Option A): this is the POST-MINT deny race only — the
      // CACHE-HIT deny path inside `tenant.ts` self-heals via silent
      // re-mint (no throw, hence no notice). `my_revocation_status()`
      // is the founder-readable inspection API for support-driven
      // inquiry on that flow. ~750ms p95 RPC latency is accepted on
      // the deny path only (one-shot per revoke).
      if (err.cause === "denied_jti") {
        await emitRevocationNotice(userId);
      }
      return null;
    }
    throw err;
  }
}

/**
 * Best-effort emit of a `revocation_notice` WS frame. Awaited by the
 * caller so `ws.close()` runs strictly AFTER the send completes.
 * Fail-open: any error inside the RPC or send is swallowed (already
 * mirrored to Sentry inside `getMyRevocationStatus`). The readyState
 * gate below short-circuits when the client is no longer listening,
 * which both (i) avoids a wasted ~750ms RPC roundtrip on dead sockets
 * and (ii) closes a DoS amplification surface where an attacker
 * hammering a revoked JWT could drain GoTrue rate-limit slots via
 * re-entrant `getFreshTenantClient` mints.
 */
async function emitRevocationNotice(userId: string): Promise<void> {
  // ReadyState gate — see docblock. Both no-session and not-OPEN cases
  // short-circuit before the RPC roundtrip.
  const session = sessions.get(userId);
  if (!session || session.ws.readyState !== WebSocket.OPEN) return;
  try {
    const status = await getMyRevocationStatus(userId);
    if (!status || !status.revoked) return;
    sendToClient(userId, {
      type: "revocation_notice",
      reason: status.reason ?? null,
      deniedAt: status.deniedAt ?? null,
    });
  } catch {
    // Already mirrored inside getMyRevocationStatus; nothing to add here.
  }
}

// ---------------------------------------------------------------------------
// Session tracking
// ---------------------------------------------------------------------------
/** Grace period before aborting session on disconnect (allows reconnection). */
const DISCONNECT_GRACE_MS = 30_000;

/**
 * Body of the disconnect grace-timer (extracted for unit-testability — #5356).
 * The reconnect window is over, so terminate the in-flight turn on BOTH
 * turn-boundary lineages:
 *   - `abortSession` (legacy `sendUserMessage` path — registered in
 *     `activeSessions`), which already checkpoints in-flight work on disconnect.
 *   - `closeCcConversation(convId, "disconnected")` (cc-soleur-go /
 *     `dispatchSoleurGoForConversation` path — tracked in its own
 *     `activeQueries` Map and never registered in `activeSessions`), which now
 *     checkpoints in-flight work on disconnect too.
 * Both calls are idempotent no-ops for the path that does not own the
 * conversation; the registries are mutually exclusive by construction (per-turn
 * routing sends a conversation to cc XOR legacy), so this never
 * double-checkpoints. See the dual-path-terminal learning
 * (`2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`):
 * any turn-boundary lifecycle hook needs wiring on BOTH lineages.
 */
export function runDisconnectGraceAbort(uid: string, convId: string): void {
  // Host-local owning-host guard (TR2 — epic #5274 Phase 1, ADR-068 §5).
  // A live local OPEN socket for this user means they have reconnected. This
  // CLOSES A REAL replicas=1 RACE: the auth/connect handler registers the new
  // socket (`sessions.set`) BEFORE its `pendingDisconnects`-cancel loop runs —
  // and that cancel sits behind three awaited workspace-bind DB calls
  // (resolveCurrentOrganizationId / getWorkspaceForUserInOrganization /
  // getDefaultWorkspaceForUser). A 30s grace timer expiring in that window would
  // otherwise abort a just-reconnected live turn (#5240). This guard relies on
  // `sessions` being keyed by userId (one live socket per user), so an OPEN entry
  // means the user is back — the same user-level semantics as that cancel loop,
  // which clears every `${userId}:`-prefixed timer regardless of conversation. It
  // also localises the ownership decision inside this function — the one seam
  // Phase 3 routes through the coordinator/Postgres lease so a reconnect landing
  // on ANOTHER host no longer lets this host abort a now-remote-live session. NO
  // host_id / lease / poll in Phase 1.
  const live = sessions.get(uid);
  if (live && live.ws.readyState === WebSocket.OPEN) {
    log.info(
      { userId: uid, conversationId: convId },
      "Reconnected on this host before grace fired — skipping grace abort (owning-host guard)",
    );
    return;
  }
  log.info(
    { userId: uid, conversationId: convId },
    "Grace period expired, aborting session",
  );
  abortSession(uid, convId);
  closeCcConversation(convId, "disconnected");
  // feat-stream-since-disconnect (#5273) — grace expired: the reconnect window
  // is over, so drop the replay frames (counter preserved). A later reconnect
  // now resolves `incomplete` → honest v1 history refetch, never a stale-replay
  // lie. See ADR-059.
  streamReplayBuffer.clear(convId);
}

/** Deferred conversation state — exists XOR conversationId exists. */
export interface PendingConversation {
  id: string;
  leaderId?: DomainLeaderId;
  context?: ConversationContext;
  /** KB document path that will become conversations.context_path at materialization. */
  contextPath?: string;
  /** soleur-go routing decided at start_session time and persisted
   *  alongside the conversations row on first materialization. Always
   *  `{ kind: "soleur_go_pending" }` since #3270 retired FLAG_CC_SOLEUR_GO;
   *  read-path stickiness is enforced by `parseConversationRouting`. */
  routing?: ConversationRouting;
}

export interface ClientSession {
  ws: WebSocket;
  conversationId?: string;
  /** Deferred conversation (no DB row yet). Cleared when materialized or closed. */
  pending?: PendingConversation;
  /** Timer for deferred abort on disconnect — cleared if user reconnects. */
  disconnectTimer?: ReturnType<typeof setTimeout>;
  /** Timestamp of last user activity (auth or chat message). */
  lastActivity: number;
  /**
   * tc_accepted_version observed at handshake. Used as a baseline so a
   * mid-session TC_VERSION bump triggers the next gated message to close
   * the socket with TC_NOT_ACCEPTED. See `recheckTcMidSession`.
   */
  tcVersionAtHandshake?: string | null;
  /**
   * Cache expiry (ms epoch) for the mid-session TC re-check. Bounded at
   * 30 s — see `TC_RECHECK_CACHE_MS`. Up to 30 s of stale-consent agent
   * traffic may pass between a TC_VERSION bump and enforcement; the
   * trade-off is explicit in plan AC6.
   */
  tcRecheckCacheUntil?: number | null;
  /** Timer that closes the connection after WS_IDLE_TIMEOUT_MS of inactivity. */
  idleTimer?: ReturnType<typeof setTimeout>;
  /** Cached subscription status — set at auth, refreshed by billing check timer. */
  subscriptionStatus?: string;
  /** Periodic refresh timer for `subscriptionStatus` — cleared on every teardown path. */
  subscriptionRefreshTimer?: ReturnType<typeof setInterval>;
  /** Cached plan tier — set at auth, refreshed in the same query as
   *  subscriptionStatus (Phase 3). Drives effectiveCap on the slot-acquire
   *  path (Phase 5). */
  planTier?: PlanTier;
  /** Per-user concurrency raise-only override from users.concurrency_override.
   *  null means "use tier default"; a number larger than the default raises
   *  the cap (see effectiveCap in lib/plan-limits.ts). */
  concurrencyOverride?: number | null;
  /** Cached Stripe subscription ID — used by the cap-hit Stripe fallback
   *  (Phase 5) to cover webhook-lag between an upgrade and the DB write. */
  stripeSubscriptionId?: string | null;
  /** Remote-IP captured at connection time — needed by the soleur-go
   *  start-session rate limiter's per-IP cap. Stage 2.13. */
  ip?: string;
  /** Cached soleur-go routing for the active conversation. Populated at
   *  materialization + refreshed by `persistActiveWorkflow` so the
   *  chat-case `parseConversationRouting` lookup can skip the per-turn
   *  DB fetch (performance P1-A). Undefined means "not yet
   *  materialized OR cache cold" — read DB on cache miss. */
  routing?: ConversationRouting;
  /** Cached `conversations.context_path` for the active conversation.
   *  Populated at materialization (from `pending.contextPath`) + on
   *  cache-miss DB lookup so chat-case follow-up turns can re-inject the
   *  open KB document into the Concierge system prompt without a
   *  per-turn DB fetch. `null` means "no scoped artifact"; `undefined`
   *  means "cache cold". */
  contextPath?: string | null;
  /** #3266 — cached `conversations.session_id` for the active
   *  conversation. Seeded on chat-case cache miss from the SELECT (and
   *  written back by the runner via `onSessionIdCaptured`). Threaded into
   *  `dispatchSoleurGo({ sessionId })` so cold-Query construction after
   *  reap/restart resumes the SDK session and activates the prefill
   *  guard. `null` means "no persisted session_id"; `undefined` means
   *  "cache cold". */
  sessionId?: string | null;
}

/** Active connections keyed by Supabase user ID. Registered in session-registry
 *  so `/health` and session-metrics can read `.size` without pulling the full
 *  ws-handler graph. Re-exported here for backwards compatibility. */
import { sessions } from "./session-registry";
export { sessions };

/**
 * Force-disconnect a user's WS session with a 4011 TIER_CHANGED preamble.
 * Called from the Stripe webhook handler when a downgrade reduces the
 * effective cap below the user's currently-held slot count. No-op if the
 * user has no active session. The client will reconnect after a 500 ms
 * delay (see ws-client.ts TIER_CHANGED_RECONNECT_DELAY_MS).
 */
export function forceDisconnectForTierChange(
  userId: string,
  preamble: { type: "tier_changed"; previousTier?: PlanTier; newTier?: PlanTier },
): boolean {
  const session = sessions.get(userId);
  if (!session || session.ws.readyState !== WebSocket.OPEN) return false;
  closeWithPreamble(session.ws, WS_CLOSE_CODES.TIER_CHANGED, preamble);
  return true;
}

/** Deferred abort timers for disconnected sessions (keyed by userId:conversationId). */
const pendingDisconnects = new Map<string, ReturnType<typeof setTimeout>>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Abort the active agent session for this user (if any), mark the conversation
 *  completed (fire-and-forget), and clear session.conversationId. No-ops if no
 *  conversation is active. */
export function abortActiveSession(userId: string, session: ClientSession): void {
  if (!session.conversationId && !session.pending) return;

  const oldConvId = session.conversationId ?? session.pending?.id;
  log.info({ userId, conversationId: oldConvId }, "Aborting active session (superseded)");

  if (session.idleTimer) clearTimeout(session.idleTimer);
  if (session.conversationId) {
    abortSession(userId, session.conversationId, "superseded");
    // feat-stream-since-disconnect (#5273) — a superseded conversation will
    // never be resumed; drop its replay frames (counter preserved). See ADR-059.
    streamReplayBuffer.clear(session.conversationId);
  }

  // Release slot for both materialized + pending conversations. The RPC
  // is idempotent (plain DELETE) so a no-op on an already-released row is
  // harmless.
  if (oldConvId) {
    void releaseSlot(userId, oldConvId);
  }

  // Invalidate the per-session routing cache so the next conversation
  // on this socket re-reads active_workflow from DB.
  session.routing = undefined;
  // Same invalidation contract for the KB context cache.
  session.contextPath = undefined;
  // Same for the session_id cache (#3266).
  session.sessionId = undefined;

  // Fire-and-forget — orphan cleanup catches failures on restart.
  // The wrapper enforces the R8 composite-key invariant; errors mirror to
  // Sentry via reportSilentFallback so we don't need a local catch.
  if (oldConvId) {
    void updateConversationFor(
      userId,
      oldConvId,
      { status: "completed", last_active: new Date().toISOString() },
      { feature: "ws-handler", op: "supersede-on-reconnect", expectMatch: true },
    );
  }

  session.conversationId = undefined;
}

/**
 * Self-healing ledger-divergence recovery for `start_session` cap_hit
 * (#stuck-active fix, AC4).
 *
 * When `acquireSlot` returns `cap_hit` and the user's *visible* active
 * conversations (status in active/waiting_for_user, archived_at IS NULL)
 * are FEWER than the slot count, the slot ledger has at least one
 * orphan row — its `conversation_id` does not appear in the visible set.
 * Reasons: a transient bug or process kill stranded a conversation row
 * (covered by AC1 + AC2), or an archive trigger fired but a slot
 * insertion raced after.
 *
 * This helper detects divergence and force-releases each orphan slot,
 * then mirrors a single Sentry event so a non-zero rate is visible to
 * on-call. The caller is expected to retry `acquireSlot` ONCE on
 * `didRecover: true`. Recursion on a second cap_hit is forbidden — fall
 * through to the existing close path so genuine cap denials behave
 * unchanged.
 *
 * Best-effort: errors during the SELECT or releaseSlot calls do not
 * throw — they short-circuit to `didRecover: false` so the caller's
 * fallback (close with `concurrency_cap_hit` preamble) still runs.
 *
 * Exported for tests; call site is the `start_session` cap_hit branch
 * below.
 */
/**
 * Is there a LIVE agent loop for this conversation on THIS instance? Reconciles
 * BOTH process-local loop registries (the dual-lineage invariant at
 * agent-session-registry.ts): the cc-soleur-go runner (`hasActiveCcQuery`, the
 * dominant path) OR the legacy `activeSessions` map (any `userId:convId[:leaderId]`
 * key). Used by the AC14 dead-socket reap so a backgrounded-but-live loop (a
 * conversation not focused by the current socket, e.g. after crash+reconnect, or
 * one paused on a review gate) is NEVER reaped — CTO ruling 2026-07-18
 * (knowledge-base/engineering/architecture/decisions): reap on agent-loop
 * liveness, not socket focus.
 */
function hasLiveAgentLoop(userId: string, conversationId: string): boolean {
  if (hasActiveCcQuery(conversationId)) return true;
  let found = false;
  forEachSessionForConversation(userId, conversationId, () => {
    found = true;
    return true; // stop at the first match
  });
  return found;
}

export async function tryLedgerDivergenceRecovery(
  userId: string,
): Promise<{ didRecover: boolean }> {
  try {
    // PR-C §2.10 (#3244): per-handler tenant client + RLS-baseline
    // probe. RuntimeAuthError → no recovery (fail open). RLS on
    // `conversations` and `user_concurrency_slots` (slots_owner_read
    // policy, migration 029:91) enforce auth.uid() ownership.
    const tenant = await tenantFor(userId, "tryLedgerDivergenceRecovery");
    if (!tenant) return { didRecover: false };

    // Visible active conversations — what the user perceives as "in
    // flight". Mirrors the ledger denominator the cap was checked
    // against.
    // visibility-sweep-audit: owner-scoped — concurrency-slot accounting is per-user
    const visibleResp = await tenant
      .from("conversations")
      .select("id")
      .eq("user_id", userId)
      .is("archived_at", null)
      .in("status", ["active", "waiting_for_user"]);
    if (visibleResp.error) {
      reportSilentFallback(visibleResp.error, {
        feature: "concurrency-ledger-divergence",
        op: "start_session-recovery-select-visible",
        extra: { userId },
      });
      return { didRecover: false };
    }
    const visibleIds = new Set<string>(
      ((visibleResp.data ?? []) as Array<{ id: string }>).map((r) => r.id),
    );

    const slotsResp = await tenant
      .from("user_concurrency_slots")
      .select("conversation_id")
      .eq("user_id", userId);
    if (slotsResp.error) {
      reportSilentFallback(slotsResp.error, {
        feature: "concurrency-ledger-divergence",
        op: "start_session-recovery-select-slots",
        extra: { userId },
      });
      return { didRecover: false };
    }
    const slotConversationIds = ((slotsResp.data ?? []) as Array<{ conversation_id: string }>)
      .map((r) => r.conversation_id);

    const orphans = slotConversationIds.filter((cid) => !visibleIds.has(cid));

    // Stale-heartbeat detector (May-6 #3354). The orphan check above only
    // catches slots whose conversation is NOT in the visible-active set;
    // it misses the boundary case where a `status='active'` conversation row
    // IS visible but its slot's `last_heartbeat_at` lapsed past 240 s
    // (SLOT_STALENESS_THRESHOLD_SECONDS) between the RPC's lazy sweep and this
    // helper's processing — e.g.
    // a tab supersession that clears the old WS's `pingInterval` so no
    // refresh fires while the helper runs. Catching it here (vs waiting
    // up to 60 s for the agent-runner reaper) flips the conv row to
    // `failed` synchronously so the dashboard "Active conversations" rail
    // truths up, and surfaces the divergence to Sentry.
    //
    // WHY THIS BRANCH IS MOSTLY INACTIVE IN STEADY STATE (#3372):
    // `acquire_conversation_slot` (migration 133) runs the IDENTICAL
    // lazy-sweep predicate (`last_heartbeat_at < now() - 240 s`) inside its
    // own transaction BEFORE the count-check. When the RPC returns `cap_hit`,
    // every surviving slot has already been swept clean — so this SELECT finds
    // stale rows only in a narrow boundary race (~50–200 ms between the RPC's
    // transaction commit and the moment this helper's SELECT executes). The
    // remaining value of this branch is therefore:
    //   1. Sentry observability: the RPC's lazy sweep is silent; this SELECT
    //      surfaces boundary-race reaps as Sentry events.
    //   2. Synchronous status flip: the lazy sweep deletes the slot but does
    //      NOT update the `conversations` row — the dashboard "Executing" state
    //      stays stuck until the async reaper (≤60 s). This branch flips it to
    //      `failed` immediately.
    //   3. Defense-in-depth: if the RPC's lazy sweep is ever refactored away,
    //      this branch becomes the primary stale-slot reaper without any code
    //      change here.
    // Decision: use the shared SLOT_STALENESS_THRESHOLD_SECONDS (240 s as of the
    // 2026-07-18 Disk-IO backoff). Re-evaluate if the async reaper interval
    // changes, or Sentry shows staleHeartbeatCount > 1% of cap-hit events at
    // scale (which would confirm the branch is load-bearing, not just
    // boundary-race defense).
    //
    // THRESHOLD-COUPLING: the 240 s staleness value is the ONE shared const
    // SLOT_STALENESS_THRESHOLD_SECONDS (server/concurrency.ts), also consumed by
    // agent-runner.ts (find_stuck_active_conversations arg) and the cap-drift
    // self-eviction + sibling-snapshot-restore liveCutoff gates below, and
    // mirrored in SQL by migration 133
    // (acquire_conversation_slot lazy sweep, user_concurrency_slots_sweep
    // pg_cron, find_stuck_active_conversations default). Importing the shared
    // symbol here (rather than a local literal) structurally prevents the
    // sibling-site drift that historically false-reaped live slots. Index path:
    // `user_concurrency_slots_user_heartbeat_idx` (migration 029) on
    // `(user_id, last_heartbeat_at)`.
    const staleCutoff = new Date(
      Date.now() - SLOT_STALENESS_THRESHOLD_SECONDS * 1_000,
    ).toISOString();
    const staleResp = await tenant
      .from("user_concurrency_slots")
      .select("conversation_id")
      .eq("user_id", userId)
      .lt("last_heartbeat_at", staleCutoff);
    let staleConversationIds: string[] = [];
    if (staleResp.error) {
      // Fail-open: a SELECT error on the new branch must NOT regress the
      // existing orphan-recovery path. Mirror once and continue.
      reportSilentFallback(staleResp.error, {
        feature: "concurrency-ledger-divergence",
        op: "start_session-recovery-select-stale-heartbeat",
        extra: { userId },
      });
    } else {
      staleConversationIds = ((staleResp.data ?? []) as Array<{ conversation_id: string }>)
        .map((r) => r.conversation_id);
    }

    const orphanSet = new Set<string>(orphans);
    const staleSet = new Set<string>(staleConversationIds);

    // AC14 (Phase 3e) — THRESHOLD-INDEPENDENT immediate cap-hit reclaim.
    // Raising the staleness threshold 120→240 s (mig 133) would otherwise lock a
    // cap-hit user out for up to 240 s: after a socket crash, the crashed
    // conversation's slot is still visible-active (not an orphan) AND stale
    // <240 s (not caught by the stale branch above), so starting a NEW
    // conversation trips CONCURRENCY_CAP until the threshold elapses. Reap the
    // NEW class the orphan/stale branches miss: a slot whose conversation has NO
    // live agent loop on this instance (hasLiveAgentLoop = cc + legacy
    // registries) AND is not the focused socket conversation — restoring the
    // immediate-free-on-reconnect behavior, independent of the heartbeat
    // threshold. Computed EXCLUSIVE of orphan/stale (they already reap those) so
    // it only adds the visible+fresh-heartbeat-but-dead case. Uses only slots
    // already fetched (no extra query). CTO ruling 2026-07-18: gate on agent-loop
    // liveness, NOT socket focus (a focus-only reap kills backgrounded-live loops
    // #5273 and review-gate-paused conversations). CROSS-HOST CAVEAT (ADR-124):
    // hasLiveAgentLoop is instance-local, so this branch's no-false-reap guarantee
    // is CONDITIONAL on user-sticky placement (ADR-068 D0 / #5274, replicas=1
    // today). Any weakening of sticky placement must re-audit this reaper.
    const focusedSession = sessions.get(userId);
    const focusedConvIds = new Set<string>(
      [focusedSession?.conversationId, focusedSession?.pending?.id].filter(
        (v): v is string => typeof v === "string",
      ),
    );
    const deadSocketConversationIds = slotConversationIds.filter(
      (cid) =>
        !orphanSet.has(cid) &&
        !staleSet.has(cid) &&
        !focusedConvIds.has(cid) &&
        !hasLiveAgentLoop(userId, cid),
    );

    // Dedup union: one releaseSlot + one finalize per unique conversation_id.
    const reapableSet = new Set<string>([
      ...orphans,
      ...staleConversationIds,
      ...deadSocketConversationIds,
    ]);
    const reapable = Array.from(reapableSet);

    if (reapable.length === 0) {
      // No divergence — genuine cap_hit; caller proceeds to close path.
      return { didRecover: false };
    }

    // Release every reapable slot in parallel — keyed DELETE is idempotent.
    await Promise.all(
      reapable.map((cid) => releaseSlot(userId, cid)),
    );

    // Conversation-row finalize. Status-only — do NOT bump `last_active`:
    // this is a server-initiated cleanup, not user activity, and bumping
    // would float wedged-and-failed rows above genuinely-recent ones in
    // sort-by-last-active surfaces (`conversations-tools.ts` MCP list,
    // `lookup-conversation-for-path.ts`). Per-row op tag distinguishes
    // the finalize cause for Sentry breadcrumb consumers — orphan rows
    // are typically already terminal/archived (no-op), stale-heartbeat
    // rows are the load-bearing case where the user-visible row flips
    // from Executing to failed. `expectMatch: false` because both classes
    // include benign zero-row outcomes (archived row, already-terminal,
    // hard-deleted). #3463: `onlyIfStatusIn: ["active"]` narrows the
    // race surface where divergence detection ran ≤Xms before a
    // legitimate result-branch flipped the row to `waiting_for_user` —
    // without the guard the recovery path stomps a healthy terminal
    // state to `failed`.
    await Promise.all(
      reapable.map((cid) =>
        updateConversationFor(
          userId,
          cid,
          { status: "failed" },
          {
            feature: "concurrency-ledger-divergence",
            op: orphanSet.has(cid)
              ? "start_session-recovery-finalize-orphan"
              : staleSet.has(cid)
                ? "start_session-recovery-finalize-stale-heartbeat"
                : "start_session-recovery-finalize-dead-socket",
            expectMatch: false,
            onlyIfStatusIn: ["active"],
          },
        ).catch(() => undefined),
      ),
    );

    // Single Sentry mirror for the divergence detection itself. AC4
    // excludes the recovered-OK path. `recoveryCause` lets dashboards
    // segment orphan vs stale-heartbeat vs dead-socket without spawning a new
    // feature key; existing aggregations on `feature` + `op` are preserved.
    const recoveryCause =
      [
        orphans.length > 0 ? "orphan" : null,
        staleConversationIds.length > 0 ? "stale-heartbeat" : null,
        deadSocketConversationIds.length > 0 ? "dead-socket" : null,
      ]
        .filter((v): v is string => v !== null)
        .join("+") || "none";
    reportSilentFallback(new Error("ledger-divergence"), {
      feature: "concurrency-ledger-divergence",
      op: "start_session-recovery",
      extra: {
        userId,
        visibleCount: visibleIds.size,
        slotCount: slotConversationIds.length,
        orphanCount: orphans.length,
        staleHeartbeatCount: staleConversationIds.length,
        deadSocketCount: deadSocketConversationIds.length,
        reapableCount: reapable.length,
        recoveryCause,
      },
    });

    return { didRecover: true };
  } catch (err) {
    // Defensive: any unexpected throw must NOT prevent the caller's
    // close path from running. Mirror once so the failure surfaces.
    reportSilentFallback(err, {
      feature: "concurrency-ledger-divergence",
      op: "start_session-recovery-throw",
      extra: { userId },
    });
    return { didRecover: false };
  }
}

/**
 * Serialize and send a WSMessage to the client identified by `userId`.
 * Returns true if the message was delivered via WebSocket, false if the
 * user has no active connection or the socket is not open.
 */
export function sendToClient(userId: string, message: WSMessage): boolean {
  const session = sessions.get(userId);
  // feat-stream-since-disconnect (#5273) — buffer-write hook. Stamp every
  // buffered-family frame with a monotonic `seq` and append it to its
  // conversation's replay ring BEFORE serialization, and REGARDLESS of send
  // success: a frame emitted to a momentarily-dead socket (the disconnect
  // grace window) is exactly what must be replayed on reconnect. Key on the
  // FRAME's `conversationId` when present (never blindly `session.conversationId`
  // — a backgrounded conv-A frame must not land in conv-B's buffer), else the
  // user's active-turn binding (survives socket close), else session. Skip if
  // no conversation can be resolved (e.g. pre-session frames). See ADR-059.
  // `message.seq === undefined` distinguishes a fresh live frame (stamp it)
  // from a REPLAYED buffered frame being re-emitted by the resume_stream
  // handler (already carries `seq` — must NOT be re-stamped, or replay would
  // duplicate it into the ring and rewind nothing). Live frames are always
  // constructed without `seq`.
  if (isBufferedFrame(message) && message.seq === undefined) {
    const frameConvId =
      "conversationId" in message && message.conversationId
        ? message.conversationId
        : getActiveTurnConversation(userId) ?? session?.conversationId;
    if (frameConvId) {
      streamReplayBuffer.stamp(frameConvId, message);
    }
  }
  if (!session || session.ws.readyState !== WebSocket.OPEN) return false;
  session.ws.send(JSON.stringify(message));
  return true;
}

/** Auth timeout: close unauthenticated connections after 5 seconds. */
const AUTH_TIMEOUT_MS = 5_000;

/** Idle timeout: close connections with no user activity (default 30 min). */
const WS_IDLE_TIMEOUT_MS = parseInt(process.env.WS_IDLE_TIMEOUT_MS ?? "1800000", 10);

/**
 * Subscription-status cache refresh cadence (default 60s). Bounds the TOCTOU
 * window between a Stripe webhook flipping `users.subscription_status` to
 * `unpaid` and the WS handler enforcing it on an already-authenticated
 * long-lived session.
 */
const WS_SUBSCRIPTION_REFRESH_INTERVAL_MS = parseInt(
  process.env.WS_SUBSCRIPTION_REFRESH_INTERVAL_MS ?? "60000",
  10,
);

/** Reset the idle timer for a session. Called after auth and on each chat message. */
function resetIdleTimer(userId: string, session: ClientSession): void {
  if (session.idleTimer) clearTimeout(session.idleTimer);
  session.lastActivity = Date.now();
  const timer = setTimeout(() => {
    log.info({ userId }, "Idle timeout — closing connection");
    session.ws.close(WS_CLOSE_CODES.IDLE_TIMEOUT, "Idle timeout");
  }, WS_IDLE_TIMEOUT_MS);
  timer.unref();
  session.idleTimer = timer;
}

/**
 * Check if user's subscription is suspended using cached session status.
 * Returns true if suspended (sends error and closes connection).
 */
function checkSubscriptionSuspended(userId: string, session: ClientSession): boolean {
  if (session.subscriptionStatus === "unpaid") {
    sendToClient(userId, {
      type: "error",
      message: "Your subscription is unpaid. Resolve payment to continue.",
    });
    session.ws.close(
      WS_CLOSE_CODES.SUBSCRIPTION_SUSPENDED,
      "Subscription suspended",
    );
    return true;
  }
  return false;
}

/**
 * Re-fetch `users.subscription_status` for this session and enforce suspension
 * if it has flipped to `unpaid`. Fail-open on transient DB errors — keep the
 * previously cached value rather than disrupting an active session.
 *
 * Exported only for tests. Includes a mandatory `ws.readyState` guard AFTER
 * the await: the socket may have closed during the DB round-trip (disconnect,
 * idle timeout, earlier suspension close). Mutating state on a dead socket
 * leaks handles to Supabase and risks calling close() on an already-closing
 * connection — see `2026-03-20-websocket-first-message-auth-toctou-race.md`.
 */
export async function refreshSubscriptionStatus(
  userId: string,
  session: ClientSession,
): Promise<void> {
  try {
    // PR-C §2.10 (#3244): tenant-scoped users SELECT + concurrency-slot
    // count. RLS on `users` (auth.uid() = id) + slots_owner_read
    // (migration 029:91). Per-handler probe via `tenantFor` — on
    // auth-probe failure, return early (fail-open per the function's
    // documented best-effort contract; keep prior cached values).
    const tenant = await tenantFor(userId, "refreshSubscriptionStatus");
    if (!tenant) return;

    const { data, error } = await tenant
      .from("users")
      .select("subscription_status, plan_tier, concurrency_override")
      .eq("id", userId)
      .single();

    // Guard: socket may have closed during the await. Do not mutate session
    // state or call close() on a dead socket.
    if (session.ws.readyState !== WebSocket.OPEN) return;

    if (error || !data) return; // fail open — keep prior cached value
    const row = data as {
      subscription_status: string | null;
      plan_tier?: PlanTier | null;
      concurrency_override?: number | null;
    };
    const prevTier = session.planTier;
    session.subscriptionStatus = row.subscription_status ?? undefined;
    session.planTier = row.plan_tier ?? "free";
    session.concurrencyOverride = row.concurrency_override ?? null;
    if (row.subscription_status === "unpaid") {
      checkSubscriptionSuspended(userId, session);
      return;
    }

    // Passive cap-drift self-evict. The Stripe webhook's
    // forceDisconnectForTierChange reaches only the in-process `sessions`
    // Map — a future horizontal scale-out (replicas > 1) silently breaks
    // downgrade enforcement for sessions on other processes. This passive
    // check runs on every subscription refresh (default 60s): if the
    // current slot count exceeds the freshly-computed effective cap,
    // evict this session so the user lands at the new cap on reconnect.
    // Non-deterministic which over-cap session gets closed — all of them
    // will on their next refresh tick, converging within one interval.
    const newCap = effectiveCap(session.planTier, session.concurrencyOverride);
    // Freshness-filter the count so crashed-but-unreaped slots don't trigger a
    // false eviction. Mirrors the acquire-RPC self-reap (093:79-81) and the
    // sibling slot probes (:526 divergence, :2013 sibling-slot). Load-bearing
    // for the migration-115 throttle (#5738): the slots sweep moved */15 → hourly,
    // so stale rows linger up to ~1h; without this filter a downgraded user with
    // a stale slot would be falsely evicted on the next refresh tick. Uses the
    // shared SLOT_STALENESS_THRESHOLD_SECONDS (240 s) so the read-side liveness
    // window matches the 240 s reaper (mig 133) — leaving it at 120 s would
    // desync from the widened threshold.
    const liveCutoff = new Date(
      Date.now() - SLOT_STALENESS_THRESHOLD_SECONDS * 1_000,
    ).toISOString();
    const { count, error: countErr } = await tenant
      .from("user_concurrency_slots")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("last_heartbeat_at", liveCutoff);
    if (!countErr && typeof count === "number" && count > newCap) {
      const convId = session.conversationId ?? session.pending?.id;
      log.info(
        { userId, convId, count, newCap, prevTier, newTier: session.planTier },
        "Cap-drift detected on refresh — evicting session",
      );
      closeWithPreamble(session.ws, WS_CLOSE_CODES.TIER_CHANGED, {
        type: "tier_changed",
        previousTier: prevTier,
        newTier: session.planTier,
      });
      if (convId) void releaseSlot(userId, convId);
    }
  } catch (err) {
    log.warn(
      { userId, err },
      "Subscription status refresh failed — keeping cached value",
    );
  }
}

/**
 * Start (or restart) the periodic subscription-status refresh timer for a
 * session. Timer is `.unref()`'d so it never blocks process exit (tests,
 * graceful SIGTERM drain). Cleared from every teardown path.
 *
 * Exported only for tests.
 */
export function startSubscriptionRefresh(
  userId: string,
  session: ClientSession,
): void {
  if (session.subscriptionRefreshTimer) {
    clearInterval(session.subscriptionRefreshTimer);
  }
  const timer = setInterval(
    () => void refreshSubscriptionStatus(userId, session),
    WS_SUBSCRIPTION_REFRESH_INTERVAL_MS,
  );
  timer.unref?.();
  session.subscriptionRefreshTimer = timer;
}

/**
 * Guard for the (user_id, context_path) partial UNIQUE index violation.
 * Exported for regression coverage — asserts that a 23505 on an unrelated
 * index (e.g., `conversations_pkey`) does NOT fall through to the
 * context_path lookup. See issue #2390.
 *
 * Prefers the structured `constraint` / `details` fields that PostgREST
 * populates for 23505 errors, falling back to a `message` substring match
 * for driver variants that omit them. Message-only matching is fragile
 * against localized `lc_messages` or future wording changes.
 */
export function isContextPathUniqueViolation(err: unknown): boolean {
  const pgErr = err as
    | { code?: string; message?: string; details?: string; constraint?: string }
    | null;
  if (!pgErr || pgErr.code !== "23505") return false;
  if (pgErr.constraint === "conversations_context_path_user_uniq") return true;
  if (
    typeof pgErr.details === "string" &&
    pgErr.details.includes("conversations_context_path_user_uniq")
  ) {
    return true;
  }
  return (
    typeof pgErr.message === "string" &&
    pgErr.message.includes("conversations_context_path_user_uniq")
  );
}

/**
 * Create a conversation row in the database and return its ID.
 *
 * When `contextPath` is set, a unique-index conflict on
 * (user_id, context_path) means another tab raced us — we look up the
 * existing row and return its id instead of duplicating.
 */
async function createConversation(
  userId: string,
  leaderId?: DomainLeaderId,
  id?: string,
  contextPath?: string,
  activeWorkflow?: string | null,
  // feat-wire-concierge-support-chat (ADR-113) — B2 repo-less support rows. A
  // "support" conversation is repo-INDEPENDENT: it carries `kind='support'` +
  // `repo_url=null`, is created even for a repo-less user (the repo-less throw
  // below is skipped), and stays out of the Command Center rail (which scopes by
  // repo_url). Default "command_center" preserves the existing behavior exactly.
  kind: "command_center" | "support" = "command_center",
): Promise<string> {
  if (!id) id = randomUUID();

  // Stamp the conversation with the user's CURRENT repo_url so Command
  // Center + context_path resume can scope by it. Users who disconnected
  // mid-session have repo_url=null; we abort rather than orphan the row
  // (plan risk R-D). See
  // 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
  //
  // Support conversations are repo-independent — never throw on a null repo_url,
  // and always persist repo_url=null so they never enter the repo-scoped rail.
  const repoUrl = await getCurrentRepoUrl(userId);
  if (!repoUrl && kind !== "support") {
    throw new Error(
      "No connected repository — conversation insert aborted (disconnect race).",
    );
  }
  const persistedRepoUrl = kind === "support" ? null : repoUrl;

  // PR-C §2.10 (#3244): tenant client. `getCurrentRepoUrl` above
  // already ran a tenant-scoped users read (Phase 2.6), so a failure
  // there would have returned null — repo_url check serves as a
  // de-facto auth probe. The explicit probe via `tenantFor` adds a
  // second JWT-mint check before the conversation INSERT to catch a
  // mid-handler jti revocation race.
  const tenant = await tenantFor(userId, "createConversation");
  if (!tenant) {
    throw new Error(
      "Tenant auth-probe failed — conversation insert aborted.",
    );
  }

  // Durable binding resolution (AC4, #5240): prefer the hot in-memory Map, then
  // rehydrate from `user_session_state.current_workspace_id` (reusing the
  // `tenant` client minted above for the conversation INSERT) on an empty Map —
  // the post-restart / pre-WS-open window that used to throw "No workspace
  // binding". The resolver throws fail-loud (and mirrors to Sentry) only when
  // the DB ALSO has no binding, preserving the abort semantics for the
  // genuinely-unbound case.
  const wsId = await resolveUserWorkspaceBinding(userId, (uid) =>
    readWorkspaceIdFromDb(uid, tenant),
  );

  // visibility-sweep-audit: INSERT — owner-scoped (user creates own conversation with workspace_id)
  const { error } = await tenant.from("conversations").insert({
    id,
    user_id: userId,
    workspace_id: wsId,
    repo_url: persistedRepoUrl,
    kind,
    domain_leader: leaderId ?? null,
    status: "active" as Conversation["status"],
    last_active: new Date().toISOString(),
    context_path: contextPath ?? null,
    ...(activeWorkflow !== undefined ? { active_workflow: activeWorkflow } : {}),
  });

  if (error) {
    // 23505 = unique_violation (postgres). When contextPath is set, this means
    // another tab created the same (user_id, repo_url, context_path) row — use
    // it instead. We disambiguate on the index name
    // (conversations_context_path_user_uniq) so an unrelated unique constraint
    // (e.g., conversations_pkey id collision) does NOT fall through into the
    // context_path lookup. See review #2390.
    if (contextPath && isContextPathUniqueViolation(error)) {
      // visibility-sweep-audit: owner-scoped — 23505 fallback resolves user's own duplicate
      const { data: existing, error: lookupErr } = await tenant
        .from("conversations")
        .select("id, active_workflow, context_path")
        .eq("user_id", userId)
        .eq("repo_url", repoUrl)
        .eq("context_path", contextPath)
        .is("archived_at", null)
        .order("last_active", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (lookupErr || !existing) {
        throw new Error(`Failed to resolve existing context_path conversation: ${lookupErr?.message ?? "not found"}`);
      }
      // data-integrity P1-B: on a two-tab race, the first writer wins
      // stickiness — if the second tab's intended `activeWorkflow`
      // disagrees with what the first tab persisted, the second tab's
      // choice is silently discarded. Mirror to Sentry per
      // `cq-silent-fallback-must-mirror-to-sentry` so the drop is
      // visible and observable. The authoritative row's routing still
      // gets returned (first-writer-wins is the correct UX — both tabs
      // converge on the same conversation history).
      const existingRow = existing as {
        id: string;
        active_workflow?: string | null;
        context_path?: string | null;
      };
      const existingWorkflow = existingRow.active_workflow ?? null;
      const intendedWorkflow = activeWorkflow ?? null;
      if (activeWorkflow !== undefined && existingWorkflow !== intendedWorkflow) {
        warnSilentFallback(
          new Error(
            "createConversation 23505 fallback: activeWorkflow diverged — first-writer-wins",
          ),
          {
            feature: "create-conversation",
            op: "23505-fallback-active-workflow",
            extra: {
              conversationId: existingRow.id,
              existingWorkflow,
              intendedWorkflow,
              userId,
            },
          },
        );
        log.warn(
          { conversationId: existingRow.id, existingWorkflow, intendedWorkflow },
          "23505 fallback: active_workflow diverged; second-tab choice discarded (first-writer-wins)",
        );
      }
      // Defense-in-depth: today the unique index is
      // `(user_id, repo_url, context_path)` so a 23505 collision means
      // both tabs supplied the SAME path — no divergence is reachable.
      // If a future schema change widens the index without including
      // `context_path`, divergence would silently leak the wrong path
      // into the second tab's session. Mirror so we see it before users
      // do (cq-silent-fallback-must-mirror-to-sentry).
      const existingContextPath = existingRow.context_path ?? null;
      if (existingContextPath !== (contextPath ?? null)) {
        warnSilentFallback(
          new Error(
            "createConversation 23505 fallback: context_path diverged — invariant assumed unreachable today",
          ),
          {
            feature: "create-conversation",
            op: "23505-fallback-context-path",
            extra: {
              conversationId: existingRow.id,
              existingContextPath,
              intendedContextPath: contextPath,
              userId,
            },
          },
        );
        log.warn(
          { conversationId: existingRow.id, existingContextPath, intendedContextPath: contextPath },
          "23505 fallback: context_path diverged; first-writer-wins — second-tab path silently discarded",
        );
      }
      return existingRow.id;
    }
    throw new Error(`Failed to create conversation: ${error.message}`);
  }

  return id;
}

/**
 * Stage 2.12: thin ws-handler adapter around `dispatchSoleurGo`. Wires
 * the `persistActiveWorkflow` callback to a `conversations.active_workflow`
 * UPDATE so the sticky-workflow detection in the runner writes through
 * to the DB.
 */
/**
 * Diagnostic breadcrumb for the cc-soleur-go cold-Query construction site.
 *
 * Fires for every cold-Query construction in `dispatchSoleurGoForConversation`
 * so two production reproductions of the #3287 poppler-utils install cascade
 * can disambiguate hypothesis A (PDF directive missed cold-Query construction)
 * from hypothesis B (directive present, model overrode it). The data payload
 * is PII-safe: no full path, no document content, no userId.
 *
 * Pairs with a `level: "warning"` `Sentry.captureMessage` ONLY when the
 * resolver was invoked (cold Query) AND a `context.path` was provided AND the
 * resolver dropped it (`documentKindResolved === null`). That branch is the
 * suspicious-skip case — a path arrived but never reached the directive — and
 * needs its own searchable Sentry event since breadcrumbs are scope-attached
 * (only surface when an event is sent in the same scope).
 *
 * Exported for unit testing; production call site is just below in
 * `dispatchSoleurGoForConversation`.
 */
export function emitConciergeDocumentResolutionBreadcrumb(args: {
  conversationId: string;
  contextPath: string | null | undefined;
  hasActiveCcQuery: boolean;
  documentArgs: Awaited<ReturnType<typeof resolveConciergeDocumentContext>>;
  routingKind: string;
}): void {
  const { conversationId, contextPath, hasActiveCcQuery, documentArgs, routingKind } = args;
  const path = typeof contextPath === "string" && contextPath.length > 0 ? contextPath : null;
  const basenameStr = path === null ? null : pathBasename(path);
  // Use lastIndexOf so a dotless basename (e.g., "Makefile") yields null —
  // not the whole filename — and `pathExtension` stays a clean enum-shaped
  // dimension in Sentry filters.
  const dot = basenameStr === null ? -1 : basenameStr.lastIndexOf(".");
  const extension = dot > 0 && basenameStr !== null
    ? basenameStr.slice(dot + 1).toLowerCase()
    : null;
  const documentKindResolved = documentArgs.documentKind ?? null;
  const documentContentBytes = documentArgs.documentContent?.length ?? 0;
  // 2026-05-06 follow-up — operators triaging "Concierge gave the apt-get
  // cascade" reach for THIS breadcrumb first (it sits at the resolution
  // boundary). Naming the typed extractor failure class here prevents the
  // ambiguity between "no path was sent" and "path was sent, parse failed
  // with class X" and lets a Sentry filter pivot directly to the user's
  // actual failure shape without crawling extractor breadcrumbs.
  const documentExtractError = documentArgs.documentExtractError ?? null;

  Sentry.addBreadcrumb({
    category: "cc-pdf-resolver",
    message: "concierge document context resolved",
    level: "info",
    data: {
      hasContextPath: path !== null,
      pathBasename: basenameStr,
      pathExtension: extension,
      hasActiveCcQuery,
      documentKindResolved,
      documentContentBytes,
      documentExtractError,
      conversationId,
      routingKind,
    },
  });

  // Suspicious-skip: cold Query (resolver was invoked) AND a path was sent
  // AND the resolver returned no documentKind. Warm turns deliberately skip
  // resolution and must NOT trigger this — that's the documented happy path.
  if (path !== null && !hasActiveCcQuery && documentKindResolved === null) {
    Sentry.captureMessage("cc-pdf-resolver-skip: path provided but resolver returned no documentKind", {
      level: "warning",
      tags: { feature: "cc-pdf-resolver", op: "skip" },
      extra: {
        conversationId,
        pathBasename: basenameStr,
        pathExtension: extension,
        routingKind,
      },
    });
  }
}

export async function dispatchSoleurGoForConversation(
  userId: string,
  conversationId: string,
  userMessage: string,
  routing: ConversationRouting,
  context?: ConversationContext,
  attachments?: import("@/lib/types").AttachmentRef[],
  sessionId?: string | null,
): Promise<void> {
  // feat-stream-since-disconnect (#5273) — turn boundary for the cc-soleur-go
  // path. The legacy fan-out wires resetTurn in `sendUserMessage`, but cc
  // conversations break before that call, so this is the symmetric site. (a)
  // `resetTurn` clears the prior turn's replay frames (counter preserved) so a
  // long never-disconnected cc conversation doesn't accumulate frames across
  // turns up to the ring cap. (b) `setActiveTurnConversation` binds the
  // conversation so the write-hook can key gap-emitted frames (cc never calls
  // `registerSession`, so without this the binding is undefined and frames
  // emitted during the disconnect grace window are silently dropped — the
  // feature's core scenario for the dominant conversation path). See ADR-059.
  streamReplayBuffer.resetTurn(conversationId);
  setActiveTurnConversation(userId, conversationId);
  const persistActiveWorkflow = async (workflow: WorkflowName | null) => {
    // data-integrity P1-A: never regress a soleur-go conversation back
    // to `legacy` via a `null` call — that silently breaks the
    // stickiness invariant (`conversation-routing.ts` docs) since the
    // next-turn `parseConversationRouting` would read `active_workflow
    // IS NULL` as legacy routing. The runner's sticky-detect path
    // never actually emits `null`, but defensive handling guards
    // against a future refactor widening the contract. Map `null`
    // back to the unrouted sentinel instead.
    const serialized = serializeConversationRouting(
      workflow === null
        ? { kind: "soleur_go_pending" }
        : { kind: "soleur_go_active", workflow },
    );
    // data-integrity P2-A: defense-in-depth — conversationId is already
    // server-derived, but the wrapper's `.eq("user_id", userId)` invariant
    // ensures a future refactor that accepts conversationId from a
    // less-trusted source cannot cross-write another user's row.
    const { ok, error } = await updateConversationFor(
      userId,
      conversationId,
      {
        active_workflow: serialized,
        last_active: new Date().toISOString(),
      },
      {
        feature: "ws-handler",
        op: "persist-active-workflow",
        extra: { workflow },
        expectMatch: true,
      },
    );
    if (!ok) {
      throw new Error(`active_workflow update failed: ${error?.message ?? "unknown"}`);
    }
    // Update the in-memory cache on the session so the next-turn
    // chat-case route lookup observes the new workflow without a DB
    // round-trip (performance P1-A).
    const liveSession = sessions.get(userId);
    if (liveSession) {
      liveSession.routing =
        workflow === null
          ? { kind: "soleur_go_pending" }
          : { kind: "soleur_go_active", workflow };
    }
  };

  // KB Concierge document context (regression fix). When the chat is
  // scoped to a KB document (PDF or text), inject the document into the
  // system prompt so the Concierge can answer questions about it instead
  // of replying that no document was attached. Mirrors the legacy
  // `agent-runner.ts § "Inject artifact context"` injection — see
  // `resolveConciergeDocumentContext` in cc-dispatcher for kind/path/
  // workspace-validation logic.
  //
  // Skip resolution when the runner already owns a live Query for this
  // conversation: the system prompt is baked at cold-Query construction
  // and reused across turns (streaming-input mode). Resolving on warm
  // turns wastes a Supabase RTT + 2 realpathSync + a 50KB readFile per
  // turn for bytes that never reach the LLM.
  // Bind the resolver's return shape directly so new fields
  // (`documentExtractError` etc.) flow through the spread at line 851
  // without a parallel literal type that drifts silently.
  let documentArgs: Awaited<
    ReturnType<typeof resolveConciergeDocumentContext>
  > = {};
  const warmCcQuery = hasActiveCcQuery(conversationId);
  if (context?.path && !warmCcQuery) {
    documentArgs = await resolveConciergeDocumentContext({
      userId,
      contextPath: context.path,
      providedContent: context.content ?? null,
    });
  }

  // 2026-05-06 Bug A1 fix — resolve workspacePath up-front when an
  // artifact directive is going to be built. `fetchUserWorkspacePath`
  // resolves the caller's ACTIVE workspace (ADR-044) — a single indexed
  // `user_session_state` read (the resolver above made the same call, but
  // the value is not cached, so this is an independent cheap resolve). For
  // warm turns or no-context dispatches, the runner skips system-prompt
  // construction entirely (the prompt is baked at cold construction), so a
  // missing workspacePath here is a no-op. On failure (DB transient error,
  // workspace not provisioned), fall through with undefined — the runner's
  // directive builder gracefully falls back to the relative path, which the
  // Bug A2 sandbox fix tolerates for in-workspace files.
  let workspacePath: string | undefined;
  if (context?.path && !warmCcQuery) {
    try {
      workspacePath = await fetchUserWorkspacePath(userId);
    } catch {
      // Resolver already mirrored to Sentry on the same failure mode;
      // skip a duplicate mirror here.
    }
  }

  // #3287 Phase 1 diagnostic — see helper JSDoc.
  emitConciergeDocumentResolutionBreadcrumb({
    conversationId,
    contextPath: context?.path ?? null,
    hasActiveCcQuery: warmCcQuery,
    documentArgs,
    routingKind: routing.kind,
  });

  try {
  await dispatchSoleurGo({
    userId,
    conversationId,
    userMessage,
    currentRouting: routing,
    sendToClient,
    persistActiveWorkflow,
    attachments,
    workspacePath,
    sessionId,
    // #3266 — refresh the in-process `ClientSession.sessionId` cache
    // alongside the DB write/clear so a subsequent chat-case warm-cache
    // turn forwards the just-persisted value. Without this, runner-reap-
    // while-WS-alive uses the stale seeded `null` on the next cold-Query
    // construction and the prefill guard's history-probe branch never
    // activates. Guards on `liveSession.conversationId === conversationId`
    // to avoid clobbering a value bound to a different conversation that
    // the user switched to mid-dispatch.
    onSessionIdPersisted: (nextSessionId) => {
      const liveSession = sessions.get(userId);
      if (liveSession && liveSession.conversationId === conversationId) {
        liveSession.sessionId = nextSessionId;
      }
    },
    // #5402 — routines "Draft a routine" tab mode flag. Derived from the
    // validated context.type; appends ROUTINE_AUTHORING_DIRECTIVE in
    // buildSoleurGoSystemPrompt. Document context (path/content) is unused
    // for this mode (it carries no path).
    routineAuthoring: context?.type === "routine-authoring",
    // feat-wire-concierge-support-chat (ADR-113) — resolve the persona from the
    // validated chat context. `"support"` (the in-app support chat) runs the
    // Concierge read-only with the repo-lifecycle gates bypassed and skills scoped
    // to kb-search; everything else is the Command Center default. REQUIRED — an
    // explicit value, never an implicit undefined.
    persona: context?.type === "support" ? "support" : "command_center",
    ...documentArgs,
  });
  } finally {
    // feat-stream-since-disconnect (#5273) — turn ended: drop the cc
    // active-turn binding (no-ops if a newer turn already repointed it). A
    // mid-turn disconnect keeps the binding alive (this finally hasn't run
    // while the turn is in flight), so gap frames are still buffered.
    clearActiveTurnConversation(userId, conversationId);
  }
}

// ---------------------------------------------------------------------------
// Mid-session T&C re-check (AC6/AC11, feat-oauth-tc-consent-3205)
// ---------------------------------------------------------------------------

/**
 * Inbound message types that must re-validate users.tc_accepted_version
 * mid-session. After a TC_VERSION bump (operator-initiated), the next
 * gated message on each live socket closes with 4004 TC_NOT_ACCEPTED.
 *
 * EXEMPT inbound types: `abort_turn`, `close_conversation`. RC8: a user
 * must always be able to stop a stream / close a conversation even with
 * stale consent — refusing those would worsen UX without changing GDPR
 * demonstrability.
 *
 * Server→client types (stream, tool_use, etc.) are rejected on inbound
 * by the ws-zod-schemas guard before reaching this point, so they need
 * no explicit listing.
 */
const TC_RECHECK_MESSAGE_TYPES = new Set([
  "start_session",
  "resume_session",
  "chat",
  "interactive_prompt_response",
  "review_gate_response",
]);

/**
 * Per-session cache window for the mid-session TC re-check. Bounds DB
 * load: at most one users.tc_accepted_version SELECT per gated message
 * per 30 s per user. Trade-off: up to 30 s of stale-consent traffic
 * after a TC_VERSION bump (plan AC6, accepted).
 */
export const TC_RECHECK_CACHE_MS = 30_000;

/**
 * Re-validate the user's tc_accepted_version against the current
 * `TC_VERSION` constant. Returns true if the socket was closed (caller
 * must return early). On stale consent, mismatch, or DB error: closes
 * with WS_CLOSE_CODES.TC_NOT_ACCEPTED (fail-closed — Art. 7(1)
 * demonstrability).
 *
 * Exported for test isolation; handleMessage invokes this above the
 * switch.
 */
export async function recheckTcMidSession(
  userId: string,
  session: ClientSession,
  msgType: WSMessage["type"],
): Promise<boolean> {
  if (!TC_RECHECK_MESSAGE_TYPES.has(msgType)) return false;

  // Fast-path: if the handshake baseline already disagrees with the current
  // TC_VERSION constant, close immediately — no DB round-trip needed. The
  // baseline is captured once at handshake (line ~1978) and reads the same
  // column the SELECT below would read; the only way they diverge is if
  // TC_VERSION was bumped mid-session, in which case the cached baseline is
  // authoritatively stale and we must close.
  if (
    session.tcVersionAtHandshake !== undefined &&
    session.tcVersionAtHandshake !== TC_VERSION
  ) {
    if (session.ws.readyState === WebSocket.OPEN) {
      session.ws.close(
        WS_CLOSE_CODES.TC_NOT_ACCEPTED,
        "T&C not accepted (mid-session)",
      );
    }
    return true;
  }

  const cacheUntil = session.tcRecheckCacheUntil ?? 0;
  if (cacheUntil && Date.now() < cacheUntil) return false;

  const { data: row, error } = await supabase
    .from("users")
    .select("tc_accepted_version")
    .eq("id", userId)
    .single();

  const rowTyped = row as { tc_accepted_version?: string | null } | null;

  if (error || rowTyped?.tc_accepted_version !== TC_VERSION) {
    // Sentry mirror on the DB-error branch so a Supabase outage during a
    // live WS session is observable (cq-silent-fallback-must-mirror-to-sentry).
    // The TC_VERSION-mismatch branch is expected and not an error — only
    // the `error` arm pages operations.
    if (error) {
      reportSilentFallback(error, {
        feature: "ws-handler",
        op: "tc_recheck_query_failed",
        message: "users.tc_accepted_version SELECT failed mid-session",
        extra: { userId, msgType },
      });
    }
    if (session.ws.readyState === WebSocket.OPEN) {
      session.ws.close(
        WS_CLOSE_CODES.TC_NOT_ACCEPTED,
        "T&C not accepted (mid-session)",
      );
    }
    return true;
  }

  session.tcRecheckCacheUntil = Date.now() + TC_RECHECK_CACHE_MS;
  return false;
}

// ---------------------------------------------------------------------------
// feat-stream-since-disconnect (#5273) — non-destructive reattach + replay.
//
// Handles a `resume_stream` control frame: a TRANSIENT reconnect within the
// disconnect grace window where the agent is STILL RUNNING. This is NOT
// `resume_session` — that aborts the live agent at its first line
// (`abortActiveSession`), which would kill the in-flight turn this feature
// exists to preserve. The reattach (`pendingDisconnects`-cancel) already
// rebound the socket without aborting; here we replay the gap's buffered
// frames, then live frames flow from the unaborted agent.
//
// Replay is gated AFTER the SAME ownership (`user_id`) + repo-scope checks the
// resume_session path uses, keyed on the VERIFIED `conv.id` (never the raw
// client-supplied conversationId). Correctness floor: never lie. On any
// failure (auth probe, ownership/repo mismatch, cursor evicted, second-tab
// slot steal) we emit `stream_replay{incomplete}` and the client falls back to
// the v1 honest persisted-history refetch. See ADR-059.
// ---------------------------------------------------------------------------

async function handleResumeStream(
  userId: string,
  session: ClientSession,
  msg: Extract<WSMessage, { type: "resume_stream" }>,
): Promise<void> {
  // Clamp the client-supplied cursor: negative/non-finite ⇒ -1 (whole tail).
  const ackSeq =
    typeof msg.ackSeq === "number" && Number.isFinite(msg.ackSeq) && msg.ackSeq >= 0
      ? Math.floor(msg.ackSeq)
      : -1;

  const fallback = (conversationId: string) =>
    sendToClient(userId, {
      type: "stream_replay",
      conversationId,
      status: "incomplete",
    });

  try {
    // Ownership + repo-scope re-verify — mirror resume_session (:1601-1632).
    const currentRepoUrl = await getCurrentRepoUrl(userId);
    const tenant = await tenantFor(userId, "handleMessage.resume-stream");
    if (!tenant) {
      // Auth probe failed — honest fallback, no replay (transient; retryable).
      fallback(msg.conversationId);
      return;
    }
    // visibility-sweep-audit: owner-scoped — WS replay binds to the user's own conversation.
    //
    // Deliberate asymmetry with the sibling `resume_session` lookup (which uses
    // .single()): here a zero-row result is a RECOVERABLE benign race (deferred-
    // creation — the row materializes lazily on the first chat message — or a
    // client reconnect before that write lands), NOT a user-facing error.
    // .maybeSingle() yields {data:null,error:null} for zero rows so we can
    // classify a genuine DB error (convErr) apart from not-materialized (!conv)
    // by SEVERITY. Do NOT "consistency-fix" this back to .single() — that
    // re-conflates PGRST116 into convErr and recreates the error-level flood
    // (#5290 / ADR-059 false-positive; see plan
    // fix-stream-replay-ownership-mismatch-false-positive).
    const { data: conv, error: convErr } = await tenant
      .from("conversations")
      .select("id, repo_url")
      .eq("id", msg.conversationId)
      .eq("user_id", userId)
      .maybeSingle();
    if (convErr) {
      // Genuine DB/transport error (outage, connection drop, PostgREST shape
      // error) — stays LOUD at error level. NOTE: an RLS *row*-denial does NOT
      // land here: `conversations` visibility is enforced by RLS policies while
      // `authenticated` holds the table SELECT grant, so a row owned by another
      // user returns ZERO ROWS (→ the `!conv` branch below), never SQLSTATE
      // 42501. The pg_code tag (observability helper) keeps SQLSTATE queryable
      // for the genuine DB error classes that DO surface here.
      reportSilentFallback(convErr, {
        feature: "stream-replay",
        op: "ownership-mismatch",
        message: "resume_stream: conversation not found or not owned",
        extra: { userId, conversationId: msg.conversationId, cause: "db-error" },
      });
      fallback(msg.conversationId);
      return;
    }
    if (!conv) {
      // Row absent. Post the Phase-2 client gate (resume_stream is only sent for
      // sessionKind==="resumed"), the benign deferred-not-yet-materialized race
      // dominates this branch — WARNING, not error. A genuine cross-user
      // conversationId also returns !conv via the .eq("user_id", userId) filter
      // (indistinguishable here without a privileged query), so this stays
      // OBSERVABLE (not silenced); the owned-by-another enumeration is deferred
      // behind the AC14 warning-volume-drop criterion.
      warnSilentFallback(
        new Error("resume_stream: conversation not found or not owned"),
        {
          feature: "stream-replay",
          op: "ownership-mismatch",
          message: "resume_stream: conversation not found or not owned",
          extra: {
            userId,
            conversationId: msg.conversationId,
            cause: "not-materialized",
          },
        },
      );
      fallback(msg.conversationId);
      return;
    }
    const verifiedConvId = (conv as { id: string }).id;
    const convRepoUrl = (conv as { repo_url?: string | null }).repo_url ?? null;
    if (currentRepoUrl === null) {
      // getCurrentRepoUrl returns null for TWO reasons (see its docstring): a
      // transient resolve failure (tenant-mint blip / workspaces query error)
      // OR a workspace that genuinely has no repo connected. Neither is a
      // repo-scope mismatch, and replaying into a repo-less / unresolvable
      // workspace would be unsound — so fail closed to an honest fallback. No
      // handler-side emit: the transient-error paths ALREADY mirror upstream
      // (feature=repo-scope, current-repo-url.ts) before returning null, so
      // re-mirroring here would double-count; the repo-less case is not a
      // degradation worth an event.
      fallback(verifiedConvId);
      return;
    }
    if (convRepoUrl !== currentRepoUrl) {
      // Genuine cross-repo stale cursor (currentRepoUrl is non-null here, so
      // both sides are real and differ) — stays LOUD at error level.
      reportSilentFallback(new Error("resume_stream: repo-scope mismatch"), {
        feature: "stream-replay",
        op: "repo-scope-mismatch",
        message: "resume_stream: repo-scope mismatch",
        extra: { userId, conversationId: verifiedConvId, cause: "url-differs" },
      });
      fallback(verifiedConvId);
      return;
    }
    // Single-session-per-userId: if a second tab took the slot for a DIFFERENT
    // conversation, do not interleave two conversations' streams — fall back.
    if (session.conversationId && session.conversationId !== verifiedConvId) {
      fallback(verifiedConvId);
      return;
    }

    const { frames, status } = streamReplayBuffer.replayFrom(verifiedConvId, ackSeq);
    if (status === "incomplete") {
      // Expected/informational (cap too low or buffer reclaimed) — warn, not error.
      warnSilentFallback(
        new Error("stream-replay cursor evicted or buffer cleared"),
        {
          feature: "stream-replay",
          op: "cursor-evicted",
          extra: { userId, conversationId: verifiedConvId, ackSeq },
        },
      );
      fallback(verifiedConvId);
      return;
    }
    // Complete: re-emit buffered frames verbatim, in order, with their stamped
    // `seq` intact (the sendToClient write-hook skips re-stamping frames that
    // already carry `seq`). The client dedups any `seq <= lastRenderedSeq`.
    // Live frames then resume from the still-running agent.
    for (const frame of frames) {
      sendToClient(userId, frame);
    }
  } catch (err) {
    Sentry.captureException(err);
    log.error(
      { userId, conversationId: msg.conversationId, err },
      "resume_stream error",
    );
    fallback(msg.conversationId);
  }
}

// ---------------------------------------------------------------------------
// Message router
// ---------------------------------------------------------------------------

export async function handleMessage(userId: string, raw: string): Promise<void> {
  let msg: WSMessage;

  try {
    msg = JSON.parse(raw) as WSMessage;
  } catch {
    sendToClient(userId, { type: "error", message: "Invalid JSON" });
    return;
  }

  const session = sessions.get(userId);
  if (!session) {
    log.warn({ userId }, "No session found — message dropped");
    return;
  }

  log.debug({ userId, msgType: msg.type }, "Message received");

  // Mid-session T&C re-check. Closes the socket on stale consent or DB
  // error for gated types only (see TC_RECHECK_MESSAGE_TYPES). Exempt
  // types (abort_turn, close_conversation) pass through unchanged.
  if (await recheckTcMidSession(userId, session, msg.type)) {
    return;
  }

  switch (msg.type) {
    // ------------------------------------------------------------------
    // start_session: create conversation, boot agent, reply with ID
    // ------------------------------------------------------------------
    case "start_session": {
      // Layer 3: Agent session creation rate limit (per-user, post-auth).
      // INVARIANT (workspace-scoping audit, 2026-06-02): the throttle key is
      // the USER, not the active workspace, and MUST stay per-user. The cap is
      // coupled to the per-user plan_tier / concurrency_override model
      // (user_concurrency_slots, mig 029) and the per-user Stripe subscription.
      // Keying it per-workspace would let one user multiply paid capacity by
      // creating workspaces. Per-workspace caps require a per-workspace billing
      // model first (deferred — see plan 2026-06-02-fix-workspace-scoping-leak D6).
      if (!sessionThrottle.isAllowed(userId)) {
        logRateLimitRejection("session-limit", userId);
        sendToClient(userId, {
          type: "error",
          message: sanitizeErrorForClient(
            new Error("Rate limited: too many sessions"),
          ),
          errorCode: "rate_limited",
        });
        return;
      }

      // soleur-go path applies an additional per-user + per-IP
      // sliding-window limiter (10/user/hour, 30/IP/hour) on top of the
      // legacy `sessionThrottle` above. Fail-closed at either cap. As
      // of #3270 (FLAG_CC_SOLEUR_GO retired) this runs unconditionally
      // for every `start_session` — cc-soleur-go is the only path.
      // security P2: use userId as the per-IP fallback when no IP was
      // captured. Falling back to a literal string like `"unknown"`
      // collides every IP-missing user into one 30/hr bucket — a
      // trivial DoS pivot if a proxy misconfiguration ever strips
      // headers. Using userId preserves per-user isolation; the
      // per-user cap still applies above it.
      const rateLimitIp = session.ip && session.ip.length > 0 ? session.ip : userId;
      const rate = getCcStartSessionRateLimiter().check({
        userId,
        ip: rateLimitIp,
      });
      if (!rate.allowed) {
        logRateLimitRejection(`cc-${rate.reason}`, userId, {
          ip: session.ip,
          ipFallback: session.ip === rateLimitIp ? undefined : "userId",
          retryAfterMs: rate.retryAfterMs,
        });
        sendToClient(userId, {
          type: "error",
          message: "Rate limited: too many conversations this hour.",
          errorCode: "rate_limited",
        });
        return;
      }
      const initialRouting: ConversationRouting = { kind: "soleur_go_pending" };

      try {
        // Validate context payload before any side effects
        let validatedContext: ConversationContext | undefined;
        try {
          validatedContext = validateConversationContext(msg.context);
        } catch (validationErr) {
          sendToClient(userId, {
            type: "error",
            message: (validationErr as Error).message,
          });
          return;
        }

        abortActiveSession(userId, session);

        // Reject invalid resumeByContextPath up-front — see review #2381.
        // The field was previously passed straight into `.eq()` with no
        // typeof/length/prefix guard, opening DoS + type-confusion surfaces.
        let validResumePath: string | null = null;
        if (msg.resumeByContextPath !== undefined && msg.resumeByContextPath !== null) {
          validResumePath = validateContextPath(msg.resumeByContextPath);
          if (!validResumePath) {
            sendToClient(userId, {
              type: "error",
              message: "Invalid resumeByContextPath",
            });
            return;
          }
        }

        // Cross-tab session supersession (#2391): `sessions` is keyed by
        // userId, not by (userId, context_path). Opening tab B with a
        // resumeByContextPath will close tab A's socket via the auth-success
        // path (search `WS_CLOSE_CODES.SUPERSEDED` in this file). Per-doc
        // context_path resumption does NOT grant two tabs independent live
        // streams; it only resolves the *persisted* conversation row so the
        // new tab shows the right history. A user-visible "another tab took
        // over" banner is tracked as a separate feature follow-up, not a
        // review-backlog drain.
        //
        // If client asked to resume by context_path (KB sidebar), look up
        // existing thread before deferring creation. The UNIQUE partial
        // index on (user_id, repo_url, context_path) now scopes by the
        // connected repo — we must filter the lookup by repo_url too, or
        // the same path in a previously-connected repo resumes a stale
        // thread. If the user is disconnected, skip resume entirely and
        // fall through to deferred creation (which aborts on null
        // repo_url — see createConversation). See plan
        // 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
        const currentRepoUrl = await getCurrentRepoUrl(userId);
        if (validResumePath && currentRepoUrl) {
          // PR-C §2.10 (#3244): tenant-scoped resume-by-context-path
          // lookup. RLS on `conversations` + FK-RLS on `messages`.
          const tenantResume = await tenantFor(
            userId,
            "handleMessage.start_session.resume",
          );
          if (!tenantResume) {
            sendToClient(userId, {
              type: "error",
              message: "Auth probe failed — please retry.",
            });
            return;
          }
          // visibility-sweep-audit: owner-scoped — WS resume creates a session bound to the user's own conversation
          const { data: existing, error: lookupErr } = await tenantResume
            .from("conversations")
            .select("id, last_active, context_path")
            .eq("user_id", userId)
            .eq("repo_url", currentRepoUrl)
            .eq("context_path", validResumePath)
            .is("archived_at", null)
            .order("last_active", { ascending: false })
            .limit(1)
            .maybeSingle();

          if (!lookupErr && existing) {
            const row = existing as { id: string; last_active: string };
            const { count: messageCount, error: countErr } = await tenantResume
              .from("messages")
              .select("id", { count: "exact", head: true })
              .eq("conversation_id", row.id);

            session.conversationId = row.id;
            session.pending = undefined;
            resetIdleTimer(userId, session);

            sendToClient(userId, {
              type: "session_resumed",
              conversationId: row.id,
              resumedFromTimestamp: row.last_active,
              messageCount: countErr ? 0 : (messageCount ?? 0),
            });

            log.info({ userId, conversationId: row.id }, "start_session resumed by context_path");
            break;
          }
        }

        // Defer conversation creation: generate UUID but don't insert into DB.
        // The row is created on the first real chat message.
        const pendingId = randomUUID();

        // Resolve the session-active workspace. The slot's workspace_id (NOT
        // NULL since mig 059) must match the conversation's workspace_id, which
        // createConversation also resolves via resolveUserWorkspaceBinding:
        // both read the same source-of-truth column (`current_workspace_id`),
        // so within one connection they read the same value (the Map-writeback
        // makes the later read a hot hit). They can still differ only if the
        // user switches active workspace BETWEEN start_session and the first
        // chat message — the same pre-existing mid-session-switch behavior the
        // process-local Map already had, not a regression introduced here.
        // Durable binding resolution (AC4, #5240): prefer the hot Map, then
        // rehydrate from `user_session_state.current_workspace_id` on an empty
        // Map (post-restart / pre-WS-open) instead of throwing. The resolver
        // fails loud (throw + Sentry) only when the DB ALSO has no binding —
        // a null p_workspace_id would re-trigger the 23502 this path closes.
        //
        // The tenant client for the durable read is minted LAZILY inside the
        // closure: on the hot path (Map warm) the closure never runs, so this
        // adds zero tenantFor/DB cost (AC4 hot-path-identical). The resume-path
        // tenant client is block-scoped to the resume branch above and is out
        // of scope here, so the closure mints its own tenant.
        const slotWorkspaceId = await resolveUserWorkspaceBinding(
          userId,
          async (uid) => {
            const tenantSlot = await tenantFor(
              uid,
              "handleMessage.slot-workspace-resolve",
            );
            if (!tenantSlot) {
              throw new Error(
                "Tenant auth-probe failed — slot workspace resolve aborted.",
              );
            }
            return readWorkspaceIdFromDb(uid, tenantSlot);
          },
        );

        // Plan-based concurrency gate. Acquire a slot keyed on (userId,
        // pendingId). A cap_hit result denies before we mutate any session
        // state so the client can present the upgrade modal without the
        // confusion of a session_started that never got a response.
        const cap = effectiveCap(session.planTier, session.concurrencyOverride);
        let acquire = await acquireSlot(userId, pendingId, cap, slotWorkspaceId);

        if (acquire.status === "cap_hit" && session.stripeSubscriptionId) {
          // Webhook-lag fallback: ask Stripe directly. If the live tier
          // grants a higher cap than the cached plan_tier, re-sync BOTH
          // planTier and concurrencyOverride from the DB (the override may
          // have been adjusted out-of-band) and retry acquire once with the
          // fresh cap. Previously only planTier was mutated; a stale
          // concurrencyOverride could over- or under-grant capacity relative
          // to the live tier. Failure here is silent — we fall through to
          // the cap_hit branch below.
          try {
            const live = await retrieveSubscriptionTier(userId, session.stripeSubscriptionId);
            // Re-read override from DB so session state matches what the
            // cap calculation assumes.
            // PR-C §2.10 (#3244): tenant-scoped re-read of override.
            // Webhook-lag fallback path — fail-open if probe fails
            // (rare; user just hits the original cap_hit branch).
            const tenantCapDrift = await tenantFor(
              userId,
              "handleMessage.cap-drift-fallback",
            );
            const { data: userRow } = tenantCapDrift
              ? await tenantCapDrift
                  .from("users")
                  .select("concurrency_override")
                  .eq("id", userId)
                  .maybeSingle()
              : { data: null };
            const freshOverride = (userRow as { concurrency_override?: number | null } | null)?.concurrency_override ?? null;
            const liveCap = effectiveCap(live.tier, freshOverride);
            if (liveCap > cap) {
              session.planTier = live.tier;
              session.concurrencyOverride = freshOverride;
              acquire = await acquireSlot(userId, pendingId, liveCap, slotWorkspaceId);
            }
          } catch (liveErr) {
            Sentry.captureException(liveErr);
          }
        }

        // Self-healing ledger-divergence recovery (#stuck-active fix, AC4).
        // Run BEFORE the existing cap_hit close path. If the slot ledger
        // has orphan rows (slot present, conversation invisible/missing),
        // release the orphans and retry acquire once. If the retry still
        // returns cap_hit, fall through to the genuine cap-deny close
        // path unchanged — DO NOT recurse.
        // non-recursive by construction; do not refactor into a loop
        if (acquire.status === "cap_hit") {
          const recovered = await tryLedgerDivergenceRecovery(userId);
          if (recovered.didRecover) {
            const cap = effectiveCap(session.planTier, session.concurrencyOverride);
            acquire = await acquireSlot(userId, pendingId, cap, slotWorkspaceId);
          }
        }

        if (acquire.status === "cap_hit" || acquire.status === "error") {
          // Emit telemetry at the deny site (plan Phase 9).
          emitConcurrencyCapHit({
            tier: session.planTier ?? "free",
            active_conversation_count: acquire.activeCount,
            effective_cap: acquire.effectiveCap,
            path: "start_session",
            action: "abandoned",
          });
          closeWithPreamble(session.ws, WS_CLOSE_CODES.CONCURRENCY_CAP, {
            type: "concurrency_cap_hit",
            currentTier: session.planTier,
            nextTier: nextTier(session.planTier ?? "free"),
            activeCount: acquire.activeCount,
            effectiveCap: acquire.effectiveCap,
          });
          return;
        }

        session.pending = {
          id: pendingId,
          leaderId: msg.leaderId,
          context: validatedContext,
          contextPath: validResumePath ?? undefined,
          routing: initialRouting,
        };
        session.conversationId = undefined;

        log.info(
          {
            userId,
            leaderId: msg.leaderId ?? "auto-route",
            pendingId,
            contextPath: validResumePath,
            routingKind: initialRouting.kind,
          },
          "start_session (deferred creation)",
        );

        sendToClient(userId, {
          type: "session_started",
          conversationId: session.pending.id,
          capabilities: WS_CAPABILITIES,
        });
        resetIdleTimer(userId, session);
        log.debug("session_started sent to client");
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "start_session error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // resume_session: reconnect to an existing conversation
    // ------------------------------------------------------------------
    case "resume_session": {
      try {
        if (checkSubscriptionSuspended(userId, session)) return;

        abortActiveSession(userId, session);
        // Clear any pending deferred state — resuming an existing conversation
        session.pending = undefined;

        // Verify conversation ownership AND repo scope. A cached id from a
        // previously-connected repo must NOT resume across a repo swap —
        // the Command Center hides it, the MCP lookup tool refuses to
        // surface it, and this path is the last remaining backdoor. See
        // plan 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
        const currentRepoUrl = await getCurrentRepoUrl(userId);
        // PR-C §2.10 (#3244): tenant-scoped conversation ownership
        // check. RLS on `conversations` is the primary control; the
        // explicit `.eq("user_id", userId)` filter is belt-and-suspenders.
        const tenantResumeConv = await tenantFor(
          userId,
          "handleMessage.resume-by-id",
        );
        if (!tenantResumeConv) {
          sendToClient(userId, {
            type: "error",
            message: "Auth probe failed — please retry.",
          });
          return;
        }
        // visibility-sweep-audit: owner-scoped — WS resume-by-id binds a session to the user's own conversation
        const convQuery = tenantResumeConv
          .from("conversations")
          .select("id, status, repo_url, workspace_id")
          .eq("id", msg.conversationId)
          .eq("user_id", userId);
        const { data: conv, error: convErr } = await convQuery.single();

        if (convErr || !conv) {
          sendToClient(userId, { type: "error", message: "Conversation not found" });
          return;
        }

        const convRepoUrl = (conv as { repo_url?: string | null }).repo_url ?? null;
        if (convRepoUrl !== currentRepoUrl) {
          // Could be cross-repo resume attempt OR a disconnected user. Keep
          // the response indistinguishable from "not found" so callers
          // can't probe for existence of cross-repo threads.
          sendToClient(userId, { type: "error", message: "Conversation not found" });
          return;
        }

        // FR1 (#5240) — re-align the agent cwd resolver with the
        // conversation's own workspace on resume. `resolveCurrentWorkspaceId`
        // reads `user_session_state.current_workspace_id` (falling back to the
        // solo `userId`); nobody re-aligns it on reconnect, so a resumed turn
        // resolves the stale solo workspace and the agent reports "nothing to
        // resume from" over intact work. We write the resolver's field via the
        // existing membership-checked switch (mirrors accept-invite/route.ts)
        // — NOT the in-memory `userWorkspaces` map, which the cwd resolver
        // ignores (R1). Run this BEFORE mutating session state so a switch
        // failure throws into the terminal catch (honest client error, no
        // silent solo-fallback per Observability fail_loud) rather than leaving
        // the session half-bound. (The prior-session teardown at the top of
        // this case already ran, by design — a failed rebind degrades to an
        // honest, retryable error on a fresh resume, not corruption.) Reuses
        // the switch's own ordering, so it cannot race a concurrent
        // `set_current_workspace_id` (R4).
        //
        // Defensive: `conversations.workspace_id` is NOT NULL (migration 059),
        // so the `?? null` guard below is a select/schema-drift tripwire, not a
        // live path — it fires loud (never silent) if the `.select()` and the
        // column constraint ever drift apart.
        const resumeWorkspaceId =
          (conv as { workspace_id?: string | null }).workspace_id ?? null;
        if (!resumeWorkspaceId) {
          reportSilentFallback(
            new Error("conversations.workspace_id null/absent on resume"),
            {
              feature: "session-resume",
              op: "resume-workspace-rebind",
              extra: { userId, conversationId: msg.conversationId },
            },
          );
          throw new Error(
            "resume-workspace-rebind: conversation workspace_id missing",
          );
        }
        const { error: switchErr } = await tenantResumeConv.rpc(
          "set_current_workspace_id",
          { p_workspace_id: resumeWorkspaceId },
        );
        if (switchErr) {
          reportSilentFallback(
            { code: switchErr.code, message: switchErr.message },
            {
              feature: "session-resume",
              op: "resume-workspace-rebind",
              message: `set_current_workspace_id on resume failed: ${switchErr.message}`,
              extra: { userId, conversationId: msg.conversationId },
            },
          );
          throw new Error(
            `resume-workspace-rebind failed: ${switchErr.message}`,
          );
        }

        // #5275 — restore the conversation's in-flight checkpoint (uncommitted
        // work preserved when a prior turn grace-aborted on disconnect) into the
        // SAME physical workspace. Runs AFTER the FR1 rebind succeeds (the
        // workspace path resolved below is correct only now) and BEFORE
        // `session_started`. Gated restore: it materializes only when doing so
        // provably cannot overwrite newer work (clean tree + no sibling slot),
        // else it refuses-and-reports honestly (the work stays at the ref). A
        // materialization failure AFTER the precondition passes throws here and
        // propagates to the terminal catch below (honest, retryable client
        // error) — never a silent path.
        {
          const restoreWorkspacePath =
            workspacePathForWorkspaceId(resumeWorkspaceId);
          // Probe for a LIVE sibling conversation slot on the SAME shared clone
          // — for EVERY resume, including solo (`workspace_id === userId`). Solo
          // is NOT single-tenant-at-rest: per-user concurrency can be >1 (free=1
          // but solo=2 / startup=5 / scale=50), so a solo user with two tabs
          // shares one working tree. A checkpoint taken by one tab can carry the
          // OTHER tab's in-flight edits (the wide path predicate snapshots the
          // whole dirty tree); restoring it over a now-clean tree would clobber
          // the sibling. The clean-tree gate proves "nothing uncommitted to
          // lose" but NOT "this snapshot belongs to this conversation" — the slot
          // probe is what supplies the latter. Liveness-filtered: stale slots are
          // swept lazily / by pg_cron but NOT on this read path. Uses the shared
          // SLOT_STALENESS_THRESHOLD_SECONDS (240 s) so this snapshot-restore gate
          // reads the same liveness window as the 240 s reaper (mig 133).
          let siblingSlotActive = false;
          const liveCutoff = new Date(
            Date.now() - SLOT_STALENESS_THRESHOLD_SECONDS * 1_000,
          ).toISOString();
          const { data: siblingSlots, error: slotErr } = await tenantResumeConv
            .from("user_concurrency_slots")
            .select("conversation_id")
            .eq("workspace_id", resumeWorkspaceId)
            .neq("conversation_id", msg.conversationId)
            .gte("last_heartbeat_at", liveCutoff);
          if (slotErr) {
            // Fail SAFE: an unreadable slot table means we cannot prove the tree
            // is sole-tenant, so treat a sibling as present (refuse the restore
            // rather than risk clobbering a teammate's / sibling tab's work).
            siblingSlotActive = true;
            reportSilentFallback(
              { code: slotErr.code, message: slotErr.message },
              {
                feature: "inflight-checkpoint",
                op: "restore-slot-probe",
                extra: { userId, conversationId: msg.conversationId },
              },
            );
          } else {
            siblingSlotActive = (siblingSlots?.length ?? 0) > 0;
          }

          const restoreResult = await restoreInflightCheckpoint(
            restoreWorkspacePath,
            msg.conversationId,
            { siblingSlotActive },
          );
          if (
            !restoreResult.restored &&
            (restoreResult.reason === "dirty" ||
              restoreResult.reason === "sibling-active" ||
              restoreResult.reason === "stale-base")
          ) {
            // Honest refuse-and-report: reuse the FR1 honest-status surface
            // (an `error`-family frame carrying human copy — the
            // `worktree_enter_failed` precedent uses this for non-fatal
            // lifecycle messages). The resume still succeeds (session_started
            // fires below); the user is told their earlier work is saved, not
            // lost or silently overwritten.
            sendToClient(userId, {
              type: "error",
              message: CHECKPOINT_REFUSED_MESSAGE,
            });
          }
        }

        session.conversationId = msg.conversationId;
        // Resuming a different conversation — invalidate the routing,
        // KB context, and session_id caches so the first chat-turn
        // re-reads `active_workflow`, `context_path`, and `session_id`.
        // The three caches share the same lifecycle invariant: invalidate
        // together.
        session.routing = undefined;
        session.contextPath = undefined;
        session.sessionId = undefined;
        resetIdleTimer(userId, session);
        sendToClient(userId, {
          type: "session_started",
          conversationId: msg.conversationId,
          capabilities: WS_CAPABILITIES,
        });
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "resume_session error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // close_conversation: explicitly end the current conversation
    // ------------------------------------------------------------------
    case "close_conversation": {
      // Handle pending state (conversation never created in DB)
      if (!session.conversationId && session.pending) {
        const pendingId = session.pending.id;
        session.pending = undefined;
        void releaseSlot(userId, pendingId);
        sendToClient(userId, { type: "session_ended", reason: "closed" });
        break;
      }

      if (!session.conversationId) {
        sendToClient(userId, {
          type: "error",
          message: "No active session.",
        });
        return;
      }

      try {
        const convId = session.conversationId;
        abortSession(userId, convId, "superseded");
        // feat-stream-since-disconnect (#5273) — explicit close: drop replay
        // frames (counter preserved). No reconnect-replay for a closed
        // conversation. See ADR-059.
        streamReplayBuffer.clear(convId);
        await updateConversationFor(
          userId,
          convId,
          { status: "completed", last_active: new Date().toISOString() },
          { feature: "ws-handler", op: "close-conversation", expectMatch: true },
        );
        session.conversationId = undefined;
        session.routing = undefined;
        session.contextPath = undefined;
        session.sessionId = undefined;
        void releaseSlot(userId, convId);
        sendToClient(userId, { type: "session_ended", reason: "closed" });
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "close_conversation error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // chat: forward user message into the running agent session
    // ------------------------------------------------------------------
    case "chat": {
      if (checkSubscriptionSuspended(userId, session)) return;

      if (!session.conversationId && !session.pending) {
        sendToClient(userId, {
          type: "error",
          message: "No active session. Send start_session first.",
        });
        return;
      }

      // Server-side attachment cap
      if (msg.attachments && msg.attachments.length > 5) {
        sendToClient(userId, {
          type: "error",
          message: "Too many files",
          errorCode: "too_many_files",
        });
        return;
      }

      // Strip `[Image #N]` SDK-CLI placeholders from inbound text. The
      // placeholders mean image bytes were already dropped upstream;
      // letting them through would persist the broken artifact to
      // `messages.content` and re-inject it into every LLM replay.
      // Surfaces a non-blocking `image_paste_lost` error to the client.
      const userContent = stripAndReportImagePlaceholders(msg.content, {
        userId,
        conversationId: session.conversationId ?? null,
        send: (m) => sendToClient(userId, m),
      });

      // User activity resets idle timer
      resetIdleTimer(userId, session);

      // Materialize pending conversation on first real message
      if (!session.conversationId && session.pending) {
        const stripped = userContent.replace(/@\w+\s*/g, "").trim();
        if (!stripped) {
          sendToClient(userId, {
            type: "error",
            message: "Please include a message along with the @-mention.",
          });
          return;
        }

        try {
          const {
            id: pendingId,
            leaderId: pendingLeader,
            context: pendingContext,
            contextPath: pendingContextPath,
            routing: pendingRouting,
          } = session.pending;
          // Stage 2.12 — persist active_workflow at creation time when the
          // soleur-go flag was on at start_session. The sentinel is
          // consumed on first dispatch via persistActiveWorkflow.
          const initialActiveWorkflow: string | null | undefined = pendingRouting
            ? serializeConversationRouting(pendingRouting)
            : undefined;
          // createConversation handles unique-violation on (user_id, context_path)
          // by resolving to the existing row (two-tab race).
          const resolvedId = await createConversation(
            userId,
            pendingLeader,
            pendingId,
            pendingContextPath,
            initialActiveWorkflow,
            // feat-wire-concierge-support-chat — a support-context session
            // materializes a repo-less kind='support' conversation (never throws
            // on a missing repo; the repo-less support user is exactly who needs help).
            pendingContext?.type === "support" ? "support" : "command_center",
          );
          session.conversationId = resolvedId;
          session.pending = undefined;
          // Seed the routing cache so chat-case on subsequent turns
          // can skip the DB lookup (performance P1-A).
          session.routing = pendingRouting;
          // Seed the KB context path so chat-case follow-up turns can
          // rebuild a synthetic ConversationContext for the soleur-go
          // path (otherwise turn 2+ loses document context).
          session.contextPath = pendingContextPath ?? null;

          log.info(
            {
              conversationId: session.conversationId,
              leaderId: pendingLeader ?? "auto-route",
              routingKind: pendingRouting?.kind,
            },
            "Conversation materialized on first message",
          );

          // Stage 2.12 branch: soleur-go routing bypasses the legacy agent
          // path entirely. The soleur-go runner owns its own Query
          // lifecycle + canUseTool + sandbox.
          if (pendingRouting && pendingRouting.kind !== "legacy") {
            // First-message branch: conversation was just inserted by
            // `createConversation`; persisted `session_id` is always null
            // until the runner emits the first `result`. Pass `null`
            // explicitly so the dispatch signature stays uniform.
            session.sessionId = null;
            await dispatchSoleurGoForConversation(
              userId,
              session.conversationId,
              userContent,
              pendingRouting,
              pendingContext,
              msg.attachments,
              null,
            );
            break;
          }

          // Legacy path unchanged: boot agent for directed sessions now
          // that conversation exists.
          if (pendingLeader) {
            startAgentSession(userId, session.conversationId, pendingLeader, undefined, undefined, pendingContext).catch(
              (err) => {
                Sentry.captureException(err);
                log.error({ userId, err }, "startAgentSession error");
                const errorCode: WSErrorCode | undefined = err instanceof KeyInvalidError
                  ? "key_invalid"
                  : err instanceof ByokDelegationError
                    ? `delegation_${err.reason}` as WSErrorCode
                    : undefined;
                sendToClient(userId, {
                  type: "error",
                  message: sanitizeErrorForClient(err),
                  errorCode,
                });
              },
            );
          }

          // sendUserMessage handles saveMessage internally — do not double-save
          await sendUserMessage(
            userId,
            session.conversationId,
            userContent,
            pendingContext,
            msg.attachments,
          );
        } catch (err) {
          Sentry.captureException(err);
          log.error({ userId, err }, "chat error (deferred creation)");
          const deferredErrorCode: WSErrorCode | undefined = err instanceof ByokDelegationError
            ? `delegation_${err.reason}` as WSErrorCode
            : undefined;
          sendToClient(userId, {
            type: "error",
            message: sanitizeErrorForClient(err),
            errorCode: deferredErrorCode,
          });
        }
        break;
      }

      try {
        // Stage 2.12 — route each turn via `parseConversationRouting`.
        // Legacy rows (NULL) flow through the existing agent-runner;
        // sentinel + workflow values dispatch to the soleur-go runner.
        //
        // performance P1-A: routing is cached on `session.routing`
        // after materialization and refreshed by `persistActiveWorkflow`.
        // Only read from DB on cache miss (reconnect, resume_session,
        // etc.). The single-source-of-truth invariant holds because
        // nothing outside this process mutates `active_workflow` in V1
        // (the runner singleton is process-local).
        const convId = session.conversationId!;
        let routing: ConversationRouting;
        if (
          session.routing &&
          session.contextPath !== undefined &&
          session.sessionId !== undefined
        ) {
          routing = session.routing;
        } else {
          // PR-C §2.10 (#3244): tenant-scoped routing lookup. RLS
          // ensures `conv.user_id = auth.uid()` — the convId comes
          // from session-state populated by an earlier authenticated
          // flow, so RLS denial here would be a corrupted-state path.
          // On auth-probe failure, surface as `routeErr` so the
          // existing Sentry+log+legacy-fallback path handles it.
          const tenantRoute = await tenantFor(
            userId,
            "handleMessage.chat.routing-lookup",
          );
          if (!tenantRoute) {
            sendToClient(userId, {
              type: "error",
              message: "Auth probe failed — please retry.",
            });
            return;
          }
          // visibility-sweep-audit: owner-scoped via RLS (no explicit user_id filter but tenant JWT scopes to auth.uid())
          const { data: row, error: routeErr } = await tenantRoute
            .from("conversations")
            .select("active_workflow, session_id, context_path")
            .eq("id", convId)
            .single();
          if (routeErr) {
            // Route lookup failure is NOT a silent drop — mirror +
            // legacy fallback keeps chat flowing rather than blocking
            // on a transient DB blip.
            Sentry.captureException(routeErr);
            log.error(
              { userId, conversationId: convId, err: routeErr },
              "chat routing lookup failed (falling through to legacy)",
            );
          }
          const typedRow = row as {
            active_workflow?: string | null;
            session_id?: string | null;
            context_path?: string | null;
          } | null;
          routing = typedRow
            ? parseConversationRouting({
                active_workflow: typedRow.active_workflow ?? null,
              })
            : { kind: "legacy" };
          // Seed all three caches for subsequent turns.
          session.routing = routing;
          session.contextPath = typedRow?.context_path ?? null;
          session.sessionId = typedRow?.session_id ?? null;
        }

        if (routing.kind !== "legacy") {
          // KB Concierge: rebuild a synthetic ConversationContext from the
          // conversation's persisted context_path so follow-up turns keep
          // injecting the open document. Without this, only the first
          // turn would see the document context (chat-case path serves
          // turn 2+).
          const chatContext: ConversationContext | undefined = session.contextPath
            ? { path: session.contextPath, type: "kb-viewer" }
            : undefined;
          await dispatchSoleurGoForConversation(
            userId,
            convId,
            userContent,
            routing,
            chatContext,
            msg.attachments,
            session.sessionId ?? null,
          );
          break;
        }

        await sendUserMessage(
          userId,
          session.conversationId!,
          userContent,
          undefined, // conversationContext
          msg.attachments,
        );
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "chat error");
        sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
      }
      break;
    }

    // ------------------------------------------------------------------
    // interactive_prompt_response: Stage 2.14 — client reply to a
    // soleur-go interactive tool prompt (ask_user / plan_preview /
    // diff / bash_approval / todo_write / notebook_edit). Extended to
    // WSMessage as a feature-local variant (see lib/types.ts §Stage 2).
    // ------------------------------------------------------------------
    case "interactive_prompt_response": {
      handleInteractivePromptResponseCase({
        userId,
        payload: msg as unknown as InteractivePromptResponse,
        sendToClient,
      });
      break;
    }

    // ------------------------------------------------------------------
    // review_gate_response: resolve a pending review gate in the agent
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // abort_turn: user-initiated Stop. Broadcast-aborts every leader's
    // session for the conversation so multi-leader dispatch can't leak
    // a hidden BYOK-burning session past the click (TR3 / G3, plan
    // §"Reconciliation" row 1). `userId` MUST come from the
    // authenticated socket session — NEVER from the message payload.
    // The `WSMessage` strictObject schema in `lib/ws-zod-schemas.ts`
    // already rejects extra fields so a forged `userId` cannot land
    // here from a network peer (TR4 cross-user invariant).
    // ------------------------------------------------------------------
    case "abort_turn": {
      // Idempotent: if no session is active for (userId, conversationId),
      // abortSession is a silent no-op (registry prefix-lookup with no
      // matches). The client-side `stopping` state holds until the
      // server's `session_ended:user_aborted` arrives (emitted by the
      // for-await abort branch in `agent-runner.ts`); a no-op here
      // means the turn already finished, which the client tolerates
      // by ignoring the late `stopping`-state timeout.
      abortSession(userId, msg.conversationId, "user_requested_stop");
      // feat-stream-since-disconnect (#5273) — user-initiated Stop: the user
      // is connected and sees the stop live, so drop replay frames (counter
      // preserved). A trailing `session_ended:user_aborted` re-stamps a tiny
      // buffer, which is honest on any subsequent reconnect. Gate on the
      // session's OWN bound conversation (not the raw client `conversationId`)
      // so a forged abort_turn cannot clear another conversation's replay
      // buffer — abortSession above is already userId-keyed and safe. ADR-059.
      if (session.conversationId === msg.conversationId) {
        streamReplayBuffer.clear(msg.conversationId);
      }
      break;
    }

    case "review_gate_response": {
      if (!session.conversationId) {
        sendToClient(userId, {
          type: "error",
          message: "No active session.",
        });
        return;
      }

      try {
        // Layer 1: transport-level length guard (defense-in-depth)
        if (typeof msg.selection !== "string" || msg.selection.length > MAX_SELECTION_LENGTH) {
          throw new Error("Invalid review gate selection");
        }

        // Stage 2.12: route by conversation routing kind. The
        // cc-soleur-go path's Bash review-gate uses a synthetic
        // AgentSession registered in `_ccBashGates` (cc-dispatcher.ts);
        // legacy domain-leader sessions live in `agent-runner.ts`
        // `activeSessions`. `resolveCcBashGate` returns false if the
        // gate is not in the cc registry — fall through to the legacy
        // resolver in that case so transitional conversations (cc
        // started, then SDK iterator emitted a gate before routing
        // moved) still resolve.
        const ccRouted =
          session.routing?.kind === "soleur_go_pending" ||
          session.routing?.kind === "soleur_go_active";
        let resolved = false;
        if (ccRouted) {
          resolved = resolveCcBashGate({
            userId,
            conversationId: session.conversationId,
            gateId: msg.gateId,
            selection: msg.selection,
            // P1 — a review_gate_response may ONLY resolve a "review" gate. A
            // held first-run disclosure gate (kind "autonomous_disclosure") is
            // refused here, so this frame cannot bypass the owner-checked
            // consent path by carrying the held gate's gateId.
            expectedKind: "review",
          });
        }
        if (!resolved) {
          await resolveReviewGate(
            userId,
            session.conversationId,
            msg.gateId,
            msg.selection,
          );
        }
      } catch (err) {
        Sentry.captureException(err);
        log.error({ userId, err }, "review_gate_response error");
        sendToClient(userId, {
          type: "error",
          message: sanitizeErrorForClient(err),
          gateId: msg.gateId,
        });
      }
      break;
    }

    // ------------------------------------------------------------------
    // autonomous_disclosure_response: the owner acknowledged the first-run
    // autonomous-mode disclosure (feat-bash-autonomous-default-on). Write the
    // per-workspace consent ack, THEN release the held Bash command by
    // resolving its gate (the soft-gate hold reuses the `_ccBashGates`
    // registry via `abortableReviewGate`, so `resolveCcBashGate` releases it).
    // Order matters: write the ack first so a re-run can never re-hold; only
    // then unblock the command. Owner-deny → surfaced, the command stays held.
    // ------------------------------------------------------------------
    case "autonomous_disclosure_response": {
      if (!session.conversationId) {
        sendToClient(userId, { type: "error", message: "No active session." });
        return;
      }
      if (
        typeof msg.selection !== "string" ||
        msg.selection.length > MAX_SELECTION_LENGTH
      ) {
        sendToClient(userId, {
          type: "error",
          message: "Invalid autonomous disclosure selection.",
          gateId: msg.gateId,
        });
        break;
      }
      // "Keep autonomous on" also flips the toggle ON (existing-workspace
      // opt-out). "Got it" / "Ask me each time" write the ack only.
      const keepAutonomous = msg.selection === "Keep autonomous on";

      // P2 — split the ack-write from the gate-release so a TRANSIENT ack-write
      // fault (RPC blip, not owner-deny) is distinguishable from an owner-deny.
      //   - owner-deny  ⇒ keep the command HELD + surface a 403-style error
      //                   (intended: a non-owner cannot consent).
      //   - transient   ⇒ release-as-DECLINE so the agent unblocks (the held
      //                   run is denied; the banner re-arms via the error frame)
      //                   instead of hanging until the 5-min gate timeout while
      //                   the client already dismissed the banner.
      //   - success     ⇒ flip the in-session posture (P1), then DRAIN ALL held
      //                   disclosure gates for the conversation (P2 multi-hold)
      //                   so a single ack releases every held command.
      let persistedAck: string | null = null;
      try {
        persistedAck = await setAutonomousAck(userId, { keepAutonomous });
      } catch (err) {
        Sentry.captureException(err);
        const ownerDenied = err instanceof AutonomousAckOwnerDeniedError;
        log.error(
          { userId, err, ownerDenied },
          "autonomous_disclosure_response ack-write error",
        );
        if (ownerDenied) {
          // Keep the command held; only an owner may consent. Surface 403-shape.
          sendToClient(userId, {
            type: "error",
            message: "Only a workspace owner can enable autonomous mode.",
            gateId: msg.gateId,
          });
        } else {
          // Transient fault — unblock the agent by DECLINING the held run so it
          // doesn't hang to timeout. The error frame lets the client re-arm.
          drainAutonomousDisclosureGates({
            userId,
            conversationId: session.conversationId,
            selection: "Ask me each time",
          });
          sendToClient(userId, {
            type: "error",
            message: sanitizeErrorForClient(err),
            gateId: msg.gateId,
          });
        }
        break;
      }

      // Ack persisted. P1 — flip the in-session posture so the released command
      // (and any subsequent command in this conversation) sees the workspace as
      // acked and does NOT re-hold. Fail-closed: parse the returned timestamp;
      // a non-finite value with a successful write still flips to Date.now().
      const ackMs = persistedAck != null ? Date.parse(persistedAck) : NaN;
      markConversationAcked(
        userId,
        session.conversationId,
        Number.isFinite(ackMs) ? ackMs : Date.now(),
      );
      // P2 multi-hold — DRAIN every held disclosure gate for the conversation
      // with the owner's selection (not just the clicked one). Combined with the
      // posture flip above, none of them re-hold. Single-use + R8-scoped per gate.
      drainAutonomousDisclosureGates({
        userId,
        conversationId: session.conversationId,
        selection: msg.selection,
      });
      // P1 chip — re-push the SERVER posture after the ack. "Got it" /
      // "Keep autonomous on" make the workspace autonomous-and-acked ("Auto-run
      // on"); "Ask me each time" writes the ack but leaves the toggle off
      // ("Approve each").
      sendToClient(userId, {
        type: "autonomous_posture",
        autonomous: msg.selection !== "Ask me each time",
      });
      break;
    }

    // ------------------------------------------------------------------
    // auth is handled at connection level, not here
    // ------------------------------------------------------------------
    case "auth": {
      sendToClient(userId, {
        type: "error",
        message: "Already authenticated.",
      });
      break;
    }

    // ------------------------------------------------------------------
    // Server -> client only types are ignored if received from client
    // ------------------------------------------------------------------
    case "auth_ok":
    case "stream":
    case "stream_start":
    case "stream_end":
    case "tool_use":
    case "tool_progress":
    case "command_stream":
    // feat-debug-mode-stream — harness instruction stream (server→client only).
    case "debug_event":
    case "review_gate":
    case "autonomous_disclosure":
    case "autonomous_posture":
    case "session_started":
    case "session_resumed":
    case "session_ended":
    case "usage_update":
    case "fanout_truncated":
    case "context_reset":
    case "upgrade_pending":
    case "interactive_prompt":
    case "subagent_spawn":
    case "subagent_complete":
    case "workflow_started":
    case "workflow_ended":
    case "error":
    case "revocation_notice":
    // feat-reasoning-chat-boxes (#5370) — agent-emitted narration is
    // server→client only (emitted from cc-dispatcher onToolResult).
    case "reasoning_narration":
    case "turn_summary":
    // feat-stream-since-disconnect (#5273) — server→client only.
    case "stream_replay": {
      sendToClient(userId, {
        type: "error",
        message: "This message type is server-to-client only.",
      });
      break;
    }

    // feat-stream-since-disconnect (#5273) — client→server transient-reconnect
    // reattach. Full ownership-gated replay handler wired in Phase 3 below.
    case "resume_stream": {
      await handleResumeStream(userId, session, msg);
      break;
    }

    default: {
      const _exhaustive: never = msg;
      sendToClient(userId, {
        type: "error",
        message: "Unknown message type.",
      });
      // Prevent unused-variable lint error
      void _exhaustive;
    }
  }
}

// ---------------------------------------------------------------------------
// Public entry point — called from server/index.ts
// ---------------------------------------------------------------------------

export function setupWebSocket(server: HTTPServer) {
  const wss = new WebSocketServer({ noServer: true });

  // Handle HTTP -> WebSocket upgrade on /ws path
  server.on("upgrade", (req, socket, head) => {
    const { pathname } = parse(req.url || "", true);

    if (pathname !== "/ws") {
      socket.destroy();
      return;
    }

    // Layer 1: IP-based connection throttle (pre-auth)
    const clientIp = extractClientIp(req);
    if (!connectionThrottle.isAllowed(clientIp)) {
      logRateLimitRejection("connection-throttle", clientIp);
      // Fixed Retry-After to avoid leaking exact window config (CWE-209)
      socket.write(
        "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 120\r\nConnection: close\r\n\r\n",
      );
      socket.destroy();
      return;
    }

    // Layer 2: Concurrent unauthenticated connection limit per IP
    if (!pendingConnections.add(clientIp)) {
      logRateLimitRejection("pending-limit", clientIp, {
        pending: pendingConnections.get(clientIp),
      });
      socket.write(
        "HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n",
      );
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req, clientIp);
    });
  });

  // New connection — auth moves to first message
  wss.on("connection", (ws: WebSocket, _req: unknown, clientIp: string) => {
    let authenticated = false;
    let userId: string | null = null;

    // ---- Auth timeout: close if no auth message within 5 seconds ----
    const authTimer = setTimeout(() => {
      if (!authenticated) {
        ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, "Auth timeout");
      }
    }, AUTH_TIMEOUT_MS);

    // ---- Heartbeat (Cloudflare terminates idle WS after 100s) ----
    let pingInterval: ReturnType<typeof setInterval> | undefined;

    // ---- Message handling ----
    ws.on("message", async (data) => {
      if (!authenticated) {
        // First message MUST be { type: "auth", token: "..." }
        let msg: { type: string; token?: string };
        try {
          msg = JSON.parse(data.toString());
        } catch {
          clearTimeout(authTimer);
          ws.close(WS_CLOSE_CODES.AUTH_REQUIRED, "Auth required");
          return;
        }

        if (msg.type !== "auth" || !msg.token) {
          clearTimeout(authTimer);
          ws.close(WS_CLOSE_CODES.AUTH_REQUIRED, "Auth required");
          return;
        }

        // Validate token via Supabase
        const {
          data: { user },
          error,
        } = await supabase.auth.getUser(msg.token);

        if (error || !user) {
          clearTimeout(authTimer);
          ws.close(WS_CLOSE_CODES.AUTH_TIMEOUT, "Unauthorized");
          return;
        }

        // Guard: if timeout fired during the await, socket is already closing
        if (ws.readyState !== WebSocket.OPEN) {
          clearTimeout(authTimer);
          return;
        }

        // Auth success — no longer pending
        clearTimeout(authTimer);
        authenticated = true;
        userId = user.id;
        pendingConnections.remove(clientIp);

        // PR-C §2.10 (#3244): tenant-scoped post-auth bootstrap. The
        // `supabase.auth.getUser(token)` above resolved `user.id`; this
        // SELECT now goes through the tenant client. `auth.getUser`
        // remains PERMANENT service-role (auth-domain bootstrap, runs
        // BEFORE userId exists). Auth-probe failure here = close socket
        // with INTERNAL_ERROR — same disclosure shape as the original
        // `tcError` branch.
        const tenantBootstrap = await tenantFor(user.id, "setupWebSocket.auth-bootstrap");
        if (!tenantBootstrap) {
          if (ws.readyState === WebSocket.OPEN) {
            ws.close(WS_CLOSE_CODES.INTERNAL_ERROR, "Internal error");
          }
          return;
        }
        // Enforce T&C acceptance (version-aware) and cache subscription status
        const { data: userRow, error: tcError } = await tenantBootstrap
          .from("users")
          .select("tc_accepted_version, subscription_status, plan_tier, concurrency_override, stripe_subscription_id")
          .eq("id", user.id)
          .single();

        // Guard: socket may have closed during the await
        if (ws.readyState !== WebSocket.OPEN) {
          return;
        }

        if (tcError) {
          log.error({ userId: user.id, err: tcError.message }, "tc_accepted_version query failed");
          ws.close(WS_CLOSE_CODES.INTERNAL_ERROR, "Internal error");
          return;
        }

        if (userRow?.tc_accepted_version !== TC_VERSION) {
          ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, "T&C not accepted");
          return;
        }

        // If user already has an open socket, close the old one
        supersedeExistingUserSocket(userId);

        // Register session — cancel any pending disconnect grace period
        const userRowTyped = userRow as {
          tc_accepted_version?: string;
          subscription_status?: string | null;
          plan_tier?: PlanTier | null;
          concurrency_override?: number | null;
          stripe_subscription_id?: string | null;
        };
        const newSession: ClientSession = {
          ws,
          lastActivity: Date.now(),
          subscriptionStatus: userRowTyped.subscription_status ?? undefined,
          planTier: userRowTyped.plan_tier ?? "free",
          concurrencyOverride: userRowTyped.concurrency_override ?? null,
          stripeSubscriptionId: userRowTyped.stripe_subscription_id ?? null,
          ip: clientIp,
          // feat-oauth-tc-consent-3205: baseline + cache slot for the
          // mid-session TC re-check (recheckTcMidSession).
          tcVersionAtHandshake: userRowTyped.tc_accepted_version ?? null,
          tcRecheckCacheUntil: null,
        };
        sessions.set(userId, newSession);
        startSubscriptionRefresh(userId, newSession);

        // Phase 5.5 / Kieran C5: bind userId → current workspace_id so
        // workspace-membership.ts:removeWorkspaceMember can SIGTERM only the
        // sessions running against the workspace being revoked (and not
        // sibling sessions in the user's other workspaces). user_session_state
        // (migration 060) is the source of truth; the lookup translates
        // org_id → workspace_id once at WS open.
        // Resolved once here, reused by the session-router placement hook below.
        let boundWorkspaceId: string | null = null;
        try {
          const orgId = await resolveCurrentOrganizationId(
            user.id,
            tenantBootstrap as never,
          );
          let workspaceId: string | null = null;
          if (orgId) {
            workspaceId = await getWorkspaceForUserInOrganization(
              user.id,
              orgId,
              tenantBootstrap as never,
            );
          }
          // Fallback to default workspace (oldest by created_at — collapses
          // to N2 invariant `workspace_id === user_id` for solo users).
          if (!workspaceId) {
            try {
              workspaceId = await getDefaultWorkspaceForUser(
                user.id,
                tenantBootstrap as never,
              );
            } catch {
              // Pre-Phase-1 migration users (no workspace_members row yet)
              // fall through with no binding — abortAllWorkspaceMemberSessions
              // becomes a no-op for them which is the safe pre-multi-tenant
              // behavior.
              workspaceId = null;
            }
          }
          if (workspaceId) setUserWorkspace(user.id, workspaceId);
          boundWorkspaceId = workspaceId;
        } catch (workspaceBindErr) {
          // Silent fallback per cq-silent-fallback-must-mirror-to-sentry: the
          // session still opens (the binding is for SIGTERM precision, not
          // auth). Mirror so the on-call sees the drift.
          reportSilentFallback(workspaceBindErr, {
            feature: "ws-handler",
            op: "bind-user-workspace",
            extra: { userId: user.id },
          });
        }

        for (const [key, timer] of pendingDisconnects) {
          if (key.startsWith(`${userId}:`)) {
            clearTimeout(timer);
            pendingDisconnects.delete(key);
            log.info({ key }, "Cancelled pending disconnect (user reconnected)");
          }
        }
        log.info({ userId }, "User connected");

        // Start idle timer after auth
        resetIdleTimer(userId, newSession);

        // Start heartbeat after auth. In addition to the WebSocket ping, touch
        // user_concurrency_slots.last_heartbeat_at for the active/pending
        // conversation so the pg_cron sweep (240s threshold, mig 133) does not
        // reclaim a still-live session. Uses the dedicated `touch_conversation_slot`
        // RPC — a single UPDATE, no cap check, no sweep, no lock — so
        // steady-state heartbeat load is O(N) cheap UPDATEs per SLOT_HEARTBEAT_INTERVAL_MS
        // (60s as of the 2026-07-18 Disk-IO backoff — halves this UPDATE's WAL)
        // rather than re-running the full acquire path. The 240s reaper threshold
        // is 4× this interval, so missed-beat tolerance is unchanged.
        pingInterval = setInterval(() => {
          if (ws.readyState !== WebSocket.OPEN) return;
          ws.ping();
          const current = sessions.get(userId!);
          const convId = current?.conversationId ?? current?.pending?.id;
          if (current && convId) {
            void touchSlot(userId!, convId);
          }
        }, SLOT_HEARTBEAT_INTERVAL_MS);

        // --- User-sticky session placement (epic #5274 Phase 3, ADR-068 D0 / CTO
        //     ruling b2) -----------------------------------------------------------
        // GATED on isGitDataStoreEnabled(): entirely inert (no per-connection DB
        // read) until the 3.D cutover — at flag-off this whole block is skipped and
        // the connection serves locally, byte-identical to pre-#5274. When on: read
        // this user's live worktree-lease holder; if a PEER host owns it,
        // TRANSPARENTLY proxy the socket to the owner over one-way TLS BEFORE
        // auth_ok (no client-visible reconnect — the fly-replay invariant). At a
        // single host every route resolves `local`, so this stays inert until a 2nd
        // host + roster come online at 3.D.
        if (isGitDataStoreEnabled() && boundWorkspaceId) {
          let route;
          try {
            route = await resolveSessionRoute({
              workspaceId: boundWorkspaceId,
              userId,
              myHostId: resolveHostId(),
            });
          } catch (routeErr) {
            // Fail-safe: a routing error degrades to local-serve (the lease acquire
            // on the write path is itself fail-closed, and the git-data fence is the
            // ultimate write guard) — never a wrong proxy dial. Mirror to Sentry.
            reportSilentFallback(routeErr, {
              feature: "ws-handler",
              op: "resolveSessionRoute",
              extra: { userId, workspaceId: boundWorkspaceId },
            });
            route = { decision: "local" as const, reason: "cold" as const };
          }
          if (ws.readyState !== WebSocket.OPEN) return; // closed during the await
          if (route.decision === "owner-unresolved") {
            // A peer owns the lease but its address is not resolvable — fail loud
            // (already Sentry'd in the router). Non-transient close → the client
            // reconnects and self-heals once the roster/owner recovers.
            ws.close(WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "session owner unreachable");
            return;
          }
          if (route.decision === "proxy") {
            // b2: relay this authenticated socket to the owner; the relay owns the
            // socket lifecycle from here (frames + close forwarded both ways). Tear
            // down the local pre-session state we set up above so this host holds no
            // stale binding for a session it is not serving.
            clearTimeout(authTimer);
            if (pingInterval) clearInterval(pingInterval);
            sessions.delete(userId);
            clearUserWorkspace(userId);
            void proxyClientToOwner({
              clientWs: ws,
              ownerAddress: route.ownerAddress,
              userId,
              workspaceId: boundWorkspaceId,
            });
            return;
          }
          // decision === "local" → fall through and serve here.
        }

        ws.send(JSON.stringify({ type: "auth_ok" }));
        return;
      }

      // Authenticated — route to handleMessage
      handleMessage(userId!, data.toString()).catch((err) => {
        Sentry.captureException(err);
        log.error({ userId, err }, "Unhandled message error");
        sendToClient(userId!, {
          type: "error",
          message: "Internal server error",
        });
      });
    });

    // ---- Cleanup on disconnect ----
    ws.on("close", () => {
      clearTimeout(authTimer);
      if (pingInterval) clearInterval(pingInterval);
      // If not yet authenticated, release the pending connection slot
      if (!authenticated) {
        pendingConnections.remove(clientIp);
      }
      if (userId) {
        teardownAuthedSessionOnClose(userId, ws);
      }
    });

    ws.on("error", (err) => {
      Sentry.captureException(err);
      log.error({ userId, err }, "Socket error");
    });
  });

  return wss;
}

/**
 * Close a user's existing OPEN socket before a new one supersedes it (one live
 * socket per user). Factored out of the native connection path so the proxied
 * attach (#5274 3.D) supersedes identically — a stale native socket and a fresh
 * proxied attach for the same user must not both stay registered.
 */
function supersedeExistingUserSocket(userId: string): void {
  const existing = sessions.get(userId);
  if (existing && existing.ws.readyState === WebSocket.OPEN) {
    if (existing.subscriptionRefreshTimer) {
      clearInterval(existing.subscriptionRefreshTimer);
    }
    existing.ws.close(WS_CLOSE_CODES.SUPERSEDED, "Superseded by new connection");
  }
}

/**
 * Teardown for an AUTHENTICATED session whose socket closed — clears the idle +
 * subscription timers, drops the session + workspace binding, and arms the
 * disconnect grace-abort. Factored out of the native `ws.on("close")` so the
 * proxied attach (#5274 3.D) tears down through the SAME path: the grace-abort is
 * host-locality-correctness-critical (#2191 / #5240) and must never drift between
 * the native and proxied lifecycles. Guards on `current.ws === ws` so a socket
 * that was already superseded does not delete its successor's registration.
 */
function teardownAuthedSessionOnClose(userId: string, ws: WebSocket): void {
  const current = sessions.get(userId);
  if (current?.ws === ws) {
    if (current.idleTimer) clearTimeout(current.idleTimer);
    if (current.subscriptionRefreshTimer) {
      clearInterval(current.subscriptionRefreshTimer);
    }
    sessions.delete(userId);
    // Phase 5.5: drop the workspace binding so a future reconnect re-resolves
    // from user_session_state (handles the org-switch + reconnect sequence
    // cleanly — see AC-FLOW3 multi-tab race coverage).
    clearUserWorkspace(userId);
    // Grace period: defer abort to allow reconnection
    if (current.conversationId) {
      const convId = current.conversationId;
      const uid = userId;
      const timer = setTimeout(
        () => runDisconnectGraceAbort(uid, convId),
        DISCONNECT_GRACE_MS,
      );
      timer.unref();
      // Store timer so reconnecting user can cancel it
      pendingDisconnects.set(`${uid}:${convId}`, timer);
    }
  }
  // No raw `userId` on this direct-logger breadcrumb — the userid-bypass-lint guard
  // (#3698) scans NEW source for `log.*({ userId })`; runtime is already safe (pino
  // formatters.log hashes top-level userId). Same posture as ensure-workspace-repo.ts.
  log.info({ gracePeriodSec: DISCONNECT_GRACE_MS / 1000 }, "User disconnected");
}

/**
 * Attach a PRE-AUTHENTICATED proxied session on the OWNER host (epic #5274 Phase
 * 3 Sub-PR 3.D, ADR-068 b2). A session that lands on a non-owning web host is
 * relayed here over one-way TLS (session-proxy.ts): the proxying host already
 * authenticated the client and the owner's proxy listener re-verified AP-2
 * membership before invoking this. So there is NO token re-auth, NO T&C gate, and
 * NO placement/routing (the session is already on its owner). This mirrors the
 * register → bind → idle → heartbeat → `auth_ok` TAIL of the native connection
 * path for a socket that arrives already-authed, then wires message→handleMessage
 * and close→teardown (through the SAME shared helpers as the native path).
 *
 * It sends only `auth_ok` — NOT a fresh-session greeting (AC8: a drain/deploy-
 * migrated session RESUMES; it must not be greeted as a new one). Never throws to
 * the caller in a way that escapes; the caller (server/index.ts) mirrors any
 * rejection to Sentry.
 */
export async function attachProxiedSession(
  ws: WebSocket,
  ctx: { userId: string; workspaceId: string },
): Promise<void> {
  const { userId, workspaceId } = ctx;

  // Supersede any existing socket for this user (mirrors the native path).
  supersedeExistingUserSocket(userId);

  // Register with a conservative free-tier PLACEHOLDER cap, then hydrate the real
  // subscription state inline BELOW before any message (hence any start_session)
  // is wired. Registering before the DB await mirrors the native path so the
  // owning-host grace-abort guard sees this OPEN socket if a supersede-armed
  // grace timer fires during the read. The free default is never consumed: no
  // message handler and no heartbeat run until after hydration completes.
  const session: ClientSession = {
    ws,
    lastActivity: Date.now(),
    planTier: "free",
  };
  sessions.set(userId, session);
  startSubscriptionRefresh(userId, session);

  // Phase 5.5: bind userId → workspaceId (the owner already holds this user's
  // worktree lease) so workspace-membership revocation SIGTERMs precisely.
  setUserWorkspace(userId, workspaceId);

  // Hydrate the migrated session's REAL plan/cap inline, BEFORE wiring
  // message→handleMessage (i.e. before any start_session can run). #5274 3.D
  // user-impact: a coordinated drain migrates many PAID users at once; without
  // this read they would be capped at the free placeholder (=1) until the first
  // ~60s subscription-refresh tick, so a start_session while already holding a
  // slot would spuriously cap_hit → hard-close the just-resumed session + pop an
  // upgrade modal at a paying customer (brand-fatal). Also populates
  // stripeSubscriptionId so the Stripe webhook-lag rescue path is reachable
  // (the native handshake sets it; the old free literal did not). Mirrors the
  // native read (subscription_status / plan_tier / concurrency_override /
  // stripe_subscription_id). Fail-open: on any DB failure keep the conservative
  // free default (mirrored to Sentry) — startSubscriptionRefresh still hydrates
  // on its next tick.
  try {
    const tenant = await tenantFor(userId, "attachProxiedSession");
    if (tenant) {
      const { data, error } = await tenant
        .from("users")
        .select(
          "tc_accepted_version, subscription_status, plan_tier, concurrency_override, stripe_subscription_id",
        )
        .eq("id", userId)
        .single();
      if (error || !data) {
        reportSilentFallback(
          error ?? new Error("proxied-attach subscription read returned no row"),
          {
            feature: "control_plane_route",
            op: "proxied-attach.subscription-read",
            extra: { userId },
          },
        );
      } else {
        const row = data as {
          tc_accepted_version?: string | null;
          subscription_status?: string | null;
          plan_tier?: PlanTier | null;
          concurrency_override?: number | null;
          stripe_subscription_id?: string | null;
        };
        session.subscriptionStatus = row.subscription_status ?? undefined;
        session.planTier = row.plan_tier ?? "free";
        session.concurrencyOverride = row.concurrency_override ?? null;
        session.stripeSubscriptionId = row.stripe_subscription_id ?? null;
        session.tcVersionAtHandshake = row.tc_accepted_version ?? null;
      }
    }
    // `tenant === null` → tenantFor already mirrored to Sentry; keep free default.
  } catch (err) {
    reportSilentFallback(err, {
      feature: "control_plane_route",
      op: "proxied-attach.subscription-read",
      extra: { userId },
    });
  }

  // Socket may have closed during the read — tear down the registration we made
  // above (grace-abort is a no-op: no conversation is active on a fresh attach).
  if (ws.readyState !== WebSocket.OPEN) {
    teardownAuthedSessionOnClose(userId, ws);
    return;
  }

  // This attach IS the reconnect — cancel any armed disconnect grace-abort (incl.
  // one armed by the supersede above) so a migrated in-flight turn is not aborted
  // out from under the resumed session.
  for (const [key, timer] of pendingDisconnects) {
    if (key.startsWith(`${userId}:`)) {
      clearTimeout(timer);
      pendingDisconnects.delete(key);
      log.info({ key }, "Cancelled pending disconnect (proxied session attached)");
    }
  }

  log.info({ workspaceId }, "Proxied session attached (owner-side)"); // no raw user id (#3698 lint; pino hashes at runtime)

  resetIdleTimer(userId, session);

  // Heartbeat (mirrors the native path): WS ping + touch the concurrency slot so
  // the pg_cron sweep does not reclaim a still-live proxied session. Cleared on
  // close. `.unref()` so it never keeps the process alive on its own. Same
  // SLOT_HEARTBEAT_INTERVAL_MS (60s) as the native path — both must move together.
  const pingInterval = setInterval(() => {
    if (ws.readyState !== WebSocket.OPEN) return;
    ws.ping();
    const current = sessions.get(userId);
    const convId = current?.conversationId ?? current?.pending?.id;
    if (current && convId) {
      void touchSlot(userId, convId);
    }
  }, SLOT_HEARTBEAT_INTERVAL_MS);
  pingInterval.unref?.();

  // Authenticated frames route straight to handleMessage — no auth branch (the
  // socket arrived pre-authed).
  ws.on("message", (data: unknown) => {
    handleMessage(userId, String(data)).catch((err) => {
      Sentry.captureException(err); // Sentry carries the error; local breadcrumb omits raw userId (#3698)
      log.error({ err }, "Unhandled message error (proxied)");
      sendToClient(userId, { type: "error", message: "Internal server error" });
    });
  });

  ws.on("close", () => {
    clearInterval(pingInterval);
    teardownAuthedSessionOnClose(userId, ws);
  });

  ws.on("error", (err) => {
    Sentry.captureException(err); // Sentry carries the error; local breadcrumb omits raw userId (#3698)
    log.error({ err }, "Proxied socket error");
  });

  // Resume signal — NOT a fresh greeting (AC8).
  ws.send(JSON.stringify({ type: "auth_ok" }));
}
