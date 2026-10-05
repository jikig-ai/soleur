const DEFAULT_MAX_SIZE = 256;

export interface CodexAppServerEventBuffer {
  push(event: unknown): void;
  close(reason?: unknown): void;
  stream(): AsyncIterable<unknown>;
  size(): number;
}

interface Waiter {
  resolve: (result: IteratorResult<unknown>) => void;
  reject: (error: unknown) => void;
}

function bufferError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

/**
 * Bounded ordered notification handoff between an App Server RPC callback and
 * the neutral event translator. Source shutdown is explicit and queued events
 * drain before a terminal source error is raised.
 */
export function createCodexAppServerEventBuffer(options: { maxSize?: number } = {}): CodexAppServerEventBuffer {
  const maxSize = options.maxSize ?? DEFAULT_MAX_SIZE;
  if (!Number.isInteger(maxSize) || maxSize < 1 || maxSize > 10_000) {
    throw bufferError("Codex event buffer size is invalid", "codex_event_buffer_invalid");
  }

  const queue: unknown[] = [];
  const waiters: Waiter[] = [];
  let closed = false;
  let terminalError: unknown;

  const close = (reason?: unknown): void => {
    if (closed) return;
    closed = true;
    terminalError = reason;
    if (terminalError !== undefined) {
      for (const waiter of waiters) waiter.reject(terminalError);
    } else {
      for (const waiter of waiters) waiter.resolve({ done: true, value: undefined });
    }
    waiters.length = 0;
  };

  const push = (event: unknown): void => {
    if (closed) return;
    const waiter = waiters.shift();
    if (waiter) {
      waiter.resolve({ done: false, value: event });
      return;
    }
    if (queue.length >= maxSize) {
      close(bufferError("Codex event buffer is full", "codex_event_backpressure"));
      return;
    }
    queue.push(event);
  };

  async function* stream(): AsyncIterable<unknown> {
    while (queue.length > 0) yield queue.shift();
    if (closed) {
      if (terminalError !== undefined) throw terminalError;
      return;
    }
    while (true) {
      const next = await new Promise<IteratorResult<unknown>>((resolve, reject) => {
        waiters.push({ resolve, reject });
      });
      if (next.done) return;
      yield next.value;
      while (queue.length > 0) yield queue.shift();
      if (closed) {
        if (terminalError !== undefined) throw terminalError;
        return;
      }
    }
  }

  return { push, close, stream, size: () => queue.length };
}
