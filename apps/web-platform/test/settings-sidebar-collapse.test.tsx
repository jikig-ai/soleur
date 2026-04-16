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
});
