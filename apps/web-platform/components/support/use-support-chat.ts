"use client";

// feat-wire-concierge-support-chat (ADR-109) — the support chat now streams REAL
// agent-driven replies from the Concierge over the dedicated SSE transport
// (POST /api/support, CTO Option D — decoupled from the Command Center WebSocket).
// State lives here (owned by the always-mounted launcher) so the thread is
// retained across panel close/reopen within a page session.
//
// The synchronous `getSupportReply` canned copy is now the FLAG-OFF / transport-
// error / persona-unresolved FALLBACK only — never the live path.

import { useCallback, useRef, useState } from "react";
import { getSupportReply } from "./canned-responder";
import {
  parseSupportSseChunks,
  reduceSupportFrame,
  initialSupportStream,
  type SupportStreamState,
} from "@/lib/support-sse";

export type SupportRole = "user" | "support";

export interface SupportMessage {
  id: string;
  role: SupportRole;
  text: string;
  /** True while the support reply is still streaming (typing indicator). */
  streaming?: boolean;
  /** True when the reply is an error/fallback (retry affordance). */
  error?: boolean;
}

export interface UseSupportChat {
  messages: SupportMessage[];
  hasConversation: boolean;
  /** Append a user message + stream the Concierge reply. No-op on empty input. */
  send: (text: string, chipKey?: string) => void;
  /** Abort any in-flight support turn (called on panel close — S1). */
  abort: () => void;
}

// No support frame for this long → treat the stream as stalled (S5).
const STREAM_IDLE_TIMEOUT_MS = 30_000;

/**
 * @param live When true, `send()` streams REAL Concierge replies over the SSE
 *   transport (POST /api/support). When false (the DEFAULT deployed state — the
 *   `support-live` flag gates it), `send()` uses the synchronous canned preview
 *   reply and makes NO network call. The live path stays gated OFF until the
 *   Phase-4 product-help corpus + search-root restriction are validated against a
 *   deployed environment (else the support agent could read the internal KB).
 */
export function useSupportChat(live: boolean = false): UseSupportChat {
  const [messages, setMessages] = useState<SupportMessage[]>([]);
  const idRef = useRef(0);
  const abortRef = useRef<AbortController | null>(null);
  const idleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const nextId = useCallback((prefix: string) => {
    idRef.current += 1;
    return `support-${prefix}-${idRef.current}`;
  }, []);

  const patch = useCallback((id: string, next: Partial<SupportMessage>) => {
    setMessages((prev) =>
      prev.map((m) => (m.id === id ? { ...m, ...next } : m)),
    );
  }, []);

  const clearIdleTimer = useCallback(() => {
    if (idleTimerRef.current) {
      clearTimeout(idleTimerRef.current);
      idleTimerRef.current = null;
    }
  }, []);

  const abort = useCallback(() => {
    // Abort the in-flight dispatch so no Concierge turn streams to nowhere
    // (per-session cost) — S1.
    abortRef.current?.abort();
    abortRef.current = null;
    clearIdleTimer();
    setMessages((prev) =>
      prev.map((m) => (m.streaming ? { ...m, streaming: false } : m)),
    );
  }, [clearIdleTimer]);

  const send = useCallback(
    (text: string, chipKey?: string) => {
      const trimmed = text.trim();
      if (trimmed.length === 0) return; // empty/whitespace is a no-op

      // Gated (default): synchronous canned preview reply, NO network. Preserves
      // the interface-preview behavior until the live backend is flag-enabled.
      if (!live) {
        const canned: SupportMessage = {
          id: nextId("support"),
          role: "support",
          text: getSupportReply(trimmed, chipKey),
        };
        setMessages((prev) => [
          ...prev,
          { id: nextId("user"), role: "user", text: trimmed },
          canned,
        ]);
        return;
      }

      // Abort a prior in-flight turn (one active support turn at a time).
      abortRef.current?.abort();
      clearIdleTimer();

      const userMessage: SupportMessage = {
        id: nextId("user"),
        role: "user",
        text: trimmed,
      };
      const supportId = nextId("support");
      const supportMessage: SupportMessage = {
        id: supportId,
        role: "support",
        text: "",
        streaming: true,
      };
      setMessages((prev) => [...prev, userMessage, supportMessage]);

      const controller = new AbortController();
      abortRef.current = controller;

      // The honest canned fallback used on any transport/persona failure so a
      // stuck user is never dead-ended (keeps the KB escape hatch).
      const fallback = () => {
        clearIdleTimer();
        patch(supportId, {
          text: getSupportReply(trimmed, chipKey),
          streaming: false,
          error: true,
        });
      };

      const armIdleTimer = () => {
        clearIdleTimer();
        idleTimerRef.current = setTimeout(() => {
          // Mid-stream stall (S5): abort + honest fallback + retry affordance.
          controller.abort();
          fallback();
        }, STREAM_IDLE_TIMEOUT_MS);
      };

      void (async () => {
        try {
          const res = await fetch("/api/support", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message: trimmed }),
            signal: controller.signal,
          });
          if (!res.ok || !res.body) {
            fallback();
            return;
          }

          armIdleTimer();
          const reader = res.body.getReader();
          const decoder = new TextDecoder();
          let buf = "";
          let state: SupportStreamState = initialSupportStream();

          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            armIdleTimer();
            buf += decoder.decode(value, { stream: true });
            const parsed = parseSupportSseChunks(buf);
            buf = parsed.rest;
            for (const msg of parsed.messages) {
              state = reduceSupportFrame(state, msg);
            }
            if (state.status === "error") {
              // Server surfaced an error frame — show honest fallback text.
              fallback();
              return;
            }
            if (state.text.length > 0) {
              patch(supportId, { text: state.text, streaming: true });
            }
          }

          clearIdleTimer();
          if (state.text.trim().length === 0) {
            // Empty result (S3) — never leave a blank bubble; honest fallback.
            fallback();
            return;
          }
          patch(supportId, { text: state.text, streaming: false });
        } catch (err) {
          if ((err as { name?: string })?.name === "AbortError") {
            // Deliberate abort (panel close / new turn) — leave state as-is.
            return;
          }
          fallback();
        } finally {
          if (abortRef.current === controller) abortRef.current = null;
        }
      })();
    },
    [live, nextId, patch, clearIdleTimer],
  );

  return { messages, hasConversation: messages.length > 0, send, abort };
}
