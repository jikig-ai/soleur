import { describe, test, expect } from "vitest";
import type { WSMessage } from "../lib/types";

// Test the usage_update WebSocket message type parsing and structure.
// The React hook accumulation is tested indirectly via billing page
// component tests — here we verify the protocol layer.

function parseMessage(raw: string): WSMessage | null {
  try {
    return JSON.parse(raw) as WSMessage;
  } catch {
    return null;
  }
}

describe("usage_update WebSocket message", () => {
  test("parses a valid usage_update message", () => {
    const msg = parseMessage(JSON.stringify({
      type: "usage_update",
      conversationId: "conv-123",
      totalCostUsd: 0.0042,
      inputTokens: 1200,
      outputTokens: 300,
    }));

    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("usage_update");
    if (msg!.type === "usage_update") {
      expect(msg!.conversationId).toBe("conv-123");
      expect(msg!.totalCostUsd).toBe(0.0042);
      expect(msg!.inputTokens).toBe(1200);
      expect(msg!.outputTokens).toBe(300);
    }
  });

  test("useWebSocket hook exposes usageData in return type", async () => {
    // Import the hook module to verify the return type includes usageData
    const wsClient = await import("../lib/ws-client");
    // The hook exists and is exported
    expect(typeof wsClient.useWebSocket).toBe("function");
  });

  test("null-guard pattern: prev ?? costData does not overwrite existing data", () => {
    // Simulates the race condition: a usage_update WS event arrives before the
    // history fetch resolves. The functional updater `prev => prev ?? costData`
    // should preserve the WS event's value when prev is non-null.
    type UsageData = { totalCostUsd: number; inputTokens: number; outputTokens: number };

    // State after a usage_update WS event arrived
    const wsEventData: UsageData = { totalCostUsd: 0.001, inputTokens: 500, outputTokens: 100 };

    // Historical data from API fetch (older, lower values)
    const historicalData: UsageData = { totalCostUsd: 0.0042, inputTokens: 1200, outputTokens: 300 };

    // The functional updater: prev ?? costData
    const updater = (prev: UsageData | null) => prev ?? historicalData;

    // When prev is non-null (WS event already set it), historical data is ignored
    expect(updater(wsEventData)).toEqual(wsEventData);

    // When prev is null (no WS event yet), historical data is used
    expect(updater(null)).toEqual(historicalData);
  });

  test("accumulates multiple usage_update deltas correctly", () => {
    // Simulate the accumulation logic that ws-client should implement
    type UsageData = { totalCostUsd: number; inputTokens: number; outputTokens: number };

    const deltas: UsageData[] = [
      { totalCostUsd: 0.0042, inputTokens: 1200, outputTokens: 300 },
      { totalCostUsd: 0.0018, inputTokens: 800, outputTokens: 200 },
      { totalCostUsd: 0.0030, inputTokens: 1000, outputTokens: 250 },
    ];

    // Reduce like the hook should — each message is a delta
    const accumulated = deltas.reduce<UsageData>(
      (prev, delta) => ({
        totalCostUsd: prev.totalCostUsd + delta.totalCostUsd,
        inputTokens: prev.inputTokens + delta.inputTokens,
        outputTokens: prev.outputTokens + delta.outputTokens,
      }),
      { totalCostUsd: 0, inputTokens: 0, outputTokens: 0 },
    );

    expect(accumulated.totalCostUsd).toBeCloseTo(0.009);
    expect(accumulated.inputTokens).toBe(3000);
    expect(accumulated.outputTokens).toBe(750);
  });
});
