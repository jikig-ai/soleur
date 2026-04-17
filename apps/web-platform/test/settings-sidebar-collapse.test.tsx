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
      const parent = expandBtn.parentElement;
      expect(parent).not.toBeNull();
      expect(parent!).toHaveClass("relative");
    });

    it("exactly one expand button exists after collapsing", async () => {
      render(<SettingsShell><div>content</div></SettingsShell>);
      await userEvent.click(screen.getByLabelText("Collapse settings nav"));
      expect(screen.getAllByLabelText("Expand settings nav").length).toBe(1);
    });
  });
});
