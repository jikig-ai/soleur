import { beforeEach, describe, expect, it, vi } from "vitest";
import { codexHeldTurnCache, type HeldCodexTurn } from "@/lib/codex-held-turn-cache";
import { reportSilentFallback } from "@/lib/client-observability";

vi.mock("@/lib/client-observability", () => ({ reportSilentFallback: vi.fn() }));

const MAX_TURNS = 32;
const MAX_BYTES = 256 * 1024;
const TTL_MS = 30 * 60 * 1000;

function syntheticToken(userId = "synthetic-user", workspaceId = "synthetic-workspace") {
  const claims = {
    sub: userId,
    app_metadata: { current_workspace_id: workspaceId, current_organization_id: null },
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
    vi.mocked(reportSilentFallback).mockReset();
    codexHeldTurnCache.clear();
    scope = codexHeldTurnCache.acceptToken(syntheticToken())!;
  });

  it("isolates expiry and invalidation listeners even if telemetry also fails", () => {
    vi.useFakeTimers();
    const expired = vi.fn();
    const invalidated = vi.fn();
    vi.mocked(reportSilentFallback).mockImplementation(() => { throw new Error("private telemetry"); });
    const offExpiry1 = codexHeldTurnCache.subscribeExpiry(() => { throw new Error("private listener"); });
    const offExpiry2 = codexHeldTurnCache.subscribeExpiry(expired);
    const offClear1 = codexHeldTurnCache.subscribe(() => { throw new Error("private listener"); });
    const offClear2 = codexHeldTurnCache.subscribe(invalidated);
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-listeners"))).toBe(true);
      expect(() => vi.advanceTimersByTime(TTL_MS)).not.toThrow();
      expect(expired).toHaveBeenCalledOnce();
      expect(() => codexHeldTurnCache.clear()).not.toThrow();
      expect(invalidated).toHaveBeenCalledOnce();
      expect(JSON.stringify(vi.mocked(reportSilentFallback).mock.calls)).not.toContain("private listener");
    } finally {
      offExpiry1(); offExpiry2(); offClear1(); offClear2();
      codexHeldTurnCache.clear(); vi.useRealTimers();
    }
  });

  it("does not let a reentrant scope listener repopulate a former scope during a switch", () => {
    const oldScope = scope;
    let reentered = false;
    const unsubscribe = codexHeldTurnCache.subscribe(() => {
      if (reentered) return;
      reentered = true;
      codexHeldTurnCache.acceptToken(syntheticToken());
      codexHeldTurnCache.put(oldScope, heldTurn("old-scope-turn"));
    });
    try {
      const nextScope = codexHeldTurnCache.acceptToken(syntheticToken("synthetic-other", "synthetic-other-workspace"));
      expect(reentered).toBe(true);
      expect(nextScope).toBeNull();
      const reauthenticated = codexHeldTurnCache.acceptToken(syntheticToken("synthetic-other", "synthetic-other-workspace"));
      expect(reauthenticated).not.toBeNull();
      expect(codexHeldTurnCache.get(reauthenticated, "synthetic-conversation")).toEqual([]);
    } finally { unsubscribe(); }
  });

  it("fails closed when a newer nested token arrives during a scope switch", () => {
    let once = false;
    const unsubscribe = codexHeldTurnCache.subscribe(() => {
      if (once) return;
      once = true;
      expect(codexHeldTurnCache.acceptToken(syntheticToken("synthetic-newer", "synthetic-newer-workspace"))).toBeNull();
    });
    try {
      expect(codexHeldTurnCache.acceptToken(syntheticToken("synthetic-other", "synthetic-other-workspace"))).toBeNull();
      expect(codexHeldTurnCache.scopeEpoch(scope)).toBeNull();
    } finally { unsubscribe(); }
  });

  it("cancels a scope transition when an auth event arrives during invalidation", () => {
    let observer: ((event: string, session: { access_token: string } | null) => void) | undefined;
    codexHeldTurnCache.observeAuth({ onAuthStateChange: (callback: typeof observer) => { observer = callback; } } as never);
    expect(observer).toBeDefined();
    for (const [event, session] of [
      ["TOKEN_REFRESHED", { access_token: syntheticToken("synthetic-newer", "synthetic-newer-workspace") }],
      ["SIGNED_IN", { access_token: syntheticToken() }],
      ["SIGNED_OUT", null],
    ] as const) {
      const current = codexHeldTurnCache.acceptToken(syntheticToken());
      expect(current).not.toBeNull();
      let once = false;
      const unsubscribe = codexHeldTurnCache.subscribe(() => {
        if (once) return;
        once = true;
        observer!(event, session);
      });
      try {
        expect(codexHeldTurnCache.acceptToken(syntheticToken("synthetic-other", "synthetic-other-workspace"))).toBeNull();
        expect(codexHeldTurnCache.scopeEpoch(current)).toBeNull();
      } finally { unsubscribe(); }
    }
  });

  it("fails closed if scope invalidation recurs during a scope switch", () => {
    let once = false;
    const unsubscribe = codexHeldTurnCache.subscribe(() => {
      if (once) return;
      once = true;
      codexHeldTurnCache.clear();
      expect(codexHeldTurnCache.acceptToken(syntheticToken())).toBeNull();
    });
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("old-scope-turn"))).toBe(true);
      expect(codexHeldTurnCache.acceptToken(syntheticToken("synthetic-other", "synthetic-other-workspace"))).toBeNull();
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { unsubscribe(); }
  });

  it("protects expiry identity from mutation by an earlier subscriber", () => {
    vi.useFakeTimers();
    const received = vi.fn();
    const offFirst = codexHeldTurnCache.subscribeExpiry((event) => { Reflect.set(event, "clientTurnId", "forged"); });
    const offSecond = codexHeldTurnCache.subscribeExpiry(received);
    try {
      const epoch = codexHeldTurnCache.scopeEpoch(scope);
      expect(codexHeldTurnCache.put(scope, heldTurn("original-turn"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS);
      expect(received).toHaveBeenCalledWith({ scopeEpoch: epoch, conversationId: "synthetic-conversation", clientTurnId: "original-turn" });
    } finally { offFirst(); offSecond(); codexHeldTurnCache.clear(); vi.useRealTimers(); }
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

  it("schedules expiry without requiring another cache operation", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-active-expiry"))).toBe(true);
      expect(vi.getTimerCount()).toBe(1);
      vi.advanceTimersByTime(TTL_MS);
      expect(vi.getTimerCount()).toBe(0);
      // Rewind only after the callback: lazy pruning on get cannot satisfy this.
      vi.setSystemTime(Date.now() - TTL_MS * 2);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("reschedules for staggered entries and cancels the timer on clear", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-first"))).toBe(true);
      vi.advanceTimersByTime(1000);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-second"))).toBe(true);
      expect(vi.getTimerCount()).toBe(1);
      vi.advanceTimersByTime(TTL_MS - 1000);
      const firstDeadline = Date.now();
      vi.setSystemTime(firstDeadline - TTL_MS * 2);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation").map((turn) => turn.clientTurnId)).toEqual(["turn-second"]);
      expect(vi.getTimerCount()).toBe(1);
      vi.setSystemTime(firstDeadline);
      vi.advanceTimersByTime(1000);
      vi.setSystemTime(firstDeadline - TTL_MS * 2);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-clear"))).toBe(true);
      expect(vi.getTimerCount()).toBe(1);
      codexHeldTurnCache.clear();
      expect(vi.getTimerCount()).toBe(0);
    } finally { codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("does not extend expiry when replacing the same held turn", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-replaced"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS - 1);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-replaced", "changed synthetic draft"))).toBe(true);
      vi.advanceTimersByTime(1);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("prunes overdue entries before a late nonce update even if the timer has not fired", () => {
    vi.useFakeTimers();
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-overdue"))).toBe(true);
      const start = Date.now();
      vi.setSystemTime(start + TTL_MS + 1);
      codexHeldTurnCache.setNoticeNonce(scope, "synthetic-conversation", 1, "C".repeat(43));
      vi.setSystemTime(start);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("emits scoped expiry identities on timer and lazy pruning without draft content", () => {
    vi.useFakeTimers();
    const events: unknown[] = [];
    const unsubscribe = codexHeldTurnCache.subscribeExpiry((event) => events.push(event));
    try {
      const epoch = codexHeldTurnCache.scopeEpoch(scope);
      expect(epoch).not.toBeNull();
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-timed"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS);
      expect(events).toEqual([{ scopeEpoch: epoch, conversationId: "synthetic-conversation", clientTurnId: "turn-timed" }]);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-lazy"))).toBe(true);
      vi.setSystemTime(Date.now() + TTL_MS + 1);
      codexHeldTurnCache.setNoticeNonce(scope, "synthetic-conversation", 1, "C".repeat(43));
      expect(events).toHaveLength(2);
      expect(events[1]).toEqual({ scopeEpoch: epoch, conversationId: "synthetic-conversation", clientTurnId: "turn-lazy" });
      unsubscribe();
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-unsubscribed"))).toBe(true);
      vi.advanceTimersByTime(TTL_MS);
      expect(events).toHaveLength(2);
    } finally { unsubscribe(); codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("does not insert after an expiry listener invalidates the authenticated scope", () => {
    vi.useFakeTimers();
    const unsubscribe = codexHeldTurnCache.subscribeExpiry(() => codexHeldTurnCache.clear());
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-old"))).toBe(true);
      vi.setSystemTime(Date.now() + TTL_MS + 1);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-new"))).toBe(false);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { unsubscribe(); codexHeldTurnCache.clear(); vi.useRealTimers(); }
  });

  it("does not insert after the same scope is invalidated and reaccepted during expiry", () => {
    vi.useFakeTimers();
    const unsubscribe = codexHeldTurnCache.subscribeExpiry(() => {
      codexHeldTurnCache.clear();
      codexHeldTurnCache.acceptToken(syntheticToken());
    });
    try {
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-old"))).toBe(true);
      vi.setSystemTime(Date.now() + TTL_MS + 1);
      expect(codexHeldTurnCache.put(scope, heldTurn("turn-new"))).toBe(false);
      expect(codexHeldTurnCache.get(scope, "synthetic-conversation")).toEqual([]);
    } finally { unsubscribe(); codexHeldTurnCache.clear(); vi.useRealTimers(); }
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
