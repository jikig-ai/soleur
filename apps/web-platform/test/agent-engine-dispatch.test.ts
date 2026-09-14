import { describe, expect, it, vi } from "vitest";
import { cancelBoundEngineRun, continueBoundEngineRun, dispatchBoundEngineRun, dispatchNewEngineRun, dispatchBoundEngineRunFromRegistry, dispatchConversationEngineRun, dispatchRoutineEngineRun, eraseBoundEngineRun, reconcileBoundEngineRun, respondToApprovalBoundEngineRun, resumeBoundEngineRun } from "@/server/agent-engine-dispatch";
import { createEngineRegistry } from "@/server/agent-engine-registry";

describe("dispatchBoundEngineRun", () => {
  it("resolves a conversation binding before selecting its adapter", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-conv-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const persisted = {
      id: "run-conv-1",
      binding: {
        workspaceId: "ws-1",
        execution: { kind: "conversation" as const, conversationId: "conv-1" },
        engineId: "claude-code",
        authMode: "managed",
        adapterVersion: "claude-v1",
        boundAt: "2026-09-14T20:00:00Z",
      },
    };
    const repository = {
      getConversationRun: vi.fn().mockResolvedValue(persisted),
      getRun: vi.fn().mockResolvedValue(persisted),
    };
    const events = [];
    for await (const event of dispatchConversationEngineRun({
      repository,
      factories: { "claude-code": () => adapter as never },
      conversationId: "conv-1",
      input: { text: "hi", attachmentIds: [] },
      context: {} as never,
    })) events.push(event);
    expect(repository.getConversationRun).toHaveBeenCalledWith("conv-1");
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("fails closed when a conversation has no persisted binding", async () => {
    const adapterFactory = vi.fn();
    const repository = {
      getConversationRun: vi.fn().mockResolvedValue(null),
      getRun: vi.fn(),
    };
    await expect((async () => {
      for await (const _event of dispatchConversationEngineRun({
        repository,
        factories: { "claude-code": adapterFactory },
        conversationId: "conv-missing",
        input: { text: "hi", attachmentIds: [] },
        context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("persisted conversation engine binding not found");
    expect(repository.getRun).not.toHaveBeenCalled();
    expect(adapterFactory).not.toHaveBeenCalled();
  });

  it("resolves a routine binding before selecting its adapter", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-routine-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const persisted = {
      id: "run-routine-1",
      binding: {
        workspaceId: "ws-1",
        execution: { kind: "routine" as const, routineId: "cron-daily-triage", routineRunId: "routine-run-1" },
        engineId: "claude-code",
        authMode: "managed",
        adapterVersion: "claude-v1",
        boundAt: "2026-09-14T20:00:00Z",
      },
    };
    const repository = {
      getRoutineRun: vi.fn().mockResolvedValue(persisted),
      getRun: vi.fn().mockResolvedValue(persisted),
    };
    const events = [];
    for await (const event of dispatchRoutineEngineRun({
      repository,
      factories: { "claude-code": () => adapter as never },
      routineId: "cron-daily-triage",
      routineRunId: "routine-run-1",
      input: { text: "run", attachmentIds: [] },
      context: {} as never,
    })) events.push(event);
    expect(repository.getRoutineRun).toHaveBeenCalledWith("cron-daily-triage", "routine-run-1");
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("fails closed when a routine has no persisted binding", async () => {
    const adapterFactory = vi.fn();
    const repository = {
      getRoutineRun: vi.fn().mockResolvedValue(null),
      getRun: vi.fn(),
    };
    await expect((async () => {
      for await (const _event of dispatchRoutineEngineRun({
        repository,
        factories: { "claude-code": adapterFactory },
        routineId: "cron-daily-triage",
        routineRunId: "routine-missing",
        input: { text: "run", attachmentIds: [] },
        context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("persisted routine engine binding not found");
    expect(repository.getRun).not.toHaveBeenCalled();
    expect(adapterFactory).not.toHaveBeenCalled();
  });

  it("resolves the adapter from the persisted engine binding", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const events = [];
    for await (const event of dispatchBoundEngineRunFromRegistry({ repository, factories: { "claude-code": () => adapter as never }, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never })) events.push(event);
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("resolves future engines through an explicit reviewed registry", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-grok-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const registry = createEngineRegistry([{
      id: "grok-build",
      version: "grok-build-v1",
      transport: "remote",
      enabledForNewRuns: true,
      enabledForExistingRuns: true,
      authModes: ["managed"],
      qualifications: [],
    }]);
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-grok-1", binding: { engineId: "grok-build" } }) };
    const events = [];
    for await (const event of dispatchBoundEngineRunFromRegistry({
      repository,
      factories: { "grok-build": () => adapter as never },
      registry,
      runId: "run-grok-1",
      input: { text: "hi", attachmentIds: [] },
      context: {} as never,
    })) events.push(event);
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("emits start, progress, and completion telemetry without event payloads", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "private" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: {
      engineId: "claude-code", workspaceId: "workspace-1", adapterVersion: "claude-v1",
      execution: { kind: "conversation", conversationId: "conversation-1" },
    } }) };
    const observability = { emit: vi.fn() };
    for await (const _event of dispatchBoundEngineRun({
      repository, adapter, observability, runId: "run-1", input: { text: "private", attachmentIds: [] }, context: {} as never,
    })) { /* no-op */ }
    expect(observability.emit.mock.calls.map(([name]) => name)).toEqual([
      "engine_dispatch_started", "engine_dispatch_progress", "engine_dispatch_completed",
    ]);
    expect(observability.emit.mock.calls[1][1]).not.toHaveProperty("text");
  });

  it("fails closed on incomplete egress evidence before invoking a provider", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "should-not-run" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "codex" } }) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRunFromRegistry({
        repository,
        factories: { codex: () => adapter as never },
        egress: {
          selection: {
            engineId: "codex",
            authMode: "managed",
            operation: "existing-run",
            workflow: "interactive",
            dataClass: "customer",
            requiredCapabilities: [],
            now: Date.now(),
          },
        },
        runId: "run-1",
        input: { text: "hi", attachmentIds: [] },
        context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toMatchObject({ code: "engine_egress_denied" });
    expect(adapter.start).not.toHaveBeenCalled();
  });

  it("rejects egress auth modes that differ from the persisted binding", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "should-not-run" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({
      id: "run-1", binding: { engineId: "codex", authMode: "api-key" },
    }) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRunFromRegistry({
        repository,
        factories: { codex: () => adapter as never },
        egress: {
          selection: {
            engineId: "codex",
            authMode: "managed",
            operation: "existing-run",
            workflow: "interactive",
            dataClass: "synthetic",
            requiredCapabilities: [],
            now: Date.now(),
          },
        },
        runId: "run-1",
        input: { text: "hi", attachmentIds: [] },
        context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("egress selection does not match persisted engine binding");
    expect(adapter.start).not.toHaveBeenCalled();
  });
  it("loads the persisted binding before invoking the adapter", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({
      id: "run-1", binding: { engineId: "claude-code" },
    }) };
    const events = [];
    for await (const event of dispatchBoundEngineRun({ repository, adapter, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never })) {
      events.push(event);
    }
    expect(repository.getRun).toHaveBeenCalledWith("run-1");
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });

  it("fails closed when persistence has no binding", async () => {
    const adapter = { start: vi.fn() };
    const repository = { getRun: vi.fn().mockResolvedValue(null) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({ repository, adapter, runId: "missing", input: { text: "hi", attachmentIds: [] }, context: {} as never })) { /* no-op */ }
    })()).rejects.toThrow("persisted engine binding not found");
    expect(adapter.start).not.toHaveBeenCalled();
  });

  it("fails closed when a run lookup returns a different persisted row", async () => {
    const adapter = { start: vi.fn() };
    const repository = {
      getRun: vi.fn().mockResolvedValue({
        id: "different-run",
        binding: { engineId: "claude-code" },
      }),
    };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("persisted engine binding does not match run");
    expect(adapter.start).not.toHaveBeenCalled();
  });

  it("fails closed when the persisted engine does not match the selected adapter", async () => {
    const adapter = { start: vi.fn() };
    const repository = { getRun: vi.fn().mockResolvedValue({
      id: "run-1", binding: { engineId: "codex" },
    }) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, adapterEngineId: "claude-code", runId: "run-1",
        input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("does not match adapter");
    expect(adapter.start).not.toHaveBeenCalled();
  });

  it("binds before dispatching a newly created execution", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-2", eventId: "evt-1", sequence: 1, payload: { type: "status", status: "running" } as const };
    }) };
    const repository = {
      bind: vi.fn().mockResolvedValue({ id: "run-2", binding: { engineId: "claude-code" } }),
      getRun: vi.fn().mockResolvedValue({ id: "run-2", binding: { engineId: "claude-code" } }),
    };
    const events = [];
    for await (const event of dispatchNewEngineRun({ repository, adapter, binding: { workspaceId: "ws-1", executionKind: "conversation", conversationId: "conv-1", createdBy: "user-1" }, input: { text: "hi", attachmentIds: [] }, context: {} as never })) events.push(event);
    expect(repository.bind).toHaveBeenCalledOnce();
    expect(repository.getRun).toHaveBeenCalledWith("run-2");
    expect(events).toHaveLength(1);
  });

  it("persists each adapter event before yielding it", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "status", status: "running" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    const events = [];
    for await (const event of dispatchBoundEngineRun({
      repository, adapter, eventSink, runId: "run-1",
      input: { text: "hi", attachmentIds: [] }, context: {} as never,
    })) events.push(event);
    expect(eventSink.appendEvent).toHaveBeenCalledWith(events[0]);
  });

  it("carries event persistence through new-run composition", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-2", eventId: "evt-1", sequence: 1, payload: { type: "status", status: "queued" } as const };
    }) };
    const repository = {
      bind: vi.fn().mockResolvedValue({ id: "run-2", binding: { engineId: "claude-code" } }),
      getRun: vi.fn().mockResolvedValue({ id: "run-2", binding: { engineId: "claude-code" } }),
    };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    for await (const _event of dispatchNewEngineRun({
      repository, adapter, eventSink, binding: {},
      input: { text: "hi", attachmentIds: [] }, context: {} as never,
    })) { /* no-op */ }
    expect(eventSink.appendEvent).toHaveBeenCalledOnce();
  });

  it("does not yield an event when durable persistence fails", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "secret" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn().mockRejectedValue(new Error("ledger unavailable")) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, eventSink, runId: "run-1",
        input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("ledger unavailable");
  });

  it("rejects transport events for a different run before persistence", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "other-run", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "cross-run" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, eventSink, runId: "run-1",
        input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("event does not match bound run");
    expect(eventSink.appendEvent).not.toHaveBeenCalled();
  });

  it("rejects malformed event payloads before persistence", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield {
        runId: "run-1",
        eventId: "evt-1",
        sequence: 1,
        payload: { type: "status", status: "not-a-run-status" },
      } as never;
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn() };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, eventSink, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("engine event payload is invalid");
    expect(eventSink.appendEvent).not.toHaveBeenCalled();
  });

  it("rejects stale transport sequences before exposing the duplicate event", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "first" } as const };
      yield { runId: "run-1", eventId: "evt-2", sequence: 1, payload: { type: "text", text: "duplicate" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, eventSink, runId: "run-1",
        input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("event sequence is stale or duplicated");
    expect(eventSink.appendEvent).toHaveBeenCalledOnce();
  });

  it("rejects a repeated event ID even when its sequence advances", async () => {
    const adapter = { start: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "first" } as const };
      yield { runId: "run-1", eventId: "evt-1", sequence: 2, payload: { type: "text", text: "replayed" } as const };
    }) };
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of dispatchBoundEngineRun({
        repository, adapter, eventSink, runId: "run-1", input: { text: "hi", attachmentIds: [] }, context: {} as never,
      })) { /* no-op */ }
    })()).rejects.toThrow("engine event ID is duplicated");
    expect(eventSink.appendEvent).toHaveBeenCalledOnce();
  });

  it("reloads the binding before cancellation and reconciliation", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({
      id: "run-1", binding: { engineId: "claude-code" },
    }) };
    const adapter = {
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
    };
    const session = { resumeHandle: "opaque", sessionId: null };
    const observability = { emit: vi.fn() };
    await expect(cancelBoundEngineRun({ repository, adapter, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, session })).resolves.toBe("requested");
    await expect(reconcileBoundEngineRun({ repository, adapter, observability, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, session })).resolves.toBe("running");
    expect(observability.emit).toHaveBeenCalledWith("engine_session_reconciled", expect.objectContaining({ runId: "run-1", status: "running" }));
    expect(repository.getRun).toHaveBeenCalledTimes(2);
  });

  it("reloads the binding before continuing a native session", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const adapter = { continue: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-2", sequence: 2, payload: { type: "text", text: "continued" } as const };
    }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    const events = [];
    for await (const event of continueBoundEngineRun({
      repository, adapter, eventSink, adapterEngineId: "claude-code", runId: "run-1", context: {} as never,
      session: { resumeHandle: "opaque", sessionId: null }, input: { text: "next", attachmentIds: [] },
    })) events.push(event);
    expect(adapter.continue).toHaveBeenCalledOnce();
    expect(eventSink.appendEvent).toHaveBeenCalledWith(events[0]);
    expect(events[0].payload).toEqual({ type: "text", text: "continued" });
  });

  it("rejects a cross-run continuation event before persistence", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const adapter = { continue: vi.fn(async function* () {
      yield { runId: "other-run", eventId: "evt-2", sequence: 2, payload: { type: "text", text: "cross-run" } as const };
    }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of continueBoundEngineRun({
        repository, adapter, eventSink, adapterEngineId: "claude-code", runId: "run-1", context: {} as never,
        session: { resumeHandle: "opaque", sessionId: null }, input: { text: "next", attachmentIds: [] },
      })) { /* no-op */ }
    })()).rejects.toThrow("event does not match bound run");
    expect(eventSink.appendEvent).not.toHaveBeenCalled();
  });

  it("reloads the binding before resuming from a cursor", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const adapter = { resumeFromCursor: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-3", sequence: 3, payload: { type: "progress", message: "replayed" } as const };
    }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    const events = [];
    for await (const event of resumeBoundEngineRun({
      repository, adapter, eventSink, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, cursor: "cursor-2",
    })) events.push(event);
    expect(adapter.resumeFromCursor).toHaveBeenCalledWith(expect.anything(), "cursor-2");
    expect(eventSink.appendEvent).toHaveBeenCalledWith(events[0]);
    expect(events).toHaveLength(1);
  });

  it("rejects a stale cursor replay event before exposing it", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const adapter = { resumeFromCursor: vi.fn(async function* () {
      yield { runId: "run-1", eventId: "evt-3", sequence: 3, payload: { type: "progress", message: "first" } as const };
      yield { runId: "run-1", eventId: "evt-4", sequence: 2, payload: { type: "progress", message: "stale" } as const };
    }) };
    const eventSink = { appendEvent: vi.fn().mockResolvedValue(undefined) };
    await expect((async () => {
      for await (const _event of resumeBoundEngineRun({
        repository, adapter, eventSink, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, cursor: "cursor-2",
      })) { /* no-op */ }
    })()).rejects.toThrow("event sequence is stale or duplicated");
    expect(eventSink.appendEvent).toHaveBeenCalledOnce();
  });

  it("reloads the binding before approval responses and erasure", async () => {
    const repository = { getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { engineId: "claude-code" } }) };
    const adapter = {
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
    };
    const session = { resumeHandle: "opaque", sessionId: null };
    await respondToApprovalBoundEngineRun({ repository, adapter, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, requestId: "approval-1", decision: "allow" });
    await expect(eraseBoundEngineRun({ repository, adapter, adapterEngineId: "claude-code", runId: "run-1", context: {} as never, session })).resolves.toBe("confirmed");
    expect(adapter.respondToApproval).toHaveBeenCalledWith(expect.anything(), "approval-1", "allow");
    expect(repository.getRun).toHaveBeenCalledTimes(2);
  });
});
