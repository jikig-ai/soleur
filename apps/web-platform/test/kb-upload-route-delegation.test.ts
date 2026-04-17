// Proof-of-delegation regression gate: route.ts source must actually invoke
// the extracted helper and must not contain an inline linearizePdf call.
// Catches the failure mode documented in
// knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md
// without polluting kb-upload.test.ts's node:fs mock.

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const routeSrc = readFileSync(
  resolve(__dirname, "../app/api/kb/upload/route.ts"),
  "utf-8",
);

describe("route delegates to prepareUploadPayload helper", () => {
  it("imports the helper", () => {
    expect(routeSrc).toMatch(
      /import\s*\{\s*prepareUploadPayload\s*\}\s*from\s*["']@\/server\/kb-upload-payload["']/,
    );
  });

  it("awaits the helper invocation", () => {
    expect(routeSrc).toMatch(/await\s+prepareUploadPayload\s*\(/);
  });

  it("does not keep the inline linearize block after extraction", () => {
    expect(routeSrc).not.toMatch(/linearizePdf\s*\(/);
  });
});
