// PDF extract-error routing partition (2026-05-07 follow-up to #3384).
//
// `PdfExtractErrorClass` is partitioned at `soleur-go-runner.ts:771`:
//
//   SOFT (route to `buildPdfGatedDirective` — SDK Read tool's Anthropic
//   Files API path may still succeed where in-process pdfjs-dist failed):
//     oversized_buffer | corrupted | parse_error | lazy_import_failed |
//     read_failed
//
//   HARD (route to `buildPdfUnreadableDirective` — SDK Read genuinely
//   cannot help: password-protected PDFs reject without the password,
//   image-only/scanned PDFs have no text layer):
//     encrypted | empty_text
//
// The cascade defense (named-binary list + cc-dispatcher's
// `disallowedTools: [Bash, Edit, Write]`) is preserved on BOTH directives.
//
// Pinned invariants per assertion below:
//   1. Soft classes route to `PDF_GATED_DIRECTIVE_LEAD`; the unreadable
//      lead must NOT be present on the soft route.
//   2. Hard classes route to `PDF_UNREADABLE_DIRECTIVE_LEAD`; the gated
//      lead must NOT be present on the hard route.
//   3. Neither route contains the named-binary cascade (`pdftotext`,
//      `pdfplumber`, `pdf-parse`, `PyPDF2`, `PyMuPDF`, `fitz`, `apt-get`,
//      `pip3 install`, `shell-installation commands`) — gated directive's
//      named-binary exclusion list bounds it on the soft route too.
//   4. Hard-class copy still depends on errorClass (`encrypted` →
//      "password-protected", `empty_text` → "scanned" or "image-only").

import { describe, it, expect } from "vitest";

import {
  buildSoleurGoSystemPrompt,
  PDF_GATED_DIRECTIVE_LEAD,
  PDF_UNREADABLE_DIRECTIVE_LEAD,
} from "@/server/soleur-go-runner";

// Binary tokens that, if PRESENT IN AN ENABLING CONTEXT, indicate the
// apt-get cascade has leaked into the prompt. The `expectNoCascade` pin
// is appropriate ONLY on the unreadable (hard-route) directive, whose body
// must not name these binaries at all — the unreadable directive should
// not even hint at shell tooling.
//
// On the gated (soft-route) directive, these tokens appear by design in
// the defensive "Do NOT call <X>" exclusion list — they are the cascade
// DEFENSE, not the cascade itself. The cascade-enabling check on the
// gated route lives in the "does NOT install software" test below
// (regex-based: `/\b(install|run)\s+apt-get\b/`, "install poppler",
// "install software"), which distinguishes defensive prose from enabling
// prose.
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

describe("PDF extract-error routing partition (soft → gated, hard → unreadable)", () => {
  it("oversized_buffer (soft): routes to gated lead", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/huge.pdf",
      documentKind: "pdf",
      documentExtractError: "oversized_buffer",
    });
    // Soft-failure route: SDK Read tool's Anthropic Files API path may
    // still succeed where pdfjs-dist's in-process buffer cap rejected.
    expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    // Cascade-enabling check is in the "does NOT install software" test
    // below — `expectNoCascade` is unsafe on the gated route because
    // the directive's defensive "Do NOT call <X>" exclusion list contains
    // those binary names by design.
  });

  it("encrypted (hard): routes to unreadable lead and tells the user the PDF is password-protected", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/locked.pdf",
      documentKind: "pdf",
      documentExtractError: "encrypted",
    });
    expect(prompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt.toLowerCase()).toContain("password-protected");
    expectNoCascade(prompt);
  });

  it("empty_text (hard): routes to unreadable lead and tells the user the PDF appears to be scanned / image-only", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/scanned.pdf",
      documentKind: "pdf",
      documentExtractError: "empty_text",
    });
    expect(prompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    const lc = prompt.toLowerCase();
    // Either "scanned" or "image-only" is acceptable — both name the failure
    // shape concretely (not "I cannot read this PDF").
    expect(lc.includes("scanned") || lc.includes("image-only")).toBe(true);
    expectNoCascade(prompt);
  });

  it("corrupted / parse_error (soft): routes to gated lead so SDK Read can attempt the Files API path", () => {
    for (const cls of ["corrupted", "parse_error"] as const) {
      const prompt = buildSoleurGoSystemPrompt({
        artifactPath: "knowledge-base/broken.pdf",
        documentKind: "pdf",
        documentExtractError: cls,
      });
      expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    }
  });

  it("lazy_import_failed (soft): routes to gated lead (in-process outage, SDK Read pipeline is independent)", () => {
    // An in-process extractor outage (lazy `import()` rejection — e.g.
    // a Node-version regression breaking pdfjs-dist's native-dep import)
    // is independent of the SDK Read tool's PDF pipeline. Route to gated
    // so the model attempts Read with the absolute workspace path before
    // refusing.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/anything.pdf",
      documentKind: "pdf",
      documentExtractError: "lazy_import_failed",
    });
    expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  it("read_failed (soft): routes to gated lead (transient I/O — Read may succeed on retry via Files API)", () => {
    // `read_failed` fires when `readFile` raised in the resolver (NFC/NFD
    // filename mismatch, URL-encoded path that wasn't decoded, file moved
    // mid-conversation). The path may resolve correctly under the SDK's
    // sandbox-aware Read; soft route lets the model try.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/transient.pdf",
      documentKind: "pdf",
      documentExtractError: "read_failed",
    });
    expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  it("does NOT install software: cascade defense holds on the soft (gated) route", () => {
    // The pre-#3338 regression is the model emitting "please install
    // poppler-utils" / "run apt-get install" replies in TEXT. The SDK-level
    // disallowedTools blocks Bash modals, but the prompt-text gaslights the
    // user about installing software the runner can't run anyway. The
    // gated directive's named-binary exclusion list is what bounds the
    // cascade on the soft route — pin its absence.
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

  it("documentExtractError WITHOUT documentKind=pdf does NOT activate either PDF branch", () => {
    // Belt-and-suspenders: the partition is gated on documentKind. A stale
    // `documentExtractError` on a text artifact must NOT alter the text
    // branch's behavior.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/notes.md",
      documentKind: "text",
      documentContent: "Hello",
      documentExtractError: "oversized_buffer",
    });
    expect(prompt).toContain("Hello");
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
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

  it("precedence (soft): documentExtractError wins over a partial documentContent and routes to gated lead", () => {
    // Pin the inline-branch precedence: even when both fields land at the
    // prompt builder (a future refactor regression), the extractor's typed
    // failure class must still route through the partition — soft classes
    // skip the inline body and emit the gated directive (so the model can
    // attempt SDK Read with the absolute path), not the inline <document>.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/partial.pdf",
      documentKind: "pdf",
      documentContent: "stale partial body that should not be inlined",
      documentExtractError: "oversized_buffer",
    });
    expect(prompt).not.toContain("<document>");
    expect(prompt).not.toContain("stale partial body");
    expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  it("precedence (hard): documentExtractError wins over a partial documentContent and routes to unreadable lead", () => {
    // Hard-class twin of the precedence test: when an `encrypted` PDF's
    // extractor surfaced its typed failure but a partial body somehow
    // leaked into the prompt builder (defensive scenario), the unreadable
    // directive still fires — the upfront refusal is correct because SDK
    // Read cannot recover a password-protected PDF either.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/locked-partial.pdf",
      documentKind: "pdf",
      documentContent: "stale partial body that should not be inlined",
      documentExtractError: "encrypted",
    });
    expect(prompt).not.toContain("<document>");
    expect(prompt).not.toContain("stale partial body");
    expect(prompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt.toLowerCase()).toContain("password-protected");
    expectNoCascade(prompt);
  });

  it("includes a chat-affordance hint so the agent can answer 'how do I paste it?' follow-ups", () => {
    // agent-native review P2: without this, the recovery loop dead-ends.
    // The directive must name how the user delivers the recovery payload
    // (paste / paperclip re-upload) so the agent has grounding for the
    // inevitable follow-up.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/anything.pdf",
      documentKind: "pdf",
      documentExtractError: "encrypted",
    });
    expect(prompt.toLowerCase()).toContain("paste");
    expect(prompt.toLowerCase()).toMatch(/paperclip|re-upload/);
  });
});
