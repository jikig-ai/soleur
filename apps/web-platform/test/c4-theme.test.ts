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
// The person-silhouette tint is keyed on TWO library DOM hooks the descendant
// selector depends on: `data-likec4-fill="mix-stroke"` (the silhouette tint,
// emitted inside the `person` shape case of ElementShape.js) AND
// `data-likec4-shape` (emitted on the node container by ElementNodeContainer.js).
// Guard both installed components so a bump that renames or moves either hook
// fails CI loudly instead of silently un-toning the silhouette (vendored-CSS
// Sharp Edge, #4938).
const LIKEC4_ELEMENT_DIR = join(
  __dirname,
  "..",
  "node_modules",
  "@likec4",
  "diagram",
  "dist",
  "base-primitives",
  "element",
);
const LIKEC4_ELEMENT_SHAPE = join(LIKEC4_ELEMENT_DIR, "ElementShape.js");
const LIKEC4_ELEMENT_CONTAINER = join(
  LIKEC4_ELEMENT_DIR,
  "ElementNodeContainer.js",
);
// Light-theme readability (§4) depends on the library's own light-scheme branch
// firing in phase with Soleur's theme. Two installed-library files are the
// load-bearing hooks the §4 CSS + the c4-shared.tsx seam fix ride on:
//   - styles.css2.js: gates light-branch edge-label vars on
//     `[data-mantine-color-scheme=light]` and consumes `--xy-edge-label-*`.
//   - EnsureMantine.js / DefaultMantineProvider.js: the seam — the library only
//     injects its own `defaultColorScheme:"auto"` provider when NO MantineContext
//     is in scope, so wrapping <LikeC4Diagram> in our <MantineProvider
//     forceColorScheme> makes the diagram follow Soleur's resolvedTheme instead
//     of the OS `prefers-color-scheme`.
const LIKEC4_CONTEXT_DIR = join(
  __dirname,
  "..",
  "node_modules",
  "@likec4",
  "diagram",
  "dist",
  "context",
);
const LIKEC4_STYLES = join(
  __dirname,
  "..",
  "node_modules",
  "@likec4",
  "diagram",
  "dist",
  "styles.css2.js",
);
const LIKEC4_ENSURE_MANTINE = join(LIKEC4_CONTEXT_DIR, "EnsureMantine.js");
const LIKEC4_DEFAULT_PROVIDER = join(
  LIKEC4_CONTEXT_DIR,
  "DefaultMantineProvider.js",
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

  it("tones the person silhouette so overrun label text stays legible (AC1/AC2/AC3)", () => {
    const css = read("c4-theme.css");
    // The rule must be scoped to .soleur-c4 and keyed on BOTH intrinsic hooks:
    // the person shape container + the silhouette's mix-stroke fill attr.
    expect(css).toMatch(
      /\.soleur-c4 \[data-likec4-shape="person"\][^{]*\[data-likec4-fill="mix-stroke"\]/,
    );
    // Capture the rule body and assert it is theme-aware (palette var, not hex)
    // and carries !important (to beat the library's mix-stroke fill recipe).
    const body = css.match(
      /\[data-likec4-shape="person"\][^{]*\[data-likec4-fill="mix-stroke"\]\s*\{([\s\S]*?)\}/,
    );
    expect(body).not.toBeNull();
    const rule = body![1];
    expect(rule).toMatch(/var\(--/);
    expect(rule).toMatch(/!important/);
    // It must re-point the silhouette `fill` off the 80%-gold mix (the shipped
    // lever — not a commented-out form, so anchor on the property declaration).
    expect(rule).toMatch(/^\s*fill:/m);
  });

  it("targets both library DOM hooks the selector depends on, in the installed @likec4/diagram (AC4)", () => {
    // The selector is a descendant combinator over TWO hooks. Guard each in the
    // installed library so a bump that renames/moves either fails CI loudly
    // instead of silently un-toning the silhouette.
    //
    // 1. `data-likec4-fill="mix-stroke"` must still live INSIDE the `person`
    //    case — the literal appears in ~6 shape cases, so a whole-file
    //    `toContain` would pass even if the person case lost it. Slice the
    //    person case (from `case "person"` to the next `case "`) and assert
    //    within that slice only.
    const shapeSrc = readFileSync(LIKEC4_ELEMENT_SHAPE, "utf8");
    const personStart = shapeSrc.indexOf('case "person"');
    expect(personStart).toBeGreaterThan(-1);
    const nextCase = shapeSrc.indexOf('case "', personStart + 1);
    const personCase = shapeSrc.slice(
      personStart,
      nextCase === -1 ? undefined : nextCase,
    );
    expect(personCase).toContain('"data-likec4-fill": "mix-stroke"');

    // 2. `data-likec4-shape` (the selector's ancestor hook) must still be
    //    emitted on the node container.
    expect(readFileSync(LIKEC4_ELEMENT_CONTAINER, "utf8")).toContain(
      '"data-likec4-shape": data.shape',
    );
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

  // --- Light-theme readability (§4) + the Mantine color-scheme seam fix ---

  it("adds a light-scoped node-separation rule that beats the library, theme-aware (AC2/AC4/AC5)", () => {
    const css = read("c4-theme.css");
    // The §4 node rule must be scoped to BOTH the light scheme AND .soleur-c4 so
    // dark theme is untouched (AC2 requires dark byte-identical).
    expect(css).toMatch(
      /\[data-mantine-color-scheme="light"\]\s+\.soleur-c4 :is\(\[data-likec4-color\]\)/,
    );
    // Capture the light-scoped node rule body; it must re-point the fill via a
    // Soleur token (not hex) and carry !important.
    const nodeBody = css.match(
      /\[data-mantine-color-scheme="light"\]\s+\.soleur-c4 :is\(\[data-likec4-color\]\)\s*\{([\s\S]*?)\}/,
    );
    expect(nodeBody).not.toBeNull();
    const node = nodeBody![1];
    expect(node).toMatch(/--likec4-palette-fill:[^;]*var\(--soleur-[^;]*!important/);
    // The relation-label token is darkened toward primary so the library's
    // +0.05 L light-branch lift still clears AA.
    expect(node).toMatch(
      /--likec4-palette-relation-label:\s*var\(--soleur-text-primary\)[^;]*!important/,
    );
  });

  it("restores the edge-label pill opacity in light theme via the library's own --xy hook (AC3/AC5)", () => {
    const css = read("c4-theme.css");
    // The library lowers the pill bg to 60% opacity in its light branch; we
    // override the SAME consumption var on .likec4-edge-label, light-scoped.
    expect(css).toMatch(
      /\[data-mantine-color-scheme="light"\]\s+\.soleur-c4 \.likec4-edge-label/,
    );
    const pillBody = css.match(
      /\[data-mantine-color-scheme="light"\]\s+\.soleur-c4 \.likec4-edge-label\s*\{([\s\S]*?)\}/,
    );
    expect(pillBody).not.toBeNull();
    expect(pillBody![1]).toMatch(
      /--xy-edge-label-background-color:[^;]*var\(--soleur-[^;]*!important/,
    );
  });

  it("keeps every §4 rule light-scoped so dark theme is untouched (AC2)", () => {
    const css = read("c4-theme.css");
    // Neither §4 hook may appear unscoped — the only occurrences of these
    // light-only selectors must sit behind [data-mantine-color-scheme="light"].
    for (const m of css.matchAll(/\.soleur-c4 \.likec4-edge-label/g)) {
      const before = css.slice(0, m.index);
      expect(before.endsWith('[data-mantine-color-scheme="light"] ')).toBe(true);
    }
  });

  it("guards the library's light-branch edge-label hooks in the installed @likec4/diagram (AC6)", () => {
    // Source-grep CSS tests are vacuous alone; this reads the INSTALLED library
    // so a bump that renames the scheme gate or the --xy hook fails CI loudly
    // instead of silently un-fixing the labels (vendored-CSS Sharp Edge, #4938).
    const styles = readFileSync(LIKEC4_STYLES, "utf8");
    // The light branch is gated on the mantine scheme attribute...
    expect(styles).toContain("[data-mantine-color-scheme=light]");
    // ...and sets the two label vars our §4 rule (and the library) consume.
    expect(styles).toContain("--xy-edge-label-color");
    expect(styles).toContain("--xy-edge-label-background-color");
    // The pill element consumes the background var; the SVG text consumes color.
    expect(styles).toMatch(
      /\.likec4-edge-label\{[^}]*background:var\(--xy-edge-label-background-color\)/,
    );
    expect(styles).toMatch(
      /\.react-flow__edge-text\{fill:var\(--xy-edge-label-color/,
    );
  });

  it("guards the Mantine color-scheme seam in the installed @likec4/diagram (AC6)", () => {
    // The seam: the library injects its OWN provider (hard-coded
    // defaultColorScheme:"auto", i.e. OS prefers-color-scheme) ONLY when no
    // MantineContext is in scope. Our wrapper provides that context, so the
    // diagram follows Soleur's resolvedTheme. If a bump removes either fact, the
    // forceColorScheme wrap stops being the seam and this fails loudly.
    expect(readFileSync(LIKEC4_DEFAULT_PROVIDER, "utf8")).toContain(
      'defaultColorScheme: "auto"',
    );
    const ensure = readFileSync(LIKEC4_ENSURE_MANTINE, "utf8");
    expect(ensure).toContain("MantineContext");
    expect(ensure).toContain("DefaultMantineProvider");
  });

  it("wraps <LikeC4Diagram> in a MantineProvider bound to Soleur's resolvedTheme (AC1/AC6)", () => {
    const shared = read("c4-shared.tsx");
    // Lever 1 (the seam fix): a Soleur-owned MantineProvider whose color scheme
    // is forced to Soleur's resolvedTheme overrides the OS prefers-color-scheme.
    expect(shared).toMatch(/import\s*\{[^}]*MantineProvider[^}]*\}\s*from\s*"@mantine\/core"/);
    expect(shared).toMatch(/<MantineProvider[^>]*forceColorScheme=\{resolvedTheme\}/);
    // resolvedTheme must come from Soleur's reactive theme hook, NOT a raw DOM
    // read of data-theme (the c4-shared.tsx CodeMirror read is non-reactive).
    expect(shared).toMatch(/const\s*\{\s*resolvedTheme\s*\}\s*=\s*useTheme\(\)/);
    expect(shared).toMatch(/from\s*"@\/components\/theme\/theme-provider"/);
  });
});
