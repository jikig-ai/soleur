// Concierge system-prompt coverage for the chapter-chunked branch (#3436
// Phase 3.A foundations).
//
// Phase 3.A intentionally DEFERS the dispatch-time per-turn chapter
// routing + content-block attachment to #3472 (Phase 3.B). Until #3472
// ships, when the resolver populates `documentExtractMeta.chapters`, the
// runner system prompt MUST fall through to the existing PR #3430
// `too_many_pages` bridge directive — never declare a content-block
// contract the dispatch layer has not yet implemented (would launder
// fabricated chapter answers under the chapter-prefix surface, crossing
// the brand-survival threshold per plan §User-Brand Impact).
//
// This file pins that fall-through invariant so a future revival of the
// chapter-chunked directive must arrive together with the dispatch
// wiring (or this test fails).

import { describe, it, expect } from "vitest";

import { buildSoleurGoSystemPrompt } from "@/server/soleur-go-runner";
import type { ChapterIndex } from "@/server/pdf-text-extract";

const sampleChapters: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication", startPage: 48, endPage: 102, depth: 0 },
];

describe("buildSoleurGoSystemPrompt — chapter-chunked branch (Phase 3.A fall-through)", () => {
  it("falls through to too_many_pages bridge when chapters are present (Phase 3.B not yet wired)", () => {
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

    // Page count from documentExtractMeta interpolated into the bridge
    // directive (existing PR #3430 behavior).
    expect(prompt).toContain("403");

    // CRITICAL: NO chapter-content-block contract leaks into the prompt
    // until #3472 actually attaches the content block at dispatch time.
    expect(prompt).not.toContain("`document` content block");
    expect(prompt).not.toMatch(
      /Prefix every reply with `\[Answering from chapter/,
    );
    expect(prompt).not.toContain("Table of contents:");
  });

  it("treats chapters-present as too_many_pages even when documentExtractError is unset", () => {
    // Resolver emits chapters with NO error (success-with-structure) —
    // runner falls through to the bridge based on chapters presence
    // alone, not on the error class.
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
    expect(prompt).toContain("250");
    expect(prompt).not.toContain("Table of contents:");
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
