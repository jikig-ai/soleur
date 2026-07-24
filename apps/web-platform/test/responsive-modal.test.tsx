import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { ResponsiveModal } from "@/components/ui/responsive-modal";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function stubViewport(isDesktop: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: isDesktop,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

describe("ResponsiveModal", () => {
  it("renders children when open and nothing when closed", () => {
    const { rerender } = render(
      <ResponsiveModal open aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    expect(screen.getByText("Body")).toBeTruthy();
    rerender(
      <ResponsiveModal open={false} aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    expect(screen.queryByText("Body")).toBeNull();
  });

  it("closes on Escape", () => {
    const onClose = vi.fn();
    render(
      <ResponsiveModal open onClose={onClose} aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    fireEvent.keyDown(window, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("closes on backdrop click by default but not when disabled", () => {
    const onClose = vi.fn();
    const { rerender } = render(
      <ResponsiveModal open onClose={onClose} aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    // The backdrop is the presentation wrapper around the dialog.
    fireEvent.click(screen.getByRole("presentation"));
    expect(onClose).toHaveBeenCalledTimes(1);

    onClose.mockClear();
    rerender(
      <ResponsiveModal open onClose={onClose} closeOnBackdrop={false} aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    fireEvent.click(screen.getByRole("presentation"));
    expect(onClose).not.toHaveBeenCalled();
  });

  it("applies the desktop max-width on wide viewports", () => {
    stubViewport(true);
    render(
      <ResponsiveModal open aria-label="Test" desktopMaxWidth="max-w-lg">
        <p>Body</p>
      </ResponsiveModal>,
    );
    expect(screen.getByRole("dialog").className).toContain("max-w-lg");
  });

  it("moves focus into the panel on open (honors aria-modal)", () => {
    render(
      <ResponsiveModal open aria-label="Test">
        <button type="button">First action</button>
        <button type="button">Second action</button>
      </ResponsiveModal>,
    );
    const dialog = screen.getByRole("dialog");
    // Focus lands on the first focusable inside the dialog, not the body.
    expect(dialog.contains(document.activeElement)).toBe(true);
    expect(document.activeElement).toBe(
      screen.getByRole("button", { name: "First action" }),
    );
  });

  it("renders the bottom-sheet (drag-handle, no max-width) on narrow viewports", () => {
    stubViewport(false);
    render(
      <ResponsiveModal open aria-label="Test">
        <p>Body</p>
      </ResponsiveModal>,
    );
    const dialog = screen.getByRole("dialog");
    expect(dialog.className).toContain("rounded-t-2xl");
    expect(dialog.className).not.toContain("max-w-md");
  });
});
