// Pure SSE transport helpers for the support chat (ADR-113, CTO Option D —
// dedicated POST /api/support + Server-Sent Events, fully decoupled from the
// Command Center WebSocket). No I/O here — the route and the hook wire these to
// a ReadableStream / fetch body reader respectively.

import type { WSMessage } from "@/lib/types";
import { buildSupportHandoffMarkdown } from "./support-handoff";

/**
 * Server→client frame carried on the support SSE stream but NEVER on the
 * Command Center WebSocket. `support_handoff` (#9539) is emitted by the
 * support route when a denied engineering action was recorded during the
 * turn — it hands the user's task to a write-capable agent session.
 *
 * Deliberately NOT a `WSMessage` union member: `ws-zod-schemas.ts`
 * `_SchemaCoversForward`/`_SchemaCoversBackward` pin `WSMessage` ≡
 * `z.infer<wsMessageSchema>` bidirectionally, so a bare member without a zod
 * arm is a compile error — and widening the WS parse contract for a frame that
 * can never legitimately arrive over the WS would be wrong anyway.
 */
export type SupportSseMessage =
  | WSMessage
  | {
      type: "support_handoff";
      task: string;
      conversationId: string;
      /**
       * #9556 — whether the dispatching workspace had a connected repo at deny
       * time (recorded, not re-resolved — zero extra DB reads). OPTIONAL so the
       * field stays additive-safe across the JSON parse boundary: frames from
       * dep-unwired emitters omit it and the copy builder falls back to the
       * legacy caveat arm.
       */
      repoConnected?: boolean;
    };

/**
 * Frame types that mean "the turn is over" — the signal to close the SSE
 * response. Exported from here (the frame-taxonomy owner) so the route's emit
 * gate and this file's reducer share one source of truth.
 */
export const SUPPORT_TERMINAL_FRAME_TYPES: ReadonlySet<string> = new Set([
  "stream_end",
  "session_ended",
  "error",
]);

/**
 * Serialize one dispatch frame as a single SSE `data:` event (server side). The
 * support dispatch's injected `sendToClient` sink calls this and enqueues the
 * result into the response `ReadableStream`.
 */
export function formatSupportSseFrame(msg: SupportSseMessage): string {
  return `data: ${JSON.stringify(msg)}\n\n`;
}

/**
 * Parse a run of concatenated SSE text (client side). SSE frames are delimited
 * by a blank line (`\n\n`); a network chunk can split a frame, so the caller
 * threads `rest` (the unterminated tail) back in on the next call. Malformed
 * `data:` payloads are dropped, never thrown (a garbled frame must not kill the
 * stream).
 */
export function parseSupportSseChunks(buffer: string): {
  messages: SupportSseMessage[];
  rest: string;
} {
  const messages: SupportSseMessage[] = [];
  const parts = buffer.split("\n\n");
  // The final element is the (possibly empty) unterminated tail — keep it.
  const rest = parts.pop() ?? "";
  for (const part of parts) {
    const line = part.trimStart();
    if (!line.startsWith("data:")) continue;
    const payload = line.slice("data:".length).trim();
    if (payload.length === 0) continue;
    try {
      const parsed = JSON.parse(payload) as SupportSseMessage;
      if (parsed && typeof parsed === "object" && typeof (parsed as { type?: unknown }).type === "string") {
        messages.push(parsed);
      }
    } catch {
      // Drop a malformed frame — the stream continues.
    }
  }
  return { messages, rest };
}

export type SupportStreamStatus = "idle" | "streaming" | "done" | "error";

export interface SupportStreamState {
  /** Cumulative assistant reply text (replace semantics — every `stream` frame
   *  is a full snapshot, matching the WS client contract). */
  text: string;
  status: SupportStreamStatus;
  error?: string;
  /**
   * The "Ask an agent" handoff markdown, set by a `support_handoff` frame.
   * Deliberately a SEPARATE field — never merged into `text`: `stream` frames
   * replace `text` wholesale and the hook's error fallback overwrites the
   * bubble, so an affordance stored inside `text` is discarded exactly on the
   * turns that need it (deny-then-error). Compose at render with
   * `composeSupportBubbleText`.
   */
  handoffMarkdown?: string;
}

export function initialSupportStream(): SupportStreamState {
  return { text: "", status: "idle" };
}

/**
 * The text the bubble should render: the reply plus the handoff affordance
 * when one was recorded. Composed at patch time (including the error/fallback
 * branch) so a `stream`-replace or a canned-fallback overwrite cannot discard
 * the affordance. The handoff stands alone when the reply was empty.
 */
export function composeSupportBubbleText(state: SupportStreamState): string {
  if (!state.handoffMarkdown) return state.text;
  return state.text.length > 0
    ? `${state.text}\n\n${state.handoffMarkdown}`
    : state.handoffMarkdown;
}

/**
 * The frames to enqueue for one incoming dispatch frame — pure so ordering and
 * the consume-gate are unit-testable without a route harness. When `msg` is a
 * terminal frame AND a deny-path escalation produced a `handoff` frame, the
 * handoff precedes the terminal frame (the route closes the stream on
 * terminal, so ordering is load-bearing). Everything else passes through
 * unchanged.
 */
export function supportTerminalPrefixFrames(
  msg: WSMessage,
  handoff: Extract<SupportSseMessage, { type: "support_handoff" }> | null,
): SupportSseMessage[] {
  if (handoff !== null && SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)) {
    return [handoff, msg];
  }
  return [msg];
}

/**
 * Reduce one dispatch frame into the support reply state. `stream` frames REPLACE
 * the text (cumulative snapshot, not append — matches ws-client.ts). Terminal
 * frames (`session_ended`/`stream_end`) mark done; an `error` frame surfaces the
 * message; a `support_handoff` frame stores the affordance in `handoffMarkdown`
 * (separate field — see `composeSupportBubbleText`). All other frame types
 * (tool_use, reasoning_narration, …) are ignored.
 */
export function reduceSupportFrame(
  state: SupportStreamState,
  msg: SupportSseMessage,
): SupportStreamState {
  switch (msg.type) {
    case "stream_start":
      return { ...state, status: "streaming" };
    case "stream":
      return { ...state, text: msg.content, status: "streaming" };
    case "support_handoff":
      return {
        ...state,
        handoffMarkdown: buildSupportHandoffMarkdown(
          msg.task,
          msg.repoConnected,
        ),
      };
    case "stream_end":
    case "session_ended":
      // Preserve an already-surfaced error; otherwise the turn completed.
      return state.status === "error" ? state : { ...state, status: "done" };
    case "error":
      return { ...state, status: "error", error: msg.message };
    default:
      // task_completed (feat-session-completion-inline) is unreachable via
      // today's emit pin (defaultSendToClient targets the CC socket, not this
      // SSE sink) — ignored by design if a future caller reintroduces it.
      // The support surface's "turn finished" signal is stream_end /
      // session_ended above.
      return state;
  }
}
