"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import type { WSMessage } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";

type ConnectionStatus = "connecting" | "connected" | "reconnecting" | "disconnected";

interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text" | "review_gate";
  /** Present only when type === "review_gate" */
  gateId?: string;
  question?: string;
  options?: string[];
}

interface UseWebSocketReturn {
  messages: ChatMessage[];
  startSession: (leaderId: string) => void;
  sendMessage: (content: string) => void;
  sendReviewGateResponse: (gateId: string, selection: string) => void;
  status: ConnectionStatus;
}

const MAX_BACKOFF = 30_000;
const INITIAL_BACKOFF = 1_000;

export function useWebSocket(conversationId: string): UseWebSocketReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [status, setStatus] = useState<ConnectionStatus>("connecting");
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mountedRef = useRef(true);

  /** Stable ref to the latest partial assistant message index for streaming */
  const streamIndexRef = useRef<number | null>(null);

  const getWsUrl = useCallback(async () => {
    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    const supabase = createClient();
    const { data: { session } } = await supabase.auth.getSession();
    const token = session?.access_token || "";
    return `${proto}://${window.location.host}/ws?token=${token}`;
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
    const url = await getWsUrl();
    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      if (!mountedRef.current) return;
      setStatus("connected");
      backoffRef.current = INITIAL_BACKOFF;
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
        case "stream": {
          setMessages((prev) => {
            if (msg.type !== "stream") return prev;

            if (streamIndexRef.current !== null && msg.partial) {
              // Append to existing partial message
              const updated = [...prev];
              const idx = streamIndexRef.current!;
              if (idx < updated.length) {
                updated[idx] = {
                  ...updated[idx],
                  content: updated[idx].content + msg.content,
                };
              }
              return updated;
            }

            if (msg.partial) {
              // Start a new streaming message
              const newMsg: ChatMessage = {
                id: `stream-${Date.now()}`,
                role: "assistant",
                content: msg.content,
                type: "text",
              };
              streamIndexRef.current = prev.length;
              return [...prev, newMsg];
            }

            // Final chunk — append remaining content and close stream
            if (streamIndexRef.current !== null) {
              const updated = [...prev];
              const idx = streamIndexRef.current;
              if (idx < updated.length) {
                updated[idx] = {
                  ...updated[idx],
                  content: updated[idx].content + msg.content,
                };
              }
              streamIndexRef.current = null;
              return updated;
            }

            // Non-partial, non-streaming message — full assistant response
            streamIndexRef.current = null;
            return [
              ...prev,
              {
                id: `msg-${Date.now()}`,
                role: "assistant",
                content: msg.content,
                type: "text",
              },
            ];
          });
          break;
        }

        case "review_gate": {
          if (msg.type !== "review_gate") break;
          streamIndexRef.current = null;
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
          streamIndexRef.current = null;
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
          streamIndexRef.current = null;
          setMessages((prev) => [
            ...prev,
            {
              id: `end-${Date.now()}`,
              role: "assistant",
              content: `Session ended: ${msg.reason}`,
              type: "text",
            },
          ]);
          break;
        }

        // session_started, chat — handled at transport level, no UI message needed
        default:
          break;
      }
    };

    ws.onclose = () => {
      if (!mountedRef.current) return;
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
  }, [getWsUrl]);

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
    (leaderId: DomainLeaderId) => {
      send({ type: "start_session", leaderId });
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

  return { messages, startSession, sendMessage, sendReviewGateResponse, status };
}
