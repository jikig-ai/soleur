// KD-6 cross-document disambiguation coverage for `selectChapter`
// (#3436 Phase 3.B — bundle PR feat-pdf-chapter-chunking-bundle).
//
// FORWARD-LOOKING GUARDS: KD-6 reachability pre-flight (plan §3.2)
// confirmed `cc-dispatcher.ts` passes a single `documentExtractMeta`
// per turn, so the multi-PDF chapter-chunked context cannot reach
// `selectChapter` today. These tests pin the discriminator wiring so
// a future resolver upgrade lands with the disambiguation behavior
// already covered.
//
// Reachability follow-up issue: filed alongside this PR — see
// PR #3550 body §Implementation.

import { describe, it, expect, vi, beforeEach } from "vitest";

import type { ChapterIndex } from "@/server/pdf-text-extract";

const { mockQuery, reportSilentFallbackSpy } = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

import { selectChapter } from "@/server/pdf-chapter-router";

const sampleOutline: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Database design", startPage: 103, endPage: 165, depth: 0 },
];

function fakeQuery(args: { text: string; totalCostUsd: number }): AsyncIterable<unknown> {
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
        usage: { input_tokens: 0, output_tokens: 0 },
        session_id: "router-session",
      };
    },
  };
}

describe("selectChapter — KD-6 cross-document (forward-looking guards)", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    reportSilentFallbackSpy.mockReset();
  });

  it("Case 10 — returns ambiguous-which-document when the question mentions neither title", async () => {
    // Multi-PDF context: caller passes 2+ candidate document titles.
    // The question text names neither, so the router short-circuits
    // BEFORE paying a routing turn (`routingCostUsd: 0`).
    const result = await selectChapter({
      question: "How does authentication work?",
      outline: sampleOutline,
      conversationCostState: { totalCostUsd: 0.05, perConvCap: 0.5 },
      candidateDocumentTitles: ["Designing-Data-Intensive-Apps", "Eloquent-Ruby"],
    });

    expect(result.kind).toBe("ambiguous-which-document");
    if (result.kind === "ambiguous-which-document") {
      expect(result.candidateTitles).toEqual([
        "Designing-Data-Intensive-Apps",
        "Eloquent-Ruby",
      ]);
      expect(result.routingCostUsd).toBe(0);
    }
    // Routing turn skipped — short-circuit before SDK call.
    expect(mockQuery).not.toHaveBeenCalled();
  });

  it("Case 11 — selected (with documentIndex implied by single title hit) when the question names exactly one candidate", async () => {
    // Single hit → router proceeds with the normal numeric/fuzzy
    // routing path. The selectChapter contract today returns
    // `{ kind: "selected", chapterIndex }` (no `documentIndex` field
    // yet — that lands when multi-PDF active context lands). The
    // forward-looking guard pins that the question-mentions-title
    // path bypasses ambiguous-which-document.
    mockQuery.mockReturnValueOnce(
      fakeQuery({ text: "2", totalCostUsd: 0.001 }),
    );
    const result = await selectChapter({
      question:
        "In Designing-Data-Intensive-Apps, how is architecture overview structured?",
      outline: sampleOutline,
      conversationCostState: { totalCostUsd: 0.05, perConvCap: 0.5 },
      candidateDocumentTitles: ["Designing-Data-Intensive-Apps", "Eloquent-Ruby"],
    });

    expect(result.kind).toBe("selected");
    if (result.kind === "selected") {
      expect(result.chapterIndex).toBe(1); // "2" → 0-based 1
    }
    expect(mockQuery).toHaveBeenCalledTimes(1);
  });

  it("does NOT engage cross-document path when candidateDocumentTitles is undefined (single-PDF case)", async () => {
    mockQuery.mockReturnValueOnce(
      fakeQuery({ text: "1", totalCostUsd: 0.001 }),
    );
    const result = await selectChapter({
      question: "What's in the introduction?",
      outline: sampleOutline,
      conversationCostState: { totalCostUsd: 0.05, perConvCap: 0.5 },
      // candidateDocumentTitles intentionally omitted
    });
    expect(result.kind).toBe("selected");
    expect(mockQuery).toHaveBeenCalledTimes(1);
  });

  it("does NOT engage cross-document path when only one candidate document is provided", async () => {
    // Single-PDF active context (len === 1) — the cross-document
    // disambiguation guard requires 2+ candidates, so the router
    // proceeds straight to the routing turn.
    mockQuery.mockReturnValueOnce(
      fakeQuery({ text: "3", totalCostUsd: 0.001 }),
    );
    const result = await selectChapter({
      question: "How is the database designed?",
      outline: sampleOutline,
      conversationCostState: { totalCostUsd: 0.05, perConvCap: 0.5 },
      candidateDocumentTitles: ["Designing-Data-Intensive-Apps"],
    });
    expect(result.kind).toBe("selected");
    expect(mockQuery).toHaveBeenCalledTimes(1);
  });
});
