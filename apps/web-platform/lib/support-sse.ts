// Pure SSE transport helpers for the support chat (ADR-109, CTO Option D —
// dedicated POST /api/support + Server-Sent Events, fully decoupled from the
// Command Center WebSocket). No I/O here — the route and the hook wire these to
// a ReadableStream / fetch body reader respectively.

import type { WSMessage } from "@/lib/types";

/**
 * Serialize one dispatch frame as a single SSE `data:` event (server side). The
 * support dispatch's injected `sendToClient` sink calls this and enqueues the
 * result into the response `ReadableStream`.
 */
export function formatSupportSseFrame(msg: WSMessage): string {
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
  messages: WSMessage[];
  rest: string;
} {
  const messages: WSMessage[] = [];
  const parts = buffer.split("\n\n");
  // The final element is the (possibly empty) unterminated tail — keep it.
  const rest = parts.pop() ?? "";
  for (const part of parts) {
    const line = part.trimStart();
    if (!line.startsWith("data:")) continue;
    const payload = line.slice("data:".length).trim();
    if (payload.length === 0) continue;
    try {
      const parsed = JSON.parse(payload) as WSMessage;
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
}

export function initialSupportStream(): SupportStreamState {
  return { text: "", status: "idle" };
}

/**
 * Reduce one dispatch frame into the support reply state. `stream` frames REPLACE
 * the text (cumulative snapshot, not append — matches ws-client.ts). Terminal
 * frames (`session_ended`/`stream_end`) mark done; an `error` frame surfaces the
 * message. All other frame types (tool_use, reasoning_narration, …) are ignored.
 */
export function reduceSupportFrame(
  state: SupportStreamState,
  msg: WSMessage,
): SupportStreamState {
  switch (msg.type) {
    case "stream_start":
      return { ...state, status: "streaming" };
    case "stream":
      return { ...state, text: msg.content, status: "streaming" };
    case "stream_end":
    case "session_ended":
      // Preserve an already-surfaced error; otherwise the turn completed.
      return state.status === "error" ? state : { ...state, status: "done" };
    case "error":
      return { ...state, status: "error", error: msg.message };
    default:
      return state;
  }
}
