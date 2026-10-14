import type {
  EngineEvent,
  EngineEventPayload,
  EngineRunStatus,
} from "./agent-engine-contract";

const TERMINAL = new Set<EngineRunStatus>(["completed", "failed", "cancelled"]);

/** In-memory lifecycle ledger used by adapters and persistence implementations. */
export class EngineEventLedger {
  private readonly events = new Map<string, EngineEvent>();
  private nextSequence = 1;
  private _status: EngineRunStatus = "queued";

  constructor(private readonly runId: string) {}

  get status(): EngineRunStatus {
    return this._status;
  }

  append(payload: EngineEventPayload, eventId: string): EngineEvent {
    const existing = this.events.get(eventId);
    if (existing) return existing;
    if (TERMINAL.has(this._status)) throw new Error("run is terminal");
    const event: EngineEvent = {
      runId: this.runId,
      eventId,
      sequence: this.nextSequence,
      payload,
    };
    this.accept(event);
    return event;
  }

  accept(event: EngineEvent): EngineEvent {
    if (event.runId !== this.runId) throw new Error("event run mismatch");
    const existing = this.events.get(event.eventId);
    if (existing) return existing;
    if (event.sequence !== this.nextSequence) throw new Error("event sequence is not contiguous");
    if (TERMINAL.has(this._status)) throw new Error("run is terminal");
    this.events.set(event.eventId, event);
    this.nextSequence += 1;
    if (event.payload.type === "status") this._status = event.payload.status;
    return event;
  }

  requestCancellation(): "uncertain" {
    if (!TERMINAL.has(this._status)) {
      this.append({ type: "status", status: "cancel_requested" }, `cancel-${this.nextSequence}`);
    }
    return "uncertain";
  }
}
