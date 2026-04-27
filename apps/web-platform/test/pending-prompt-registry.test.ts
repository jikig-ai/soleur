import { describe, it, expect, beforeEach } from "vitest";
import {
  PendingPromptRegistry,
  makePendingPromptKey,
  type PendingPromptRecord,
  type InteractivePromptKind,
} from "@/server/pending-prompt-registry";
import { mintPromptId, mintConversationId } from "@/lib/branded-ids";

const pid = mintPromptId;
const cid = mintConversationId;

// RED test for Stage 2.4 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// The registry holds interactive prompts that the soleur-go-runner emits
// while a user message is being processed (ask_user, plan_preview, diff,
// bash_approval, todo_write, notebook_edit). Each prompt maps to a
// pending SDK `tool_use_id` — the runner cannot reply to the SDK until
// the user responds via the ws interactive_prompt_response message.
//
// Invariants under test (per plan Stage 2 §"Pending-prompt registry" and
// HARD REQUIREMENT #4):
//
//   (a) Key composition: `${userId}:${conversationId}:${promptId}`.
//       Prevents cross-conversation or cross-user collision.
//   (b) Cross-user ownership check: lookup with mismatched userId
//       returns undefined (silent denial — do not leak existence).
//   (c) Idempotency: second consume() returns undefined; downstream
//       handler must treat duplicate responses as no-ops, not errors.
//   (d) 5-minute reaper: entries older than ttlMs are dropped.
//   (e) Per-conversation cap of 50: register() throws on the 51st prompt
//       for the same conversationId, regardless of userId.

const TTL_MS = 5 * 60 * 1000;
const CAP = 50;

function makeRecord(
  overrides: Partial<PendingPromptRecord> = {},
): PendingPromptRecord {
  return {
    promptId: pid("p-1"),
    conversationId: cid("conv-1"),
    userId: "user-1",
    kind: "ask_user" as InteractivePromptKind,
    toolUseId: "toolu-abc",
    createdAt: 1_000_000,
    payload: { question: "?", options: [], multiSelect: false },
    ...overrides,
  };
}

describe("makePendingPromptKey", () => {
  it("composes userId:conversationId:promptId", () => {
    expect(makePendingPromptKey("u1", cid("c1"), pid("p1"))).toBe("u1:c1:p1");
  });

  it("distinguishes different users for the same prompt id", () => {
    expect(makePendingPromptKey("u1", cid("c1"), pid("p1"))).not.toBe(
      makePendingPromptKey("u2", cid("c1"), pid("p1")),
    );
  });
});

describe("PendingPromptRegistry", () => {
  let now = 1_000_000;
  let registry: PendingPromptRegistry;

  beforeEach(() => {
    now = 1_000_000;
    registry = new PendingPromptRegistry({
      nowFn: () => now,
      ttlMs: TTL_MS,
      perConversationCap: CAP,
    });
  });

  describe("register + get", () => {
    it("stores a record that get() can retrieve with matching userId", () => {
      const record = makeRecord();
      registry.register(record);
      const key = makePendingPromptKey(
        record.userId,
        record.conversationId,
        record.promptId,
      );
      expect(registry.get(key, record.userId)).toEqual(record);
    });

    it("returns undefined for cross-user lookup (ownership check)", () => {
      const record = makeRecord({ userId: "owner" });
      registry.register(record);
      const key = makePendingPromptKey(
        record.userId,
        record.conversationId,
        record.promptId,
      );
      // Attacker knows the key but not the true userId — registry must
      // not confirm existence.
      expect(registry.get(key, "attacker")).toBeUndefined();
    });

    it("returns undefined for unknown keys", () => {
      expect(registry.get("u:c:missing", "u")).toBeUndefined();
    });
  });

  describe("consume (idempotency)", () => {
    it("first consume returns the record and removes it", () => {
      const record = makeRecord();
      registry.register(record);
      const key = makePendingPromptKey(
        record.userId,
        record.conversationId,
        record.promptId,
      );
      expect(registry.consume(key, record.userId)).toEqual(record);
      expect(registry.consume(key, record.userId)).toBeUndefined();
    });

    it("consume with mismatched userId does NOT remove the record", () => {
      const record = makeRecord({ userId: "owner" });
      registry.register(record);
      const key = makePendingPromptKey(
        record.userId,
        record.conversationId,
        record.promptId,
      );
      expect(registry.consume(key, "attacker")).toBeUndefined();
      // Legitimate owner can still consume.
      expect(registry.consume(key, "owner")).toEqual(record);
    });
  });

  describe("TTL reaper", () => {
    it("reap() drops entries older than ttlMs", () => {
      const r1 = makeRecord({ promptId: pid("p1"), createdAt: now });
      registry.register(r1);
      now += TTL_MS + 1;
      const r2 = makeRecord({ promptId: pid("p2"), createdAt: now });
      registry.register(r2);
      const reaped = registry.reap();
      expect(reaped).toBe(1);
      expect(registry.size()).toBe(1);
      const k1 = makePendingPromptKey(r1.userId, r1.conversationId, r1.promptId);
      const k2 = makePendingPromptKey(r2.userId, r2.conversationId, r2.promptId);
      expect(registry.get(k1, r1.userId)).toBeUndefined();
      expect(registry.get(k2, r2.userId)).toEqual(r2);
    });

    it("reap() is a no-op when no entries are expired", () => {
      registry.register(makeRecord({ promptId: pid("p1"), createdAt: now }));
      registry.register(makeRecord({ promptId: pid("p2"), createdAt: now }));
      expect(registry.reap()).toBe(0);
      expect(registry.size()).toBe(2);
    });

    it("entries AT exactly ttlMs boundary are reaped (inclusive expiry)", () => {
      registry.register(makeRecord({ createdAt: now }));
      now += TTL_MS;
      expect(registry.reap()).toBe(1);
    });
  });

  describe("per-conversation cap", () => {
    it("accepts up to cap prompts for one conversation", () => {
      for (let i = 0; i < CAP; i++) {
        registry.register(
          makeRecord({
            promptId: pid(`p-${i}`),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        );
      }
      expect(registry.size()).toBe(CAP);
    });

    it("rejects the (cap+1)th prompt for the same conversation", () => {
      for (let i = 0; i < CAP; i++) {
        registry.register(
          makeRecord({
            promptId: pid(`p-${i}`),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        );
      }
      expect(() =>
        registry.register(
          makeRecord({
            promptId: pid("p-overflow"),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        ),
      ).toThrow();
    });

    it("the cap is per-conversation, not global", () => {
      for (let i = 0; i < CAP; i++) {
        registry.register(
          makeRecord({
            promptId: pid(`p-${i}`),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        );
      }
      // A different conversation still has its own cap budget.
      expect(() =>
        registry.register(
          makeRecord({
            promptId: pid("p-A"),
            conversationId: cid("conv-B"),
            createdAt: now,
          }),
        ),
      ).not.toThrow();
    });

    it("consumed prompts free up cap budget", () => {
      for (let i = 0; i < CAP; i++) {
        registry.register(
          makeRecord({
            promptId: pid(`p-${i}`),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        );
      }
      // Consume one — should free a slot.
      const key = makePendingPromptKey("user-1", cid("conv-A"), pid("p-0"));
      registry.consume(key, "user-1");
      expect(() =>
        registry.register(
          makeRecord({
            promptId: pid("p-new"),
            conversationId: cid("conv-A"),
            createdAt: now,
          }),
        ),
      ).not.toThrow();
    });
  });

  describe("cross-user isolation via key composition", () => {
    it("same promptId + conversationId for two users does not collide", () => {
      const r1 = makeRecord({ userId: "u1" });
      const r2 = makeRecord({ userId: "u2" });
      registry.register(r1);
      registry.register(r2);
      const k1 = makePendingPromptKey(r1.userId, r1.conversationId, r1.promptId);
      const k2 = makePendingPromptKey(r2.userId, r2.conversationId, r2.promptId);
      expect(registry.get(k1, "u1")).toEqual(r1);
      expect(registry.get(k2, "u2")).toEqual(r2);
    });
  });
});
