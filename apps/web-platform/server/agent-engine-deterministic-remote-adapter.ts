import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";

export interface DeterministicRemoteScenario {
  approval?: boolean;
  cancellationConfirmAfter?: number;
  duplicateSequence?: boolean;
  terminalStatus?: Extract<EngineRunStatus, "completed" | "failed">;
}

/**
 * Network-free remote adapter used to qualify lifecycle and recovery behavior.
 * It deliberately has no credentials, provider SDK, or customer-data path.
 */
export function createDeterministicRemoteAdapter(
  scenario: DeterministicRemoteScenario = {},
): EngineAdapter {
  let cancellationRequested = false;
  let reconcileCount = 0;
  let disposed = false;
  const cancellationConfirmAfter = Math.max(1, scenario.cancellationConfirmAfter ?? 2);

  function assertUsable(): void {
    if (disposed) throw new Error("deterministic remote adapter disposed");
  }

  async function* stream(context: EngineRunContext, includeApproval: boolean): AsyncGenerator<EngineEvent> {
    assertUsable();
    let sequence = 0;
    const emit = (payload: EngineEvent["payload"], eventId = `remote-${sequence + 1}`): EngineEvent => ({
      runId: context.runId,
      eventId,
      sequence: ++sequence,
      payload,
    });

    yield emit({ type: "status", status: "queued" });
    yield emit({ type: "status", status: "running" });
    if (includeApproval) {
      yield emit({ type: "status", status: "waiting" });
      yield emit({ type: "approval", requestId: "remote-approval-1", tool: "remote-action", description: "Synthetic approval" });
    }
    yield emit({
      type: "usage",
      usage: {
        native: [{ unit: "remote_steps", value: 1 }],
        cost: { provenance: "unavailable" },
      },
    });
    if (scenario.duplicateSequence) {
      yield { ...emit({ type: "progress", message: "duplicate" }), sequence: sequence - 1, eventId: "remote-duplicate" };
      return;
    }
    yield emit({ type: "status", status: scenario.terminalStatus ?? "completed" });
  }

  return {
    start: (context) => stream(context, scenario.approval === true),
    continue: (context, _session, _input) => stream(context, false),
    cancel: async () => {
      assertUsable();
      cancellationRequested = true;
      return "requested";
    },
    reconcile: async () => {
      assertUsable();
      reconcileCount += 1;
      return cancellationRequested && reconcileCount >= cancellationConfirmAfter
        ? "cancelled"
        : "running";
    },
    resumeFromCursor: (context) => stream(context, false),
    respondToApproval: async () => {
      assertUsable();
    },
    erase: async (): Promise<"confirmed"> => {
      assertUsable();
      return "confirmed";
    },
    dispose: async () => {
      disposed = true;
    },
  } satisfies EngineAdapter;
}

export type DeterministicRemoteAdapter = EngineAdapter;
