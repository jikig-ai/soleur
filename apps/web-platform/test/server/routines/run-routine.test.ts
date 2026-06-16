import { beforeEach, describe, expect, it, vi } from "vitest";

const { mockInngestSend, mockSendInngestWithRetry } = vi.hoisted(() => ({
  mockInngestSend: vi.fn(),
  mockSendInngestWithRetry: vi.fn(async (thunk: () => Promise<unknown>) => {
    await thunk();
  }),
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));
vi.mock("@/server/inngest/send-with-retry", () => ({
  sendInngestWithRetry: mockSendInngestWithRetry,
}));

import { runRoutine } from "@/server/routines/run-routine";

beforeEach(() => {
  mockInngestSend.mockReset();
  mockInngestSend.mockResolvedValue({ ids: ["evt"] });
  mockSendInngestWithRetry.mockClear();
});

describe("runRoutine — policy", () => {
  it("rejects an unknown / event-driven fnId without dispatching", async () => {
    const r = await runRoutine({ fnId: "cfo-on-payment-failed", actorClass: "human" });
    expect(r).toEqual({ ok: false, code: "unknown_routine", status: 400 });
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("requires confirmation for a protected (confirm) routine", async () => {
    const r = await runRoutine({ fnId: "cron-content-publisher", actorClass: "human" });
    expect(r).toEqual({ ok: false, code: "confirmation_required", status: 409 });
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("dispatches a protected routine when confirmed", async () => {
    const r = await runRoutine({
      fnId: "cron-content-publisher",
      actorClass: "human",
      actorId: "op-1",
      confirmed: true,
    });
    expect(r).toEqual({ ok: true, event: "cron/content-publisher.manual-trigger" });
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  it("dispatches an allowed routine immediately", async () => {
    const r = await runRoutine({ fnId: "cron-daily-triage", actorClass: "human", actorId: "op-1" });
    expect(r.ok).toBe(true);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });
});

describe("runRoutine — attribution (route-controlled keys spread last)", () => {
  it("overrides forged caller data.actor_class with the chokepoint value", async () => {
    await runRoutine({
      fnId: "cron-daily-triage",
      actorClass: "human",
      actorId: "op-1",
      data: { actor_class: "system", actor_id: "forged", trigger: "scheduled" },
    });
    const sent = mockInngestSend.mock.calls[0][0];
    expect(sent.name).toBe("cron/daily-triage.manual-trigger");
    expect(sent.data.actor_class).toBe("human");
    expect(sent.data.actor_id).toBe("op-1");
    expect(sent.data.trigger).toBe("manual");
  });

  it("sets trigger=agent for an agent run", async () => {
    await runRoutine({
      fnId: "cron-daily-triage",
      actorClass: "agent",
      actorId: "u1",
      delegatingPrincipal: "op1",
    });
    const sent = mockInngestSend.mock.calls[0][0];
    expect(sent.data.trigger).toBe("agent");
    expect(sent.data.actor_class).toBe("agent");
    expect(sent.data.delegating_principal).toBe("op1");
  });

  it("sets trigger=manual-api for the system (secret) tier", async () => {
    await runRoutine({
      fnId: "cron-daily-triage",
      actorClass: "system",
      confirmed: true,
      data: { issue_number: 42 },
    });
    const sent = mockInngestSend.mock.calls[0][0];
    expect(sent.data.trigger).toBe("manual-api");
    expect(sent.data.actor_class).toBe("system");
    expect(sent.data.issue_number).toBe(42); // per-cron payload preserved
  });
});
