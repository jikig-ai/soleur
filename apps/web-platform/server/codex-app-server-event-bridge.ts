import {
  createCodexAppServerEventBuffer,
  type CodexAppServerEventBuffer,
} from "./codex-app-server-event-buffer";

export interface CodexAppServerEventBridge extends CodexAppServerEventBuffer {
  onNotification(message: Record<string, unknown>): void;
  onClose(reason?: unknown): void;
  streamTurn(turnId: string): AsyncIterable<unknown>;
}

/** Adapt RPC callbacks into one bounded stream owned by a Codex source. */
export function createCodexAppServerEventBridge(
  options: { maxSize?: number } = {},
): CodexAppServerEventBridge {
  const buffer = createCodexAppServerEventBuffer(options);
  let activeTurnStream = false;
  return {
    push: buffer.push,
    close: buffer.close,
    stream: buffer.stream,
    size: buffer.size,
    onNotification: (message) => buffer.push(message),
    onClose: (reason) => buffer.close(reason),
    streamTurn: async function* (turnId) {
      if (activeTurnStream) throw new Error("codex_turn_stream_active");
      activeTurnStream = true;
      try {
        for await (const event of buffer.stream()) {
          yield event;
          if (!event || typeof event !== "object" || Array.isArray(event)) continue;
          const message = event as Record<string, unknown>;
          const params = message.params;
          const turn = params && typeof params === "object" && !Array.isArray(params)
            ? (params as Record<string, unknown>).turn
            : null;
          if (message.method === "turn/completed" && turn && typeof turn === "object" && !Array.isArray(turn)
            && (turn as Record<string, unknown>).id === turnId) return;
        }
      } finally {
        activeTurnStream = false;
      }
    },
  };
}
