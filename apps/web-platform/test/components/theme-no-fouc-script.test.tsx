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

  it("injects a transient style element with the __soleur-no-transition id", () => {
    const src = readScriptSource();
    expect(src).toContain("__soleur-no-transition");
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
  it("script literals match globals.css --soleur-bg-base values", () => {
    const script = readScriptSource();
    const css = readFileSync(CSS_FILE, "utf8");

    // Extract --soleur-bg-base from :root[data-theme="light"] and "dark" blocks.
    // The CSS declares the dark variables under both `:root` and
    // `:root[data-theme="dark"]`; either qualifier is acceptable.
    const lightMatch = css.match(
      /\[data-theme="light"\][^}]*--soleur-bg-base:\s*([^;]+);/,
    );
    const darkMatch = css.match(
      /\[data-theme="dark"\][^}]*--soleur-bg-base:\s*([^;]+);/,
    );

    expect(lightMatch?.[1]?.trim()).toBeTruthy();
    expect(darkMatch?.[1]?.trim()).toBeTruthy();
    expect(script.toLowerCase()).toContain(lightMatch![1].trim().toLowerCase());
    expect(script.toLowerCase()).toContain(darkMatch![1].trim().toLowerCase());
  });
});
