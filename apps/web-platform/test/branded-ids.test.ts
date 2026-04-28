import { describe, test, expect } from "vitest";
import {
  mintSpawnId,
  mintPromptId,
  mintConversationId,
  type SpawnId,
  type PromptId,
  type ConversationId,
} from "@/lib/branded-ids";

// Branded IDs (#2885 Stage 3): SpawnId, PromptId, ConversationId carry a
// compile-time brand so a callsite can't pass a raw string into a slot
// expecting a typed identifier. The test asserts (a) mint helpers produce
// the underlying string value at runtime, (b) plain string assignment fails
// at compile time via the @ts-expect-error markers (`tsc --noEmit` is the
// gate; vitest only verifies the runtime behaviour).

describe("branded-ids: mint helpers preserve string value", () => {
  test("mintSpawnId returns the underlying string", () => {
    const id: SpawnId = mintSpawnId("spawn-abc");
    expect(id).toBe("spawn-abc");
    expect(typeof id).toBe("string");
  });

  test("mintPromptId returns the underlying string", () => {
    const id: PromptId = mintPromptId("prompt-xyz");
    expect(id).toBe("prompt-xyz");
    expect(typeof id).toBe("string");
  });

  test("mintConversationId returns the underlying string", () => {
    const id: ConversationId = mintConversationId("conv-123");
    expect(id).toBe("conv-123");
    expect(typeof id).toBe("string");
  });
});

describe("branded-ids: brand cross-confusion is a compile error", () => {
  test("plain string cannot be assigned to a branded slot (compile-only)", () => {
    function takeSpawn(_s: SpawnId): void { /* noop */ }
    function takePrompt(_s: PromptId): void { /* noop */ }
    function takeConv(_s: ConversationId): void { /* noop */ }

    // Accepting branded values flows.
    takeSpawn(mintSpawnId("a"));
    takePrompt(mintPromptId("b"));
    takeConv(mintConversationId("c"));

    // Plain string is rejected at compile time. The @ts-expect-error markers
    // fail the build if these lines start compiling — i.e. if the brand is
    // dropped or widened to plain string.
    // @ts-expect-error — plain string cannot widen to SpawnId
    takeSpawn("plain-string");
    // @ts-expect-error — plain string cannot widen to PromptId
    takePrompt("plain-string");
    // @ts-expect-error — plain string cannot widen to ConversationId
    takeConv("plain-string");

    // Cross-brand confusion is also rejected.
    // @ts-expect-error — SpawnId is not a PromptId
    takePrompt(mintSpawnId("a"));
    // @ts-expect-error — PromptId is not a ConversationId
    takeConv(mintPromptId("b"));

    // Reaching this expectation proves the runtime executed past the markers.
    expect(true).toBe(true);
  });
});
