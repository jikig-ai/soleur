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
} from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import {
  applyStreamEvent,
  applyTimeout,
  type ChatMessage,
  type StreamEventResult,
  type WorkflowLifecycleState,
  type SpawnIndex,
} from "@/lib/chat-state-machine";
import { isKnownWSMessageType } from "@/lib/ws-known-types";
import { parseWSMessage } from "@/lib/ws-zod-schemas";
import { reportSilentFallback } from "@/lib/client-observability";
import { STUCK_TIMEOUT_MS } from "@/lib/ws-constants";

export { STUCK_TIMEOUT_MS } from "@/lib/ws-constants";

type ConnectionStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

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
  [WS_CLOSE_CODES.CONCURRENCY_CAP]: { reason: "Concurrent-conversation limit reached" },
};

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
  pendingTimerAction?: StreamEventResult["timerAction"];
}

export type StreamEventMsg = Parameters<typeof applyStreamEvent>[2];

export type ChatAction =
  | { type: "stream_event"; msg: StreamEventMsg }
  | { type: "timeout"; leaderId: string }
  | { type: "clear_streams" }
  | { type: "ack_timer_action" }
  | { type: "add_message"; message: ChatMessage }
  | { type: "filter_prepend"; messages: ChatMessage[] }
  | { type: "gate_error"; gateId: string; message: string }
  | { type: "resolve_gate"; gateId: string; selection: string }
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
      return {
        messages: result.messages,
        activeStreams: result.activeStreams,
        workflow: result.workflow,
        spawnIndex: result.spawnIndex,
        pendingTimerAction: result.timerAction,
      };
    }
    case "timeout": {
      const result = applyTimeout(state.messages, state.activeStreams, action.leaderId);
      return {
        ...state,
        messages: result.messages,
        activeStreams: result.activeStreams,
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
      return {
        ...state,
        activeStreams: new Map(),
        workflow: { state: "idle" },
        spawnIndex: new Map(),
        pendingTimerAction: undefined,
      };
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
  const [usageData, setUsageData] = useState<UsageData | null>(null);
  // Stage 4 review F3: persisted `workflow_ended_at` from history fetch.
  const [workflowEndedAt, setWorkflowEndedAt] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mountedRef = useRef(true);
  /** Most-recent close preamble carried on `ws.message` before `ws.close` fires.
   *  Populated by onmessage for `concurrency_cap_hit` / `tier_changed` types;
   *  consumed + cleared in onclose. */
  const pendingPreambleRef = useRef<ConcurrencyCapHitPreamble | TierChangedPreamble | null>(null);

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
    dispatch({ type: "ack_timer_action" });
  }, [chatState.pendingTimerAction, resetLeaderTimeout, clearLeaderTimeout, clearAllTimeouts]);

  /** Permanently tear down the WebSocket — prevents reconnect loop.
   *  Mirrors the key_invalid teardown pattern. */
  const teardown = useCallback(() => {
    mountedRef.current = false;
    clearTimeout(reconnectTimerRef.current);
    dispatch({ type: "clear_streams" });
    clearAllTimeouts();
    setSessionConfirmed(false);
    setRealConversationId(null);
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
      if (!mountedRef.current) return;

      let parsed: unknown;
      try {
        parsed = JSON.parse(event.data);
      } catch {
        return;
      }

      // Close preambles are sent immediately before ws.close(4010/4011). Cache
      // the payload so onclose can dispatch the modal with tier/count context.
      if (parsed && typeof parsed === "object" && "type" in parsed) {
        const t = (parsed as { type: string }).type;
        if (t === "concurrency_cap_hit" || t === "tier_changed") {
          pendingPreambleRef.current = parsed as
            | ConcurrencyCapHitPreamble
            | TierChangedPreamble;
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

      switch (msg.type) {
        case "auth_ok": {
          setStatus("connected");
          backoffRef.current = INITIAL_BACKOFF;
          break;
        }

        case "stream_start":
        case "tool_use":
        case "tool_progress":
        case "stream":
        case "stream_end":
        case "review_gate":
        case "subagent_spawn":
        case "subagent_complete":
        case "workflow_started":
        case "workflow_ended":
        case "interactive_prompt": {
          // Store routing source from the first stream_start
          if (msg.type === "stream_start" && msg.source) {
            setRouteSource(msg.source);
          }
          // Dispatch to the pure reducer — no ref mutations inside the updater.
          // activeStreams and messages update atomically; pendingTimerAction carries
          // the timer intent out of the pure reducer for the useEffect above. See #2217.
          // Stage 3 (#2885) — `subagent_*`, `workflow_*`, `interactive_prompt`
          // are inert pass-throughs in the reducer; Stage 4 wires rendering.
          dispatch({ type: "stream_event", msg });
          break;
        }

        case "error": {
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
          if (msg.conversationId) setRealConversationId(msg.conversationId);
          setResumedFrom(null);
          setSessionConfirmed(true);
          break;
        }

        case "session_resumed": {
          setRealConversationId(msg.conversationId);
          setResumedFrom({
            conversationId: msg.conversationId,
            timestamp: msg.resumedFromTimestamp,
            messageCount: msg.messageCount,
          });
          setSessionConfirmed(true);
          break;
        }

        case "usage_update": {
          setUsageData((prev) => ({
            totalCostUsd: (prev?.totalCostUsd ?? 0) + msg.totalCostUsd,
            inputTokens: (prev?.inputTokens ?? 0) + msg.inputTokens,
            outputTokens: (prev?.outputTokens ?? 0) + msg.outputTokens,
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
        case "interactive_prompt_response":
        case "fanout_truncated":
        case "upgrade_pending":
          break;
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

      // 4011 TIER_CHANGED — schedule a single reconnect after a fixed delay so
      // the new plan_tier is re-read from the DB. Use a manual setTimeout (not
      // AbortSignal.timeout) so vitest fake timers intercept reliably.
      if (event.code === WS_CLOSE_CODES.TIER_CHANGED) {
        pendingPreambleRef.current = null;
        setStatus("reconnecting");
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
        }

        if (entry.target) {
          window.location.href = entry.target;
        }
        return;
      }

      // Transient failure — reconnect with exponential backoff
      setStatus("reconnecting");
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
  } | null> {
    // Validate targetId is a safe path segment to satisfy CodeQL's
    // request-forgery check. Allows UUIDs and alphanumeric IDs only.
    // The server enforces ownership via user_id.
    if (!/^[0-9a-zA-Z-]+$/.test(targetId)) return null;

    const supabase = createClient();
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) return null;

    const res = await fetch(
      `/api/conversations/${targetId}/messages`,
      {
        headers: { Authorization: `Bearer ${session.access_token}` },
        signal,
      },
    );
    if (!res.ok) {
      console.warn(`History fetch failed for ${targetId}: ${res.status}`);
      return null;
    }

    const json = await res.json();
    const mapped = json.messages.map((m: { id: string; role: string; content: string; leader_id: string | null }) => ({
      id: m.id,
      role: m.role as "user" | "assistant",
      content: m.content,
      type: "text" as const,
      leaderId: m.leader_id ?? undefined,
      // History messages intentionally leave state undefined so the
      // completion checkmark only appears on messages that completed via a
      // WS stream event in the current session. renderBubbleContent handles
      // undefined state via its default branch (MarkdownRenderer), which is
      // functionally identical to case "done" for messages without toolsUsed.
      // See #2218 (checkmark on historical bubbles) and #2139 (original fix).
    }));

    const costData: UsageData | null =
      json.totalCostUsd > 0
        ? { totalCostUsd: json.totalCostUsd, inputTokens: json.inputTokens, outputTokens: json.outputTokens }
        : null;

    const workflowEndedAtFromServer: string | null =
      typeof json.workflowEndedAt === "string" ? json.workflowEndedAt : null;

    return { messages: mapped, costData, workflowEndedAt: workflowEndedAtFromServer };
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

  // Fetch conversation history on mount (once per conversationId)
  useEffect(() => {
    if (conversationId === "new") return;
    const controller = new AbortController();

    (async () => {
      try {
        const result = await fetchConversationHistory(conversationId, controller.signal);
        if (!result || !mountedRef.current) return;

        // filter_prepend deduplicates by id against whatever stream events
        // landed while the fetch was in flight — strictly safer than an
        // activeStreams.size === 0 guard and matches the resume path.
        dispatch({ type: "filter_prepend", messages: result.messages });
        seedCostData(result.costData);
        seedWorkflowEndedAt(result.workflowEndedAt);
      } catch (err) {
        if (err instanceof DOMException && err.name === "AbortError") return;
        console.error("Failed to load history:", err);
      }
    })();

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

    const controller = new AbortController();

    (async () => {
      try {
        const result = await fetchConversationHistory(realConversationId, controller.signal);
        if (!result || !mountedRef.current) return;

        // Deduplicate: filter out any messages already present from stream events
        // that arrived while the fetch was in-flight. More robust than the
        // activeStreams.size === 0 guard: handles the window where a stream
        // event arrives and completes before the fetch resolves.
        dispatch({ type: "filter_prepend", messages: result.messages });
        seedCostData(result.costData);
        seedWorkflowEndedAt(result.workflowEndedAt);
      } catch (err) {
        if (err instanceof DOMException && err.name === "AbortError") return;
        console.error("Failed to load resume history:", err);
      }
    })();

    return () => controller.abort();
  }, [realConversationId, conversationId]);

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

  const reconnect = useCallback(() => {
    setLastError(null);
    setDisconnectReason(undefined);
    mountedRef.current = true;
    backoffRef.current = INITIAL_BACKOFF;
    connect();
  }, [connect]);

  return {
    messages: chatState.messages,
    startSession,
    resumeSession,
    sendMessage,
    sendReviewGateResponse,
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
    realConversationId,
    resumedFrom,
    workflow: chatState.workflow,
    workflowEndedAt,
  };
}
