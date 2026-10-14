import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";
import { translateClaudeSdkStream } from "./claude-code-message-translator";

export interface ClaudeCodeAdapterTransport {
  start(context: EngineRunContext, input: EngineInput): AsyncIterable<EngineEvent>;
  continue(context: EngineRunContext, session: NativeSessionReference, input: EngineInput): AsyncIterable<EngineEvent>;
  cancel(context: EngineRunContext, session: NativeSessionReference): Promise<"requested" | "confirmed">;
  reconcile(context: EngineRunContext, session: NativeSessionReference): Promise<EngineRunStatus>;
  resumeFromCursor(context: EngineRunContext, cursor: string | null): AsyncIterable<EngineEvent>;
  respondToApproval(context: EngineRunContext, requestId: string, decision: "allow" | "deny"): Promise<void>;
  erase(context: EngineRunContext, session: NativeSessionReference): Promise<"confirmed" | "unsupported">;
  dispose(): Promise<void>;
}

type ClaudeSdkMessageStream = AsyncIterable<unknown> | Promise<AsyncIterable<unknown>>;

/** Provider-facing source used while extracting the existing Claude runner. */
export interface ClaudeCodeSdkMessageSource {
  start(context: EngineRunContext, input: EngineInput): ClaudeSdkMessageStream;
  continue(context: EngineRunContext, session: NativeSessionReference, input: EngineInput): ClaudeSdkMessageStream;
  cancel(context: EngineRunContext, session: NativeSessionReference): Promise<"requested" | "confirmed">;
  reconcile(context: EngineRunContext, session: NativeSessionReference): Promise<EngineRunStatus>;
  resumeFromCursor(context: EngineRunContext, cursor: string | null): ClaudeSdkMessageStream;
  respondToApproval(context: EngineRunContext, requestId: string, decision: "allow" | "deny"): Promise<void>;
  erase(context: EngineRunContext, session: NativeSessionReference): Promise<"confirmed" | "unsupported">;
  dispose(): Promise<void>;
}

export const CLAUDE_CODE_ENGINE_ID = "claude-code" as const;

export function sanitizeClaudeError(error: unknown): Error {
  const candidate = error as { code?: unknown } | null;
  const code = typeof candidate?.code === "string" && /^[a-z0-9_-]{1,64}$/i.test(candidate.code)
    ? candidate.code
    : "claude_provider_error";
  return Object.assign(new Error("Claude provider request failed"), { code });
}

export function validateClaudeEvent(event: EngineEvent, expectedRunId: string): EngineEvent {
  if (event.runId !== expectedRunId || !event.eventId || !Number.isInteger(event.sequence) || event.sequence < 1) {
    throw Object.assign(new Error("Claude event does not match the bound run"), { code: "claude_event_invalid" });
  }
  return event;
}

/**
 * Adapt an SDK-shaped message source without importing SDK types into the
 * neutral transport. Lifecycle side effects remain owned by the source.
 */
export function createClaudeCodeSdkTransport(source: ClaudeCodeSdkMessageSource): ClaudeCodeAdapterTransport {
  async function* stream(load: () => ClaudeSdkMessageStream, runId: string): AsyncIterable<EngineEvent> {
    yield* translateClaudeSdkStream(await load(), runId);
  }
  return {
    start: (context, input) => stream(() => source.start(context, input), context.runId),
    continue: (context, session, input) => stream(() => source.continue(context, session, input), context.runId),
    cancel: (context, session) => source.cancel(context, session),
    reconcile: (context, session) => source.reconcile(context, session),
    resumeFromCursor: (context, cursor) => stream(() => source.resumeFromCursor(context, cursor), context.runId),
    respondToApproval: (context, requestId, decision) => source.respondToApproval(context, requestId, decision),
    erase: (context, session) => source.erase(context, session),
    dispose: () => source.dispose(),
  };
}

/** Claude-specific transport stays behind this adapter; the web contract does not import SDK messages. */
export function createClaudeCodeAdapter(transport: ClaudeCodeAdapterTransport): EngineAdapter {
  async function* stream(load: () => AsyncIterable<EngineEvent>, runId: string): AsyncIterable<EngineEvent> {
    let lastSequence = 0;
    try {
      for await (const event of load()) {
        const validated = validateClaudeEvent(event, runId);
        if (validated.sequence <= lastSequence) {
          throw Object.assign(new Error("Claude event sequence is stale or duplicated"), {
            code: "claude_event_sequence_invalid",
          });
        }
        lastSequence = validated.sequence;
        yield validated;
      }
    } catch (error) {
      throw sanitizeClaudeError(error);
    }
  }
  const call = async <T>(operation: () => Promise<T>): Promise<T> => {
    try { return await operation(); } catch (error) { throw sanitizeClaudeError(error); }
  };
  return {
    start: (context, input) => stream(() => transport.start(context, input), context.runId),
    continue: (context, session, input) => stream(() => transport.continue(context, session, input), context.runId),
    cancel: (context, session) => call(() => transport.cancel(context, session)),
    reconcile: (context, session) => call(() => transport.reconcile(context, session)),
    resumeFromCursor: (context, cursor) => stream(() => transport.resumeFromCursor(context, cursor), context.runId),
    respondToApproval: (context, requestId, decision) => call(() => transport.respondToApproval(context, requestId, decision)),
    erase: (context, session) => call(() => transport.erase(context, session)),
    dispose: () => call(() => transport.dispose()),
  };
}
