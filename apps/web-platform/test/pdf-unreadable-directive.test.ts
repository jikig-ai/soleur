// Phase 3 of `2026-05-06-fix-extract-pdf-text-null-in-production-plan.md`:
// when the in-process extractor surfaces a typed failure class
// (`oversized_buffer | encrypted | corrupted | parse_error | empty_text |
// lazy_import_failed`), the system prompt MUST emit a content-grounded
// `buildPdfUnreadableDirective` instead of the apt-get-cascade-prone
// `buildPdfGatedDirective`. Pre-fix, every extractor null fell through to the
// gated directive and re-introduced the exact bug #3338 was supposed to fix.
//
// Pinned invariants per assertion below:
//   1. The unreadable directive is reachable when documentExtractError is set.
//   2. It does NOT contain the named-binary cascade (`pdftotext`, `pdfplumber`,
//      `pdf-parse`, `PyPDF2`, `PyMuPDF`, `fitz`, `apt-get`, `pip3 install`,
//      `shell-installation commands`).
//   3. It does NOT start with `PDF_GATED_DIRECTIVE_LEAD` ("The user is
//      currently viewing the PDF document"). The gated lead is the proximate
//      anchor for the model's "I should Read this PDF" prior — replacing it
//      is the load-bearing fix.
//   4. The reply phrasing depends on errorClass — `oversized_buffer` →
//      "too large", `encrypted` → "password-protected", `empty_text` →
//      "scanned" or "image-only".

import { describe, it, expect } from "vitest";

import {
  buildSoleurGoSystemPrompt,
  PDF_GATED_DIRECTIVE_LEAD,
} from "@/server/soleur-go-runner";

const FORBIDDEN_BINARIES = [
  "pdftotext",
  "pdfplumber",
  "pdf-parse",
  "PyPDF2",
  "PyMuPDF",
  "fitz",
  "apt-get",
  "pip3 install",
  "shell-installation commands",
];

function expectNoCascade(prompt: string) {
  for (const token of FORBIDDEN_BINARIES) {
    expect(prompt).not.toContain(token);
  }
}

describe("buildPdfUnreadableDirective via buildSoleurGoSystemPrompt", () => {
  it("oversized_buffer: emits a 'too large' message and does NOT contain the apt-get cascade", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/huge.pdf",
      documentKind: "pdf",
      documentExtractError: "oversized_buffer",
    });
    expect(prompt).toContain("too large");
    expectNoCascade(prompt);
    // Pin: the gated lead substring (the apt-get-prone Read directive's
    // opening anchor) must NOT appear when the unreadable branch fires.
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
  });

  it("encrypted: tells the user the PDF is password-protected", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/locked.pdf",
      documentKind: "pdf",
      documentExtractError: "encrypted",
    });
    expect(prompt.toLowerCase()).toContain("password-protected");
    expectNoCascade(prompt);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
  });

  it("empty_text: tells the user the PDF appears to be scanned / image-only", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/scanned.pdf",
      documentKind: "pdf",
      documentExtractError: "empty_text",
    });
    const lc = prompt.toLowerCase();
    // Either "scanned" or "image-only" is acceptable — both name the failure
    // shape concretely (not "I cannot read this PDF").
    expect(lc.includes("scanned") || lc.includes("image-only")).toBe(true);
    expectNoCascade(prompt);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
  });

  it("corrupted / parse_error: tells the user the PDF is corrupted or unreadable", () => {
    for (const cls of ["corrupted", "parse_error"] as const) {
      const prompt = buildSoleurGoSystemPrompt({
        artifactPath: "knowledge-base/broken.pdf",
        documentKind: "pdf",
        documentExtractError: cls,
      });
      expect(prompt.toLowerCase()).toMatch(/corrupted|unreadable/);
      expectNoCascade(prompt);
      expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    }
  });

  it("lazy_import_failed: still emits a graceful unreadable message (no cascade)", () => {
    // Defense-in-depth: an in-process extractor outage (lazy `import()`
    // rejection, e.g. broken native dep in the runner image) is invisible
    // to the user — the surface is still "I can't read this PDF" rather than
    // an internal error.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/anything.pdf",
      documentKind: "pdf",
      documentExtractError: "lazy_import_failed",
    });
    expectNoCascade(prompt);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    // Suggest a recoverable next step (paste/share/smaller) — the runner
    // doesn't know which class fired exactly, so the directive is generic.
    expect(prompt.toLowerCase()).toMatch(/can'?t read|unable to read|cannot read/);
  });

  it("does NOT install software: directive must not offer to install poppler-utils or similar", () => {
    // The pre-#3338 regression is the model emitting "please install
    // poppler-utils" / "run apt-get install" replies in TEXT. The SDK-level
    // disallowedTools blocks Bash modals, but the prompt-text gaslights the
    // user about installing software the runner can't run anyway. Pin the
    // absence of install verbs.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/x.pdf",
      documentKind: "pdf",
      documentExtractError: "oversized_buffer",
    });
    const lc = prompt.toLowerCase();
    expect(lc).not.toContain("install poppler");
    expect(lc).not.toContain("install software");
    expect(lc).not.toMatch(/\b(install|run)\s+apt-get\b/);
  });

  it("documentExtractError WITHOUT documentKind=pdf does NOT activate the unreadable branch", () => {
    // Belt-and-suspenders: the unreadable branch is gated on documentKind.
    // A stale `documentExtractError` on a text artifact must NOT alter the
    // text branch's behavior.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/notes.md",
      documentKind: "text",
      documentContent: "Hello",
      documentExtractError: "oversized_buffer",
    });
    expect(prompt).toContain("Hello");
    expect(prompt.toLowerCase()).not.toContain("too large");
  });

  it("documentExtractError unset on documentKind=pdf preserves the inline-or-gated branches (regression-only addition)", () => {
    // When the resolver succeeded (documentContent set, no error),
    // documentExtractError is undefined — the existing inline branch must
    // continue to fire byte-equally with the pre-fix behavior.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/research.pdf",
      documentKind: "pdf",
      documentContent: "Chapter 1: Inlined.",
    });
    expect(prompt).toContain("<document>");
    expect(prompt).toContain("Chapter 1: Inlined.");
  });
});
