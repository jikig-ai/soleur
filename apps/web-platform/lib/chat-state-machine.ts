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
  /**
   * FR5 (#2861): set by `applyTimeout` on the first stuck-timeout and cleared
   * on a follow-up `tool_progress` or the second consecutive timeout. When
   * true, `message-bubble.tsx` shows the "Retrying…" chip with aria-live
   * polite. The bubble's `state` stays in its transitional form
   * (`thinking` / `tool_use`) — `retrying` is the orthogonal render flag.
   */
  retrying?: boolean;
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
  | { type: "tool_progress" }
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
        // Reset the stuck-state timer on each tool_use — long-running tools
        // (Read on large files, Bash commands, web searches) can exceed the
        // 45s timeout. Each new tool_use proves the agent is still active.
        // See #2430.
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "tool_progress": {
      // FR4 (#2861): SDK heartbeat for long-running tool execution. Do NOT
      // mutate messages on the hot path — a 1/5s heartbeat for every active
      // tool would churn the bubble re-render. The only effects are:
      //   (1) reset the watchdog so 45s timeouts don't fire mid-tool
      //   (2) if the bubble is showing `retrying`, clear the flag — a fresh
      //       heartbeat means the tool is alive and the first-timeout retry
      //       should transition back to tool_use.
      const idx = activeStreams.get(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        // Unknown leader (e.g., heartbeat races stream_end) — inert no-op.
        return { messages: prev, activeStreams };
      }
      const current = prev[idx];
      if (current.retrying) {
        const updated = [...prev];
        const { retrying: _retrying, ...rest } = updated[idx];
        void _retrying;
        updated[idx] = { ...rest };
        return {
          messages: updated,
          activeStreams,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
      return {
        messages: prev,
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
      // Transition any bubble still mid-turn to "done" BEFORE clearing
      // activeStreams. Leaking "thinking" / "tool_use" / "streaming" into an
      // unclearable state is the root cause of the stuck orange "Working"
      // badge when a review_gate fires while peer leaders are still streaming
      // (see #2843). The gate message itself is appended after the transition.
      const updated = prev.slice();
      for (const idx of activeStreams.values()) {
        if (idx >= updated.length) continue;
        const m = updated[idx];
        if (m.state === "thinking" || m.state === "tool_use" || m.state === "streaming") {
          updated[idx] = { ...m, state: "done" };
        }
      }
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
        messages: [...updated, gateMsg],
        activeStreams: new Map(),
        timerAction: { type: "clear_all" },
      };
    }
  }
}

/**
 * Apply the stuck-state timeout for a leader. Two-stage lifecycle (FR5 #2861):
 *   1. First timeout on a transitional bubble → set `retrying: true`, keep
 *      the bubble active, reset the watchdog. Visible as "Retrying…" chip.
 *   2. Second consecutive timeout (bubble already has `retrying: true`) →
 *      transition to `error`, preserve `toolLabel` for the error chip, clear
 *      the watchdog.
 * Bubbles that have already progressed to streaming/done/error are left alone.
 */
export function applyTimeout(
  prev: ChatMessage[],
  activeStreams: Map<string, number>,
  leaderId: string,
): {
  messages: ChatMessage[];
  activeStreams: Map<string, number>;
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string };
} {
  const idx = activeStreams.get(leaderId);
  if (idx === undefined || idx >= prev.length) {
    return { messages: prev, activeStreams };
  }
  const current = prev[idx];
  if (current.state !== "thinking" && current.state !== "tool_use") {
    return { messages: prev, activeStreams };
  }

  // Second consecutive timeout — already in retrying, give up.
  if (current.retrying) {
    const updated = [...prev];
    const { retrying: _retrying, ...rest } = updated[idx];
    void _retrying;
    updated[idx] = { ...rest, state: "error" };
    const nextStreams = new Map(activeStreams);
    nextStreams.delete(leaderId);
    return {
      messages: updated,
      activeStreams: nextStreams,
      timerAction: { type: "clear", leaderId },
    };
  }

  // First timeout — flag as retrying, keep bubble active, restart watchdog.
  const updated = [...prev];
  updated[idx] = { ...updated[idx], retrying: true };
  return {
    messages: updated,
    activeStreams,
    timerAction: { type: "reset", leaderId },
  };
}
