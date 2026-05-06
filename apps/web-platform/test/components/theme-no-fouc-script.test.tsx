/**
 * Unit + drift-guard tests for the inline <NoFoucScript> bootstrap. The
 * SCRIPT constant is a static string rendered via dangerouslySetInnerHTML,
 * so we assert on its source rather than executing it under JSDOM.
 *
 * The drift-guard test reads globals.css and confirms the inline script's
 * hex literals match the canonical --soleur-bg-base values declared for
 * each palette. A brand-guide palette refresh that updates globals.css
 * without updating the script will fail this test at CI time.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  NO_TRANSITION_CSS_TEXT,
  NO_TRANSITION_STYLE_ID,
} from "@/components/theme/no-transition-contract";

const SCRIPT_FILE = resolve(__dirname, "../../components/theme/no-fouc-script.tsx");
const CSS_FILE = resolve(__dirname, "../../app/globals.css");

function readScriptSource(): string {
  return readFileSync(SCRIPT_FILE, "utf8");
}

describe("NoFoucScript SCRIPT contents", () => {
  it("writes documentElement.style.colorScheme synchronously", () => {
    const src = readScriptSource();
    expect(src).toMatch(/\.style\.colorScheme\s*=/);
  });

  it("writes documentElement.style.backgroundColor synchronously", () => {
    const src = readScriptSource();
    expect(src).toMatch(/\.style\.backgroundColor\s*=/);
  });

  it("contains the light palette base hex literal (#fbf7ee)", () => {
    const src = readScriptSource();
    expect(src.toLowerCase()).toContain("#fbf7ee");
  });

  it("contains the dark palette base hex literal (#0a0a0a)", () => {
    const src = readScriptSource();
    expect(src.toLowerCase()).toContain("#0a0a0a");
  });

  it("imports the shared NO_TRANSITION_STYLE_ID + NO_TRANSITION_CSS_TEXT contract", () => {
    const src = readScriptSource();
    // Both the runtime helper (theme-provider.tsx) and this boot script
    // import these constants from no-transition-contract.ts. TypeScript's
    // compile-time identity is the load-bearing drift-guard between the
    // two files; this test just confirms the import edge survives any
    // future refactor that might inline the literals back into either
    // file. The constants themselves ARE used (referenced via
    // ${"$"}{JSON.stringify(NO_TRANSITION_STYLE_ID)} interpolation in the
    // SCRIPT template), so an unused-import lint would flag a regression.
    expect(src).toMatch(
      /from\s+["']@\/components\/theme\/no-transition-contract["']/,
    );
    expect(src).toContain("NO_TRANSITION_STYLE_ID");
    expect(src).toContain("NO_TRANSITION_CSS_TEXT");
    // Sanity: confirm the constants resolve to non-empty values at test
    // time so the contract module isn't accidentally exporting empty strings.
    expect(NO_TRANSITION_STYLE_ID.length).toBeGreaterThan(0);
    expect(NO_TRANSITION_CSS_TEXT).toMatch(/transition:\s*none/);
  });

  it("calls localStorage.getItem('soleur:theme') exactly once", () => {
    const src = readScriptSource();
    const matches = src.match(/localStorage\.getItem\(["']soleur:theme["']\)/g) ?? [];
    expect(matches.length).toBe(1);
  });

  it("falls back to 'system' on invalid stored values", () => {
    const src = readScriptSource();
    // Two fallback paths: invalid value normalisation + try/catch fallback.
    // Both must coerce to "system".
    const systemFallbacks = src.match(/=\s*["']system["']/g) ?? [];
    expect(systemFallbacks.length).toBeGreaterThanOrEqual(2);
  });

  it("queries prefers-color-scheme to resolve 'system' to a concrete palette", () => {
    const src = readScriptSource();
    expect(src).toContain("prefers-color-scheme");
  });
});

describe("no-fouc-script hex literal drift-guard", () => {
  // Anchor to `:root[data-theme="..."]` (canonical block in globals.css)
  // rather than `[data-theme="..."]`; the @custom-variant declaration at
  // the top of globals.css also contains `[data-theme="dark"]` but no
  // `--soleur-bg-base`, and a permissive regex would silently fall through
  // to a later match on a CSS reorder. Anchoring removes that ambiguity.
  function extractBgBase(css: string, palette: "light" | "dark"): string {
    const re = new RegExp(
      `:root\\[data-theme="${palette}"\\]\\s*\\{[^}]*?--soleur-bg-base:\\s*([^;]+);`,
    );
    const match = css.match(re);
    return match?.[1]?.trim() ?? "";
  }

  it("script literal matches globals.css :root[data-theme=light] --soleur-bg-base", () => {
    const script = readScriptSource();
    const css = readFileSync(CSS_FILE, "utf8");
    const lightHex = extractBgBase(css, "light");

    expect(lightHex, "light --soleur-bg-base not found in globals.css").toBeTruthy();
    expect(
      script.toLowerCase(),
      `script missing light hex literal '${lightHex}'`,
    ).toContain(lightHex.toLowerCase());
  });

  it("script literal matches globals.css :root[data-theme=dark] --soleur-bg-base", () => {
    const script = readScriptSource();
    const css = readFileSync(CSS_FILE, "utf8");
    const darkHex = extractBgBase(css, "dark");

    expect(darkHex, "dark --soleur-bg-base not found in globals.css").toBeTruthy();
    expect(
      script.toLowerCase(),
      `script missing dark hex literal '${darkHex}'`,
    ).toContain(darkHex.toLowerCase());
  });
});
