// Unit tests for `selectChapter` (#3436 Phase 3).
//
// `selectChapter` runs a small, model-pinned routing turn (Sonnet 4.6 / 200K)
// over a question + outline and returns one of three discriminated shapes:
//
//   - { kind: "selected"; chapterIndex; alternates }      — numeric parse OR
//                                                           Levenshtein fuzzy fallback
//   - { kind: "ambiguous"; candidates }                   — model returned
//                                                           AMBIGUOUS, or numeric
//                                                           parse failed AND fuzzy
//                                                           match failed
//   - { kind: "cost-cap-hit"; cap; totalCostUsd }         — routing-turn cost
//                                                           pushes state at/over cap
//
// The model is mocked so the tests are deterministic and engine-floor-
// independent. Real-API verification happens at Phase 1 spike (S1) and
// post-merge AC #4 (operator-driven).

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import type { ChapterIndex } from "@/server/pdf-text-extract";

const { mockQuery } = vi.hoisted(() => ({ mockQuery: vi.fn() }));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
}));

// BYOK lease access — router pulls the active lease from ALS so cost
// charging respects per-user keys. We stub `getCurrentByokLease` to a
// no-op (null) since the routing turn carries `ANTHROPIC_API_KEY` from
// process env in the dev/test path; production prepends the BYOK key
// inside `runWithByokLease`.
const { getCurrentByokLeaseSpy } = vi.hoisted(() => ({
  getCurrentByokLeaseSpy: vi.fn(() => null),
}));

vi.mock("@/server/byok-lease", () => ({
  getCurrentByokLease: getCurrentByokLeaseSpy,
}));

import { selectChapter } from "@/server/pdf-chapter-router";

const sampleOutline: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication and authorization", startPage: 48, endPage: 102, depth: 0 },
  { title: "Database design", startPage: 103, endPage: 165, depth: 0 },
  { title: "Deployment", startPage: 166, endPage: 210, depth: 0 },
];

/**
 * Build a fake `Query` async-iterable that yields a single text reply
 * followed by an SDK `result` carrying a non-zero cost. The router
 * inspects `text` (the assistant turn) and `total_cost_usd` (charged
 * against the per-conv cap before the answer turn fires).
 */
function fakeQuery(args: {
  text: string;
  totalCostUsd: number;
  inputTokens?: number;
  outputTokens?: number;
}): AsyncIterable<unknown> {
  return {
    async *[Symbol.asyncIterator]() {
      yield {
        type: "assistant",
        message: {
          role: "assistant",
          content: [{ type: "text", text: args.text }],
        },
      };
      yield {
        type: "result",
        subtype: "success",
        total_cost_usd: args.totalCostUsd,
        usage: {
          input_tokens: args.inputTokens ?? 0,
          output_tokens: args.outputTokens ?? 0,
        },
        session_id: "router-session",
      };
    },
  };
}

describe("selectChapter", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    getCurrentByokLeaseSpy.mockReset();
    getCurrentByokLeaseSpy.mockReturnValue(null);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("returns kind:'selected' on a numeric reply (1-based input → 0-based chapterIndex)", async () => {
    mockQuery.mockReturnValue(fakeQuery({ text: "3", totalCostUsd: 0.01 }));

    const result = await selectChapter({
      question: "What does chapter on auth cover?",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0.05, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("selected");
    if (result.kind !== "selected") throw new Error("type narrow");
    expect(result.chapterIndex).toBe(2);
    expect(Array.isArray(result.alternates)).toBe(true);
    expect(result.routingCostUsd).toBe(0.01);
  });

  it("returns kind:'ambiguous' when the model returns AMBIGUOUS", async () => {
    mockQuery.mockReturnValue(
      fakeQuery({ text: "AMBIGUOUS", totalCostUsd: 0.005 }),
    );

    const result = await selectChapter({
      question: "Tell me about the system",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("ambiguous");
    if (result.kind !== "ambiguous") throw new Error("type narrow");
    expect(result.routingCostUsd).toBe(0.005);
  });

  it("returns kind:'cost-cap-hit' when totalCostUsd + routing cost crosses the cap", async () => {
    mockQuery.mockReturnValue(fakeQuery({ text: "2", totalCostUsd: 0.06 }));

    const result = await selectChapter({
      question: "Anything in chapter 2",
      outline: sampleOutline,
      userId: "u1",
      // 0.46 + 0.06 = 0.52 > 0.5
      conversationCostState: { totalCostUsd: 0.46, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("cost-cap-hit");
    if (result.kind !== "cost-cap-hit") throw new Error("type narrow");
    expect(result.cap).toBe(0.5);
    expect(result.totalCostUsd).toBeGreaterThanOrEqual(0.5);
  });

  it("falls back to fuzzy title match (Levenshtein) when reply is non-numeric prose", async () => {
    // Reply paraphrases a chapter title; numeric parse fails → fuzzy match.
    mockQuery.mockReturnValue(
      fakeQuery({
        text: "Authentication and authorization",
        totalCostUsd: 0.008,
      }),
    );

    const result = await selectChapter({
      question: "How does login work?",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("selected");
    if (result.kind !== "selected") throw new Error("type narrow");
    expect(result.chapterIndex).toBe(2);
  });

  it("returns kind:'ambiguous' with empty candidates when neither numeric parse nor fuzzy match succeeds", async () => {
    mockQuery.mockReturnValue(
      fakeQuery({
        text: "I don't know which chapter covers that question.",
        totalCostUsd: 0.009,
      }),
    );

    const result = await selectChapter({
      question: "What is the meaning of life",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("ambiguous");
    if (result.kind !== "ambiguous") throw new Error("type narrow");
    expect(result.candidates).toEqual([]);
  });

  it("clamps numeric replies that are out of range and falls through to ambiguous", async () => {
    // 999 out of range — numeric parse rejected; fuzzy match also fails.
    mockQuery.mockReturnValue(fakeQuery({ text: "999", totalCostUsd: 0.005 }));

    const result = await selectChapter({
      question: "What's in chapter 999",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0, perConvCap: 0.5 },
    });

    expect(result.kind).toBe("ambiguous");
  });

  it("pins the routing model to Sonnet 4.6 / 200K (call-options invariant)", async () => {
    mockQuery.mockReturnValue(fakeQuery({ text: "1", totalCostUsd: 0.001 }));

    await selectChapter({
      question: "anything",
      outline: sampleOutline,
      userId: "u1",
      conversationCostState: { totalCostUsd: 0, perConvCap: 0.5 },
    });

    expect(mockQuery).toHaveBeenCalledTimes(1);
    const callArgs = mockQuery.mock.calls[0]?.[0] as
      | { options?: { model?: string } }
      | undefined;
    // Pin Sonnet 4.6 — DO NOT inherit runner's model (may be Opus on KB chats).
    expect(callArgs?.options?.model).toBe("claude-sonnet-4-6");
  });
});
