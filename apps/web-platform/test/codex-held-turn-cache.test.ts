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
    noticeNonce: "A".repeat(43),
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

  it("refreshes one current notice nonce across every held turn in its generation", () => {
    codexHeldTurnCache.put(scope, { ...heldTurn("turn-a"), noticeNonce: "A".repeat(43) });
    codexHeldTurnCache.put(scope, { ...heldTurn("turn-b"), noticeNonce: "B".repeat(43) });
    codexHeldTurnCache.setNoticeNonce(scope, "synthetic-conversation", 1, "C".repeat(43));

    expect(codexHeldTurnCache.get(scope, "synthetic-conversation").map((turn) => turn.noticeNonce))
      .toEqual(["C".repeat(43), "C".repeat(43)]);
  });

  it("measures UTF-8 bytes, permits same-key replacement at the exact limit, and rejects overflow", () => {
    const id = "turn-byte-boundary";
    expect(codexHeldTurnCache.put(scope, heldTurn(id, "small"))).toBe(true);

    const empty = heldTurn(id, "");
    empty.message.delivery = "unsent";
    const remaining = MAX_BYTES - new TextEncoder().encode(JSON.stringify(empty)).length;
    const content = "é".repeat(Math.floor(remaining / 2)) + (remaining % 2 === 1 ? "a" : "");
    const exact = heldTurn(id, content);
    exact.message.delivery = "unsent";
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

  it("atomically preserves the exact unresolved payload and refuses overwrite or another claim", () => {
    const draft = heldTurn("turn-1");
    draft.message.attachments = [{ storagePath: "synthetic/a", filename: "a", contentType: "text/plain", sizeBytes: 1 }];
    expect(codexHeldTurnCache.put(scope, draft)).toBe(true);
    draft.message.attachments[0].filename = "mutated";
    const first = codexHeldTurnCache.markUnresolved(scope, "synthetic-conversation", "turn-1");
    expect(first?.message).toEqual(expect.objectContaining({ delivery: "unresolved", attachments: [expect.objectContaining({ filename: "a" })] }));
    expect(codexHeldTurnCache.markUnresolved(scope, "synthetic-conversation", "turn-1")).toBeNull();
    expect(codexHeldTurnCache.put(scope, heldTurn("turn-1", "replacement"))).toBe(false);
    expect(codexHeldTurnCache.get(scope, "synthetic-conversation")[0].message).toEqual(first?.message);
  });

  it("does not extend the expiry when an unresolved turn is marked", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-1"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS - 1);
      expect(codexHeldTurnCache.markUnresolved(scope, "synthetic-conversation", "turn-1")).not.toBeNull();
      vi.advanceTimersByTime(1);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { vi.useRealTimers(); }
  });
});
