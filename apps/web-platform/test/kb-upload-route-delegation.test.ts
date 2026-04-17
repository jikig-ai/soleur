// Negative-space regression gate per
// knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md
//
// The route-level PDF tests in kb-upload.test.ts already prove behavioral
// delegation (mockLinearize fires through the helper, bytes reach the PUT
// body) — this file covers the one thing mock-based tests CANNOT: asserting
// a specific symbol is absent from the route source. Without this, a future
// edit could re-introduce an inline linearizePdf call alongside the helper
// and all behavioral tests would still pass.

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const routeSrc = readFileSync(
  resolve(__dirname, "../app/api/kb/upload/route.ts"),
  "utf-8",
);

describe("route delegates PDF linearization exclusively via prepareUploadPayload", () => {
  it("route source contains no inline linearizePdf() call (would double-transform PDFs)", () => {
    expect(routeSrc).not.toMatch(/linearizePdf\s*\(/);
  });
});
