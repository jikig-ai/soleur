import { describe, expect, it } from "vitest";
import { EngineEventLedger } from "@/server/agent-engine-events";

describe("EngineEventLedger", () => {
  it("deduplicates event ids and enforces contiguous sequence numbers", () => {
    const ledger = new EngineEventLedger("run-1");
    const event = ledger.append({ type: "text", text: "hello" }, "evt-1");
    expect(ledger.append({ type: "text", text: "changed" }, "evt-1")).toEqual(event);
    expect(() => ledger.accept({ runId: "run-1", eventId: "evt-3", sequence: 3, payload: { type: "text", text: "x" } }))
      .toThrow(/sequence/);
  });

  it("allows one terminal state and ignores stale later events", () => {
    const ledger = new EngineEventLedger("run-2");
    ledger.append({ type: "status", status: "completed" }, "evt-terminal");
    expect(() => ledger.append({ type: "status", status: "running" }, "evt-stale")).toThrow(/terminal/);
    expect(ledger.status).toBe("completed");
  });

  it("records uncertain cancellation without claiming remote confirmation", () => {
    const ledger = new EngineEventLedger("run-3");
    expect(ledger.requestCancellation()).toBe("uncertain");
    expect(ledger.status).toBe("cancel_requested");
  });
});
