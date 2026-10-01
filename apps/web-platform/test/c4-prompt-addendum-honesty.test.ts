import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { C4_PROMPT_ADDENDUM, C4_TOOL_DESCRIPTION } from "@/server/c4-concierge-tools";

// Honesty gate for the two LLM-facing C4 surfaces — the edit_c4_diagram tool
// description AND the Concierge system-prompt addendum in cc-dispatcher.ts. They
// sit in the same context window, so the re-render contract must be stated
// consistently in BOTH (the #4963 learning: LLM-facing claims live in both the
// tool description and the prompt addendum — sweep both).
//
// As of Layer 2 (#4964) the diagram DOES re-render after edit_c4_diagram, gated
// on the `rerendered` response field. This gate asserts the new truthful
// contract and that the old Layer-1 "only refreshes out-of-band / you cannot
// trigger" copy is gone from both surfaces. Standalone source-read file (no
// node:fs mock) per the source-delegation-test convention.
const ROOT = path.resolve(__dirname, "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

// #8623: both copies now live in c4-concierge-tools.ts (C4_TOOL_DESCRIPTION and
// C4_PROMPT_ADDENDUM share one rerender-outcome paragraph); cc-dispatcher.ts
// assigns the constant (pinned by c4-concierge-copy.test.ts). So the honesty
// sweep reads the constants, and the dispatcher must carry no inline copy.

const surfaces: Array<[string, () => string]> = [
  ["C4_TOOL_DESCRIPTION", () => C4_TOOL_DESCRIPTION],
  ["C4_PROMPT_ADDENDUM", () => C4_PROMPT_ADDENDUM],
  ["server/cc-dispatcher.ts", () => read("server/cc-dispatcher.ts")],
];

describe("C4 edit-tool / prompt-addendum honesty (Layer 2)", () => {
  for (const [rel, load] of surfaces) {
    it(`${rel} keys the re-render claim on the rerendered field`, () => {
      const src = load();
      if (rel.endsWith(".ts")) {
        // The dispatcher delegates to the shared constant rather than restating it.
        expect(src).toMatch(/c4PromptAddendum\s*=\s*C4_PROMPT_ADDENDUM/);
        expect(src.toLowerCase()).not.toContain("out-of-band");
        expect(src.toLowerCase()).not.toContain("cannot trigger");
        return;
      }
      // The truthful contract references the `rerendered` signal.
      expect(src).toContain("rerendered");
      // The stale Layer-1 copy ("only ... out-of-band", "you cannot trigger")
      // must be gone — the diagram now re-renders on the write path.
      expect(src.toLowerCase()).not.toContain("out-of-band");
      expect(src.toLowerCase()).not.toContain("cannot trigger");
    });
  }
});
