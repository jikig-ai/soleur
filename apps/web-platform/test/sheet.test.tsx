import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Sheet } from "@/components/ui/sheet";

/**
 * Stub matchMedia. When `desktop` is true, the desktop media query
 * `(min-width: 768px)` matches.
 */
function installMatchMedia(desktop: boolean) {
  vi.stubGlobal(
    "matchMedia",
    vi.fn((query: string) => ({
      matches: desktop && query.includes("min-width"),
      media: query,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  );
}

describe("Sheet", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
    // Mock innerHeight for snap point math (100vh = 800px; 10vh = 80px).
    Object.defineProperty(window, "innerHeight", {
      writable: true,
      configurable: true,
      value: 800,
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("renders nothing when closed", () => {
    installMatchMedia(true);
    render(
      <Sheet open={false} onClose={() => {}} aria-label="Test sheet">
        <p>hidden content</p>
      </Sheet>,
    );
    expect(screen.queryByText("hidden content")).toBeNull();
  });

  it("renders content via portal when open", () => {
    installMatchMedia(true);
    render(
      <Sheet open={true} onClose={() => {}} aria-label="Test sheet">
        <p>visible content</p>
      </Sheet>,
    );
    expect(screen.getByText("visible content")).toBeInTheDocument();
  });

  it("renders desktop sheet inline (not portaled to body, not fixed)", () => {
    installMatchMedia(true);
    const { container } = render(
      <div data-testid="parent-container">
        <Sheet open={true} onClose={() => {}} aria-label="Desktop sheet">
          <p>x</p>
        </Sheet>
      </div>,
    );
    const panel = screen.getByRole("dialog", { name: "Desktop sheet" });
    // Should render inside the parent container, not portaled to document.body
    const parent = container.querySelector("[data-testid='parent-container']");
    expect(parent?.contains(panel)).toBe(true);
    // Should NOT have fixed positioning
    expect(panel.className).not.toMatch(/\bfixed\b/);
    // Should have shrink-0 for flex layout
    expect(panel.className).toMatch(/shrink-0/);
    // Desktop has no drag handle
    expect(screen.queryByLabelText(/resize panel/i)).toBeNull();
  });

  it("renders with bottom-sheet classes and drag handle on mobile", () => {
    installMatchMedia(false);
    render(
      <Sheet open={true} onClose={() => {}} aria-label="Mobile sheet">
        <p>x</p>
      </Sheet>,
    );
    const panel = screen.getByRole("dialog", { name: "Mobile sheet" });
    expect(panel.className).toMatch(/bottom-0/);
    expect(screen.getByLabelText(/resize panel/i)).toBeInTheDocument();
  });

  it("invokes onClose when Escape is pressed while focused inside", async () => {
    installMatchMedia(true);
    const onClose = vi.fn();
    render(
      <Sheet open={true} onClose={onClose} aria-label="Esc sheet">
        <button>inside</button>
      </Sheet>,
    );
    const btn = screen.getByText("inside");
    btn.focus();
    await userEvent.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("invokes onClose when mobile drag ends below 10vh threshold", () => {
    installMatchMedia(false);
    const onClose = vi.fn();
    render(
      <Sheet open={true} onClose={onClose} aria-label="Drag close sheet">
        <p>x</p>
      </Sheet>,
    );
    const handle = screen.getByLabelText(/resize panel/i);
    // Start drag near top of sheet, release below collapsed threshold.
    // innerHeight = 800, 10vh = 80. Pointer releasing at y=790 means
    // sheet height would be ~10px — well below the 80px close threshold.
    fireEvent.pointerDown(handle, { clientY: 200, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientY: 790, pointerId: 1 });
    fireEvent.pointerUp(handle, { clientY: 790, pointerId: 1 });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("does NOT invoke onClose when mobile drag ends above close threshold", () => {
    installMatchMedia(false);
    const onClose = vi.fn();
    render(
      <Sheet open={true} onClose={onClose} aria-label="Drag snap sheet">
        <p>x</p>
      </Sheet>,
    );
    const handle = screen.getByLabelText(/resize panel/i);
    // Start drag, release at ~400 (halfway) — sheet snaps, does not close.
    fireEvent.pointerDown(handle, { clientY: 200, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientY: 400, pointerId: 1 });
    fireEvent.pointerUp(handle, { clientY: 400, pointerId: 1 });
    expect(onClose).not.toHaveBeenCalled();
  });
});
