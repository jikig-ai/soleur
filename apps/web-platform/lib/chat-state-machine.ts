import type { WSMessage, MessageState, AttachmentRef } from "./types";
import type { DomainLeaderId } from "@/server/domain-leaders";

/**
 * Pure streaming state machine for the chat message lifecycle.
 *
 * Extracted from ws-client.ts so tests exercise the real production code
 * instead of a shadow copy. The function is deliberately pure: takes the
 * current messages array and active-stream map, returns the new state.
 * The hook layer owns timers and other side effects — this module only
 * computes state transitions.
 */

interface ChatMessageBase {
  id: string;
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  attachments?: AttachmentRef[];
  state?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
}

interface ChatTextMessage extends ChatMessageBase {
  type: "text";
}

interface ChatGateMessage extends ChatMessageBase {
  type: "review_gate";
  gateId: string;
  question: string;
  options: string[];
  header?: string;
  descriptions?: Record<string, string | undefined>;
  stepProgress?: { current: number; total: number };
  resolved?: boolean;
  selectedOption?: string;
  gateError?: string;
}

export type ChatMessage = ChatTextMessage | ChatGateMessage;

export interface StreamEventResult {
  messages: ChatMessage[];
  activeStreams: Map<string, number>;
  /**
   * Optional timer action the caller should apply. The state machine is
   * pure, so it doesn't call setTimeout — it only declares intent.
   *   - `reset`: (re)start the stuck-state timer for the given leaderId
   *   - `clear`: cancel any pending timer for the given leaderId
   * `undefined` means "no timer change" (e.g., auth_ok).
   */
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string }
    | { type: "clear_all" };
}

/**
 * Events that the state machine reacts to. Covers the subset of WSMessage
 * types that mutate the chat state machine (stream lifecycle + review gates).
 * Other event types (auth_ok, session_started, usage_update, etc.) are
 * handled directly in the hook and don't pass through here.
 */
type StreamEvent = Extract<
  WSMessage,
  | { type: "stream_start" }
  | { type: "stream" }
  | { type: "stream_end" }
  | { type: "tool_use" }
  | { type: "review_gate" }
>;

/**
 * Apply a single WS event to the chat state. Pure function — does not
 * mutate the passed `prev` or `activeStreams`, returns new instances.
 */
export function applyStreamEvent(
  prev: ChatMessage[],
  activeStreams: Map<string, number>,
  event: StreamEvent,
): StreamEventResult {
  switch (event.type) {
    case "stream_start": {
      const newMsg: ChatMessage = {
        id: `stream-${event.leaderId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "text",
        leaderId: event.leaderId,
        state: "thinking",
        toolsUsed: [],
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, prev.length);
      return {
        messages: [...prev, newMsg],
        activeStreams: nextStreams,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "tool_use": {
      const idx = activeStreams.get(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        return { messages: prev, activeStreams };
      }
      const updated = [...prev];
      updated[idx] = {
        ...updated[idx],
        state: "tool_use",
        toolLabel: event.label,
        toolsUsed: [...(updated[idx].toolsUsed ?? []), event.label],
      };
      return {
        messages: updated,
        activeStreams,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "stream": {
      const idx = activeStreams.get(event.leaderId);
      if (idx !== undefined && idx < prev.length) {
        // REPLACE content (not append) — server sends cumulative snapshots
        const updated = [...prev];
        updated[idx] = {
          ...updated[idx],
          content: event.content,
          state: "streaming",
          toolLabel: undefined,
        };
        return {
          messages: updated,
          activeStreams,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
      // No active stream for this leader (stream_start may have been missed)
      const newMsg: ChatMessage = {
        id: `stream-${event.leaderId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: event.content,
        type: "text",
        leaderId: event.leaderId,
        state: "streaming",
        toolsUsed: [],
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, prev.length);
      return {
        messages: [...prev, newMsg],
        activeStreams: nextStreams,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "stream_end": {
      const idx = activeStreams.get(event.leaderId);
      const nextStreams = new Map(activeStreams);
      nextStreams.delete(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        return {
          messages: prev,
          activeStreams: nextStreams,
          timerAction: { type: "clear", leaderId: event.leaderId },
        };
      }
      const updated = [...prev];
      updated[idx] = { ...updated[idx], state: "done" };
      return {
        messages: updated,
        activeStreams: nextStreams,
        timerAction: { type: "clear", leaderId: event.leaderId },
      };
    }

    case "review_gate": {
      const gateMsg: ChatMessage = {
        id: `gate-${event.gateId}`,
        role: "assistant",
        content: event.question,
        type: "review_gate",
        gateId: event.gateId,
        question: event.question,
        options: event.options,
        header: event.header,
        descriptions: event.descriptions,
        stepProgress: event.stepProgress,
      };
      return {
        messages: [...prev, gateMsg],
        activeStreams: new Map(),
        timerAction: { type: "clear_all" },
      };
    }
  }
}

/**
 * Apply the 30s stuck-state timeout for a leader. Only transitions a bubble
 * to "error" if it is still in a transitional state (thinking/tool_use).
 * Bubbles that have already progressed to streaming/done/error are left
 * alone — the timeout is stale and should no-op.
 */
export function applyTimeout(
  prev: ChatMessage[],
  activeStreams: Map<string, number>,
  leaderId: string,
): { messages: ChatMessage[]; activeStreams: Map<string, number> } {
  const idx = activeStreams.get(leaderId);
  if (idx === undefined || idx >= prev.length) {
    return { messages: prev, activeStreams };
  }
  const current = prev[idx];
  // Guard: only apply "error" if bubble is still in a transitional state.
  if (current.state !== "thinking" && current.state !== "tool_use") {
    return { messages: prev, activeStreams };
  }
  const updated = [...prev];
  updated[idx] = { ...updated[idx], state: "error" };
  const nextStreams = new Map(activeStreams);
  nextStreams.delete(leaderId);
  return { messages: updated, activeStreams: nextStreams };
}
