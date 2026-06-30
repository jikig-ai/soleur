"use client";

// feat-support-interface — local conversation state for the support shell.
// No network, no persistence across reload. State lives here (owned by the
// always-mounted launcher) so the thread is retained across panel close/reopen
// within a page session.

import { useCallback, useRef, useState } from "react";
import { getSupportReply } from "./canned-responder";

export type SupportRole = "user" | "support";

export interface SupportMessage {
  id: string;
  role: SupportRole;
  text: string;
}

export interface UseSupportChat {
  messages: SupportMessage[];
  hasConversation: boolean;
  /** Append a user message + its canned support reply. No-op on empty input. */
  send: (text: string, chipKey?: string) => void;
}

export function useSupportChat(): UseSupportChat {
  const [messages, setMessages] = useState<SupportMessage[]>([]);
  const idRef = useRef(0);

  const nextId = useCallback((prefix: string) => {
    idRef.current += 1;
    return `support-${prefix}-${idRef.current}`;
  }, []);

  const send = useCallback(
    (text: string, chipKey?: string) => {
      const trimmed = text.trim();
      if (trimmed.length === 0) return; // empty/whitespace is a no-op

      const userMessage: SupportMessage = {
        id: nextId("user"),
        role: "user",
        text: trimmed,
      };
      const reply = getSupportReply(trimmed, chipKey);
      const supportMessage: SupportMessage = {
        id: nextId("support"),
        role: "support",
        text: reply,
      };
      setMessages((prev) => [...prev, userMessage, supportMessage]);
    },
    [nextId],
  );

  return { messages, hasConversation: messages.length > 0, send };
}
