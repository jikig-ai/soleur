import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";

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

export const CLAUDE_CODE_ENGINE_ID = "claude-code" as const;

/** Claude-specific transport stays behind this adapter; the web contract does not import SDK messages. */
export function createClaudeCodeAdapter(transport: ClaudeCodeAdapterTransport): EngineAdapter {
  return {
    start: (context, input) => transport.start(context, input),
    continue: (context, session, input) => transport.continue(context, session, input),
    cancel: (context, session) => transport.cancel(context, session),
    reconcile: (context, session) => transport.reconcile(context, session),
    resumeFromCursor: (context, cursor) => transport.resumeFromCursor(context, cursor),
    respondToApproval: (context, requestId, decision) => transport.respondToApproval(context, requestId, decision),
    erase: (context, session) => transport.erase(context, session),
    dispose: () => transport.dispose(),
  };
}
