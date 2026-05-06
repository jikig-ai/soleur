import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { ThemeToggle } from "@/components/theme/theme-toggle";

const STORAGE_KEY = "soleur:theme";

function makeMatchMedia(initialDarkMatches: boolean) {
  const list = {
    matches: initialDarkMatches,
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  return () => list;
}

function renderToggle() {
  return render(
    <ThemeProvider>
      <ThemeToggle />
    </ThemeProvider>,
  );
}

describe("ThemeToggle", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
    vi.stubGlobal("matchMedia", makeMatchMedia(true));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("renders three segments with the spec-defined accessible names", () => {
    renderToggle();

    expect(screen.getByRole("button", { name: "Dark theme" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Light theme" })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Follow system theme" }),
    ).toBeInTheDocument();
  });

  it("each segment exposes a tooltip-friendly title with the human label", () => {
    renderToggle();

    expect(screen.getByRole("button", { name: "Dark theme" })).toHaveAttribute(
      "title",
      "Dark",
    );
    expect(screen.getByRole("button", { name: "Light theme" })).toHaveAttribute(
      "title",
      "Light",
    );
    expect(
      screen.getByRole("button", { name: "Follow system theme" }),
    ).toHaveAttribute("title", "System");
  });

  it("aria-pressed reflects the active theme; default is system", () => {
    renderToggle();

    const dark = screen.getByRole("button", { name: "Dark theme" });
    const light = screen.getByRole("button", { name: "Light theme" });
    const system = screen.getByRole("button", { name: "Follow system theme" });

    expect(dark.getAttribute("aria-pressed")).toBe("false");
    expect(light.getAttribute("aria-pressed")).toBe("false");
    expect(system.getAttribute("aria-pressed")).toBe("true");
  });

  it("clicking a segment changes the active theme and persists to localStorage", () => {
    renderToggle();

    const light = screen.getByRole("button", { name: "Light theme" });
    fireEvent.click(light);

    expect(light.getAttribute("aria-pressed")).toBe("true");
    expect(
      screen.getByRole("button", { name: "Dark theme" }).getAttribute("aria-pressed"),
    ).toBe("false");
    expect(localStorage.getItem(STORAGE_KEY)).toBe("light");
    expect(document.documentElement.dataset.theme).toBe("light");
  });

  it("renders icons-only by default — visible label text is absent", () => {
    renderToggle();

    // The accessible names come from aria-label, NOT visible text content.
    // No segment should render the literal labels "Dark", "Light", "System"
    // as visible text — only icons + tooltip via title attribute.
    const dark = screen.getByRole("button", { name: "Dark theme" });
    const light = screen.getByRole("button", { name: "Light theme" });
    const system = screen.getByRole("button", { name: "Follow system theme" });

    // textContent must NOT contain the human labels (they live only in
    // aria-label + title). Icon SVGs have no text nodes.
    expect(dark.textContent ?? "").not.toMatch(/Dark/);
    expect(light.textContent ?? "").not.toMatch(/Light/);
    expect(system.textContent ?? "").not.toMatch(/System/);
  });

  it("ArrowRight from the active segment moves selection to the next segment", () => {
    renderToggle();

    const group = screen.getByRole("group", { name: "Theme" });
    // Default starts at 'system' (index 2). ArrowRight wraps to 'dark' (0).
    fireEvent.keyDown(group, { key: "ArrowRight" });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("dark");
    expect(
      screen.getByRole("button", { name: "Dark theme" }).getAttribute("aria-pressed"),
    ).toBe("true");
  });

  it("ArrowLeft from the active segment moves selection to the previous segment", () => {
    renderToggle();

    // 'system' (index 2) → ArrowLeft → 'light' (index 1).
    const group = screen.getByRole("group", { name: "Theme" });
    fireEvent.keyDown(group, { key: "ArrowLeft" });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("light");
  });

  it("Home selects the first segment and End the last", () => {
    renderToggle();
    const group = screen.getByRole("group", { name: "Theme" });

    fireEvent.keyDown(group, { key: "Home" });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("dark");

    fireEvent.keyDown(group, { key: "End" });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("system");
  });
});
