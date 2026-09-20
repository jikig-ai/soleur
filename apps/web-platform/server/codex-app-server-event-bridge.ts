import {
  createCodexAppServerEventBuffer,
  type CodexAppServerEventBuffer,
} from "./codex-app-server-event-buffer";

export interface CodexAppServerEventBridge extends CodexAppServerEventBuffer {
  onNotification(message: Record<string, unknown>): void;
  onClose(reason?: unknown): void;
}

/** Adapt RPC callbacks into one bounded stream owned by a Codex source. */
export function createCodexAppServerEventBridge(
  options: { maxSize?: number } = {},
): CodexAppServerEventBridge {
  const buffer = createCodexAppServerEventBuffer(options);
  return {
    push: buffer.push,
    close: buffer.close,
    stream: buffer.stream,
    size: buffer.size,
    onNotification: (message) => buffer.push(message),
    onClose: (reason) => buffer.close(reason),
  };
}
