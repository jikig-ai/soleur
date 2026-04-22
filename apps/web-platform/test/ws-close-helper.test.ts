import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockReport } = vi.hoisted(() => ({ mockReport: vi.fn() }));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: mockReport,
}));

import { closeWithPreamble } from "../lib/ws-close-helper";
import { WS_CLOSE_CODES, type ClosePreamble } from "../lib/types";

type FakeWs = {
  readyState: number;
  send: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
};

function makeWs(overrides: Partial<FakeWs> = {}): FakeWs {
  return {
    readyState: 1, // OPEN
    send: vi.fn(),
    close: vi.fn(),
    ...overrides,
  };
}

describe("closeWithPreamble", () => {
  beforeEach(() => {
    mockReport.mockReset();
  });

  test("sends JSON preamble once, then closes with code + label — in order", () => {
    const ws = makeWs();
    const preamble: ClosePreamble = {
      type: "concurrency_cap_hit",
      activeCount: 2,
      effectiveCap: 2,
      nextTier: "startup",
      currentTier: "solo",
    };

    closeWithPreamble(ws as never, WS_CLOSE_CODES.CONCURRENCY_CAP, preamble);

    expect(ws.send).toHaveBeenCalledTimes(1);
    expect(ws.send).toHaveBeenNthCalledWith(1, JSON.stringify(preamble));
    expect(ws.close).toHaveBeenCalledTimes(1);
    expect(ws.close).toHaveBeenNthCalledWith(1, 4010, "CONCURRENCY_CAP");

    // Order: send first, then close.
    const sendOrder = ws.send.mock.invocationCallOrder[0];
    const closeOrder = ws.close.mock.invocationCallOrder[0];
    expect(sendOrder).toBeLessThan(closeOrder);
  });

  test("maps TIER_CHANGED to label", () => {
    const ws = makeWs();
    closeWithPreamble(ws as never, WS_CLOSE_CODES.TIER_CHANGED, {
      type: "tier_changed",
      newTier: "solo",
      previousTier: "startup",
    });
    expect(ws.close).toHaveBeenCalledWith(4011, "TIER_CHANGED");
  });

  test("skips send + close when socket is not open", () => {
    const ws = makeWs({ readyState: 3 }); // CLOSED
    closeWithPreamble(ws as never, WS_CLOSE_CODES.CONCURRENCY_CAP, {
      type: "concurrency_cap_hit",
      activeCount: 2,
      effectiveCap: 2,
    });
    expect(ws.send).not.toHaveBeenCalled();
    expect(ws.close).not.toHaveBeenCalled();
  });

  test("preamble > 2 KiB mirrors a warning via reportSilentFallback", () => {
    const ws = makeWs();
    const big: ClosePreamble = {
      type: "concurrency_cap_hit",
      activeCount: 2,
      effectiveCap: 2,
      nextTier: "startup",
      // oversize filler smuggled via `extra` — we only need body.length > 2048.
    };
    // @ts-expect-error — intentional oversize for the test
    big.blob = "x".repeat(3000);
    closeWithPreamble(ws as never, WS_CLOSE_CODES.CONCURRENCY_CAP, big);
    expect(mockReport).toHaveBeenCalledTimes(1);
    const call = mockReport.mock.calls[0];
    expect(call[1]).toMatchObject({ feature: "concurrency" });
    // Still sent + closed — warning is an observability signal, not a block.
    expect(ws.send).toHaveBeenCalledTimes(1);
    expect(ws.close).toHaveBeenCalledTimes(1);
  });
});
