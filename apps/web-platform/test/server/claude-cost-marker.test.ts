import { afterEach, describe, expect, it, vi } from "vitest";

// The marker helper constructs a dedicated pino instance at module load. Mock
// pino so we can (a) capture the warn payload and (b) make warn throw to prove
// the fail-open contract. `warnMock` is hoisted so the factory can close over it.
const { warnMock } = vi.hoisted(() => ({ warnMock: vi.fn() }));

vi.mock("pino", () => ({
  default: vi.fn(() => ({ warn: warnMock })),
}));

import { emitClaudeCostMarker } from "@/server/claude-cost-marker";

afterEach(() => {
  warnMock.mockReset();
});

describe("emitClaudeCostMarker (AC1/AC3)", () => {
  const marker = {
    source: "agent-runner" as const,
    model: "claude-opus-4-8",
    input_tokens: 100,
    output_tokens: 20,
    cache_read_input_tokens: 5,
    cache_creation_input_tokens: 3,
    cost_usd: 0.42,
    id: "conv-123",
    capture_status: "ok" as const,
  };

  it("emits a WARN line with the SOLEUR_CLAUDE_COST discriminator + all fields", () => {
    emitClaudeCostMarker(marker);
    expect(warnMock).toHaveBeenCalledTimes(1);
    const [obj, msg] = warnMock.mock.calls[0];
    expect(obj).toMatchObject({ SOLEUR_CLAUDE_COST: true, ...marker });
    expect(msg).toBe("claude cost");
  });

  it("is fail-open: a throwing log.warn does not propagate (AC3)", () => {
    warnMock.mockImplementation(() => {
      throw new Error("pino boom");
    });
    expect(() => emitClaudeCostMarker(marker)).not.toThrow();
  });
});
