import { render, screen } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { ThemeToggle } from "@/components/theme/theme-toggle";

/**
 * SSR-hydration / mounted-gate contract.
 *
 * Production bug (PR #3318 follow-up): React 18+ production hydration does
 * NOT patch className mismatches. The SSR snapshot paints System as active
 * (window undefined → resolveClientInitialTheme returns "system"); the
 * client renders the real theme; aria-pressed gets patched but the active
 * className on System persists, producing a "two pills highlighted" visual.
 *
 * Mitigation: ThemeToggle uses a mounted gate. Pre-mount, every segment
 * renders data-active="false" (no active className). Post-mount, exactly
 * one segment lights up. After fix, this test is GREEN; before fix the
 * data-active attribute does not exist and the assertion is RED.
 *
 * Vitest cannot fully reproduce production React's hydration semantics
 * (vitest uses dev React; mismatch warnings differ from prod). This test
 * asserts the *contract* that the fix establishes: a single source of
 * truth (`data-active`) for the active visual state, regardless of how
 * hydration resolved className. The Playwright e2e suite covers the
 * full prod-build hydration path.
 */

const STORAGE_KEY = "soleur:theme";

const EXPECTED_ACCESSIBLE_NAME: Record<"dark" | "light" | "system", string> = {
  dark: "Dark theme",
  light: "Light theme",
  system: "Follow system theme",
};

function makeMatchMedia(initialDarkMatches: boolean) {
  const list = {
    matches: initialDarkMatches,
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  return () => list;
}

describe("ThemeToggle — SSR/hydration mounted-gate contract", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
    vi.stubGlobal("matchMedia", makeMatchMedia(true));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe.each(["dark", "light", "system"] as const)(
    "stored theme = %s",
    (stored) => {
      it("post-mount: exactly one segment has data-active='true' and it is the stored theme", () => {
        localStorage.setItem(STORAGE_KEY, stored);
        // Simulate the inline NoFoucScript having written dataset.theme.
        document.documentElement.dataset.theme = stored;

        render(
          <ThemeProvider>
            <ThemeToggle collapsed={false} />
          </ThemeProvider>,
        );

        const group = screen.getByRole("group", { name: "Theme" });
        const buttons = Array.from(group.querySelectorAll("button"));
        const active = buttons.filter(
          (b) => b.getAttribute("data-active") === "true",
        );

        expect(active).toHaveLength(1);
        expect(active[0]?.getAttribute("aria-label")).toBe(
          EXPECTED_ACCESSIBLE_NAME[stored],
        );
      });

      it("post-mount: at most one segment has the active className token (single-active visual invariant)", () => {
        localStorage.setItem(STORAGE_KEY, stored);
        document.documentElement.dataset.theme = stored;

        render(
          <ThemeProvider>
            <ThemeToggle collapsed={false} />
          </ThemeProvider>,
        );

        const group = screen.getByRole("group", { name: "Theme" });
        const buttons = Array.from(group.querySelectorAll("button"));
        const withActiveBg = buttons.filter((b) =>
          b.className.includes("bg-soleur-bg-surface-1"),
        );

        expect(withActiveBg).toHaveLength(1);
        expect(withActiveBg[0]?.getAttribute("aria-label")).toBe(
          EXPECTED_ACCESSIBLE_NAME[stored],
        );
      });
    },
  );

  it("collapsed cycle button exposes data-active='true' for the current theme post-mount", () => {
    localStorage.setItem(STORAGE_KEY, "dark");
    document.documentElement.dataset.theme = "dark";

    render(
      <ThemeProvider>
        <ThemeToggle collapsed={true} />
      </ThemeProvider>,
    );

    const cycle = screen.getByTestId("theme-cycle-button");
    expect(cycle.getAttribute("data-active")).toBe("true");
    expect(cycle.getAttribute("data-theme-current")).toBe("dark");
  });
});
