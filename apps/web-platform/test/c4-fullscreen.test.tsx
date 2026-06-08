import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// Mock the browser-only LikeC4 runtime. Unlike c4-shared.test.tsx (which returns
// useLikeC4ViewModel: () => null to exercise the "View not found" branch), this
// suite MUST return a non-null view model so ViewCanvas renders the diagram +
// the new expand control. The LikeC4Diagram stub renders a Code/Concierge-free
// marker so AC4's "no owner-only affordance in the overlay" assertion is real.
vi.mock("@likec4/diagram", () => ({
  LikeC4ModelProvider: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="likec4-provider">{children}</div>
  ),
  LikeC4Diagram: () => <div data-testid="likec4-diagram">diagram-canvas</div>,
  useLikeC4ViewModel: () => ({ $view: { id: "index" } }),
}));
vi.mock("@likec4/core/model", () => ({
  LikeC4Model: { create: () => ({ views: { index: {} } }) },
}));
vi.mock("@codemirror/theme-one-dark", () => ({ oneDark: {} }));
vi.mock("@uiw/react-codemirror", () => ({
  default: () => <textarea data-testid="cm" />,
}));

import { C4Canvas } from "@/components/kb/c4-shared";

function renderCanvas() {
  return render(
    <C4Canvas dump={{ views: { index: {} } }} initialViewId="index" />,
  );
}

beforeEach(() => {
  vi.restoreAllMocks();
});
afterEach(() => {
  // Defensive: ensure scroll-lock never leaks across tests.
  document.body.style.overflow = "";
});

describe("C4Canvas — fullscreen / expand control", () => {
  it("AC1: renders an Enter-fullscreen expand button", () => {
    renderCanvas();
    expect(
      screen.getByRole("button", { name: /enter fullscreen/i }),
    ).toBeTruthy();
  });

  it("AC2: activating expand renders a fixed inset-0 role=dialog aria-modal overlay", () => {
    renderCanvas();
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    const dialog = screen.getByRole("dialog");
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(dialog.className).toMatch(/fixed/);
    expect(dialog.className).toMatch(/inset-0/);
  });

  it("AC3: overlay closes on Escape and via the Exit-fullscreen button", async () => {
    renderCanvas();
    // Open, then Escape.
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    expect(screen.queryByRole("dialog")).toBeTruthy();
    fireEvent.keyDown(window, { key: "Escape" });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    // Re-open, then click Exit fullscreen.
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    fireEvent.click(screen.getByRole("button", { name: /exit fullscreen/i }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("AC4: the overlay exposes no Code/Concierge/Save affordance", () => {
    renderCanvas();
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    const dialog = screen.getByRole("dialog");
    // The overlay re-parents ONLY C4Canvas (diagram). No owner-only controls.
    expect(dialog.textContent || "").not.toMatch(/Concierge|Save|Code\b/i);
    expect(
      dialog.querySelector('[data-testid="cm"]'),
    ).toBeNull();
  });

  it("AC5: the overlay subtree is wrapped in .soleur-c4 (theme scoping)", () => {
    renderCanvas();
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    const dialog = screen.getByRole("dialog");
    // Either the dialog itself or an ancestor/descendant carries .soleur-c4.
    const scoped =
      dialog.classList.contains("soleur-c4") ||
      dialog.closest(".soleur-c4") !== null ||
      dialog.querySelector(".soleur-c4") !== null;
    expect(scoped).toBe(true);
  });

  it("AC6: body scroll is locked while open and restored on close", async () => {
    document.body.style.overflow = "auto";
    renderCanvas();
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    expect(document.body.style.overflow).toBe("hidden");
    fireEvent.keyDown(window, { key: "Escape" });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(document.body.style.overflow).toBe("auto");
  });

  it("AC10: focus moves into the overlay on open", async () => {
    renderCanvas();
    fireEvent.click(screen.getByRole("button", { name: /enter fullscreen/i }));
    const dialog = screen.getByRole("dialog");
    await waitFor(() =>
      expect(dialog.contains(document.activeElement)).toBe(true),
    );
  });

  it("renders the diagram canvas inline before expanding", () => {
    renderCanvas();
    expect(screen.getByTestId("likec4-diagram")).toBeTruthy();
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});
