import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Source-level regression gate for the Soleur re-theme of the LikeC4 C4 visualizer
// (remove the upstream "LikeC4" marks + scope a Soleur palette to the diagram).
// CSS/label changes are not exercised by jsdom unit tests, so these negative-space
// assertions guard against a regression silently restoring the upstream branding.
const kb = (f: string) => join(__dirname, "..", "components", "kb", f);
const read = (f: string) => readFileSync(kb(f), "utf8");
// The upstream logo art is the load-bearing DOM hook (the diagram's LogoButton
// carries no stable class). Guard the installed library version so a bump that
// changes the logo SVG fails CI loudly instead of silently un-hiding the logo.
const LIKEC4_LOGO = join(
  __dirname,
  "..",
  "node_modules",
  "@likec4",
  "diagram",
  "dist",
  "components",
  "Logo.js",
);

describe("C4 visualizer Soleur re-theme", () => {
  it("removes the literal 'LikeC4 ·' chrome label from our components (AC2)", () => {
    // The second "LikeC4" mark lives in OUR tab-strip header, not the library.
    expect(read("c4-diagram.tsx")).not.toContain("LikeC4 ·");
    expect(read("c4-workspace.tsx")).not.toContain("LikeC4 ·");
  });

  it("hides the upstream logo via the real DOM hook, scoped to the diagram (AC1/AC5)", () => {
    const css = read("c4-theme.css");
    // The logo button is identified by the unique full-wordmark viewBox; the
    // rule must be scoped to .soleur-c4 (not global) and collapse the button.
    expect(css).toMatch(
      /\.soleur-c4 button:has\(svg\[viewBox="0 0 222 56"\]\)/,
    );
    expect(css).toMatch(/display:\s*none\s*!important/);
  });

  it("targets a logo hook that still exists in the installed @likec4/diagram (AC1)", () => {
    // If a library bump renames/redraws the logo, this fails — the CSS hook
    // above would silently stop matching otherwise.
    expect(readFileSync(LIKEC4_LOGO, "utf8")).toContain('viewBox: "0 0 222 56"');
  });

  it("overrides the LikeC4 palette vars with Soleur tokens, not blue hex (AC3)", () => {
    const css = read("c4-theme.css");
    // At minimum the element fill var must be re-pointed at a Soleur token.
    expect(css).toMatch(/--likec4-palette-fill:\s*var\(--soleur-/);
    // The per-node override MUST carry !important — it is the only thing that
    // beats the library's ID-specificity runtime rule (see c4-theme.css §2b).
    expect(css).toMatch(
      /\[data-likec4-color\][\s\S]*?--likec4-palette-fill:[^;]*!important/,
    );
    // Guard against the upstream default blue leaking back in.
    expect(css).not.toContain("#3b82f6");
  });

  it("anchors the override on a Soleur wrapper that the shared canvas renders (AC5/AC7)", () => {
    const shared = read("c4-shared.tsx");
    // The shared C4Canvas is the single choke point for both entry points.
    expect(shared).toContain("soleur-c4");
    expect(shared).toContain('"./c4-theme.css"');
    // The whole CSS approach depends on the light-DOM <LikeC4Diagram> (not the
    // ShadowRoot ReactLikeC4/LikeC4View variants). Guard the component choice.
    expect(shared).toContain("<LikeC4Diagram");
  });
});
