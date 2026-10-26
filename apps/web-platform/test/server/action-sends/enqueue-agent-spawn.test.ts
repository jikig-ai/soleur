/**
 * #10543 — enqueueAgentSpawn: the single place the dashboard send route dispatches `agent.spawn.requested`.
 *
 * Pins: the event id is derived from the action_sends row (so every retry attempt AND every founder re-click replay
 * dedups on the same id), the payload carries exactly the five consumer fields (installationId stays server-resolved,
 * invariant I1), and the send goes through the REAL sendInngestWithRetry (transient errors retried, others not).
 */

import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

const { mockInngestSend } = vi.hoisted(() => ({ mockInngestSend: vi.fn() }));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

import { enqueueAgentSpawn } from "@/server/action-sends/enqueue-agent-spawn";

const FOUNDER = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const MSG = "11111111-1111-4111-aaaa-111111111111";
const AS_ID = "33333333-3333-4333-aaaa-333333333333";

const ARGS = {
  founderId: FOUNDER,
  messageId: MSG,
  actionClass: "engineering.pr_review_pending",
  sourceRef: "pr-acme:repo:7",
  actionSendId: AS_ID,
} as const;

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("enqueueAgentSpawn", () => {
  test("sends event id agent-spawn-<actionSendId> and exactly the five consumer fields", async () => {
    mockInngestSend.mockResolvedValue({ ids: ["evt-1"] });

    await enqueueAgentSpawn({ ...ARGS });

    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as Record<string, unknown>;
    expect(sent.id).toBe(`agent-spawn-${AS_ID}`);
    expect(sent.name).toBe("agent.spawn.requested");
    expect(sent.data).toStrictEqual({
      founderId: FOUNDER,
      messageId: MSG,
      actionClass: "engineering.pr_review_pending",
      sourceRef: "pr-acme:repo:7",
      actionSendId: AS_ID,
    });
    expect(sent.data).not.toHaveProperty("installationId");
  });

  test("a transient 'fetch failed' on attempts 1 and 2 then success resolves, and the SAME id is sent on all 3 attempts", async () => {
    mockInngestSend
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce({ ids: ["evt-3"] });

    const p = enqueueAgentSpawn({ ...ARGS });
    await vi.advanceTimersByTimeAsync(5_000);
    await expect(p).resolves.toBeUndefined();

    expect(mockInngestSend).toHaveBeenCalledTimes(3);
    const ids = mockInngestSend.mock.calls.map(
      (c) => (c[0] as { id: string }).id,
    );
    expect(new Set(ids)).toEqual(new Set([`agent-spawn-${AS_ID}`]));
  });

  test("a non-transient error is not retried and rejects", async () => {
    mockInngestSend.mockRejectedValue(new Error("inngest returned 401"));

    await expect(enqueueAgentSpawn({ ...ARGS })).rejects.toThrow(
      "inngest returned 401",
    );
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  test("three transient failures reject after exactly 3 calls", async () => {
    mockInngestSend.mockRejectedValue(new TypeError("fetch failed"));

    const p = enqueueAgentSpawn({ ...ARGS });
    // Attach the rejection expectation BEFORE advancing timers so the
    // eventual rejection is never unhandled.
    const settled = expect(p).rejects.toThrow("fetch failed");
    await vi.advanceTimersByTimeAsync(5_000);
    await settled;

    expect(mockInngestSend).toHaveBeenCalledTimes(3);
  });
});
