import logger from "./logger";

export type EngineObservabilityEvent =
  | "engine_dispatch_started"
  | "engine_dispatch_progress"
  | "engine_dispatch_completed"
  | "engine_dispatch_failed"
  | "engine_session_reconciled"
  | "engine_replay_item_dropped"
  | "engine_replay_failed";

export interface EngineObservabilityMetadata {
  engineId?: string;
  workspaceId?: string;
  conversationId?: string;
  routineId?: string;
  routineRunId?: string;
  adapterVersion?: string;
  runId?: string;
  status?: string;
  failureClass?: string;
  sequence?: number;
  itemType?: string;
  reason?: string;
}

export type EngineObservabilitySink = (
  event: EngineObservabilityEvent,
  metadata: EngineObservabilityMetadata,
) => void;

const defaultSink: EngineObservabilitySink = (event, metadata) => {
  logger.info({ event, ...metadata }, event);
};

/**
 * Structured engine lifecycle telemetry. The narrow metadata type prevents
 * prompts, provider payloads, credentials, and native handles from entering
 * pino or Sentry through this boundary.
 */
export function createEngineObservability(sink: EngineObservabilitySink = defaultSink) {
  return {
    emit(event: EngineObservabilityEvent, metadata: EngineObservabilityMetadata = {}): void {
      try {
        sink(event, { ...metadata });
      } catch {
        // Observability must never change the provider or user-visible path.
      }
    },
  };
}

export type EngineObservability = ReturnType<typeof createEngineObservability>;
