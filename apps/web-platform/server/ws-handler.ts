import { Server as HTTPServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { parse } from "url";
import { randomUUID } from "crypto";

import { KeyInvalidError, WS_CLOSE_CODES, type PlanTier, type WSMessage, type Conversation } from "@/lib/types";
import type { ConversationContext } from "@/lib/types";
import { validateConversationContext } from "./context-validation";
import { createServiceClient } from "@/lib/supabase/service";
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
import { effectiveCap, nextTier } from "@/lib/plan-limits";
import { closeWithPreamble } from "@/lib/ws-close-helper";
import { retrieveSubscriptionTier } from "@/lib/stripe";
import {
  acquireSlot,
  releaseSlot,
  touchSlot,
  emitConcurrencyCapHit,
} from "./concurrency";
import {
  parseConversationRouting,
  resolveInitialRouting,
  serializeConversationRouting,
  type ConversationRouting,
  type WorkflowName,
} from "./conversation-routing";
import {
  dispatchSoleurGo,
  getCcStartSessionRateLimiter,
  handleInteractivePromptResponseCase,
  resolveCcBashGate,
  resolveConciergeDocumentContext,
} from "./cc-dispatcher";
import { getFlag } from "@/lib/feature-flags/server";
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
const supabase = new Proxy({} as ServiceClient, {
  get(_target, prop) {
    _supabase ??= createServiceClient();
    const value = Reflect.get(_supabase, prop);
    return typeof value === "function" ? value.bind(_supabase) : value;
  },
});

// ---------------------------------------------------------------------------
// Session tracking
// ---------------------------------------------------------------------------
/** Grace period before aborting session on disconnect (allows reconnection). */
const DISCONNECT_GRACE_MS = 30_000;

/** Deferred conversation state — exists XOR conversationId exists. */
export interface PendingConversation {
  id: string;
  leaderId?: DomainLeaderId;
  context?: ConversationContext;
  /** KB document path that will become conversations.context_path at materialization. */
  contextPath?: string;
  /** Stage 2 (#2853): soleur-go routing decided at start_session time
   *  (flag is read once per conversation — never again) and persisted
   *  alongside the conversations row on first materialization. */
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
 * Serialize and send a WSMessage to the client identified by `userId`.
 * Returns true if the message was delivered via WebSocket, false if the
 * user has no active connection or the socket is not open.
 */
export function sendToClient(userId: string, message: WSMessage): boolean {
  const session = sessions.get(userId);
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
    const { data, error } = await supabase
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
    const { count, error: countErr } = await supabase
      .from("user_concurrency_slots")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId);
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
): Promise<string> {
  if (!id) id = randomUUID();

  // Stamp the conversation with the user's CURRENT repo_url so Command
  // Center + context_path resume can scope by it. Users who disconnected
  // mid-session have repo_url=null; we abort rather than orphan the row
  // (plan risk R-D). See
  // 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
  const repoUrl = await getCurrentRepoUrl(userId);
  if (!repoUrl) {
    throw new Error(
      "No connected repository — conversation insert aborted (disconnect race).",
    );
  }

  const { error } = await supabase.from("conversations").insert({
    id,
    user_id: userId,
    repo_url: repoUrl,
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
      const { data: existing, error: lookupErr } = await supabase
        .from("conversations")
        .select("id, active_workflow")
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
      const existingRow = existing as { id: string; active_workflow?: string | null };
      const existingWorkflow = existingRow.active_workflow ?? null;
      const intendedWorkflow = activeWorkflow ?? null;
      if (activeWorkflow !== undefined && existingWorkflow !== intendedWorkflow) {
        Sentry.captureMessage(
          "createConversation 23505 fallback: activeWorkflow diverged — first-writer-wins",
          {
            level: "warning",
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
async function dispatchSoleurGoForConversation(
  userId: string,
  conversationId: string,
  userMessage: string,
  routing: ConversationRouting,
  context?: ConversationContext,
): Promise<void> {
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
  // `agent-runner.ts:595-631` injection — see
  // `resolveConciergeDocumentContext` in cc-dispatcher for kind/path/
  // workspace-validation logic.
  let documentArgs: {
    artifactPath?: string;
    documentKind?: "pdf" | "text";
    documentContent?: string;
  } = {};
  if (context?.path) {
    documentArgs = await resolveConciergeDocumentContext({
      userId,
      contextPath: context.path,
      providedContent: context.content ?? null,
    });
  }

  await dispatchSoleurGo({
    userId,
    conversationId,
    userMessage,
    currentRouting: routing,
    sendToClient,
    persistActiveWorkflow,
    ...documentArgs,
  });
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

  switch (msg.type) {
    // ------------------------------------------------------------------
    // start_session: create conversation, boot agent, reply with ID
    // ------------------------------------------------------------------
    case "start_session": {
      // Layer 3: Agent session creation rate limit (per-user, post-auth)
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

      // Stage 2.13 — soleur-go path gets an additional per-user + per-IP
      // sliding-window limiter (10/user/hour, 30/IP/hour) on top of the
      // legacy `sessionThrottle` above. Fail-closed at either cap.
      // Flag is read ONCE here — the routing decision is sticky.
      const ccFlagEnabled = getFlag("command-center-soleur-go");
      if (ccFlagEnabled) {
        // security P2: use userId as the per-IP fallback when no IP
        // was captured. Falling back to a literal string like
        // `"unknown"` collides every IP-missing user into one 30/hr
        // bucket — a trivial DoS pivot if a proxy misconfiguration
        // ever strips headers. Using userId preserves per-user
        // isolation; the per-user cap still applies above it.
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
      }
      const initialRouting: ConversationRouting = resolveInitialRouting(ccFlagEnabled);

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
          const { data: existing, error: lookupErr } = await supabase
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
            const { count: messageCount, error: countErr } = await supabase
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

        // Plan-based concurrency gate. Acquire a slot keyed on (userId,
        // pendingId). A cap_hit result denies before we mutate any session
        // state so the client can present the upgrade modal without the
        // confusion of a session_started that never got a response.
        const cap = effectiveCap(session.planTier, session.concurrencyOverride);
        let acquire = await acquireSlot(userId, pendingId, cap);

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
            const { data: userRow } = await supabase
              .from("users")
              .select("concurrency_override")
              .eq("id", userId)
              .maybeSingle();
            const freshOverride = (userRow as { concurrency_override?: number | null } | null)?.concurrency_override ?? null;
            const liveCap = effectiveCap(live.tier, freshOverride);
            if (liveCap > cap) {
              session.planTier = live.tier;
              session.concurrencyOverride = freshOverride;
              acquire = await acquireSlot(userId, pendingId, liveCap);
            }
          } catch (liveErr) {
            Sentry.captureException(liveErr);
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

        sendToClient(userId, { type: "session_started", conversationId: session.pending.id });
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
        const convQuery = supabase
          .from("conversations")
          .select("id, status, repo_url")
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

        session.conversationId = msg.conversationId;
        // Resuming a different conversation — invalidate the routing
        // cache so the first chat-turn re-reads `active_workflow`.
        session.routing = undefined;
        resetIdleTimer(userId, session);
        sendToClient(userId, {
          type: "session_started",
          conversationId: msg.conversationId,
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
        await updateConversationFor(
          userId,
          convId,
          { status: "completed", last_active: new Date().toISOString() },
          { feature: "ws-handler", op: "close-conversation", expectMatch: true },
        );
        session.conversationId = undefined;
        session.routing = undefined;
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

      // User activity resets idle timer
      resetIdleTimer(userId, session);

      // Materialize pending conversation on first real message
      if (!session.conversationId && session.pending) {
        const stripped = msg.content.replace(/@\w+\s*/g, "").trim();
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
            await dispatchSoleurGoForConversation(
              userId,
              session.conversationId,
              msg.content,
              pendingRouting,
              pendingContext,
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
                sendToClient(userId, {
                  type: "error",
                  message: sanitizeErrorForClient(err),
                  errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
                });
              },
            );
          }

          // sendUserMessage handles saveMessage internally — do not double-save
          await sendUserMessage(userId, session.conversationId, msg.content, pendingContext);
        } catch (err) {
          Sentry.captureException(err);
          log.error({ userId, err }, "chat error (deferred creation)");
          sendToClient(userId, { type: "error", message: sanitizeErrorForClient(err) });
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
        if (session.routing && session.contextPath !== undefined) {
          routing = session.routing;
        } else {
          const { data: row, error: routeErr } = await supabase
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
          // Seed both caches for subsequent turns.
          session.routing = routing;
          session.contextPath = typedRow?.context_path ?? null;
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
            msg.content,
            routing,
            chatContext,
          );
          break;
        }

        await sendUserMessage(
          userId,
          session.conversationId!,
          msg.content,
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
    case "review_gate":
    case "session_started":
    case "session_resumed":
    case "session_ended":
    case "usage_update":
    case "fanout_truncated":
    case "upgrade_pending":
    case "interactive_prompt":
    case "subagent_spawn":
    case "subagent_complete":
    case "workflow_started":
    case "workflow_ended":
    case "error": {
      sendToClient(userId, {
        type: "error",
        message: "This message type is server-to-client only.",
      });
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

        // Enforce T&C acceptance (version-aware) and cache subscription status
        const { data: userRow, error: tcError } = await supabase
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
        const existing = sessions.get(userId);
        if (existing && existing.ws.readyState === WebSocket.OPEN) {
          if (existing.subscriptionRefreshTimer) {
            clearInterval(existing.subscriptionRefreshTimer);
          }
          existing.ws.close(WS_CLOSE_CODES.SUPERSEDED, "Superseded by new connection");
        }

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
        };
        sessions.set(userId, newSession);
        startSubscriptionRefresh(userId, newSession);
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
        // conversation so the pg_cron sweep (120s threshold) does not reclaim
        // a still-live session. Uses the dedicated `touch_conversation_slot`
        // RPC — a single UPDATE, no cap check, no sweep, no lock — so
        // steady-state heartbeat load is O(N) cheap UPDATEs per 30s rather
        // than re-running the full acquire path. Matters at scale: at 1k
        // live sessions, the full-acquire heartbeat cost ~33 writes/s +
        // 33 per-user advisory locks/s; touchSlot cuts that to 33 cheap
        // UPDATEs with no lock contention.
        pingInterval = setInterval(() => {
          if (ws.readyState !== WebSocket.OPEN) return;
          ws.ping();
          const current = sessions.get(userId!);
          const convId = current?.conversationId ?? current?.pending?.id;
          if (current && convId) {
            void touchSlot(userId!, convId);
          }
        }, 30_000);

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
        const current = sessions.get(userId);
        if (current?.ws === ws) {
          if (current.idleTimer) clearTimeout(current.idleTimer);
          if (current.subscriptionRefreshTimer) {
            clearInterval(current.subscriptionRefreshTimer);
          }
          sessions.delete(userId);
          // Grace period: defer abort to allow reconnection
          if (current.conversationId) {
            const convId = current.conversationId;
            const uid = userId;
            const timer = setTimeout(() => {
              log.info({ userId: uid, conversationId: convId }, "Grace period expired, aborting session");
              abortSession(uid, convId);
            }, DISCONNECT_GRACE_MS);
            timer.unref();
            // Store timer so reconnecting user can cancel it
            pendingDisconnects.set(`${uid}:${convId}`, timer);
          }
        }
        log.info({ userId, gracePeriodSec: DISCONNECT_GRACE_MS / 1000 }, "User disconnected");
      }
    });

    ws.on("error", (err) => {
      Sentry.captureException(err);
      log.error({ userId, err }, "Socket error");
    });
  });

  return wss;
}
