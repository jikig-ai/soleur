import { render, screen, cleanup } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { ThemeProvider, useTheme } from "@/components/theme/theme-provider";

const STORAGE_KEY = "soleur:theme";

function Probe() {
  const { theme, resolvedTheme } = useTheme();
  return (
    <div>
      <span data-testid="theme">{theme}</span>
      <span data-testid="resolved">{resolvedTheme}</span>
    </div>
  );
}

/**
 * Mount <ThemeProvider> in the production "no-bootstrap, SSR-hydration" state:
 * the inline <NoFoucScript> did NOT run (dataset.theme absent), the user has a
 * durable stored choice, and React's lazy state initializers landed on
 * "system" (because in production they run server-side where window — and thus
 * localStorage — is undefined; React's first client render reuses that snapshot).
 *
 * Faithfully simulating "init saw no durable store, the post-mount effect does"
 * requires a synchronous discriminator (render + effects flush in one act()).
 * We use REAL localStorage (empty at init → lazy initializers resolve "system")
 * and write the stored value via the matchMedia getter: getSystemPreference()
 * touches matchMedia during the second lazy initializer — strictly AFTER both
 * initializers' storage reads and strictly BEFORE the client-only first-mount
 * effect. So the initializers observe no stored value (→ state "system"), while
 * the effect reads the user's real choice from a genuinely-populated store. No
 * getItem spy means no mock state can bleed across tests.
 */
function mountScenario({ stored, osDark }: { stored: string; osDark: boolean }): void {
  // No-bootstrap precondition: no data-theme attribute, empty store at init.
  document.documentElement.removeAttribute("data-theme");
  localStorage.clear();

  const mql = {
    get matches() {
      // First read is inside getSystemPreference() during the second lazy
      // initializer — post-init, pre-effect. Populate the durable store now so
      // only the client-side first-mount effect can observe the stored choice.
      localStorage.setItem(STORAGE_KEY, stored);
      return osDark;
    },
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  vi.stubGlobal("matchMedia", () => mql);

  render(
    <ThemeProvider>
      <Probe />
    </ThemeProvider>,
  );
}

describe("explicit theme choice survives reload (no-bootstrap SSR-hydration path)", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
    const stale = document.head.querySelector("style#__soleur-no-transition");
    if (stale) stale.remove();
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("stored 'light' + OS dark + no bootstrap → palette resolves light, not the OS preference", () => {
    mountScenario({ stored: "light", osDark: true });

    // The real invariant: the resolved palette follows the stored choice, NOT
    // the OS preference. Before the fix, the first-mount else-branch writes
    // React's "system" snapshot, so dataset.theme === "system" and the
    // @media (prefers-color-scheme) cascade drives the palette to OS dark.
    expect(document.documentElement.dataset.theme).toBe("light");
    // State-sync invariant (avoids reintroducing the #3318 wrong-segment bug).
    expect(screen.getByTestId("theme").textContent).toBe("light");
    expect(screen.getByTestId("resolved").textContent).toBe("light");
  });

  it("stored 'dark' + OS light + no bootstrap → palette resolves dark", () => {
    mountScenario({ stored: "dark", osDark: false });

    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(screen.getByTestId("theme").textContent).toBe("dark");
    expect(screen.getByTestId("resolved").textContent).toBe("dark");
  });

  it("control: stored 'system' + OS light + no bootstrap → still follows OS (light)", () => {
    mountScenario({ stored: "system", osDark: false });

    // Genuine system-follow is preserved: data-theme stays "system" so the
    // @media block tracks the OS, and resolved follows OS light.
    expect(document.documentElement.dataset.theme).toBe("system");
    expect(screen.getByTestId("theme").textContent).toBe("system");
    expect(screen.getByTestId("resolved").textContent).toBe("light");
  });
});
