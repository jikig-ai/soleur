import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Source-level regression gate for the Soleur re-theme of the LikeC4 C4 visualizer
// (remove the upstream "LikeC4" marks + scope a Soleur palette to the diagram).
// CSS/label changes are not exercised by jsdom unit tests, so these negative-space
// assertions guard against a regression silently restoring the upstream branding.
const kb = (f: string) => join(__dirname, "..", "components", "kb", f);
const read = (f: string) => readFileSync(kb(f), "utf8");

describe("C4 visualizer Soleur re-theme", () => {
  it("removes the literal 'LikeC4 ·' chrome label from our components (AC2)", () => {
    // The second "LikeC4" mark lives in OUR tab-strip header, not the library.
    expect(read("c4-diagram.tsx")).not.toContain("LikeC4 ·");
    expect(read("c4-workspace.tsx")).not.toContain("LikeC4 ·");
  });

  it("ships a scoped C4 theme stylesheet that hides the upstream logo (AC1/AC5)", () => {
    const css = read("c4-theme.css");
    // Logo-hide must be scoped to a C4-specific ancestor, not global.
    expect(css).toMatch(/\.soleur-c4[^{]*\.likec4-navigation-panel__logo/);
    expect(css).toMatch(/display:\s*none/);
  });

  it("overrides the LikeC4 palette vars with Soleur tokens, not blue hex (AC3)", () => {
    const css = read("c4-theme.css");
    // At minimum the element fill var must be re-pointed at a Soleur token.
    expect(css).toMatch(/--likec4-palette-fill:\s*var\(--soleur-/);
    // Guard against the upstream default blue leaking back in.
    expect(css).not.toContain("#3b82f6");
  });

  it("anchors the override on a Soleur wrapper that the shared canvas renders (AC5/AC7)", () => {
    const shared = read("c4-shared.tsx");
    // The shared C4Canvas is the single choke point for both entry points.
    expect(shared).toContain("soleur-c4");
    expect(shared).toContain('"./c4-theme.css"');
  });
});
