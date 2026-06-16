"use client";

import { useState, useEffect, useReducer, useMemo, useRef, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  WS_CLOSE_CODES,
  type WSMessage,
  type ConversationContext,
  type AttachmentRef,
  type ConcurrencyCapHitPreamble,
  type TierChangedPreamble,
  type MembershipRevokedPreamble,
} from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import {
  applyStreamEvent,
  applyTimeout,
  type ChatMessage,
  type StreamEventResult,
  type WorkflowLifecycleState,
  type SpawnIndex,
  type ConnectionPhase,
} from "@/lib/chat-state-machine";

export type { ConnectionPhase } from "@/lib/chat-state-machine";
import { isKnownWSMessageType } from "@/lib/ws-known-types";
import { parseWSMessage } from "@/lib/ws-zod-schemas";
import { reportSilentFallback, warnSilentFallback } from "@/lib/client-observability";
import * as Sentry from "@sentry/nextjs";
import { STUCK_TIMEOUT_MS } from "@/lib/ws-constants";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";

export { STUCK_TIMEOUT_MS } from "@/lib/ws-constants";

type ConnectionStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

/**
 * Per-turn stream lifecycle exposed on the hook return surface.
 *
 *   - `"idle"`     — no in-flight assistant turn for this conversation.
 *   - `"streaming"` — at least one leader is mid-stream (entered on the first
 *                    `stream_start` after auth).
 *   - `"stopping"`  — user clicked Stop / pressed Esc; an `abort_turn` frame
 *                    was sent. Stays here until `session_ended` arrives so the
 *                    Stop button can disable + show "Stopping…" without a
 *                    second client-side timer.
 *
 * Distinct from `activeLeaderIds`: a multi-leader dispatch may still have
 * leaders responding while we are already in `"stopping"` — the UI binds the
 * Stop button to `streamState`, not to the per-leader map.
 */
export type StreamState = "idle" | "streaming" | "stopping";

export interface WebSocketError {
  code: string;
  message: string;
  action?: {
    label: string;
    href: string;
  };
}

// ChatMessage type is now re-exported from chat-state-machine (see import above)
// to ensure the pure reducer and the hook share the same shape. See #2124.

export interface UsageData {
  totalCostUsd: number;
  inputTokens: number;
  outputTokens: number;
  // Cache tokens — `0` when prompt caching is not engaged. Widened
  // 2026-05-12 so the chat-surface cost badge can render the same
  // total-input semantics the dashboard's API Usage section does.
  cacheReadInputTokens: number;
  cacheCreationInputTokens: number;
}

export interface StartSessionOptions {
  leaderId?: DomainLeaderId;
  context?: ConversationContext;
  resumeByContextPath?: string;
}

export interface ResumedFrom {
  conversationId: string;
  timestamp: string;
  messageCount: number;
}

interface UseWebSocketReturn {
  messages: ChatMessage[];
  startSession: (optsOrLeaderId?: StartSessionOptions | DomainLeaderId, context?: ConversationContext) => void;
  resumeSession: (conversationId: string) => void;
  sendMessage: (content: string, attachments?: AttachmentRef[]) => void;
  sendReviewGateResponse: (gateId: string, selection: string) => void;
  /** feat-bash-autonomous-default-on: client→server ack for the first-run
   *  autonomous-mode disclosure soft-gate. Selection is "Got it" /
   *  "Keep autonomous on" / "Ask me each time". Releases the held command. */
  sendAutonomousDisclosureResponse: (gateId: string, selection: string) => void;
  /** Stage 4 (#2886): client→server send for `interactive_prompt_response`.
   *  Used by `<InteractivePromptCard>` to post the user's choice. */
  sendInteractivePromptResponse: (msg: Extract<WSMessage, { type: "interactive_prompt_response" }>) => void;
  /** Stage 4 (#2886): optimistically mark a prompt card as resolved
   *  (locally; the runner's reaper handles staleness). */
  resolveInteractivePrompt: (
    promptId: string,
    conversationId: string,
    response: unknown,
  ) => void;
  status: ConnectionStatus;
  sessionConfirmed: boolean;
  disconnectReason: string | undefined;
  lastError: WebSocketError | null;
  reconnect: () => void;
  routeSource: "auto" | "mention" | null;
  activeLeaderIds: DomainLeaderId[];
  usageData: UsageData | null;
  /** feat-bash-autonomous-default-on — SERVER-resolved autonomous posture for the
   *  persistent chip. `null` before the server pushes; `true` = "Auto-run on"
   *  (autonomous AND first-run-acked); `false` = "Approve each". Driven ONLY by
   *  the server `autonomous_posture` frame — never message presence. */
  autonomousPosture: boolean | null;
  /** The real conversation UUID from session_started (pending ID that becomes the row ID). */
  realConversationId: string | null;
  /** Populated when the server resolved an existing thread via resumeByContextPath. */
  resumedFrom: ResumedFrom | null;
  /** Stage 4 (#2886): ambient lifecycle-bar slice (idle/routing/active/ended). */
  workflow: WorkflowLifecycleState;
  /** Stage 4 review F3 (#2886): persisted `workflow_ended_at` from the
   *  conversation row, hydrated on history fetch. The chat surface ORs this
   *  into `workflowEnded` so input stays disabled across reloads even when
   *  the in-memory lifecycle slice is `idle` post-mount. */
  workflowEndedAt: string | null;
  /** PR-B (#3603) — conversation row's `created_at`, hydrated by the
   *  history fetch. The chat surface uses it to gate the
   *  cohort-missing-reply marker on the row-absence cohort window
   *  (2026-05-05..2026-05-12 UTC). `null` before hydration completes;
   *  the marker treats `null` as "do not render". */
  conversationCreatedAt: string | null;
  /** True while a `/api/conversations/:id/messages` fetch is in flight.
   *  Surfaces from the resume-history and mount-time history-fetch effects.
   *  ChatSurface uses this to gate the "Send a message to get started"
   *  empty-state placeholder so it does NOT flash during the round-trip,
   *  and to defer the `onMessageCountChange?.(0)` mount-time write that
   *  would otherwise clobber `useKbLayoutState`'s prefetched messageCount
   *  (race H3 in the resume hydration plan). */
  historyLoading: boolean;
  /** Per-turn stream lifecycle (#3448 PR2). See `StreamState` jsdoc. The
   *  Stop button + Esc shortcut bind to this field, NOT to
   *  `activeLeaderIds.length > 0` — a multi-leader dispatch may have
   *  leaders responding while we are already `"stopping"`. */
  streamState: StreamState;
  /** feat-reasoning-chat-boxes (#5370) — the transient live narration line for
   *  the in-flight turn, or null. Rendered near the "Working…" badge; torn down
   *  by the reducer on every turn-end path. Live-only (never persisted). */
  liveNarration: string | null;
  /** User-initiated Stop. Sends `{ type: "abort_turn", conversationId }` and
   *  optimistically transitions `streamState` to `"stopping"`. No-op when
   *  `streamState !== "streaming"` (idempotent under double-click) or when
   *  no conversationId is resolved yet (pre-`session_started`). */
  abort: () => void;
  /** #5282 — connection-lifecycle slice for the reconnect state machine. The
   *  chat surface feeds `connection.phase` (+ the per-message `retrying` flag)
   *  into `deriveReconnectView` for the State-1-vs-State-2 precedence, renders
   *  State 3 when `phase === "unrecoverable"`, and the State-4 notice from the
   *  transient `connection.resumedAt`. */
  connection: { phase: ConnectionPhase; resumedAt?: number };
  /** #5282 — State-3 "Resume with full context" action. Escapes the sticky
   *  `unrecoverable` phase (via `reset_connection`) and re-opens the socket;
   *  `reconnect` alone is a no-op against the sticky guard. */
  resumeAfterUnrecoverable: () => void;
}

const MAX_BACKOFF = 30_000;
const INITIAL_BACKOFF = 1_000;

/** Close codes where reconnecting will never succeed. */
export const NON_TRANSIENT_CLOSE_CODES: Record<number, { target?: string; reason: string }> = {
  [WS_CLOSE_CODES.AUTH_TIMEOUT]: { target: "/login", reason: "Session expired" },
  [WS_CLOSE_CODES.SUPERSEDED]: { reason: "Superseded by another tab" },
  [WS_CLOSE_CODES.AUTH_REQUIRED]: { target: "/login", reason: "Authentication required" },
  [WS_CLOSE_CODES.TC_NOT_ACCEPTED]: { target: "/accept-terms", reason: "Terms acceptance required" },
  [WS_CLOSE_CODES.INTERNAL_ERROR]: { reason: "Server error" },
  [WS_CLOSE_CODES.RATE_LIMITED]: { reason: "Too many requests. Please try again later." },
  [WS_CLOSE_CODES.IDLE_TIMEOUT]: { reason: "Session expired due to inactivity" },
  // Recovery hint: archive (not just complete) frees a slot — the
  // AFTER UPDATE OF archived_at trigger in migration 036 fires
  // release_conversation_slot only on archive, NOT on status='completed'.
  // (Plan Risk #5: resume_session does not call acquireSlot, so releasing
  // on completed alone would let resumes bypass the cap.)
  // Copy (May-6 #3354) names the dashboard remediation surface, removes
  // the misleading "*completed*" qualifier (active rows can be archived
  // too), and sets expectation about the auto-reclaim window
  // (60 s reaper tick + 120 s threshold ≈ 3 min). The widened
  // `tryLedgerDivergenceRecovery` (server-side) eliminates this dead-end
  // for stale-heartbeat slots; the copy still applies when the cap is
  // genuinely held by a fresh-heartbeat conversation.
  [WS_CLOSE_CODES.CONCURRENCY_CAP]: {
    reason:
      "You've reached your concurrent-conversation limit. Archive an active or completed conversation from the dashboard to free a slot. If a conversation appears stuck Executing, the server will automatically reclaim it within ~3 minutes.",
  },
  // AC-FLOW2: workspace owner revoked this user's membership. Terminal screen
  // rendered by the dashboard layout via OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT.
  // No reconnect (the JWT claim still encodes the now-removed workspace; the
  // user must sign out or switch orgs).
  [WS_CLOSE_CODES.MEMBERSHIP_REVOKED]: {
    reason: "Workspace access revoked",
  },
};

/** Window-event name dispatched on `ws.close(4012)` so a top-level listener
 *  can render the membership-revoked terminal screen. Payload is the
 *  `MembershipRevokedPreamble`. */
export const OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT =
  "soleur:membership-revoked";

/** Combined chat state: messages and activeStreams update atomically via useReducer
 *  so StrictMode double-invocation cannot observe a partially-updated ref.
 *
 *  `pendingTimerAction` carries the timer-side-effect intent declared by the
 *  last stream event out of the pure reducer. It is consumed by a useEffect
 *  and then cleared via `ack_timer_action` so stale intent cannot leak into
 *  subsequent unrelated dispatches. */
export interface ChatState {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  /** Stage 4 (#2886): ambient lifecycle-bar slice. */
  workflow: WorkflowLifecycleState;
  /** Stage 4 (#2886): reverse-lookup index for `subagent_complete`. */
  spawnIndex: SpawnIndex;
  /**
   * #3448 PR2 — per-turn stream lifecycle.
   *
   * Folded into `ChatState` (rather than a parallel `useState`) so transitions
   * are atomic with the reducer-managed `activeStreams` and `messages` they
   * track — a render cannot observe `activeStreams.size === 0` while
   * `streamState === "streaming"` (or vice versa). Also keeps all five
   * transition sites (`stream_start`/`stream`/`tool_use`/`tool_progress` →
   * "streaming"; `enter_stopping` → "stopping"; `clear_streams` → "idle")
   * inside the reducer's `: never` rail, where a future widening of
   * `StreamState` fails build instead of silently flowing into a Send branch.
   */
  streamState: StreamState;
  pendingTimerAction?: StreamEventResult["timerAction"];
  /**
   * #5282 — connection-lifecycle slice. Folded into `ChatState` (not a parallel
   * `useState`) so the sticky-terminal `unrecoverable` guard lives inside the
   * reducer's `: never` rail and transitions are atomic with `streamState`.
   * `ConnectionPhase` is the minimum the socket-layer `ConnectionStatus` lacks
   * (a value that survives the socket flipping back to `connected` on reattach).
   * Fed by `connection_change` (socket/abort handlers) + `reset_connection`
   * (new user turn). See `deriveReconnectView` for the State-1-vs-State-2
   * precedence and the `connection_change` reducer arm for the sticky guard.
   *
   * `resumedAt`: transient render affordance for State 4 (the "Continuing… ·
   * workspace restored" notice). Set on a successful reconnect-reattach; State 3
   * (`unrecoverable`) takes render precedence over it, which enforces "no 3→4
   * flip" at the render layer. NOT a phase — it has no surviving invariant.
   */
  connection: { phase: ConnectionPhase; resumedAt?: number };
  /**
   * feat-reasoning-chat-boxes (#5370) — the TRANSIENT live narration line
   * ("Looking into the navigation issue…"). Owned HERE (the turn-lifecycle
   * reducer), NOT in the pure message-state-machine's `ChatStateSnapshot`,
   * because abort/timeout/disconnect are ws-client actions
   * (`enter_stopping`/`timeout`/`connection_change`/`clear_streams`) that never
   * produce a server `StreamEvent` — so teardown MUST live on those arms or the
   * line persists past turn-end and reads as a finished record (the #1 named
   * brand failure). Single slot (not per-leader): `narrate` registers only on
   * the interactive/cc-router path (single-leader); worst case is a flicker, not
   * a cross-tenant incident. Set by `set_live_narration`; cleared on every
   * turn-end arm + on the turn-ending `stream_event` (activeStreams emptied).
   */
  liveNarration: string | null;
}

export type StreamEventMsg = Parameters<typeof applyStreamEvent>[2];

export type ChatAction =
  | { type: "stream_event"; msg: StreamEventMsg }
  | { type: "timeout"; leaderId: string }
  | { type: "clear_streams" }
  /** feat-reasoning-chat-boxes (#5370) — set the transient live narration line
   *  from a `reasoning_narration` frame. Teardown is owned by the turn-end arms
   *  (clear_streams / enter_stopping / connection_change-non-live) + the
   *  turn-ending stream_event, NOT by a separate clear action. */
  | { type: "set_live_narration"; message: string }
  | { type: "ack_timer_action" }
  | { type: "add_message"; message: ChatMessage }
  | { type: "filter_prepend"; messages: ChatMessage[] }
  | { type: "gate_error"; gateId: string; message: string }
  | { type: "resolve_gate"; gateId: string; selection: string }
  | { type: "resolve_autonomous_disclosure"; gateId: string; selection: string }
  /** #3448 PR2 — user clicked Stop / pressed Esc. Transitions
   *  `streamState` "streaming" → "stopping". No-op if already
   *  "stopping" or "idle" (idempotent under double-click). The
   *  `abort_turn` WS frame is sent imperatively from the hook, NOT
   *  inside the reducer (the reducer is pure). */
  | { type: "enter_stopping" }
  /** #5282 — connection-lifecycle transition observed by the socket/abort
   *  handlers (NOT a server `StreamEvent`/`WSMessage` — onclose has no frame).
   *  Latest-wins (the slice holds exactly one phase, so no banner stacking —
   *  AC4), EXCEPT the sticky guard: once `unrecoverable`, a change to
   *  `live`/`reconnecting` is a no-op (AC11 no 3→4 flip). `resumedAt` (State 4)
   *  rides along only on a `live` transition. */
  | { type: "connection_change"; phase: ConnectionPhase; resumedAt?: number }
  /** #5282 — the ONLY escape from sticky `unrecoverable`, dispatched solely
   *  from the user-new-turn `sendMessage` path. NOT `clear_streams` (which fires
   *  on every reconnect at connect() and from abort handlers — coupling the
   *  reset to it would defeat the sticky guard). Resets to `{ phase: "live" }`. */
  | { type: "reset_connection" }
  | {
      type: "resolve_interactive_prompt";
      promptId: string;
      conversationId: string;
      response: unknown;
    };

export function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case "stream_event": {
      const result = applyStreamEvent(
        state.messages,
        state.activeStreams,
        action.msg,
        state.spawnIndex,
        state.workflow,
      );
      // #3448 PR2: enter "streaming" on the first turn-active event of an
      // idle hook. Any of `stream_start`/`stream`/`tool_use`/`tool_progress`
      // qualifies — see the architectural rationale on `ChatState.streamState`.
      // Stays in "stopping" if the user already aborted; otherwise stays
      // in "streaming" through the rest of the turn.
      const isTurnActive =
        action.msg.type === "stream_start" ||
        action.msg.type === "stream" ||
        action.msg.type === "tool_use" ||
        action.msg.type === "tool_progress";
      const nextStreamState: StreamState =
        state.streamState === "idle" && isTurnActive
          ? "streaming"
          : state.streamState;
      return {
        messages: result.messages,
        activeStreams: result.activeStreams,
        workflow: result.workflow,
        spawnIndex: result.spawnIndex,
        streamState: nextStreamState,
        pendingTimerAction: result.timerAction,
        // #5282 — stream events never touch connection state; carry it through.
        connection: state.connection,
        // #5370 — tear down the live narration line when the turn fully ends
        // (the last stream drained); otherwise carry it through unchanged.
        liveNarration:
          result.activeStreams.size === 0 ? null : state.liveNarration,
      };
    }
    case "set_live_narration":
      // #5370 — single-slot set; teardown happens on the turn-end arms.
      return { ...state, liveNarration: action.message };
    case "timeout": {
      const result = applyTimeout(state.messages, state.activeStreams, action.leaderId);
      return {
        ...state,
        messages: result.messages,
        activeStreams: result.activeStreams,
        // #5370 — a timeout that escalates the last leader to error ends the
        // turn (activeStreams emptied) → tear down the live narration line.
        liveNarration:
          result.activeStreams.size === 0 ? null : state.liveNarration,
        // FR5 (#2861): first timeout returns `{type:"reset"}` so the watchdog
        // restarts against the same leader; second consecutive timeout returns
        // `{type:"clear"}`. Propagate either (may be undefined for stale
        // bubbles) so the useEffect can re-arm or clear the timer.
        pendingTimerAction: result.timerAction,
      };
    }
    case "clear_streams":
      // Review F1: clear_streams must also reset workflow and spawnIndex.
      // Otherwise after `key_invalid` / `session_ended` / socket remount
      // (`connect()`), the lifecycle bar still renders the old workflow's
      // `state: "active"` and stale spawnIndex entries linger.
      // #3448 PR2: also resets streamState to "idle" — atomicity invariant
      // for the per-turn lifecycle slice.
      return {
        ...state,
        activeStreams: new Map(),
        workflow: { state: "idle" },
        spawnIndex: new Map(),
        streamState: "idle",
        pendingTimerAction: undefined,
        // #5370 — turn teardown (session_ended / socket remount / abort
        // completion) clears the transient live narration line.
        liveNarration: null,
      };
    case "enter_stopping":
      // #3448 PR2: idempotent under double-click — only "streaming" → "stopping".
      // "idle" / "stopping" are no-ops. Send-of-`abort_turn` is performed
      // by the caller (the hook's `abort()` callback) BEFORE dispatching
      // this action, so a returning identity-equal state from the reducer
      // signals nothing to the WS frame either way.
      // #5370 — user Stop tears down the live narration line (the turn is
      // ending; the line must never persist as a finished record).
      return state.streamState === "streaming"
        ? { ...state, streamState: "stopping", liveNarration: null }
        : state;
    case "connection_change": {
      // #5282 — sticky guard (AC11): once `unrecoverable`, the in-flight
      // session is genuinely gone (grace expired → replay buffer reclaimed, or
      // a non-transient socket close). The socket-layer `status` flips back to
      // `connected` on reattach and CANNOT express terminal-after-grace, so
      // this guard is the load-bearing invariant that prevents a late reattach
      // frame from flipping State 3 → State 4. The ONLY escape is
      // `reset_connection` (a new user turn). Do NOT relax this to "redundant".
      if (state.connection.phase === "unrecoverable") {
        return state;
      }
      // Latest-wins (AC4): the slice holds exactly one phase, so rapid
      // disconnect→reconnect→disconnect can never stack banners.
      return {
        ...state,
        connection: { phase: action.phase, resumedAt: action.resumedAt },
        // #5370 — a non-live transition (disconnect/reconnecting/unrecoverable)
        // tears down the stale live narration line; the live-only frame does
        // not replay, so a stale line would otherwise hang on reconnect.
        liveNarration: action.phase === "live" ? state.liveNarration : null,
      };
    }
    case "reset_connection":
      // #5282 — escape the sticky `unrecoverable` on an explicit new user turn.
      return state.connection.phase === "live" && state.connection.resumedAt === undefined
        ? state
        : { ...state, connection: { phase: "live" } };
    case "ack_timer_action":
      return state.pendingTimerAction === undefined ? state : { ...state, pendingTimerAction: undefined };
    case "add_message":
      return { ...state, messages: [...state.messages, action.message] };
    case "filter_prepend": {
      const existingIds = new Set(state.messages.map(m => m.id));
      const unique = action.messages.filter(m => !existingIds.has(m.id));
      return { ...state, messages: [...unique, ...state.messages] };
    }
    case "gate_error":
      return {
        ...state,
        messages: state.messages.map(m =>
          m.type === "review_gate" && m.gateId === action.gateId
            ? { ...m, gateError: action.message, resolved: false, selectedOption: undefined }
            : m,
        ),
      };
    case "resolve_gate":
      return {
        ...state,
        messages: state.messages.map(m =>
          m.type === "review_gate" && m.gateId === action.gateId
            ? { ...m, resolved: true, selectedOption: action.selection, gateError: undefined }
            : m,
        ),
      };
    case "resolve_autonomous_disclosure":
      return {
        ...state,
        messages: state.messages.map((m) =>
          m.type === "autonomous_disclosure" && m.gateId === action.gateId
            ? { ...m, resolved: true, selectedOption: action.selection }
            : m,
        ),
      };
    case "resolve_interactive_prompt":
      return {
        ...state,
        messages: state.messages.map((m) =>
          m.type === "interactive_prompt" &&
          m.promptId === action.promptId &&
          m.conversationId === action.conversationId
            ? {
                ...m,
                resolved: true,
                selectedResponse: action.response as ChatMessage extends infer T
                  ? T extends { type: "interactive_prompt"; selectedResponse?: infer R }
                    ? R
                    : never
                  : never,
              }
            : m,
        ),
      };
    default: {
      // Review F12: compile-time exhaustiveness rail on ChatAction.
      // A new action variant added to the union without a case here fails
      // `tsc --noEmit`.
      const _exhaustive: never = action;
      void _exhaustive;
      return state;
    }
  }
}

/** Reconnect delay (ms) after a 4011 TIER_CHANGED close. Uses manual
 *  AbortController + setTimeout so vitest fake timers intercept reliably —
 *  see `cq-abort-signal-timeout-vs-fake-timers`. */
export const TIER_CHANGED_RECONNECT_DELAY_MS = 500;

/** Global event dispatched on a 4010 close; layout listens and mounts the modal. */
export const OPEN_UPGRADE_MODAL_EVENT = "soleur:openUpgradeModal";

export function useWebSocket(conversationId: string): UseWebSocketReturn {
  const [chatState, dispatch] = useReducer(chatReducer, null, (): ChatState => ({
    messages: [],
    activeStreams: new Map<DomainLeaderId, number>(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: null,
  }));

  // Derive activeLeaderIds from reducer state. `applyStreamEvent` preserves the
  // activeStreams Map reference for mid-stream `stream` and `tool_use` events
  // (the hot per-token path), so this memo recomputes only on leader-set
  // boundary events (stream_start, stream_end, review_gate) — matching the
  // cadence of the pre-refactor gated setActiveLeaderIds call.
  const activeLeaderIds = useMemo(
    () => Array.from(chatState.activeStreams.keys()),
    [chatState.activeStreams],
  );

  const [status, setStatus] = useState<ConnectionStatus>("connecting");
  const [disconnectReason, setDisconnectReason] = useState<string>();
  const [lastError, setLastError] = useState<WebSocketError | null>(null);
  const [routeSource, setRouteSource] = useState<"auto" | "mention" | null>(null);
  const [sessionConfirmed, setSessionConfirmed] = useState(false);
  const [realConversationId, setRealConversationId] = useState<string | null>(null);
  const [resumedFrom, setResumedFrom] = useState<ResumedFrom | null>(null);
  // Discriminates a brand-new (deferred-creation) session from a genuine
  // resume so the resume-history effect can skip the fetch for fresh
  // conversations whose DB row does not exist yet. `session_started` sets
  // "fresh" (no row — fetch would 404); `session_resumed` sets "resumed"
  // (row exists, even with 0 messages — fetch the 200-empty body). Keys the
  // FR1 gate on the session kind, NOT on message count, so a resumed-but-
  // empty thread still hydrates. Client-local (no wire change): the server
  // already distinguishes the two via distinct message types.
  const [sessionKind, setSessionKind] = useState<"fresh" | "resumed" | null>(null);
  const [usageData, setUsageData] = useState<UsageData | null>(null);
  // feat-bash-autonomous-default-on — SERVER-resolved autonomous posture for the
  // persistent chip. `null` before the server pushes (chip hidden/neutral);
  // `true` = "Auto-run on" (autonomous AND acked); `false` = "Approve each".
  // Set ONLY from the server `autonomous_posture` frame — never inferred from
  // message presence (a held un-acked disclosure must read "Approve each").
  const [autonomousPosture, setAutonomousPosture] = useState<boolean | null>(null);
  // Stage 4 review F3: persisted `workflow_ended_at` from history fetch.
  const [workflowEndedAt, setWorkflowEndedAt] = useState<string | null>(null);
  // PR-B (#3603) — conversation start time hydrated from history fetch.
  const [conversationCreatedAt, setConversationCreatedAt] = useState<string | null>(null);
  // True while either history-fetch effect (mount-time or resume-by-ID) has
  // an in-flight fetch. ChatSurface gates its empty-state placeholder on
  // `!historyLoading` so the placeholder cannot render during the round-trip,
  // and skips the mount-time `onMessageCountChange?.(0)` write while loading
  // so the trigger button does not flip to "Ask about this document" between
  // the prefetch (`useKbLayoutState`) and the history fetch resolving.
  const [historyLoading, setHistoryLoading] = useState(false);
  // #3448 PR2: per-turn stream lifecycle now lives in `chatState.streamState`
  // (folded into the reducer for atomicity with `activeStreams`/`messages`
  // and a `: never` rail on the union — see ChatState jsdoc).
  // Mirror of `realConversationId` for the `abort()` callback so a stale
  // closure cannot send the wrong conversationId on the wire.
  const realConversationIdRef = useRef<string | null>(null);
  // #5290 false-positive fix — mirror of `sessionKind` for the `auth_ok`
  // reconnect closure. That handler lives in the `connect` useCallback whose
  // dep array excludes `sessionKind`, so the useState would be captured STALE
  // there (unlike the history-fetch useEffect at the bottom, which lists
  // `sessionKind` in its deps and can read the state directly). The ref is read
  // fresh. Kept paired with realConversationIdRef's reset sites so the resume
  // gate survives future refactors that decouple the two writes (#4816
  // corollary).
  const sessionKindRef = useRef<"fresh" | "resumed" | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  // feat-stream-since-disconnect (#5273) — highest server-stamped `seq` this
  // client has rendered for the active conversation. Sent as the `ackSeq`
  // cursor on a transient reconnect (`resume_stream`) and used to dedup
  // replayed frames (`seq <= lastRenderedSeq` were already applied). Survives
  // socket drops (a ref). Reset to -1 on a new/resumed session and on the
  // honest-refetch (`stream_replay{incomplete}`) path. See ADR-059.
  // INVARIANT: this single per-hook cursor is valid only because per-
  // conversation server seq spaces (each from 0) never interleave on one hook
  // WITHOUT an intervening session_started/session_resumed reset (both reset it
  // to -1). The sidebar hook is reused across conversation switches, but each
  // switch fires session_started/resumed first, so two conversations' seq
  // spaces can never be live against the same cursor.
  const lastRenderedSeqRef = useRef<number>(-1);
  // True once the first `auth_ok` of this hook's life has landed. Gates the
  // `resume_stream` reattach to genuine RECONNECTS only — a fresh initial
  // connect must not request replay (its history fetch is authoritative and a
  // replayed `usage_update` would double-count against it).
  const hasConnectedBeforeRef = useRef(false);
  // #5282 — true between a reconnect `auth_ok` (resume_stream sent) and the
  // first genuinely-rendered post-reattach frame. Gates the honest State-4
  // ("workspace restored") notice: only a confirmed resume (a frame actually
  // flowed) sets `connection.resumedAt`, never the optimistic auth_ok. Cleared
  // on confirmation, on `stream_replay{incomplete}` (failed resume), and on a
  // fresh/resumed session boundary so it can't leak into a different turn.
  const reattachPendingRef = useRef(false);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mountedRef = useRef(true);
  /** Most-recent close preamble carried on `ws.message` before `ws.close` fires.
   *  Populated by onmessage for `concurrency_cap_hit` / `tier_changed` types;
   *  consumed + cleared in onclose. */
  const pendingPreambleRef = useRef<
    | ConcurrencyCapHitPreamble
    | TierChangedPreamble
    | MembershipRevokedPreamble
    | null
  >(null);

  /** Map of per-leader timeout timers for stuck THINKING/TOOL_USE states (STUCK_TIMEOUT_MS) */
  const timeoutTimersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  /** Clear a single leader's timeout timer */
  const clearLeaderTimeout = useCallback((leaderId: string) => {
    const timer = timeoutTimersRef.current.get(leaderId);
    if (timer) {
      clearTimeout(timer);
      timeoutTimersRef.current.delete(leaderId);
    }
  }, []);

  /** Clear all timeout timers */
  const clearAllTimeouts = useCallback(() => {
    for (const timer of timeoutTimersRef.current.values()) {
      clearTimeout(timer);
    }
    timeoutTimersRef.current.clear();
  }, []);

  /** Start/reset the stuck-state timeout for a leader — transitions to error on fire
   *  ONLY if the bubble is still in a transitional state (thinking/tool_use).
   *  Guard lives in `applyTimeout` in chat-state-machine.ts so a slow first
   *  token that arrived just before the timer fired cannot clobber a bubble
   *  that has already progressed to streaming or done. See #2136. */
  const resetLeaderTimeout = useCallback((leaderId: string) => {
    clearLeaderTimeout(leaderId);
    const timer = setTimeout(() => {
      if (!mountedRef.current) return;
      dispatch({ type: "timeout", leaderId });
      timeoutTimersRef.current.delete(leaderId);
    }, STUCK_TIMEOUT_MS);
    timeoutTimersRef.current.set(leaderId, timer);
  }, [clearLeaderTimeout]);

  /** #5240 — (re)start EVERY currently-armed timer. Iterates the live timer Map
   *  (NOT `chatState.activeStreams`), mirroring `clearAllTimeouts` so the reset
   *  is self-contained (no cross-state-slice read) and touches exactly the set
   *  of armed timers. Used by the single-leader debug heartbeat, whose
   *  `reset_all` intent has no `leaderId` to name. */
  const resetAllTimeouts = useCallback(() => {
    for (const leaderId of [...timeoutTimersRef.current.keys()]) {
      resetLeaderTimeout(leaderId);
    }
  }, [resetLeaderTimeout]);

  // Mirror realConversationId into a ref so `abort()` reads the latest value
  // without re-binding on every WS frame that updates state. The Stop UX
  // tolerates a one-tick stale read (the user has to click), but the abort
  // payload's conversationId MUST be current — a stale closure here would
  // route the abort to a prior conversation under multi-tab navigation.
  useEffect(() => {
    realConversationIdRef.current = realConversationId;
  }, [realConversationId]);

  // Apply timer side-effects declared by the reducer after each stream event,
  // then clear the pending intent so unrelated subsequent dispatches (add_message,
  // filter_prepend, gate_error, resolve_gate) cannot carry stale timer state
  // forward via `...state` spread. useEffect runs after paint; the latency is
  // negligible for 45-second timeouts.
  useEffect(() => {
    const ta = chatState.pendingTimerAction;
    if (!ta) return;
    if (ta.type === "reset") resetLeaderTimeout(ta.leaderId);
    else if (ta.type === "clear") clearLeaderTimeout(ta.leaderId);
    else if (ta.type === "clear_all") clearAllTimeouts();
    else if (ta.type === "reset_all") resetAllTimeouts();
    else {
      // Exhaustiveness rail: this if-ladder (not an exhaustive switch) is the
      // ONLY runtime consumer of the timerAction union, so tsc cannot otherwise
      // catch a future member added without a branch here — it would silently
      // no-op. A 6th member fails the build at this assignment instead.
      const _exhaustive: never = ta;
      void _exhaustive;
    }
    dispatch({ type: "ack_timer_action" });
  }, [chatState.pendingTimerAction, resetLeaderTimeout, clearLeaderTimeout, clearAllTimeouts, resetAllTimeouts]);

  /** Permanently tear down the WebSocket — prevents reconnect loop.
   *  Mirrors the key_invalid teardown pattern. */
  const teardown = useCallback(() => {
    mountedRef.current = false;
    clearTimeout(reconnectTimerRef.current);
    dispatch({ type: "clear_streams" });
    clearAllTimeouts();
    setSessionConfirmed(false);
    setRealConversationId(null);
    // Keep sessionKind paired with realConversationId: both are only ever
    // written together by the session_started/session_resumed handlers, so
    // clearing the id without clearing the kind would leave a stale "resumed"
    // that could re-arm the resume-history fetch on the next id resolution.
    // (review: P3 reset-symmetry — defends the FR1 gate against future
    // refactors that decouple the two writes.)
    setSessionKind(null);
    sessionKindRef.current = null;
    if (wsRef.current) {
      wsRef.current.onclose = null;
      wsRef.current.close();
    }
  }, [clearAllTimeouts]);

  const getWsUrlAndToken = useCallback(async () => {
    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    const supabase = createClient();
    const { data: { session } } = await supabase.auth.getSession();
    const token = session?.access_token || "";
    return { url: `${proto}://${window.location.host}/ws`, token };
  }, []);

  const send = useCallback((msg: WSMessage) => {
    const ws = wsRef.current;
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(msg));
    }
  }, []);

  const connect = useCallback(async () => {
    if (!mountedRef.current) return;
    // Clear stale state from any prior connection — incoming events on the
    // new socket must not mutate wrong message indices or resume timers
    // that were tied to the previous socket. See #2135.
    dispatch({ type: "clear_streams" });
    clearAllTimeouts();
    setSessionConfirmed(false);
    setUsageData(null);

    // Clean up any existing connection
    if (wsRef.current) {
      wsRef.current.onopen = null;
      wsRef.current.onclose = null;
      wsRef.current.onmessage = null;
      wsRef.current.onerror = null;
      if (
        wsRef.current.readyState === WebSocket.OPEN ||
        wsRef.current.readyState === WebSocket.CONNECTING
      ) {
        wsRef.current.close();
      }
    }

    setStatus("connecting");
    const { url, token } = await getWsUrlAndToken();
    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      if (!mountedRef.current) return;
      // Send auth as first message — do NOT set status to "connected" yet
      ws.send(JSON.stringify({ type: "auth", token }));
    };

    ws.onmessage = (event) => {
      if (!mountedRef.current) {
        // Stale frame after teardown — onmessage stays attached for the
        // close handshake. See learnings/ui-bugs/2026-05-05-kb-chat-continuing-banner-h1-h5-residual-races.md (#3267).
        // rawPrefix carries the frame's conversationId (when present) for
        // correlation; truncated to bound ingestion cost on a malformed-frame storm.
        Sentry.addBreadcrumb({
          category: "kb-chat",
          message: "ws-message-after-teardown",
          level: "warning",
          data: { rawPrefix: String(event.data).slice(0, 64) },
        });
        return;
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(event.data);
      } catch {
        return;
      }

      // Close preambles are sent immediately before ws.close(4010/4011/4012). Cache
      // the payload so onclose can dispatch the modal with tier/count/org context.
      if (parsed && typeof parsed === "object" && "type" in parsed) {
        const t = (parsed as { type: string }).type;
        if (
          t === "concurrency_cap_hit" ||
          t === "tier_changed" ||
          t === "membership_revoked"
        ) {
          pendingPreambleRef.current = parsed as
            | ConcurrencyCapHitPreamble
            | TierChangedPreamble
            | MembershipRevokedPreamble;
          return;
        }
      }

      // FR4 (#2861): boundary guard. Drop any event whose type isn't in the
      // known allowlist, and breadcrumb it so server/client skew is visible.
      // Stage 3 (#2885) added a Zod schema as the strict gate; the
      // `isKnownWSMessageType` allowlist stays as a cheap fast-path so a
      // single bad-`type` frame doesn't pay for full schema validation.
      const rawType = (parsed as { type?: unknown } | null)?.type;
      if (!isKnownWSMessageType(rawType)) {
        reportSilentFallback(null, {
          feature: "command-center",
          op: "ws-unknown-event",
          extra: { rawType: typeof rawType === "string" ? rawType : String(rawType) },
        });
        return;
      }

      const parseResult = parseWSMessage(parsed);
      if (!parseResult.ok) {
        // Strip per-issue `input` values from the Zod error before
        // breadcrumbing — Zod 4 includes the offending payload value in
        // each issue's `input` field, which would exfiltrate frame data
        // through Sentry on a malformed-frame storm (CWE-201). Keep only
        // the issue path + message + code.
        const sanitizedIssues = parseResult.error.issues.map((issue) => ({
          path: issue.path,
          code: issue.code,
          message: issue.message,
        }));
        reportSilentFallback(null, {
          feature: "command-center",
          op: "ws-zod-parse-failure",
          extra: {
            rawType: typeof rawType === "string" ? rawType : String(rawType),
            issues: sanitizedIssues,
          },
        });
        return;
      }
      const msg = parseResult.msg;

      // feat-stream-since-disconnect (#5273) — replay dedup gate. Buffered-
      // family frames carry a server-stamped monotonic `seq`. After a within-
      // grace reconnect the server replays the gap's frames; any with
      // `seq <= lastRenderedSeq` were already rendered live (pre-disconnect)
      // and MUST be dropped BEFORE applying — critically before the additive
      // `usage_update` accumulation below, or replayed cost double-counts. New
      // gap frames (`seq > lastRenderedSeq`) advance the cursor and render.
      // Non-buffered frames carry no `seq` and bypass the gate.
      const frameSeq = (msg as { seq?: number }).seq;
      if (typeof frameSeq === "number") {
        if (frameSeq <= lastRenderedSeqRef.current) {
          return; // already-rendered replayed frame — drop
        }
        lastRenderedSeqRef.current = frameSeq;
      }

      switch (msg.type) {
        case "auth_ok": {
          setStatus("connected");
          backoffRef.current = INITIAL_BACKOFF;
          // feat-stream-since-disconnect (#5273) — on a genuine RECONNECT (not
          // the first connect of this hook's life), if we were mid-conversation
          // when the socket dropped, reattach to the live stream and request
          // replay of frames emitted during the gap. The agent kept running
          // through the 30s grace window, so the server replays `seq > ackSeq`
          // then live frames resume; on a miss it sends stream_replay{incomplete}
          // and we fall back to an honest history refetch. NOT resume_session
          // (which would abort the live agent).
          const isReconnect = hasConnectedBeforeRef.current;
          hasConnectedBeforeRef.current = true;
          const activeConvId = realConversationIdRef.current;
          // #5290 false-positive fix — only request replay for a row that
          // PROVABLY EXISTS server-side, so the owner-scoped `(id,user_id)`
          // lookup cannot return zero rows and mint a spurious
          // `op=ownership-mismatch`. Two eligible cases:
          //   (1) `"resumed"` — a materialized, owned row (the sidebar resume).
          //   (2) `"fresh"` that has ALREADY rendered ≥1 server-stamped frame
          //       (`lastRenderedSeq >= 0`). A stamped frame is emitted only
          //       after the agent starts streaming, which only happens once the
          //       deferred row has materialized on the first chat message — so a
          //       rendered frame is proof the row exists. This recovers the
          //       mid-turn reconnect case (new chat, first turn streaming, socket
          //       drops): its gap frames replay instead of being lost (review:
          //       user-impact P2).
          // A `"fresh"` conv that has streamed NOTHING yet (`lastRenderedSeq
          // === -1`) stays ineligible — that is the not-yet-materialized race
          // whose `resume_stream` produced the false positive. `null`→ineligible.
          // Positive allowlist over the `"fresh" | "resumed" | null` union; never
          // `!== "fresh"` (#4816 single-literal-gate corollary: a future 4th kind
          // forces a conscious in/out call).
          const sessionKindNow = sessionKindRef.current;
          const replayEligible =
            sessionKindNow === "resumed" ||
            (sessionKindNow === "fresh" && lastRenderedSeqRef.current >= 0);
          if (isReconnect && activeConvId && replayEligible) {
            const ackSeq = lastRenderedSeqRef.current;
            send({
              type: "resume_stream",
              conversationId: activeConvId,
              ...(ackSeq >= 0 ? { ackSeq } : {}),
            });
            // #5282 — clear the State-1 banner (live) but do NOT set `resumedAt`
            // yet: the resume is UNCONFIRMED until the server actually replays a
            // frame. Setting State 4 ("workspace restored") here would be a lie
            // for the ~1-RTT window before a `stream_replay{incomplete}` arrives
            // on a failed resume — a false "restored" that then flips to State 3
            // (the inverse of the no-3→4-flip invariant). Instead, arm a pending
            // flag; the FIRST genuinely-rendered post-reattach frame confirms the
            // stream is alive and promotes to State 4. The sticky guard still
            // no-ops this `live` if `unrecoverable` was already set (AC11).
            reattachPendingRef.current = true;
            dispatch({ type: "connection_change", phase: "live" });
          } else {
            // Not replay-eligible: a fresh initial connect, OR a reconnect of a
            // `"fresh"`/unknown-kind session (no materialized row to replay, no
            // buffered turn worth requesting). Plain `live`, no replay request,
            // no notice.
            dispatch({ type: "connection_change", phase: "live" });
          }
          break;
        }

        case "stream_start":
        case "tool_use":
        case "tool_progress":
        case "stream":
        case "stream_end":
        case "command_stream":
        // feat-debug-mode-stream — harness instruction stream (separate panel).
        case "debug_event":
        case "review_gate":
        case "autonomous_disclosure":
        case "subagent_spawn":
        case "subagent_complete":
        case "workflow_started":
        case "workflow_ended":
        case "interactive_prompt":
        case "context_reset": {
          // Store routing source from the first stream_start
          if (msg.type === "stream_start" && msg.source) {
            setRouteSource(msg.source);
          }
          // #3448 PR2: streamState transitions live inside the reducer
          // (`stream_event` case in chatReducer). The reducer enters
          // `"streaming"` on the first turn-active event of an idle hook
          // and leaves all other transitions to `clear_streams` /
          // `enter_stopping`. Atomic with the rest of ChatState.
          // Dispatch to the pure reducer — no ref mutations inside the updater.
          // activeStreams and messages update atomically; pendingTimerAction carries
          // the timer intent out of the pure reducer for the useEffect above. See #2217.
          // Stage 3 (#2885) — `subagent_*`, `workflow_*`, `interactive_prompt`
          // are inert pass-throughs in the reducer; Stage 4 wires rendering.
          dispatch({ type: "stream_event", msg });
          // #5282 — a genuinely-rendered post-reattach frame CONFIRMS the resume
          // succeeded (replayed gap frame or resumed live frame). Promote to the
          // honest State-4 "workspace restored" notice now, not optimistically at
          // auth_ok. Replayed already-seen frames were dropped by the seq dedup
          // gate above, so reaching here means real forward progress. The sticky
          // guard no-ops this if `unrecoverable` was set in the interim.
          if (reattachPendingRef.current) {
            reattachPendingRef.current = false;
            dispatch({ type: "connection_change", phase: "live", resumedAt: Date.now() });
          }
          break;
        }

        case "autonomous_posture": {
          // Server truth for the persistent chip — never a message-presence guess.
          setAutonomousPosture(msg.autonomous);
          break;
        }

        case "error": {
          // `clear_streams` resets streamState to "idle" atomically.
          dispatch({ type: "clear_streams" });
          clearAllTimeouts();

          // Key invalidation: set structured error instead of redirect
          if (msg.errorCode === "key_invalid") {
            setLastError({
              code: "key_invalid",
              message: "Your API key is invalid or expired.",
              action: { label: "Update key", href: "/dashboard/settings" },
            });
            teardown();
            return;
          }

          if (msg.errorCode === "rate_limited") {
            setLastError({
              code: "rate_limited",
              message: "You've been rate limited. Please wait before trying again.",
            });
          }

          // feat-operator-cc-oauth FR5 — subscription credit/rate-limit
          // exhaustion on an oauth_token run. Distinct from `key_invalid`
          // (no "Update key" action — re-pasting the token would be the
          // WRONG action) and non-retryable (the credit window must reset).
          // Server-side producer (SDK credit-signal classification) lands on
          // first real hit per plan §Phase 5; the reception + render path is
          // pre-wired here so that hit needs no client change.
          if (msg.errorCode === "subscription_limit") {
            setLastError({
              code: "subscription_limit",
              message:
                "Claude subscription limit reached. Runs resume when the subscription credit window resets.",
            });
            teardown();
            return;
          }

          // #3254 — image-placeholder-strip surfaced a structured error.
          // Promote into `lastError` so a programmatic / agent-driven
          // client can branch on `code` instead of regexing the assistant
          // message text. The message itself ALSO falls through to the
          // chat-bubble path below for the human reader.
          if (msg.errorCode === "image_paste_lost") {
            setLastError({
              code: "image_paste_lost",
              message: msg.message,
            });
          }

          // ADR-044 PR-1 — member reset to an empty solo workspace. Surface a
          // structured switcher action so a programmatic client can branch on
          // `code`; the action opens the workspace switcher in the dashboard
          // chrome (NOT a direct `set_current_workspace_id(switchToWorkspaceId)`
          // — a reset user is a NON-member of that team by construction, so a
          // direct switch would be rejected; the switcher lists only joinable
          // workspaces). Falls through to the chat-bubble so the human reader
          // also sees the honest message text.
          if (msg.errorCode === "workspace_switch_required") {
            setLastError({
              code: "workspace_switch_required",
              message: msg.message,
              action: { label: "Switch workspace", href: "/dashboard" },
            });
          }

          if (msg.errorCode?.startsWith("delegation_")) {
            setLastError({
              code: msg.errorCode,
              message: msg.message,
              action: { label: "View settings", href: "/dashboard/settings/team" },
            });
            return;
          }

          // Route gateId-targeted errors to the review gate message
          if (msg.gateId) {
            dispatch({ type: "gate_error", gateId: msg.gateId, message: msg.message });
            break;
          }

          dispatch({
            type: "add_message",
            message: {
              id: `err-${Date.now()}`,
              role: "assistant",
              content: `Error: ${msg.message}`,
              type: "text",
            },
          });
          break;
        }

        case "session_ended": {
          dispatch({ type: "clear_streams" });
          clearAllTimeouts();
          // #5282 DELIBERATE NON-MAPPING (do not "fix" this back to the plan's
          // original AC3/FR4): `session_ended` does NOT dispatch
          // `connection_change(unrecoverable)`. Every live `session_ended.reason`
          // is recoverable/normal — `turn_complete` (every normal turn),
          // `user_aborted`, `closed`, terminal-workflow statuses (recoverable via
          // a new turn), or `session_revoked` (which has its OWN 4012 terminal
          // screen). Mapping it to State 3 would flash "session reset" on EVERY
          // completed turn. The genuine in-flight-reclaim case happens server-side
          // during the disconnect grace window (ws-handler.ts grace-expiry →
          // abortSession + streamReplayBuffer.clear) while the client is already
          // disconnected; the client learns of it on the NEXT reconnect via
          // `stream_replay{incomplete}` — the actual wired unrecoverable signal.
          // #3448 PR2 (review fix): a turn ended — reset streamState so the
          // Send button comes back. Initial implementation gated this on
          // `msg.conversationId === realConversationIdRef.current` for
          // multi-tab disambiguation, but that left two failure modes:
          //   (a) stuck-stopping deadlock — if the server ever emits a
          //       mismatched conversationId (server bug, race during a
          //       `session_resumed` transition), the client would sit in
          //       "stopping" forever with the Send button never returning.
          //   (b) asymmetric scoping — `clear_streams` and
          //       `clearAllTimeouts()` above this block run unconditionally,
          //       so the gate only protected `streamState`, not the rest of
          //       the lifecycle slice. Either we gate everything or nothing
          //       (architecture-strategist + data-integrity findings).
          // Resolution: reset unconditionally (mirror clear_streams behavior),
          // emit a Sentry breadcrumb when conversationId mismatches the
          // current realConversationId so the observability stays — if the
          // server ever produces such a frame, the breadcrumb surfaces it
          // for triage instead of leaving a silent Stop UI deadlock.
          const targetConv = realConversationIdRef.current;
          if (
            msg.conversationId &&
            targetConv &&
            msg.conversationId !== targetConv
          ) {
            Sentry.addBreadcrumb({
              category: "abort-turn",
              message: "session-ended-conversationid-mismatch",
              level: "warning",
              data: {
                received: msg.conversationId,
                current: targetConv,
                reason: msg.reason,
              },
            });
          }
          // streamState reset to "idle" handled by `clear_streams` above.
          // Don't display "turn_complete" as a visible message — it's a lifecycle signal
          if (msg.reason !== "turn_complete") {
            dispatch({
              type: "add_message",
              message: {
                id: `end-${Date.now()}`,
                role: "assistant",
                content: `Session ended: ${msg.reason}`,
                type: "text",
              },
            });
          }
          break;
        }

        case "session_started": {
          if (msg.conversationId) {
            setRealConversationId(msg.conversationId);
            // #3448 PR2 (review fix): mirror to ref synchronously so a
            // first-turn Stop click that races the realConversationId
            // useEffect mirror (line below the WS message handler block)
            // still sees the resolved id. Without this, abort() at
            // streamState="streaming" would no-op silently — the
            // brand-survival worst case named in the plan ("Stop button
            // click that silently does nothing") on the most common
            // new-conversation path.
            realConversationIdRef.current = msg.conversationId;
          }
          setResumedFrom(null);
          // feat-stream-since-disconnect (#5273) — a new conversation's stream
          // starts at seq 0; reset the replay cursor so the first live frame
          // is never mistaken for an already-rendered replay.
          lastRenderedSeqRef.current = -1;
          // #5282 — a new session is not a reattach; cancel any pending State-4
          // confirmation so the first frame of this fresh turn can't promote to
          // a "workspace restored" notice.
          reattachPendingRef.current = false;
          // Deferred-creation: no DB row exists for this pending UUID yet
          // (it materializes on the first chat message). Mark fresh so the
          // resume-history effect skips the would-be-404 fetch (FR1).
          setSessionKind("fresh");
          // #5290 — keep the ref in lockstep with the state for the auth_ok
          // reconnect gate (a fresh deferred conv must NOT request resume_stream).
          sessionKindRef.current = "fresh";
          setSessionConfirmed(true);
          break;
        }

        case "session_resumed": {
          setRealConversationId(msg.conversationId);
          // feat-stream-since-disconnect (#5273) — full transcript resume
          // rehydrates from persisted history; reset the replay cursor.
          lastRenderedSeqRef.current = -1;
          // #5282 — full transcript resume is a new turn boundary, not a live
          // reattach; cancel any pending State-4 confirmation.
          reattachPendingRef.current = false;
          // Same synchronous-ref invariant as session_started — a fast
          // Stop click after `session_resumed` lands but before the
          // mirroring useEffect runs MUST find the resolved id.
          realConversationIdRef.current = msg.conversationId;
          setResumedFrom({
            conversationId: msg.conversationId,
            timestamp: msg.resumedFromTimestamp,
            messageCount: msg.messageCount,
          });
          // Real row exists (even if messageCount === 0) — the resume-history
          // effect SHOULD fetch (api-messages returns 200-empty for a zero-
          // message row). Gate keys on session kind, not count (FR2).
          setSessionKind("resumed");
          // #5290 — ref lockstep: a resumed (materialized, owned) row is the
          // ONLY kind that may request resume_stream replay on reconnect.
          sessionKindRef.current = "resumed";
          setSessionConfirmed(true);
          break;
        }

        case "usage_update": {
          setUsageData((prev) => ({
            totalCostUsd: (prev?.totalCostUsd ?? 0) + msg.totalCostUsd,
            inputTokens: (prev?.inputTokens ?? 0) + msg.inputTokens,
            outputTokens: (prev?.outputTokens ?? 0) + msg.outputTokens,
            // `?? 0` coerces frames from old-shape servers (cache fields
            // absent) during a rolling deploy. Tighten to required when
            // the Zod schema flips back to non-optional.
            cacheReadInputTokens:
              (prev?.cacheReadInputTokens ?? 0) + (msg.cacheReadInputTokens ?? 0),
            cacheCreationInputTokens:
              (prev?.cacheCreationInputTokens ?? 0) +
              (msg.cacheCreationInputTokens ?? 0),
          }));
          break;
        }

        // Client→server message types (never received here) and inert
        // server-side acks. Listed explicitly so a new server→client variant
        // added to `WSMessage` falls through to the `: never` rail and
        // fails `tsc --noEmit` per `cq-union-widening-grep-three-patterns`.
        case "auth":
        case "chat":
        case "start_session":
        case "resume_session":
        case "close_conversation":
        case "review_gate_response":
        case "autonomous_disclosure_response":
        case "abort_turn":
        case "interactive_prompt_response":
        case "fanout_truncated":
        case "upgrade_pending":
        // feat-stream-since-disconnect (#5273) — client→server only; the
        // client never receives it. Listed for exhaustiveness.
        case "resume_stream":
          break;
        case "revocation_notice": {
          // #3930 — discriminated revocation toast. Replaces the generic
          // "Authentication unavailable; retry shortly" surface with a
          // founder-readable reason from `denied_jti.reason`. The
          // server-side handler closes the socket immediately after
          // emitting this frame; we surface via `setLastError` so the
          // existing toast UX renders the message + Reason text.
          dispatch({ type: "clear_streams" });
          clearAllTimeouts();
          setLastError({
            code: "session_expired",
            message: msg.reason
              ? `Your session was revoked. Reason: ${msg.reason}. Contact support.`
              : "Your session was revoked. Contact support.",
          });
          break;
        }
        case "stream_replay": {
          // feat-stream-since-disconnect (#5273) — fallback signal: the server
          // could not replay from our cursor (evicted, or the buffer was
          // reclaimed after grace/abort). Fall back to the v1 honest persisted-
          // history refetch (never a silent stale/duplicate render), and
          // reconcile cost to the AUTHORITATIVE persisted value — the additive
          // pre-disconnect `usage_update` partials may have over/under-counted,
          // and the normal `seedCostData` (prev ?? costData) would keep the
          // stale in-memory value. Reset the replay cursor so subsequent live
          // frames render from the rehydrated base. See ADR-059.
          lastRenderedSeqRef.current = -1;
          const targetId = realConversationIdRef.current ?? msg.conversationId;
          const controller = new AbortController();
          void runHistoryFetch(targetId, controller, { reconcileCost: true });
          // #5282 — failed resume: cancel the pending State-4 confirmation so a
          // later unrelated frame cannot promote to a false "restored" notice.
          reattachPendingRef.current = false;
          // #5282 — this is THE honest unrecoverable signal (AC11): the reconnect
          // requested replay and the server's buffer was reclaimed after the
          // grace window / abort (ADR-059). The in-flight session is gone, so go
          // STICKY-unrecoverable (State 3, "Resume with full context") — never a
          // stale State-4 "resumed" lie. The sticky guard then holds State 3 even
          // if a late auth_ok dispatches `live`.
          dispatch({ type: "connection_change", phase: "unrecoverable" });
          break;
        }
        case "reasoning_narration": {
          // feat-reasoning-chat-boxes (#5370) — transient live status line.
          // Set the single liveNarration slot; teardown is owned by the
          // turn-end reducer arms (clear_streams / enter_stopping /
          // connection_change-non-live) + the turn-ending stream_event. This
          // frame is live-only (no seq), so it bypassed the replay-dedup gate
          // above and never replays on reconnect.
          dispatch({ type: "set_live_narration", message: msg.message });
          break;
        }
        case "turn_summary": {
          // feat-reasoning-chat-boxes (#5370) — durable per-turn summary box.
          // Buffered (carries seq → already advanced the replay cursor above),
          // so it survives reconnect replay AND is rehydrated from the messages
          // table on reload. Route through the message reducer to append a
          // ChatTurnSummaryMessage to the main list.
          dispatch({ type: "stream_event", msg });
          break;
        }
        default: {
          // Review F12: compile-time exhaustiveness rail. A new server→client
          // variant added to `WSMessage` without a case here fails build.
          const _exhaustive: never = msg;
          void _exhaustive;
          break;
        }
      }
    };

    ws.onclose = (event: CloseEvent) => {
      if (!mountedRef.current) return;

      // 4010 CONCURRENCY_CAP — dispatch modal with cached preamble payload, then
      // fall through to the standard non-transient teardown (no reconnect).
      if (event.code === WS_CLOSE_CODES.CONCURRENCY_CAP) {
        const preamble = pendingPreambleRef.current;
        pendingPreambleRef.current = null;
        if (typeof window !== "undefined") {
          window.dispatchEvent(
            new CustomEvent(OPEN_UPGRADE_MODAL_EVENT, { detail: preamble ?? null }),
          );
        }
      }

      // 4012 MEMBERSHIP_REVOKED — workspace owner removed this user. Dispatch
      // the terminal-screen event with the preamble (org name) and fall through
      // to the standard non-transient teardown path (no reconnect).
      if (event.code === WS_CLOSE_CODES.MEMBERSHIP_REVOKED) {
        const preamble = pendingPreambleRef.current as
          | MembershipRevokedPreamble
          | null;
        pendingPreambleRef.current = null;
        if (typeof window !== "undefined") {
          window.dispatchEvent(
            new CustomEvent(OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT, {
              detail: preamble ?? null,
            }),
          );
        }
      }

      // 4011 TIER_CHANGED — schedule a single reconnect after a fixed delay so
      // the new plan_tier is re-read from the DB. Use a manual setTimeout (not
      // AbortSignal.timeout) so vitest fake timers intercept reliably.
      if (event.code === WS_CLOSE_CODES.TIER_CHANGED) {
        pendingPreambleRef.current = null;
        setStatus("reconnecting");
        // #5282 — a tier-change reconnect is a transient drop (State 1).
        dispatch({ type: "connection_change", phase: "reconnecting" });
        backoffRef.current = INITIAL_BACKOFF;
        if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = setTimeout(() => {
          if (mountedRef.current) connect();
        }, TIER_CHANGED_RECONNECT_DELAY_MS);
        return;
      }

      const entry = NON_TRANSIENT_CLOSE_CODES[event.code];
      if (entry) {
        teardown();
        setStatus("disconnected");
        setDisconnectReason(entry.reason);

        // Set structured error for non-redirect disconnections
        if (!entry.target) {
          setLastError({
            code: "disconnected",
            message: entry.reason,
          });
          // #5282 — a non-transient close with NO redirect target (server
          // error, superseded, rate-limited, idle-timeout) cannot be recovered
          // by reconnect → sticky State 3. Redirect-target closes (auth
          // expired/terms) navigate away below, so marking them unrecoverable
          // would be a State-3 banner the user never sees; skip those.
          // CONCURRENCY_CAP (4010) + MEMBERSHIP_REVOKED (4012) have their OWN
          // dedicated terminal UI (upgrade modal / revoked screen) dispatched
          // above; a State-3 banner under those is redundant and only invisible
          // today because the overlays occlude it — don't dispatch for them.
          if (
            event.code !== WS_CLOSE_CODES.CONCURRENCY_CAP &&
            event.code !== WS_CLOSE_CODES.MEMBERSHIP_REVOKED
          ) {
            dispatch({ type: "connection_change", phase: "unrecoverable" });
          }
        }

        if (entry.target) {
          window.location.href = entry.target;
        }
        return;
      }

      // Transient failure — reconnect with exponential backoff
      setStatus("reconnecting");
      // #5282 — transient drop (State 1): we will reconnect with backoff.
      dispatch({ type: "connection_change", phase: "reconnecting" });
      const delay = backoffRef.current;
      backoffRef.current = Math.min(backoffRef.current * 2, MAX_BACKOFF);

      reconnectTimerRef.current = setTimeout(() => {
        if (mountedRef.current) {
          connect();
        }
      }, delay);
    };

    ws.onerror = () => {
      // onclose will fire after onerror — reconnect logic lives there
    };
  }, [getWsUrlAndToken, teardown, clearAllTimeouts]);

  /** Fetch and map conversation history from the messages API. Shared by
   *  the mount-time effect (non-"new" IDs) and the resume effect ("new" → UUID). */
  async function fetchConversationHistory(
    targetId: string,
    signal: AbortSignal,
  ): Promise<{
    messages: ChatMessage[];
    costData: UsageData | null;
    workflowEndedAt: string | null;
    createdAt: string | null;
  } | null> {
    // Validate targetId is a safe path segment to satisfy CodeQL's
    // request-forgery check. Allows UUIDs and alphanumeric IDs only.
    // The server enforces ownership via user_id.
    if (!/^[0-9a-zA-Z-]+$/.test(targetId)) return null;

    const supabase = createClient();
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      // Distinct op disambiguates from `history-fetch-failed` (4xx/5xx) and
      // `history-fetch-error` (network throw). See #3267 learning.
      reportSilentFallback(null, {
        feature: "kb-chat",
        op: "history-fetch-no-session",
        extra: { conversationId: targetId },
      });
      return null;
    }

    // NOTE: this endpoint is wired in the Node custom server
    // (`server/api-messages.ts` via `server/index.ts:75-81` regex), NOT in
    // `app/api/conversations/`. Do not add a duplicate `route.ts` — Next.js
    // routing precedence between the App Router and the custom server is
    // undefined and the duplicate would shadow this path silently.
    const res = await fetch(
      `/api/conversations/${targetId}/messages`,
      {
        headers: { Authorization: `Bearer ${session.access_token}` },
        signal,
      },
    );
    if (!res.ok) {
      // A 404 on the deferred-creation path is an expected, recoverable
      // state (FR1 eliminates it at the source for fresh KB-chat opens; a
      // residual 404 is a stale deep-link or multi-tab race). Mirror it at
      // WARNING level so it stays observable without paging. Genuine
      // failures (401 invalid-token, 500 messages-load) keep ERROR level
      // and continue to page. Op string + HTTP handling unchanged (FR4).
      const mirror = res.status === 404 ? warnSilentFallback : reportSilentFallback;
      mirror(null, {
        feature: "kb-chat",
        op: "history-fetch-failed",
        extra: { conversationId: targetId, status: res.status },
      });
      return null;
    }

    const json = await res.json();
    type RawAttachment = {
      id: string;
      storage_path: string;
      filename: string;
      content_type: string;
      size_bytes: number;
    };
    type RawUsage = {
      input_tokens: number;
      output_tokens: number;
      cost_usd?: number | null;
      completed_actions?: Array<{
        tool_name: string;
        input_summary: string;
        result_summary: string;
      }>;
    };
    const mapped = json.messages.map((m: {
      id: string;
      role: string;
      content: string;
      leader_id: string | null;
      message_attachments?: RawAttachment[] | null;
      status?: "complete" | "aborted" | null;
      usage?: RawUsage | null;
      message_kind?: string | null;
    }): ChatMessage => {
      // feat-reasoning-chat-boxes (#5370) — a persisted turn_summary row
      // (message_kind, migration 105) rehydrates as the durable confirmed box
      // (plain-text render), NOT a generic text bubble. Branch BEFORE the text
      // mapping so the discriminator is honored on reload. A future unknown
      // message_kind falls through to the text mapping (forward-compatible
      // read; the render switch is the authoritative throw-on-unknown gate).
      if (m.message_kind === "turn_summary") {
        return {
          id: m.id,
          role: "assistant" as const,
          content: m.content,
          type: "turn_summary" as const,
        };
      }
      return {
      id: m.id,
      role: m.role as "user" | "assistant",
      content: m.content,
      type: "text" as const,
      // Trusted DB-sourced leader id; the column is unconstrained text but is
      // only ever written from the DomainLeaderId set. (The explicit return
      // annotation above makes this cast necessary; pre-annotation it was an
      // implicit widening.)
      leaderId: (m.leader_id ?? undefined) as DomainLeaderId | undefined,
      // History messages intentionally leave state undefined so the
      // completion checkmark only appears on messages that completed via a
      // WS stream event in the current session. renderBubbleContent handles
      // undefined state via its default branch (MarkdownRenderer), which is
      // functionally identical to case "done" for messages without toolsUsed.
      // See #2218 (checkmark on historical bubbles) and #2139 (original fix).
      attachments: (m.message_attachments ?? []).map((a) => ({
        id: a.id,
        storagePath: a.storage_path,
        filename: a.filename,
        contentType: a.content_type,
        sizeBytes: a.size_bytes,
      })),
      // #3448 PR2: surface persistence-tier abort status + usage snapshot
      // so MessageBubble can render the abort marker on history reload.
      // Review fix (perf): only attach the `usage` object when the row is
      // actually aborted — otherwise every history-loaded `complete` row
      // carries a fresh object literal that defeats <MessageBubble>'s
      // React.memo (referential inequality on `usage` re-renders the
      // bubble on every parent render, regressing the 10-50 Hz token-stream
      // memo guarantee on long threads).
      status: m.status ?? undefined,
      // #3640 F6 — derive nested `usage.variant` from `leader_id` per the
      // `AbortMarkerUsage` doc-comment in `components/chat/message-bubble.tsx`
      // and the `Message.usage` doc-comment in `lib/types.ts`. The cc-router path
      // (`leader_id === CC_ROUTER_LEADER_ID`) persists the cc-narrowed
      // `{ cost_usd }` shape; the legacy agent-runner path persists the
      // full `UsageSnapshot`. Downstream readers (`renderAbortedAssistant`
      // in `message-bubble.tsx`) switch on `usage.variant` instead of the
      // pre-#3640 `typeof === "number"` field-presence checks.
      usage:
        m.status === "aborted" && m.usage
          ? m.leader_id === CC_ROUTER_LEADER_ID
            ? {
                variant: "cc" as const,
                cost_usd: m.usage.cost_usd ?? null,
              }
            : {
                variant: "legacy" as const,
                input_tokens: m.usage.input_tokens,
                output_tokens: m.usage.output_tokens,
                cost_usd: m.usage.cost_usd ?? null,
                completed_actions: m.usage.completed_actions,
              }
          : null,
      };
    });

    const costData: UsageData | null =
      json.totalCostUsd > 0
        ? {
            totalCostUsd: json.totalCostUsd,
            inputTokens: json.inputTokens,
            outputTokens: json.outputTokens,
            // History responses pre-2026-05-12 omit cache token fields;
            // default to 0 so the resume path can hydrate without
            // throwing on missing fields. Forward-going responses
            // populate these from `api-messages.ts`.
            cacheReadInputTokens:
              typeof json.cacheReadInputTokens === "number"
                ? json.cacheReadInputTokens
                : 0,
            cacheCreationInputTokens:
              typeof json.cacheCreationInputTokens === "number"
                ? json.cacheCreationInputTokens
                : 0,
          }
        : null;

    const workflowEndedAtFromServer: string | null =
      typeof json.workflowEndedAt === "string" ? json.workflowEndedAt : null;

    const createdAtFromServer: string | null =
      typeof json.createdAt === "string" ? json.createdAt : null;

    return {
      messages: mapped,
      costData,
      workflowEndedAt: workflowEndedAtFromServer,
      createdAt: createdAtFromServer,
    };
  }

  /** Seed usageData from fetched cost data. Uses functional updater so a
   *  racing usage_update WS event is never overwritten by stale history. */
  function seedCostData(costData: UsageData | null) {
    if (costData) {
      setUsageData(prev => prev ?? costData);
    }
  }

  /** Stage 4 review F3: seed `workflowEndedAt` from history fetch.
   *  Functional updater so a racing `workflow_ended` WS event that
   *  preceded the fetch is not clobbered by stale (null) history. */
  function seedWorkflowEndedAt(value: string | null) {
    if (value) setWorkflowEndedAt((prev) => prev ?? value);
  }

  // Single hydration helper used by both the mount-time effect (non-"new" IDs)
  // and the resume effect ("new" → resolved UUID via session_resumed). Keeps
  // the dispatch + seed + Sentry-mirror lifecycle in one place so a future
  // change (extra seed, retry policy, etc.) cannot drift between the two
  // call sites — exactly the failure mode that produced this bug class.
  async function runHistoryFetch(
    targetId: string,
    controller: AbortController,
    opts?: { reconcileCost?: boolean },
  ) {
    setHistoryLoading(true);
    try {
      const result = await fetchConversationHistory(targetId, controller.signal);
      if (!result) return;
      // Pathological "had data and dropped it" branch — gated on result !== null
      // so the routine "abort before fetch resolved" path (which throws
      // AbortError into the catch) does not generate noise. Same `warning`
      // level as the empty-200 breadcrumb so Sentry's per-event downsampling
      // preserves it in triage. See #3267 learning.
      if (controller.signal.aborted) {
        Sentry.addBreadcrumb({
          category: "kb-chat",
          message: "history-fetch-abort-after-success",
          level: "warning",
          data: { conversationId: targetId, messageCount: result.messages.length },
        });
        return;
      }
      // filter_prepend deduplicates by id against whatever stream events
      // landed while the fetch was in flight — strictly safer than an
      // activeStreams.size === 0 guard.
      dispatch({ type: "filter_prepend", messages: result.messages });
      // feat-stream-since-disconnect (#5273) — on the replay-incomplete path,
      // OVERWRITE cost to the authoritative persisted value (the additive
      // pre-disconnect partials are no longer trustworthy); otherwise keep the
      // default `prev ?? costData` seed so a racing live `usage_update` wins.
      const reconciledCost = result.costData;
      if (opts?.reconcileCost && reconciledCost) {
        setUsageData(() => reconciledCost);
      } else {
        seedCostData(result.costData);
      }
      seedWorkflowEndedAt(result.workflowEndedAt);
      // PR-B (#3603): write the resolved row's createdAt. Unlike
      // seedCostData/seedWorkflowEndedAt (which guard against racing WS
      // events that could clobber a fresher in-memory value), `created_at`
      // is a write-once row attribute with no WS-side update path — the
      // history fetch is the only writer. The sidebar variant reuses one
      // useWebSocket hook across conversation switches (resumeByContextPath
      // resolves a new realConversationId while keeping the hook alive);
      // a `prev ?? value` seed would silently render conversation A's date
      // while the user is reading conversation B. See review #3653.
      setConversationCreatedAt(result.createdAt);
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      reportSilentFallback(err, {
        feature: "kb-chat",
        op: "history-fetch-error",
        extra: { conversationId: targetId },
      });
    } finally {
      if (!controller.signal.aborted) setHistoryLoading(false);
    }
  }

  // Fetch conversation history on mount (once per conversationId).
  useEffect(() => {
    if (conversationId === "new") return;
    const controller = new AbortController();
    void runHistoryFetch(conversationId, controller);
    return () => controller.abort();
  }, [conversationId]);

  // Fetch history for resumed sessions where conversationId="new" (sidebar resume path).
  // The existing effect above skips "new" IDs. When the server responds with
  // session_resumed, realConversationId transitions from null → UUID. This effect
  // catches that transition and fetches history for the resolved conversation. #2425
  useEffect(() => {
    if (!realConversationId) return;
    if (realConversationId === conversationId) return; // existing effect handles this
    if (conversationId !== "new") return; // only the sidebar resume path
    // FR1: a fresh (`session_started`) conversation has no DB row yet —
    // deferred creation materializes it only on the first chat message. A
    // fetch here would 404 (`history-fetch-404-not-owned-or-missing`) on
    // every new KB-chat open. Only a genuine resume (`session_resumed`,
    // sessionKind === "resumed") has a row to fetch. Keyed on session kind,
    // not message count, so a resumed-but-empty thread still hydrates (FR2).
    if (sessionKind !== "resumed") return;

    const controller = new AbortController();
    void runHistoryFetch(realConversationId, controller);
    return () => controller.abort();
  }, [realConversationId, conversationId, sessionKind]);

  useEffect(() => {
    mountedRef.current = true;
    setLastError(null);
    setDisconnectReason(undefined);
    setSessionConfirmed(false);
    connect();

    return () => {
      mountedRef.current = false;
      clearTimeout(reconnectTimerRef.current);
      clearAllTimeouts();
      if (wsRef.current) {
        wsRef.current.onclose = null; // prevent reconnect on intentional close
        wsRef.current.close();
      }
    };
  }, [connect, conversationId, clearAllTimeouts]);

  const startSession = useCallback(
    (optsOrLeaderId?: StartSessionOptions | DomainLeaderId, contextArg?: ConversationContext) => {
      const opts: StartSessionOptions =
        typeof optsOrLeaderId === "object" && optsOrLeaderId !== null
          ? optsOrLeaderId
          : { leaderId: optsOrLeaderId, context: contextArg };
      setSessionConfirmed(false);
      setResumedFrom(null);
      send({
        type: "start_session",
        leaderId: opts.leaderId,
        context: opts.context,
        resumeByContextPath: opts.resumeByContextPath,
      });
    },
    [send],
  );

  const resumeSession = useCallback(
    (targetConversationId: string) => {
      setSessionConfirmed(false);
      send({ type: "resume_session", conversationId: targetConversationId });
    },
    [send],
  );

  const sendMessage = useCallback(
    (content: string, attachments?: AttachmentRef[]) => {
      // #5282 — an explicit new user turn is the ONLY escape from a sticky
      // `unrecoverable` connection state (AC11). This single `sendMessage` is the
      // unified send path for BOTH the legacy fan-out and cc-soleur-go (AC9), so
      // wiring the reset here covers both paths without per-path branching. No-op
      // when already `live` (the reducer arm short-circuits).
      dispatch({ type: "reset_connection" });
      // Add the user message to local state immediately
      dispatch({
        type: "add_message",
        message: {
          id: `user-${crypto.randomUUID()}`,
          role: "user",
          content,
          type: "text",
          attachments,
        },
      });
      send({ type: "chat", content, attachments });
    },
    [send],
  );

  const sendReviewGateResponse = useCallback(
    (gateId: string, selection: string) => {
      send({ type: "review_gate_response", gateId, selection });
      // Optimistically mark as resolved
      dispatch({ type: "resolve_gate", gateId, selection });
    },
    [send],
  );

  const sendAutonomousDisclosureResponse = useCallback(
    (gateId: string, selection: string) => {
      send({ type: "autonomous_disclosure_response", gateId, selection });
      // Optimistically mark resolved so the banner dismisses immediately; the
      // server releases the held command + writes the ack on receipt.
      dispatch({ type: "resolve_autonomous_disclosure", gateId, selection });
    },
    [send],
  );

  const sendInteractivePromptResponse = useCallback(
    (msg: Extract<WSMessage, { type: "interactive_prompt_response" }>) => {
      send(msg);
    },
    [send],
  );

  const resolveInteractivePrompt = useCallback(
    (promptId: string, conversationId: string, response: unknown) => {
      dispatch({
        type: "resolve_interactive_prompt",
        promptId,
        conversationId,
        response,
      });
    },
    [],
  );

  /**
   * #3448 PR2 — user-initiated Stop. The contract:
   *
   *   - No-op when streamState !== "streaming" — handles both the idle
   *     "no turn to stop" case and the double-click-while-stopping case.
   *   - No-op when the WebSocket is not OPEN.
   *   - No-op when no conversationId is resolved yet (pre-`session_started`).
   *
   * Sends `{ type: "abort_turn", conversationId }` and transitions
   * streamState to "stopping" optimistically. The hook stays in "stopping"
   * until `session_ended` arrives (single source of truth for the turn
   * boundary). The server resolves `userId` from the authenticated socket
   * — `userId` is intentionally NOT in the wire payload (TR4 cross-user
   * invariant; see plan §"User-Brand Impact").
   */
  const abort = useCallback(() => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    if (chatState.streamState !== "streaming") return;
    const targetConv =
      realConversationIdRef.current ??
      (conversationId !== "new" ? conversationId : null);
    if (!targetConv) return;
    // Review fix (security): readyState was OPEN above, but a server-
    // initiated close (4011 tier-changed, 4010 cap, network drop) can flip
    // the socket between the readyState read and `send`. Browsers throw
    // `InvalidStateError` from `send()` on a non-OPEN socket — without
    // this catch, the throw escapes the click handler, AND we still
    // dispatched `enter_stopping` below, leaving the Stop button stuck on
    // a closed socket (no `session_ended` will arrive). On throw, surface
    // to Sentry and stay in "streaming" — the WS onclose path will reset
    // to "idle" via clear_streams, and the standard reconnect/error UI
    // covers the connection failure.
    try {
      ws.send(JSON.stringify({ type: "abort_turn", conversationId: targetConv }));
    } catch (err) {
      reportSilentFallback(err, {
        feature: "abort-turn",
        op: "send-abort-turn-throw",
        extra: { conversationId: targetConv },
      });
      return;
    }
    dispatch({ type: "enter_stopping" });
  }, [chatState.streamState, conversationId]);

  const reconnect = useCallback(() => {
    setLastError(null);
    setDisconnectReason(undefined);
    mountedRef.current = true;
    backoffRef.current = INITIAL_BACKOFF;
    connect();
  }, [connect]);

  // #5282 — the State-3 "Resume with full context" action. `reconnect()` alone
  // cannot leave the sticky `unrecoverable` phase (the reducer guard no-ops any
  // `connection_change` back to live), so the banner would stay stuck. Dispatch
  // `reset_connection` (the sanctioned escape, same one `sendMessage` uses) to
  // clear State 3, THEN re-open the socket. The next user turn resumes the SDK
  // transcript with full context (#5240 v1 verified rebind).
  const resumeAfterUnrecoverable = useCallback(() => {
    dispatch({ type: "reset_connection" });
    reconnect();
  }, [reconnect]);

  return {
    messages: chatState.messages,
    startSession,
    resumeSession,
    sendMessage,
    sendReviewGateResponse,
    sendAutonomousDisclosureResponse,
    sendInteractivePromptResponse,
    resolveInteractivePrompt,
    status,
    sessionConfirmed,
    disconnectReason,
    lastError,
    reconnect,
    routeSource,
    activeLeaderIds,
    usageData,
    autonomousPosture,
    realConversationId,
    resumedFrom,
    workflow: chatState.workflow,
    workflowEndedAt,
    conversationCreatedAt,
    historyLoading,
    streamState: chatState.streamState,
    liveNarration: chatState.liveNarration,
    abort,
    connection: chatState.connection,
    resumeAfterUnrecoverable,
  };
}
