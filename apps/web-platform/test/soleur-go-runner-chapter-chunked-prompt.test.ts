// Concierge system-prompt coverage for the chapter-chunked branch (#3436
// Phase 3 foundations). Verifies that when the resolver populates
// `documentExtractMeta.chapters`, the assembled system prompt:
//
//   - declares the table of contents (chapter # + title + page range)
//   - tells the model the answer-turn chapter content arrives as a
//     `document` content block on the user message
//   - asks the model to prefix replies with `[Answering from chapter
//     <N>: "<title>"]`
//   - includes the standard NO-ASK clause
//
// Per plan §Sharp Edges, the directive is byte-stable per session — no
// per-turn chapter info leaks into the system prompt (that's the cache-
// invalidation hazard the design avoids). Per-turn chapter routing +
// content-block attachment is wired at the dispatch layer in a follow-up.

import { describe, it, expect } from "vitest";

import { buildSoleurGoSystemPrompt } from "@/server/soleur-go-runner";
import type { ChapterIndex } from "@/server/pdf-text-extract";

const sampleChapters: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication", startPage: 48, endPage: 102, depth: 0 },
];

describe("buildSoleurGoSystemPrompt — chapter-chunked branch", () => {
  it("emits a TOC + content-block + prefix directive when chapters are present", () => {
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

    // TOC is interpolated by index (1-based) + title + page range.
    expect(prompt).toContain("1. Introduction (pages 1-12)");
    expect(prompt).toContain("2. Architecture overview (pages 13-47)");
    expect(prompt).toContain("3. Authentication (pages 48-102)");

    // Cache-cumulative-prefix invariant: per-turn chapter content is
    // declared to arrive on the user message, not in the system prompt.
    // (Match across the directive's line wrap.)
    expect(prompt).toMatch(/`document` content[\s\S]{0,3}block/);

    // Loaded-chapter prefix instruction (AC #5 carrier).
    expect(prompt).toContain(
      'Prefix every reply with `[Answering from chapter <N>: "<title>"]`',
    );

    // Standard NO-ASK clause.
    expect(prompt).toContain(
      "Do not ask which document the user is referring to",
    );
  });

  it("chapter-chunked branch wins over `too_many_pages` when both fields are present (defense-in-depth)", () => {
    // Resolver makes them mutually exclusive but a partial body must
    // still take the chapter-chunked branch — chapters-set is the
    // success-with-structure discriminator.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: {
        numPages: 403,
        chapters: sampleChapters,
        fullExtractedText: "(extracted body)",
      },
      workspacePath: "/workspaces/u1",
    });

    expect(prompt).toContain("Table of contents:");
    // Should NOT carry the too_many_pages bridge copy in this branch.
    expect(prompt).not.toContain("too long for me to read in one pass");
  });

  it("falls through to `too_many_pages` directive when chapters is empty / unset", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
      workspacePath: "/workspaces/u1",
    });

    expect(prompt).not.toContain("Table of contents:");
    // Existing too_many_pages copy continues to surface.
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
