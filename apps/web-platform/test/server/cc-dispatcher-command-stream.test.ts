/**
 * feat-concierge-stream-commands — AC2 / AC4 / AC5 / AC6.
 *
 * Two layers:
 *  1. RUNNER forwarding (AC5): the soleur-go-runner correlates a Bash
 *     `tool_use` with its synthetic `user`-role `tool_use_result` (via
 *     `bashToolUses`) and invokes `events.onToolResult({toolUseId, command,
 *     output})`. NON-Bash tool-uses never fire it.
 *  2. EMIT-boundary transform (AC4/AC6): the dispatcher redacts the
 *     command/output AND byte-caps the output (per-chunk + per-command)
 *     with a `[… truncated]` marker. The transform is the composition of
 *     the exported `capUtf8Bytes` + `redactCommandForDisplay` used at the
 *     `command_stream` emit site. Asserts no secret substring survives and
 *     the capped payload length ≤ cap + marker.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type {
  Query,
  SDKMessage,
  SDKAssistantMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  createSoleurGoRunner,
  type QueryFactory,
  type DispatchEvents,
} from "@/server/soleur-go-runner";
import {
  capUtf8Bytes,
  COMMAND_STREAM_CHUNK_CAP_BYTES,
  COMMAND_STREAM_TOTAL_CAP_BYTES,
  COMMAND_STREAM_TRUNCATION_MARKER,
} from "@/server/cc-dispatcher";
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

const GHS = "ghs_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5";

function makeAssistant(
  content: Array<
    | { type: "text"; text: string }
    | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
  >,
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: "msg_1",
      role: "assistant",
      model: "claude-sonnet-5",
      stop_reason: null,
      stop_sequence: null,
      type: "message",
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        server_tool_use: null,
        service_tier: null,
      },
      content,
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    uuid: "00000000-0000-0000-0000-000000000001" as never,
    session_id: "sess-1",
  } as SDKAssistantMessage;
}

/** Synthetic `user`-role tool_use_result carrying one `tool_result` block. */
function makeToolResult(toolUseId: string, text: string): SDKUserMessage {
  return {
    type: "user",
    message: {
      role: "user",
      content: [
        { type: "tool_result", tool_use_id: toolUseId, content: [{ type: "text", text }] },
      ],
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    tool_use_result: { stdout: text },
    session_id: "sess-1",
  } as SDKUserMessage;
}

function createMockQuery() {
  let closed = false;
  const queue: SDKMessage[] = [];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (queue.length > 0) return { value: queue.shift()!, done: false };
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((resolve) => {
        resolveNext = resolve;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(err) {
      closed = true;
      throw err;
    },
    async [Symbol.asyncDispose]() {
      closed = true;
    },
    [Symbol.asyncIterator]() {
      return iter;
    },
  };
  function emit(msg: SDKMessage): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }
  function finish(): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: undefined, done: true });
    }
    closed = true;
  }
  const q: Mutable<Partial<Query>> = {
    ...(iter as unknown as Query),
    close: () => finish(),
    interrupt: vi.fn(async () => {}),
    setPermissionMode: vi.fn(async () => {}),
    setModel: vi.fn(async () => {}),
    setMaxThinkingTokens: vi.fn(async () => {}),
    applyFlagSettings: vi.fn(async () => {}),
    // biome-ignore lint/suspicious/noExplicitAny: test stub
    initializationResult: vi.fn(async () => ({}) as any),
    supportedCommands: vi.fn(async () => []),
    supportedModels: vi.fn(async () => []),
    streamInput: vi.fn(async () => {}),
    stopTask: vi.fn(async () => {}),
  };
  return { query: q as Query, emit, finish };
}

async function flushMicrotasks(count = 12): Promise<void> {
  for (let i = 0; i < count; i++) await Promise.resolve();
}

function makeEvents(
  overrides: Partial<DispatchEvents> = {},
): DispatchEvents {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
    ...overrides,
  };
}

describe("command_stream RUNNER forwarding (AC5)", () => {
  let toolResults: Array<{ toolUseId: string; command: string; output: string }>;

  beforeEach(() => {
    vi.useFakeTimers({ now: 0 });
    toolResults = [];
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  async function run(
    tool: { id: string; name: string; input: Record<string, unknown> },
    resultText: string,
  ): Promise<void> {
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => Date.now() });
    const events = makeEvents({
      onToolResult: (b) => {
        toolResults.push(b);
      },
    });
    await runner.dispatch({
      conversationId: "conv-1",
      userId: "user-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emit(makeAssistant([{ type: "tool_use", ...tool }]));
    await flushMicrotasks();
    mock.emit(makeToolResult(tool.id, resultText));
    await flushMicrotasks();
    mock.finish();
    await flushMicrotasks();
  }

  it("Bash tool_use + matching tool_result → onToolResult fires with command + output", async () => {
    await run(
      { id: "toolu_bash", name: "Bash", input: { command: "git status" } },
      "On branch main\n",
    );
    expect(toolResults).toHaveLength(1);
    expect(toolResults[0].toolUseId).toBe("toolu_bash");
    expect(toolResults[0].command).toBe("git status");
    expect(toolResults[0].output).toBe("On branch main\n");
  });

  it("non-Bash tool_use (Read) → onToolResult never fires", async () => {
    await run(
      { id: "toolu_read", name: "Read", input: { file_path: "/x" } },
      "file contents",
    );
    expect(toolResults).toHaveLength(0);
  });
});

describe("command_stream EMIT-boundary transform (AC4/AC6)", () => {
  // The emit site applies: capUtf8Bytes(chunk) → capUtf8Bytes(total) →
  // redactCommandForDisplay → marker. These assertions pin that contract.

  it("AC4 — a command carrying a `ghs_` token is redacted before emit", () => {
    const raw = `git clone https://x-access-token:${GHS}@github.com/o/r`;
    const redacted = redactCommandForDisplay(raw);
    expect(redacted).not.toContain(GHS);
    expect(redacted).toContain("[redacted-key]");
  });

  it("AC4 — output echoing a token (env) is redacted before emit", () => {
    const raw = `GH_TOKEN=${"p4t_synthetic_0123456789ABCDEF"}\n`;
    const redacted = redactCommandForDisplay(raw);
    expect(redacted).toContain("GH_TOKEN=[redacted-key]");
    expect(redacted).not.toContain("p4t_synthetic_0123456789ABCDEF");
  });

  it("AC6 — per-chunk cap bounds a single oversized output", () => {
    const huge = "a".repeat(COMMAND_STREAM_CHUNK_CAP_BYTES * 3);
    const capped = capUtf8Bytes(huge, COMMAND_STREAM_CHUNK_CAP_BYTES);
    expect(capped.truncated).toBe(true);
    expect(Buffer.from(capped.text, "utf8").length).toBeLessThanOrEqual(
      COMMAND_STREAM_CHUNK_CAP_BYTES,
    );
  });

  it("AC6 — per-command total cap bounds cumulative output; emitted payload ≤ cap + marker", () => {
    // Simulate the emit-site budget math: feed > total cap of output across
    // chunks and assert the cumulative emitted bytes never exceed the cap.
    let budget = COMMAND_STREAM_TOTAL_CAP_BYTES;
    let emittedTotal = 0;
    for (let i = 0; i < 10; i++) {
      const chunk = capUtf8Bytes("x".repeat(COMMAND_STREAM_CHUNK_CAP_BYTES), COMMAND_STREAM_CHUNK_CAP_BYTES);
      const capped = capUtf8Bytes(chunk.text, Math.max(0, budget));
      const bytes = Buffer.from(capped.text, "utf8").length;
      budget -= bytes;
      emittedTotal += bytes;
    }
    expect(emittedTotal).toBeLessThanOrEqual(COMMAND_STREAM_TOTAL_CAP_BYTES);
    // A truncated chunk's wire payload = redacted text + marker.
    const wire = `${capUtf8Bytes("y".repeat(100), 50).text}${COMMAND_STREAM_TRUNCATION_MARKER}`;
    expect(wire.endsWith("[… truncated]")).toBe(true);
  });

  it("AC6 — under-cap output is NOT truncated and passes through unchanged", () => {
    const small = "all good\n";
    const capped = capUtf8Bytes(small, COMMAND_STREAM_CHUNK_CAP_BYTES);
    expect(capped.truncated).toBe(false);
    expect(capped.text).toBe(small);
  });

  it("capUtf8Bytes never splits a multi-byte code point", () => {
    // "✨" is 3 UTF-8 bytes. Cap at 4 bytes → must keep 1 full char (3 bytes),
    // not a half-char.
    const s = "✨✨";
    const capped = capUtf8Bytes(s, 4);
    expect(capped.truncated).toBe(true);
    expect(capped.text).toBe("✨");
  });
});
