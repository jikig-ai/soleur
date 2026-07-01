// Shared SDK fixture harness for the `soleur-go-runner-*.test.ts` suite
// (#3331). Consolidates the near-duplicate per-file helpers (mock Query,
// SDK message builders, recording DispatchEvents, microtask flusher) into
// one import-only module.
//
// IMPORTANT: this file MUST NOT carry a `.test.ts` suffix — vitest's
// `test/**/*.test.ts` glob would otherwise collect it as an (empty) suite.
//
// The helpers diverge across call sites (positional vs options-object
// `makeResult`; `duration_ms` 100 vs 1; a rich scripted `createMockQuery`
// vs a lean one; differing `makeEvents` shapes). Rather than force one
// shape, this module exports CONFIGURABLE SUPERSETS plus BOTH named
// `createMockQuery*` variants so each consumer keeps its exact behavior.

import { vi } from "vitest";
import type {
  Query,
  SDKMessage,
  SDKUserMessage,
  SDKResultMessage,
  SDKAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";
import type { DispatchEvents, WorkflowEnd } from "@/server/soleur-go-runner";

/** Strips `readonly` so test fixtures can assemble partial SDK Query stubs. */
type Mutable<T> = { -readonly [K in keyof T]: T[K] };

// ---------------------------------------------------------------------------
// SDK message builders
// ---------------------------------------------------------------------------

/**
 * Builds a minimal `SDKAssistantMessage` from a partial. This is the
 * `partial`-form used by `awaiting-user` / `tool-result-idle-reset`:
 * `id` falls back to `partial.uuid ?? "msg_1"`, and `parent_tool_use_id`
 * / `uuid` / `session_id` are overridable.
 */
export function makeAssistant(
  partial: Partial<SDKAssistantMessage> & {
    content: Array<
      | { type: "text"; text: string }
      | {
          type: "tool_use";
          id: string;
          name: string;
          input: Record<string, unknown>;
        }
    >;
  },
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: partial.uuid ?? "msg_1",
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
      content: partial.content,
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: partial.parent_tool_use_id ?? null,
    uuid: (partial.uuid ?? "00000000-0000-0000-0000-000000000001") as never,
    session_id: partial.session_id ?? "sess-1",
  } as SDKAssistantMessage;
}

/**
 * Builds a minimal `SDKResultMessage`. Superset covering BOTH call-site
 * shapes:
 *   - positional `makeResult(totalCostUsd, sessionId?)` — most files;
 *   - options `makeResult({ totalCostUsd?, sessionId?, durationMs? })` —
 *     `session-id-rebound` (where `sessionId` may be `null`, coerced to "").
 *
 * `durationMs` defaults to `100`; lean positional callers receive that same
 * `100` default. The value is observationally inert — the runner derives
 * elapsed time from the clock and never reads `msg.duration_ms` — so the
 * default is a placeholder, not a behavioral knob.
 */
export function makeResult(totalCostUsd?: number, sessionId?: string): SDKResultMessage;
export function makeResult(opts: {
  totalCostUsd?: number;
  sessionId?: string | null;
  durationMs?: number;
}): SDKResultMessage;
export function makeResult(
  arg1?: number | { totalCostUsd?: number; sessionId?: string | null; durationMs?: number },
  arg2?: string,
): SDKResultMessage {
  const opts =
    typeof arg1 === "object" && arg1 !== null
      ? arg1
      : { totalCostUsd: arg1, sessionId: arg2 };
  const durationMs = opts.durationMs ?? 100;
  return {
    type: "result",
    subtype: "success",
    duration_ms: durationMs,
    duration_api_ms: 50,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: opts.totalCostUsd ?? 0,
    // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: (opts.sessionId ?? "sess-1") as string,
  } as SDKResultMessage;
}

/**
 * A `user`-role SDK message carrying `tool_use_result` — the SDK's own
 * forward-progress signal. Used by `tool-result-idle-reset`.
 */
export function makeUserToolResult(
  toolUseId: string,
  sessionId = "sess-1",
): SDKUserMessage {
  return {
    type: "user",
    message: {
      role: "user",
      content: [
        {
          type: "tool_result",
          tool_use_id: toolUseId,
          content: "ok",
        },
      ],
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    isSynthetic: true,
    tool_use_result: { ok: true },
    session_id: sessionId,
  } as SDKUserMessage;
}

/**
 * An `SDKToolProgressMessage` — the SDK's mid-tool forward-progress heartbeat
 * (`type: 'tool_progress'`, carrying `tool_use_id`/`tool_name`/
 * `elapsed_time_seconds`). It flows into `consumeStream` because
 * `includePartialMessages: true` is set in the shared options builder
 * (`agent-runner-query-options.ts:156`). The soleur-go runner re-arms
 * `state.runaway` off this message (reads no fields — pure re-arm).
 */
export function makeToolProgress(
  toolUseId: string,
  elapsedSeconds: number,
  sessionId = "sess-1",
): SDKMessage {
  return {
    type: "tool_progress",
    tool_use_id: toolUseId,
    tool_name: "Read",
    parent_tool_use_id: null,
    elapsed_time_seconds: elapsedSeconds,
    uuid: "00000000-0000-0000-0000-0000000000bb" as never,
    session_id: sessionId,
    // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
  } as any;
}

/**
 * `SDKUserMessageReplay` shares the `tool_use_result?: unknown` field with
 * `SDKUserMessage`; a structural superset of {@link makeUserToolResult}.
 */
export function makeUserToolResultReplay(
  toolUseId: string,
  sessionId = "sess-1",
): SDKUserMessage {
  return {
    ...makeUserToolResult(toolUseId, sessionId),
    isReplay: true,
    uuid: "00000000-0000-0000-0000-0000000000aa" as never,
    // biome-ignore lint/suspicious/noExplicitAny: replay variant is a structural superset
  } as any;
}

// ---------------------------------------------------------------------------
// Mock Query factories
// ---------------------------------------------------------------------------

/** Shared base set of no-op `Query` control methods (interrupt, setModel, …). */
function queryControlStubs(): Omit<
  Mutable<Partial<Query>>,
  "close" | typeof Symbol.asyncIterator | "next" | "return" | "throw"
> {
  return {
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
}

/**
 * Rich, scripted mock Query: a pre-seeded queue plus `emit` / `emitError` /
 * `finish` / `throwOnNext` controls and an `emitted` log. Mirrors the
 * variant in `awaiting-user` (and, minus `emitError`, `tool-result-idle-reset`).
 */
export function createMockQueryScripted(scripted: SDKMessage[] = []) {
  let closed = false;
  const queue: SDKMessage[] = [...scripted];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const emitted: SDKMessage[] = [];
  const closeSpy = vi.fn();
  let throwOnNext: unknown = null;

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (throwOnNext !== null) {
        const err = throwOnNext;
        throwOnNext = null;
        throw err;
      }
      if (queue.length > 0) {
        const value = queue.shift()!;
        emitted.push(value);
        return { value, done: false };
      }
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
      emitted.push(msg);
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }

  function emitError(err: unknown): void {
    // Inject an error into the consumeStream loop. If a consumer is
    // currently awaiting next(), we must reject that pending promise.
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      // Trigger via the iterator's `throw` semantics: settle the awaiting
      // promise with a rejected one.
      Promise.resolve().then(() => r(Promise.reject(err) as never));
    } else {
      throwOnNext = err;
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
    close: () => {
      closeSpy();
      finish();
    },
    ...queryControlStubs(),
  };

  return {
    query: q as Query,
    emit,
    emitError,
    finish,
    closeSpy,
    emitted,
    isClosed: () => closed,
  };
}

/**
 * Lean mock Query: `emit` / `finish` only (no scripted queue, no
 * `emitError`). Mirrors the variant in `lifecycle` / `session-id-rebound`
 * / `interactive-prompt` / `chapter-chunked`. Captures `sessionId` for the
 * call sites that thread it.
 */
export function createMockQueryLean(sessionId = "sess-1") {
  let closed = false;
  const queue: SDKMessage[] = [];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const closeSpy = vi.fn();

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (queue.length > 0) {
        const v = queue.shift()!;
        return { value: v, done: false };
      }
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((r) => {
        resolveNext = r;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(e) {
      closed = true;
      throw e;
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
    close: () => {
      closeSpy();
      finish();
    },
    ...queryControlStubs(),
  };

  return {
    query: q as Query,
    emit,
    finish,
    closeSpy,
    sessionId,
    isClosed: () => closed,
  };
}

// ---------------------------------------------------------------------------
// Recording DispatchEvents
// ---------------------------------------------------------------------------

/**
 * A `DispatchEvents` recorder that collects ended workflows and observed
 * tool-use blocks. Superset of the `awaiting-user` / `tool-result-idle-reset`
 * shape; the `_tools` field is ignored by call sites that only read `_ended`.
 */
export function makeRecordingEvents(): DispatchEvents & {
  _ended: WorkflowEnd[];
  _tools: Array<{ name: string; input: Record<string, unknown> }>;
  _progress: Array<{
    toolUseId: string;
    toolName: string;
    elapsedSeconds: number;
  }>;
} {
  const ended: WorkflowEnd[] = [];
  const tools: Array<{ name: string; input: Record<string, unknown> }> = [];
  // #5214 — captures `onToolProgress` heartbeat emits (raw, un-debounced at
  // the runner boundary). Call sites that ignore progress simply never read
  // `_progress`; the optional `onToolProgress` field keeps existing recorders
  // behavior-neutral.
  const progress: Array<{
    toolUseId: string;
    toolName: string;
    elapsedSeconds: number;
  }> = [];
  return {
    onText: () => {},
    onToolUse: (b) => tools.push(b),
    onToolProgress: (b) => progress.push(b),
    onWorkflowDetected: () => {},
    onWorkflowEnded: (e) => ended.push(e),
    onResult: () => {},
    _ended: ended,
    _tools: tools,
    _progress: progress,
  };
}

// ---------------------------------------------------------------------------
// Microtask flusher
// ---------------------------------------------------------------------------

/** Awaits `count` resolved microtasks so queued async runner work settles. */
export async function flushMicrotasks(count = 8): Promise<void> {
  for (let i = 0; i < count; i++) await Promise.resolve();
}
