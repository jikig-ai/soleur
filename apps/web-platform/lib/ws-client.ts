"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { WS_CLOSE_CODES, type WSMessage, type ConversationContext } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";

type ConnectionStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

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
}

interface UseWebSocketReturn {
  messages: ChatMessage[];
  startSession: (leaderId?: DomainLeaderId, context?: ConversationContext) => void;
  sendMessage: (content: string) => void;
  sendReviewGateResponse: (gateId: string, selection: string) => void;
  status: ConnectionStatus;
  disconnectReason: string | undefined;
  routeSource: "auto" | "mention" | null;
  activeLeaderIds: DomainLeaderId[];
}

const MAX_BACKOFF = 30_000;
const INITIAL_BACKOFF = 1_000;

/** Close codes where reconnecting will never succeed. */
const NON_TRANSIENT_CLOSE_CODES: Record<number, { target?: string; reason: string }> = {
  [WS_CLOSE_CODES.AUTH_TIMEOUT]: { target: "/login", reason: "Session expired" },
  [WS_CLOSE_CODES.SUPERSEDED]: { reason: "Superseded by another tab" },
  [WS_CLOSE_CODES.AUTH_REQUIRED]: { target: "/login", reason: "Authentication required" },
  [WS_CLOSE_CODES.TC_NOT_ACCEPTED]: { target: "/accept-terms", reason: "Terms acceptance required" },
  [WS_CLOSE_CODES.INTERNAL_ERROR]: { reason: "Server error" },
  [WS_CLOSE_CODES.RATE_LIMITED]: { reason: "Too many requests. Please try again later." },
};

export function useWebSocket(conversationId: string): UseWebSocketReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [status, setStatus] = useState<ConnectionStatus>("connecting");
  const [disconnectReason, setDisconnectReason] = useState<string>();
  const [routeSource, setRouteSource] = useState<"auto" | "mention" | null>(null);
  const [activeLeaderIds, setActiveLeaderIds] = useState<DomainLeaderId[]>([]);
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
          if (msg.type !== "stream_start") break;
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
          if (msg.type !== "stream") break;
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
          if (msg.type !== "stream_end") break;
          // Finalize this leader's stream — remove from active streams map
          activeStreamsRef.current.delete(msg.leaderId);
          setActiveLeaderIds(Array.from(activeStreamsRef.current.keys()) as DomainLeaderId[]);
          break;
        }

        case "review_gate": {
          if (msg.type !== "review_gate") break;
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
            },
          ]);
          break;
        }

        case "error": {
          if (msg.type !== "error") break;
          activeStreamsRef.current.clear();

          // Key invalidation: redirect to setup instead of showing error
          if (msg.errorCode === "key_invalid") {
            teardown();
            window.location.href = "/setup-key";
            return; // Prevent post-redirect state updates
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
          if (msg.type !== "session_ended") break;
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

        // auth (client-only), session_started, chat — no UI message needed
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

  useEffect(() => {
    mountedRef.current = true;
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
    },
    [send],
  );

  return { messages, startSession, sendMessage, sendReviewGateResponse, status, disconnectReason, routeSource, activeLeaderIds };
}
