import { render, screen, act } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
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
    // Scrub any stale transition-disable style left by an undrained rAF in
    // the previous test on this happy-dom worker. Tests that do not stub
    // rAF rely on happy-dom's native rAF, which may not fire before the
    // test ends — cleanup callbacks (and their <style> elements) leak.
    const stale = document.head.querySelector("style#__soleur-no-transition");
    if (stale) stale.remove();
  });

  afterEach(() => {
    // Hygiene: every test stubs matchMedia. Without afterEach, a test that
    // throws mid-flight leaks the stub into the next test's render and
    // produces confusing "why did the OS preference flip" failures.
    vi.unstubAllGlobals();
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
  });

  it("setTheme(dark) persists 'dark' to localStorage and writes data-theme='dark'", () => {
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
  });

  it("setTheme(light) persists 'light' to localStorage and writes data-theme='light'", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    act(() => {
      screen.getByText("set-light").click();
    });

    expect(screen.getByTestId("theme").textContent).toBe("light");
    expect(localStorage.getItem(STORAGE_KEY)).toBe("light");
    expect(document.documentElement.dataset.theme).toBe("light");
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
  });

  it("cross-tab: storage event with a valid Theme value updates state without remount", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme").textContent).toBe("system");

    // Another tab wrote 'light' — fire a synthetic storage event.
    act(() => {
      window.dispatchEvent(
        new StorageEvent("storage", { key: STORAGE_KEY, newValue: "light" }),
      );
    });

    expect(screen.getByTestId("theme").textContent).toBe("light");
  });

  it("cross-tab: storage event with garbage value falls back to 'system'", () => {
    localStorage.setItem(STORAGE_KEY, "dark");
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme").textContent).toBe("dark");

    // Hostile or malformed value from another tab.
    act(() => {
      window.dispatchEvent(
        new StorageEvent("storage", { key: STORAGE_KEY, newValue: "neon" }),
      );
    });

    expect(screen.getByTestId("theme").textContent).toBe("system");
  });

  it("cross-tab: storage event for unrelated keys is ignored", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    act(() => {
      window.dispatchEvent(
        new StorageEvent("storage", { key: "some-other-key", newValue: "light" }),
      );
    });

    expect(screen.getByTestId("theme").textContent).toBe("system");
  });

  it("useTheme throws a descriptive error when used outside <ThemeProvider>", () => {
    // Render Probe with no provider; React's error boundary surface here is
    // the thrown message itself. Suppress the React-Testing-Library noise by
    // muting console.error for this assertion.
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() => render(<Probe />)).toThrow(/useTheme.*ThemeProvider/);
    consoleSpy.mockRestore();
  });

  it("syncs React state from <html data-theme> on mount when state diverged from the inline-script's value", () => {
    // Simulate the SSR-vs-client divergence the inline <NoFoucScript> sees:
    // the boot script wrote data-theme="dark" to <html> from localStorage,
    // but at hydration time React's lazy initializer didn't pick it up (the
    // SSR snapshot ran with `typeof window === "undefined"` and produced
    // "system"). Without a mount-sync, ThemeToggle reads theme="system"
    // from context and highlights the wrong segment even though the page
    // palette is correct (CSS reads dataset.theme, not the React context).
    document.documentElement.dataset.theme = "dark";
    // localStorage.clear() ran in beforeEach so readStoredTheme returns "system" —
    // this is the state the lazy initializer would land on if it had no
    // access to localStorage at hydration time.
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    // After mount, React state must reflect the inline-script's value.
    expect(screen.getByTestId("theme").textContent).toBe("dark");
    // The mount sync must NOT overwrite the inline script's data-theme attribute
    // (which would cause a one-frame palette flicker as CSS re-resolves through
    // the @media (prefers-color-scheme) fallback).
    expect(document.documentElement.dataset.theme).toBe("dark");
  });

  it("setTheme injects __soleur-no-transition style and removes it on next frames", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    // Defer the queued rAF callbacks so the test can observe the style
    // BEFORE the cleanup runs, then explicitly drain. Two-deep recursion is
    // expected (double-rAF cleanup); the loop drains both.
    const rafs: Array<FrameRequestCallback> = [];
    vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => {
      rafs.push(cb);
      return rafs.length;
    });

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    // Initial mount queued one rAF. Drain only the cleanup pair from the
    // mount BEFORE the click so the click's helper invocation can re-inject
    // (won't bail) and we observe a fresh style element.
    while (rafs.length) {
      const next = rafs.shift()!;
      next(0);
    }
    expect(document.head.querySelector("style#__soleur-no-transition")).toBeNull();

    act(() => {
      screen.getByText("set-light").click();
    });

    // setTheme injected the style synchronously.
    const styleEl = document.head.querySelector("style#__soleur-no-transition");
    expect(styleEl).not.toBeNull();
    expect(styleEl!.textContent).toMatch(/transition\s*:\s*none/);

    // Drain queued rAFs; each invocation may schedule another (double-rAF
    // cleanup). After the queue empties, the override style is removed.
    while (rafs.length) {
      const next = rafs.shift()!;
      next(0);
    }

    expect(document.head.querySelector("style#__soleur-no-transition")).toBeNull();
  });

  it("setTheme survives localStorage.setItem quota errors (state still updates)", () => {
    const { matchMedia } = makeMatchMedia(true);
    vi.stubGlobal("matchMedia", matchMedia);

    // Force setItem to throw (simulates Safari private-mode quota or a
    // browser extension blocking writes).
    const setItemSpy = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("quota exceeded", "QuotaExceededError");
    });

    render(
      <ThemeProvider>
        <Probe />
      </ThemeProvider>,
    );

    expect(() => {
      act(() => {
        screen.getByText("set-dark").click();
      });
    }).not.toThrow();

    // In-memory state still flipped — degraded persistence is acceptable.
    expect(screen.getByTestId("theme").textContent).toBe("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");

    setItemSpy.mockRestore();
  });
});
