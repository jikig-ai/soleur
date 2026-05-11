import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

let mockPathname = "/dashboard/settings";

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname,
}));

import { SettingsShell } from "@/components/settings/settings-shell";

describe("Settings sidebar collapse", () => {
  beforeEach(() => {
    mockPathname = "/dashboard/settings";
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it("renders a collapse toggle button for settings sidebar", () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    expect(screen.getByLabelText("Collapse settings nav")).toBeInTheDocument();
  });

  it("toggles settings sidebar on click", async () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    const toggle = screen.getByLabelText("Collapse settings nav");
    await userEvent.click(toggle);
    expect(screen.getByLabelText("Expand settings nav")).toBeInTheDocument();
  });

  it("Cmd+B toggles settings sidebar on /dashboard/settings routes", () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    expect(screen.getByLabelText("Collapse settings nav")).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand settings nav")).toBeInTheDocument();
  });

  it("Ctrl+B toggles settings sidebar", () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    fireEvent.keyDown(document, { key: "b", ctrlKey: true });
    expect(screen.getByLabelText("Expand settings nav")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in an input", () => {
    render(
      <SettingsShell>
        <input data-testid="test-input" />
      </SettingsShell>,
    );
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse settings nav")).toBeInTheDocument();
  });

  it("mobile bottom tab bar is unchanged", () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    const mobileBar = document.querySelector(".md\\:hidden");
    expect(mobileBar).toBeInTheDocument();
  });

  // Alignment contract — mirrors KB layout precedent at
  // apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx:318-328.
  // If KB's expand-chevron recipe changes, update these assertions to match.
  describe("expand button alignment with main nav chevron", () => {
    it("expand button has KB-style absolute positioning classes when collapsed", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      expect(expandBtn).toHaveClass("absolute", "left-2", "top-5", "z-10", "h-6", "w-6");
    });

    it("expand button icon size matches main nav chevron (h-4 w-4)", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      const svg = expandBtn.querySelector("svg");
      expect(svg).not.toBeNull();
      expect(svg).toHaveClass("h-4", "w-4");
    });

    it("expand button has no border (matches main nav toggle)", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      expect(expandBtn.className).not.toMatch(/\bborder(-|\s|$)/);
    });

    it("expand button is hidden on mobile (hidden md:flex)", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      expect(expandBtn).toHaveClass("hidden", "md:flex");
    });

    it("content area parent has relative positioning so absolute button anchors correctly", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      const positionedAncestor = expandBtn.closest(".relative");
      expect(positionedAncestor).not.toBeNull();
    });

    it("exactly one expand button exists after collapsing", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      expect(screen.getAllByLabelText("Expand settings nav").length).toBe(1);
    });
  });

  // Alignment contract for the expanded-state collapse chevron.
  // Main nav header at apps/web-platform/app/(dashboard)/layout.tsx uses py-5;
  // the settings <nav> must match so both <` chevrons land on the same y-row.
  describe("collapse button alignment with main nav chevron (expanded state)", () => {
    it("nav wrapper uses py-5 to align chevron y-origin with main nav header", () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      const collapseBtn = screen.getByLabelText("Collapse settings nav");
      const navEl = collapseBtn.closest("nav");
      expect(navEl).not.toBeNull();
      expect(navEl).toHaveClass("py-5");
      expect(navEl?.className).not.toMatch(/\bpy-10\b/);
    });

    it("collapse button keeps h-6 w-6 geometry matching main nav toggle", () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      const btn = screen.getByLabelText("Collapse settings nav");
      expect(btn).toHaveClass("h-6", "w-6", "rounded");
      expect(btn.className).not.toMatch(/\bborder(-|\s|$)/);
      const svg = btn.querySelector("svg");
      expect(svg).toHaveClass("h-4", "w-4");
    });

    it("settings header row matches main sidebar brand row height (min-h-7)", () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      const collapseBtn = screen.getByLabelText("Collapse settings nav");
      const headerRow = collapseBtn.parentElement;
      expect(headerRow).not.toBeNull();
      expect(headerRow).toHaveClass("min-h-7");
      expect(headerRow).toHaveClass("flex", "items-center", "justify-between");
    });
  });

  describe("content area collapses cleanly when sidebar is closed", () => {
    it("collapsed nav has zero rendered width contribution (no border, no width, overflow hidden)", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const navEl = document.querySelector("nav");
      expect(navEl).not.toBeNull();
      expect(navEl?.className).toMatch(/\bmd:w-0\b/);
      expect(navEl?.className).toMatch(/\bmd:overflow-hidden\b/);
      expect(navEl?.className).toMatch(/\bmd:border-r-0\b/);
    });

    it("nav padding is constant across open/collapsed so inner content doesn't jump to (0, 0) when collapsing", async () => {
      const { rerender } = render(<SettingsShell><div>content</div></SettingsShell>);
      const navEl = document.querySelector("nav");
      expect(navEl?.className).toMatch(/\bpx-4\b/);
      expect(navEl?.className).toMatch(/\bpy-5\b/);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      rerender(<SettingsShell><div>content</div></SettingsShell>);
      const navCollapsed = document.querySelector("nav");
      // Padding MUST remain across the toggle — width animates while overflow-hidden
      // clips the still-padded inner content. Removing the padding on collapse causes
      // the SETTINGS label + nav items to flash to (0, 0) at the start of the transition.
      expect(navCollapsed?.className).toMatch(/\bpx-4\b/);
      expect(navCollapsed?.className).toMatch(/\bpy-5\b/);
    });

    it("collapsed content area pl matches sidebar-width + open-padding to keep centered text stationary", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      const contentArea = expandBtn.parentElement;
      expect(contentArea).not.toBeNull();
      // Sidebar = w-48 (12rem) + open pad = md:px-10 (2.5rem) → collapsed pl must equal 14.5rem
      // so the `mx-auto max-w-2xl` inner content's screen-x position is identical in both states.
      expect(contentArea?.className).toMatch(/(?:^|\s)md:pl-\[14\.5rem\](?:\s|$)/);
    });

    it("content area transitions padding in sync with sidebar width (200ms ease-out)", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      const expandBtn = screen.getByLabelText("Expand settings nav");
      const contentArea = expandBtn.parentElement;
      expect(contentArea).not.toBeNull();
      expect(contentArea?.className).toMatch(/(?:^|\s)md:transition-\[padding\](?:\s|$)/);
      expect(contentArea?.className).toMatch(/\bmd:duration-200\b/);
      expect(contentArea?.className).toMatch(/\bmd:ease-out\b/);
    });
  });
});
