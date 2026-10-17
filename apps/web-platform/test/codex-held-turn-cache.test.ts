import { beforeEach, describe, expect, it, vi } from "vitest";
import { codexHeldTurnCache, type HeldCodexTurn } from "@/lib/codex-held-turn-cache";

const MAX_TURNS = 32;
const MAX_BYTES = 256 * 1024;
const TTL_MS = 30 * 60 * 1000;

function syntheticToken() {
  const claims = {
    sub: "synthetic-user",
    app_metadata: { current_workspace_id: "synthetic-workspace", current_organization_id: null },
  };
  return `synthetic.${btoa(JSON.stringify(claims))}.synthetic`;
}

function heldTurn(clientTurnId: string, content = "synthetic draft"): HeldCodexTurn {
  return {
    clientTurnId,
    conversationId: "synthetic-conversation",
    authModeGeneration: 1,
    message: { id: `user-${clientTurnId}`, type: "text", role: "user", content },
  };
}

describe("Codex held-turn cache bounds", () => {
  let scope: string;

  beforeEach(() => {
    codexHeldTurnCache.clear();
    scope = codexHeldTurnCache.acceptToken(syntheticToken())!;
  });

  it("retains at most 32 unique held turns", () => {
    for (let index = 0; index < MAX_TURNS; index += 1) {
      expect(codexHeldTurnCache.put(scope, heldTurn(`turn-${index}`))).toBe(true);
    }

    expect(codexHeldTurnCache.put(scope, heldTurn("turn-over-limit"))).toBe(false);
    expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toHaveLength(MAX_TURNS);
  });

  it("measures UTF-8 bytes, permits same-key replacement at the exact limit, and rejects overflow", () => {
    const id = "turn-byte-boundary";
    expect(codexHeldTurnCache.put(scope, heldTurn(id, "small"))).toBe(true);

    const empty = heldTurn(id, "");
    const remaining = MAX_BYTES - new TextEncoder().encode(JSON.stringify(empty)).length;
    const content = "é".repeat(Math.floor(remaining / 2)) + (remaining % 2 === 1 ? "a" : "");
    const exact = heldTurn(id, content);
    expect(new TextEncoder().encode(JSON.stringify(exact)).length).toBe(MAX_BYTES);
    expect(codexHeldTurnCache.put(scope, exact)).toBe(true);
    expect(codexHeldTurnCache.put(scope, heldTurn("turn-byte-overflow", "x"))).toBe(false);
  });

  it("expires held turns after the configured TTL", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-expiring"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS + 1);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally {
      vi.useRealTimers();
    }
  });
});
