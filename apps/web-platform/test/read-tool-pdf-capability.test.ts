import { describe, it, expect } from "vitest";

import {
  READ_TOOL_PDF_CAPABILITY_DIRECTIVE,
  buildSoleurGoSystemPrompt,
} from "@/server/soleur-go-runner";

// RED test for plan 2026-05-05-fix-cc-pdf-read-capability-prompt-plan.md (#3253).
//
// The Concierge / domain-leader baselines were silent on the Claude Agent
// SDK Read tool's native PDF support. When a user mentioned a PDF in chat
// without a "currently-viewing" KB artifact, the model fabricated a
// plausible refusal ("PDF Reader doesn't seem installed") and refused to
// read the file. The fix is a single load-bearing capability directive
// promoted to BOTH baselines (Concierge router + leader) via a shared
// constant — so the model's self-knowledge of its tools is never silent
// on PDFs.
//
// Wording is purely positive (declarative-then-imperative). The 2026
// prompt-engineering corpus (Lakera, Gadlet, k2view) shows that negative
// framings ("do not / never") underperform at scale and overtrigger
// Claude. Scenario 2 includes an anti-priming guard so a future edit
// re-introducing negation tokens fails the test.

describe("READ_TOOL_PDF_CAPABILITY_DIRECTIVE (load-bearing baseline directive — #3253)", () => {
  // Scenario 1 — constant exported and non-empty
  it("exports a non-empty READ_TOOL_PDF_CAPABILITY_DIRECTIVE string", () => {
    expect(typeof READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toBe("string");
    expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE.length).toBeGreaterThan(80);
  });

  // Scenario 2 — purely positive; pins the load-bearing capability claim
  it("directive states Read supports PDFs (purely positive — no negation)", () => {
    expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("Read tool");
    expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("PDF");
    // Load-bearing capability claim — exact substring shared with the
    // existing assertive directives at soleur-go-runner.ts:506 and
    // agent-runner.ts:613 (so a single substring grep audits all three).
    expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("supports PDF files");
    // Anti-priming guard: the directive MUST NOT contain negation tokens
    // ("do not", "never", "not installed"). Per 2026 prompt-engineering
    // best practice (Lakera/Gadlet/k2view), negation underperforms at
    // scale and overtriggers Claude. A future edit that re-introduces
    // "Do not claim …" must fail this test.
    expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).not.toMatch(
      /\b(do not|never|not installed)\b/i,
    );
  });

  // Scenario 3 — buildSoleurGoSystemPrompt() baseline embeds the directive
  it("buildSoleurGoSystemPrompt() embeds the PDF-capability directive in the baseline (no args)", () => {
    const prompt = buildSoleurGoSystemPrompt();
    expect(prompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
  });

  it("the directive is present even when artifactPath/documentKind are NOT set", () => {
    // The exact failure mode of #3253: user mentions a PDF in chat with
    // no "currently-viewing" artifact thread. Baseline must still teach
    // the model that Read handles PDFs.
    const promptNoArtifact = buildSoleurGoSystemPrompt({});
    expect(promptNoArtifact).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);

    const promptWithText = buildSoleurGoSystemPrompt({
      artifactPath: "vision.md",
      documentKind: "text",
      documentContent: "v1",
    });
    expect(promptWithText).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
  });

  // Scenario 5 — symmetry: baseline + gated directives coexist when artifact IS a PDF
  it("buildSoleurGoSystemPrompt with documentKind: pdf contains BOTH baseline directive AND gated directive", () => {
    // Future-proof against a "merge the two PDF mentions" refactor that
    // accidentally drops one. The baseline directive teaches the model
    // about Read's PDF capability in general; the gated directive
    // additionally tells it which specific PDF the user is viewing.
    // Both must be present on the gated path.
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "research.pdf",
      documentKind: "pdf",
    });
    expect(prompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE); // baseline
    expect(prompt).toContain("currently viewing the PDF document"); // gated
  });
});
