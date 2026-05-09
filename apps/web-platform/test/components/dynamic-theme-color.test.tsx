import { render, act } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { DynamicThemeColor } from "@/components/theme/dynamic-theme-color";

const STORAGE_KEY = "soleur:theme";
const FORGE = "#0a0a0a";
const RADIANCE = "#fbf7ee";

function makeMatchMedia(initialDarkMatches: boolean) {
  const list = {
    matches: initialDarkMatches,
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  return () => list;
}

function getMeta(): HTMLMetaElement | null {
  return document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
}

describe("DynamicThemeColor", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
    // Strip any pre-existing theme-color meta so each test starts clean.
    document.querySelectorAll('meta[name="theme-color"]').forEach((el) => el.remove());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("creates a <meta name='theme-color'> when none exists and applies Forge for dark", () => {
    localStorage.setItem(STORAGE_KEY, "dark");
    vi.stubGlobal("matchMedia", makeMatchMedia(true));

    render(
      <ThemeProvider>
        <DynamicThemeColor />
      </ThemeProvider>,
    );

    const meta = getMeta();
    expect(meta).not.toBeNull();
    expect(meta?.content).toBe(FORGE);
  });

  it("applies Radiance to theme-color when light is resolved", () => {
    localStorage.setItem(STORAGE_KEY, "light");
    vi.stubGlobal("matchMedia", makeMatchMedia(false));

    render(
      <ThemeProvider>
        <DynamicThemeColor />
      </ThemeProvider>,
    );

    expect(getMeta()?.content).toBe(RADIANCE);
  });

  it("reuses an existing meta tag rather than appending a duplicate", () => {
    const seed = document.createElement("meta");
    seed.name = "theme-color";
    seed.content = "#stale";
    document.head.appendChild(seed);

    localStorage.setItem(STORAGE_KEY, "dark");
    vi.stubGlobal("matchMedia", makeMatchMedia(true));

    render(
      <ThemeProvider>
        <DynamicThemeColor />
      </ThemeProvider>,
    );

    const all = document.querySelectorAll('meta[name="theme-color"]');
    expect(all.length).toBe(1);
    expect((all[0] as HTMLMetaElement).content).toBe(FORGE);
  });

  it("system + OS=dark resolves to Forge; the visual swap happens via CSS, the meta value via this component", () => {
    // No stored preference → "system". OS reports dark.
    vi.stubGlobal("matchMedia", makeMatchMedia(true));

    render(
      <ThemeProvider>
        <DynamicThemeColor />
      </ThemeProvider>,
    );

    expect(getMeta()?.content).toBe(FORGE);
  });

  it("system + OS=light resolves to Radiance", () => {
    vi.stubGlobal("matchMedia", makeMatchMedia(false));

    render(
      <ThemeProvider>
        <DynamicThemeColor />
      </ThemeProvider>,
    );

    expect(getMeta()?.content).toBe(RADIANCE);
  });
});
