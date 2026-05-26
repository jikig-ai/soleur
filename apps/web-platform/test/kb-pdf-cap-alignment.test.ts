// Drift guard for the PDF input cap (#3338 follow-up).
//
// Hypothesis A from `2026-05-06-fix-extract-pdf-text-null-in-production-plan.md`:
// `#3337` raised the PDF upload cap to 24 MB (`MAX_AGENT_READABLE_PDF_SIZE`),
// but `pdf-text-extract.ts` kept a local `INPUT_BUFFER_CAP_BYTES = 15 MB`
// constant. PDFs in the [15 MB, 24 MB] band passed upload and silently
// returned null at extraction → the apt-get / find / pdftotext cascade.
//
// The fix imports the shared constant directly. This test is the negative-
// space gate that prevents the cap from being re-shadowed by a local literal:
// it reads the extractor source via `fs.readFileSync` and asserts the file
// neither hard-codes the prior 15 MB literal NOR re-introduces a renamed
// `INPUT_BUFFER_CAP_BYTES` constant.

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";

describe("kb-pdf cap alignment drift guard", () => {
  it("MAX_AGENT_READABLE_PDF_SIZE is 24 MB (the source of truth #3337 ratified)", () => {
    expect(MAX_AGENT_READABLE_PDF_SIZE).toBe(24 * 1024 * 1024);
  });

  it("pdf-text-extract.ts imports MAX_AGENT_READABLE_PDF_SIZE and does NOT hard-code the cap", () => {
    const src = readFileSync(
      path.resolve(__dirname, "../server/pdf-text-extract.ts"),
      "utf8",
    );

    // Belt: the extractor MUST import the shared constant.
    expect(src).toMatch(
      /import\s*\{[^}]*MAX_AGENT_READABLE_PDF_SIZE[^}]*\}\s*from\s*"@\/lib\/attachment-constants"/,
    );

    // Suspenders: ANY hand-rolled `<n> * 1024 * 1024` literal anywhere in
    // the executable source path is forbidden. A re-shadow as
    // `25 * 1024 * 1024` or `0x1800000` would slip past a per-value
    // assertion; this catches the entire shape. We strip line/block
    // comments first so historical references in JSDoc do not trip the
    // gate.
    const sourceWithoutComments = src
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|\s)\/\/[^\n]*/g, "$1");
    expect(sourceWithoutComments).not.toMatch(/\d+\s*\*\s*1024\s*\*\s*1024/);

    // No revival of the prior `INPUT_BUFFER_CAP_BYTES` shadow constant.
    // Anchored on `const ` so a comment referencing the historical name
    // (which IS valuable for future readers tracing the regression) still
    // passes.
    expect(src).not.toMatch(/const\s+INPUT_BUFFER_CAP_BYTES\s*=/);
  });
});
