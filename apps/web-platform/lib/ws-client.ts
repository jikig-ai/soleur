"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { WS_CLOSE_CODES, type WSMessage, type ConversationContext } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";

type ConnectionStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

export interface WebSocketError {
  code: string;
  message: string;
  action?: {
    label: string;
    href: string;
  };
}

interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text" | "review_gate";
  leaderId?: DomainLeaderId;
  /** Present only when type === "review_gate" */
  gateId?: string;
  question?: string;
  options?: string[];
  header?: string;
  descriptions?: Record<string, string | undefined>;
  resolved?: boolean;
  selectedOption?: string;
  gateError?: string;
}

export interface UsageData {
  totalCostUsd: number;
  inputTokens: number;
  outputTokens: number;
}

interface UseWebSocketReturn {
  messages: ChatMessage[];
  startSession: (leaderId?: DomainLeaderId, context?: ConversationContext) => void;
  sendMessage: (content: string) => void;
  sendReviewGateResponse: (gateId: string, selection: string) => void;
  status: ConnectionStatus;
  sessionConfirmed: boolean;
  disconnectReason: string | undefined;
  lastError: WebSocketError | null;
  reconnect: () => void;
  routeSource: "auto" | "mention" | null;
  activeLeaderIds: DomainLeaderId[];
  usageData: UsageData | null;
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
};

export function useWebSocket(conversationId: string): UseWebSocketReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [status, setStatus] = useState<ConnectionStatus>("connecting");
  const [disconnectReason, setDisconnectReason] = useState<string>();
  const [lastError, setLastError] = useState<WebSocketError | null>(null);
  const [routeSource, setRouteSource] = useState<"auto" | "mention" | null>(null);
  const [activeLeaderIds, setActiveLeaderIds] = useState<DomainLeaderId[]>([]);
  const [sessionConfirmed, setSessionConfirmed] = useState(false);
  const [usageData, setUsageData] = useState<UsageData | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mountedRef = useRef(true);

  /** Map of active leader streams: leaderId → message index in the messages array */
  const activeStreamsRef = useRef<Map<string, number>>(new Map());

  /** Permanently tear down the WebSocket — prevents reconnect loop.
   *  Mirrors the key_invalid teardown pattern. */
  const teardown = useCallback(() => {
    mountedRef.current = false;
    clearTimeout(reconnectTimerRef.current);
    activeStreamsRef.current.clear();
    setSessionConfirmed(false);
    if (wsRef.current) {
      wsRef.current.onclose = null;
      wsRef.current.close();
    }
  }, []);

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

      let msg: WSMessage;
      try {
        msg = JSON.parse(event.data);
      } catch {
        return;
      }

      switch (msg.type) {
        case "auth_ok": {
          setStatus("connected");
          backoffRef.current = INITIAL_BACKOFF;
          break;
        }

        case "stream_start": {
          // Store routing source from first stream_start
          if (msg.source) {
            setRouteSource(msg.source);
          }
          // Create a new empty message bubble for this leader
          setMessages((prev) => {
            const newMsg: ChatMessage = {
              id: `stream-${msg.leaderId}-${Date.now()}`,
              role: "assistant",
              content: "",
              type: "text",
              leaderId: msg.leaderId,
            };
            activeStreamsRef.current.set(msg.leaderId, prev.length);
            setActiveLeaderIds(Array.from(activeStreamsRef.current.keys()) as DomainLeaderId[]);
            return [...prev, newMsg];
          });
          break;
        }

        case "stream": {
          const streamLeaderId = msg.leaderId;

          setMessages((prev) => {
            // Look up the message index for this leader's active stream
            const idx = activeStreamsRef.current.get(streamLeaderId);

            if (idx !== undefined && idx < prev.length) {
              // Append to existing bubble for this leader
              const updated = [...prev];
              updated[idx] = {
                ...updated[idx],
                content: updated[idx].content + msg.content,
              };
              return updated;
            }

            // No active stream for this leader (stream_start may have been missed)
            // Create a new bubble
            const newMsg: ChatMessage = {
              id: `stream-${streamLeaderId}-${Date.now()}`,
              role: "assistant",
              content: msg.content,
              type: "text",
              leaderId: streamLeaderId,
            };
            activeStreamsRef.current.set(streamLeaderId, prev.length);
            return [...prev, newMsg];
          });
          break;
        }

        case "stream_end": {
          // Finalize this leader's stream — remove from active streams map
          activeStreamsRef.current.delete(msg.leaderId);
          setActiveLeaderIds(Array.from(activeStreamsRef.current.keys()) as DomainLeaderId[]);
          break;
        }

        case "review_gate": {
          activeStreamsRef.current.clear();
          setMessages((prev) => [
            ...prev,
            {
              id: `gate-${msg.gateId}`,
              role: "assistant",
              content: msg.question,
              type: "review_gate",
              gateId: msg.gateId,
              question: msg.question,
              options: msg.options,
              header: msg.header,
              descriptions: msg.descriptions,
            },
          ]);
          break;
        }

        case "error": {
          activeStreamsRef.current.clear();

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
            setMessages((prev) => prev.map((m) =>
              m.gateId === msg.gateId
                ? { ...m, gateError: msg.message, resolved: false, selectedOption: undefined }
                : m,
            ));
            break;
          }

          setMessages((prev) => [
            ...prev,
            {
              id: `err-${Date.now()}`,
              role: "assistant",
              content: `Error: ${msg.message}`,
              type: "text",
            },
          ]);
          break;
        }

        case "session_ended": {
          activeStreamsRef.current.clear();
          // Don't display "turn_complete" as a visible message — it's a lifecycle signal
          if (msg.reason !== "turn_complete") {
            setMessages((prev) => [
              ...prev,
              {
                id: `end-${Date.now()}`,
                role: "assistant",
                content: `Session ended: ${msg.reason}`,
                type: "text",
              },
            ]);
          }
          break;
        }

        case "session_started": {
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

        // auth (client-only), chat — no UI message needed
        default:
          break;
      }
    };

    ws.onclose = (event: CloseEvent) => {
      if (!mountedRef.current) return;

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
  }, [getWsUrlAndToken, teardown]);

  // Fetch conversation history on mount (once per conversationId)
  useEffect(() => {
    if (conversationId === "new") return;
    const controller = new AbortController();

    (async () => {
      try {
        const supabase = createClient();
        const { data: { session } } = await supabase.auth.getSession();
        if (!session?.access_token) return;

        const res = await fetch(
          `/api/conversations/${conversationId}/messages`,
          {
            headers: { Authorization: `Bearer ${session.access_token}` },
            signal: controller.signal,
          },
        );
        if (!res.ok) return;

        const { messages: history } = await res.json();
        const mapped: ChatMessage[] = history.map((m: { id: string; role: string; content: string; leader_id: string | null }) => ({
          id: m.id,
          role: m.role as "user" | "assistant",
          content: m.content,
          type: "text" as const,
          leaderId: m.leader_id ?? undefined,
        }));

        if (activeStreamsRef.current.size === 0) {
          setMessages(prev => [...mapped, ...prev]);
        }
      } catch (err) {
        if (err instanceof DOMException && err.name === "AbortError") return;
        console.error("Failed to load history:", err);
      }
    })();

    return () => controller.abort();
  }, [conversationId]);

  useEffect(() => {
    mountedRef.current = true;
    setLastError(null);
    setDisconnectReason(undefined);
    setSessionConfirmed(false);
    connect();

    return () => {
      mountedRef.current = false;
      clearTimeout(reconnectTimerRef.current);
      if (wsRef.current) {
        wsRef.current.onclose = null; // prevent reconnect on intentional close
        wsRef.current.close();
      }
    };
  }, [connect, conversationId]);

  const startSession = useCallback(
    (leaderId?: DomainLeaderId, context?: ConversationContext) => {
      setSessionConfirmed(false);
      send({ type: "start_session", leaderId, context });
    },
    [send],
  );

  const sendMessage = useCallback(
    (content: string) => {
      // Add the user message to local state immediately
      setMessages((prev) => [
        ...prev,
        {
          id: `user-${Date.now()}`,
          role: "user",
          content,
          type: "text",
        },
      ]);
      send({ type: "chat", content });
    },
    [send],
  );

  const sendReviewGateResponse = useCallback(
    (gateId: string, selection: string) => {
      send({ type: "review_gate_response", gateId, selection });
      // Optimistically mark as resolved
      setMessages((prev) => prev.map((m) =>
        m.gateId === gateId
          ? { ...m, resolved: true, selectedOption: selection, gateError: undefined }
          : m,
      ));
    },
    [send],
  );

  const reconnect = useCallback(() => {
    setLastError(null);
    setDisconnectReason(undefined);
    mountedRef.current = true;
    backoffRef.current = INITIAL_BACKOFF;
    connect();
  }, [connect]);

  return { messages, startSession, sendMessage, sendReviewGateResponse, status, sessionConfirmed, disconnectReason, lastError, reconnect, routeSource, activeLeaderIds, usageData };
}
