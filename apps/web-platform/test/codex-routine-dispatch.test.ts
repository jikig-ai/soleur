import { describe, expect, it, vi } from "vitest";
import { createEngineRegistry } from "@/server/agent-engine-registry";
import { dispatchCodexRoutineToEvents } from "@/server/codex-routine-dispatch";

describe("Codex routine dispatch bridge", () => {
  it("dispatches a persisted Codex routine and persists neutral events", async () => {
    const events = [] as unknown[];
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "e-1", sequence: 1, payload: { type: "status", status: "completed" } as const };
    }) };
    const binding = { workspaceId: "ws-1", execution: { kind: "routine" as const, routineId: "cron-daily-triage", routineRunId: "routine-1" }, engineId: "codex", authMode: "api-key", adapterVersion: "codex-v1", boundAt: new Date().toISOString() };
    const repository = {
      getRoutineRun: vi.fn().mockResolvedValue({ id: "run-1", binding }),
      getRun: vi.fn().mockResolvedValue({ id: "run-1", binding }),
      appendEvent: vi.fn(async (event: unknown) => { events.push(event); }),
    };
    const provider = { mode: "api-key" as const, acquire: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }), refresh: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }), logout: async () => undefined };
    const registry = createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true, authModes: ["api-key"],
      qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "routine", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "test", capabilities: {} }],
    }]);
    const received = [] as unknown[];
    for await (const event of dispatchCodexRoutineToEvents({
      repository,
      runtime: { userId: "user-1", transport: {} as never, apiKeyProvider: provider, createCodex: () => adapter as never },
      routineId: "cron-daily-triage",
      routineRunId: "routine-1",
      input: { text: "run", attachmentIds: [] },
      context: { runId: "run-1", binding: binding as never, idempotencyKey: "idempotency", signal: new AbortController().signal },
      selection: { engineId: "codex", authMode: "api-key", operation: "existing-run", workflow: "routine", dataClass: "synthetic", requiredCapabilities: [], now: Date.now() },
      evidence: { endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"], vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false },
      registry,
    })) received.push(event);
    expect(received).toHaveLength(1);
    expect(events).toHaveLength(1);
  });
});
