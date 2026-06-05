import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Negative-space regression gate: the false "the diagram re-renders" claim used
// to live in TWO places — the edit_c4_diagram tool description AND the Concierge
// system-prompt addendum in cc-dispatcher.ts. They sit in the same context window,
// so a stale copy in either re-introduces the lie the honesty fix removed. This
// gate reads both sources and asserts the false claim is gone from both. It is a
// standalone source-read file (no node:fs mock) per the source-delegation-test
// convention. See plan 2026-06-05-fix-likec4-code-editor-save-noop-plan.md.
const ROOT = path.resolve(__dirname, "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

describe("C4 edit-tool / prompt-addendum honesty", () => {
  const surfaces = [
    "server/c4-concierge-tools.ts",
    "server/cc-dispatcher.ts",
  ];

  for (const rel of surfaces) {
    it(`${rel} does not falsely claim the diagram re-renders`, () => {
      const src = read(rel);
      // The exact old lie ("the diagram re-renders" / "diagram re-renders —").
      expect(src).not.toMatch(/\bdiagram re-renders\b/i);
    });
  }

  it("both surfaces state the diagram refreshes out-of-band", () => {
    for (const rel of surfaces) {
      expect(read(rel).toLowerCase()).toContain("out-of-band");
    }
  });
});
