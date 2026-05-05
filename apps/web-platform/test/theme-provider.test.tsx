import { render, screen, act } from "@testing-library/react";
import { describe, it, expect, beforeEach, vi } from "vitest";
import { ThemeProvider, useTheme } from "@/components/theme/theme-provider";

const STORAGE_KEY = "soleur:theme";

type MediaQueryListLike = {
  matches: boolean;
  addEventListener: (type: "change", listener: (e: { matches: boolean }) => void) => void;
  removeEventListener: (type: "change", listener: (e: { matches: boolean }) => void) => void;
  // Test-only handle to fire change events.
  __fire(matches: boolean): void;
};

function makeMatchMedia(initialDarkMatches: boolean): {
  matchMedia: (query: string) => MediaQueryListLike;
  fireOSChange: (matches: boolean) => void;
} {
  let listener: ((e: { matches: boolean }) => void) | null = null;
  let currentMatches = initialDarkMatches;

  const list: MediaQueryListLike = {
    get matches() {
      return currentMatches;
    },
    addEventListener: (_, l) => {
      listener = l;
    },
    removeEventListener: (_, l) => {
      if (listener === l) listener = null;
    },
    __fire(matches: boolean) {
      currentMatches = matches;
      if (listener) listener({ matches });
    },
  };

  return {
    matchMedia: () => list,
    fireOSChange: (matches: boolean) => list.__fire(matches),
  };
}

function Probe() {
  const { theme, resolvedTheme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="theme">{theme}</span>
      <span data-testid="resolved">{resolvedTheme}</span>
      <button onClick={() => setTheme("dark")}>set-dark</button>
      <button onClick={() => setTheme("light")}>set-light</button>
      <button onClick={() => setTheme("system")}>set-system</button>
    </div>
  );
}

describe("ThemeProvider", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });

  it("defaults to 'system' with no stored preference", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme").textContent).toBe("system");
    expect(screen.getByTestId("resolved").textContent).toBe("dark");
    vi.unstubAllGlobals();
  });

  it("hydrates from localStorage on mount", () => {
    localStorage.setItem(STORAGE_KEY, "light");
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme").textContent).toBe("light");
    expect(screen.getByTestId("resolved").textContent).toBe("light");
    expect(document.documentElement.dataset.theme).toBe("light");
    vi.unstubAllGlobals();
  });

  it("setTheme persists to localStorage and applies data-theme on <html>", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    act(() => {
      screen.getByText("set-dark").click();
    });

    expect(screen.getByTestId("theme").textContent).toBe("dark");
    expect(localStorage.getItem(STORAGE_KEY)).toBe("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");

    act(() => {
      screen.getByText("set-light").click();
    });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("light");
    expect(document.documentElement.dataset.theme).toBe("light");
    vi.unstubAllGlobals();
  });

  it("system mode resolves to OS preference and updates live on matchMedia change", () => {
    const { matchMedia, fireOSChange } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    // Force system explicitly so the assertion is independent of default-state.
    act(() => {
      screen.getByText("set-system").click();
    });

    expect(screen.getByTestId("theme").textContent).toBe("system");
    expect(screen.getByTestId("resolved").textContent).toBe("dark");
    expect(document.documentElement.dataset.theme).toBe("system");

    // OS swaps to light without remount.
    act(() => {
      fireOSChange(false);
    });

    expect(screen.getByTestId("resolved").textContent).toBe("light");
    // theme stays "system"; data-theme stays "system" (the @media block in
    // globals.css is what swaps the CSS vars when prefers-color-scheme flips).
    expect(screen.getByTestId("theme").textContent).toBe("system");
    expect(document.documentElement.dataset.theme).toBe("system");
    vi.unstubAllGlobals();
  });

  it("rejects invalid stored values and falls back to 'system'", () => {
    localStorage.setItem(STORAGE_KEY, "neon"); // garbage from a future version or attacker
    const { matchMedia } = makeMatchMedia(false);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme").textContent).toBe("system");
    expect(screen.getByTestId("resolved").textContent).toBe("light");
    vi.unstubAllGlobals();
  });
});
