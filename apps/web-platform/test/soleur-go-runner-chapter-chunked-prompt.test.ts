// Concierge system-prompt coverage for the chapter-chunked branch
// (#3436 Phase 3.B — bundle PR feat-pdf-chapter-chunking-bundle).
//
// Phase 3.A intentionally DEFERRED the chapter-chunked system-prompt
// directive: when `documentExtractMeta.chapters` was populated, the
// system prompt fell through to PR #3430's `too_many_pages` bridge.
// This file pinned that fall-through invariant.
//
// Phase 3.B (TR4 → AC #18) revives the directive in lockstep with the
// dispatch-time content-block attachment. This file is now flipped:
// when the resolver populates chapters, the system prompt MUST carry
// the chapter-chunked directive (Table of contents, content-block
// contract, prefix instruction).
//
// The single-commit invariant guarantees the dispatch wiring lands in
// the same commit — see `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts`
// for the dispatch-side integration coverage.

import { describe, it, expect } from "vitest";

import { buildSoleurGoSystemPrompt } from "@/server/soleur-go-runner";
import type { ChapterIndex } from "@/server/pdf-text-extract";

const sampleChapters: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication", startPage: 48, endPage: 102, depth: 0 },
];

describe("buildSoleurGoSystemPrompt — chapter-chunked branch (Phase 3.B PRESENT)", () => {
  it("emits the chapter-chunked directive when chapters are present", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/manning-large.pdf",
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 403,
        chapters: sampleChapters,
        fullExtractedText: "(extracted body)",
      },
      workspacePath: "/workspaces/u1",
    });

    // Currently-viewing line names the artifact.
    expect(prompt).toContain("knowledge-base/manning-large.pdf");

    // Table-of-contents preamble + at least one sanitized title with its
    // 1-based page range.
    expect(prompt).toContain("Table of contents:");
    expect(prompt).toContain("1. Introduction (pages 1-12)");
    expect(prompt).toContain("2. Architecture overview (pages 13-47)");
    expect(prompt).toContain("3. Authentication (pages 48-102)");

    // Content-block contract + prefix instruction (single-PDF shape — no
    // document title in the prefix template).
    expect(prompt).toContain("`document` content block");
    expect(prompt).toMatch(
      /Prefix every reply with `\[Answering from chapter <N>: "<title>"\]`/,
    );

    // Crucially, the bridge `too_many_pages` directive page-count copy
    // does NOT also fire on the chapter-chunked branch.
    expect(prompt).not.toMatch(/I see 403 pages/);
  });

  it("emits the directive even when documentExtractError is unset (success-with-structure)", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 250,
        chapters: sampleChapters,
        fullExtractedText: "(body)",
      },
      workspacePath: "/workspaces/u1",
    });
    expect(prompt).toContain("Table of contents:");
    expect(prompt).toContain("`document` content block");
  });

  it("falls through to too_many_pages directive when chapters is empty / unset (existing behavior)", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
      workspacePath: "/workspaces/u1",
    });

    expect(prompt).not.toContain("Table of contents:");
    expect(prompt).toContain("403");
  });

  it("byte-stability: same chapters input produces identical prompt across calls (cache-prefix invariant)", () => {
    const args = {
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf" as const,
      documentExtractMeta: {
        numPages: 403,
        chapters: sampleChapters,
        fullExtractedText: "(body)",
      },
      workspacePath: "/workspaces/u1",
    };
    const a = buildSoleurGoSystemPrompt(args);
    const b = buildSoleurGoSystemPrompt(args);
    expect(a).toBe(b);
  });
});
