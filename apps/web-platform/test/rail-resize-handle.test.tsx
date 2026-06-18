import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { RailResizeHandle } from "@/components/dashboard/rail-resize-handle";

// Widenable KB rail (amendment). The handle is a thin right-edge separator that
// drives the aside width via pointer drag + Arrow-key nudge. It is a11y-first
// (role=separator, aria-orientation, aria-valuenow/min/max) so keyboard / AT
// users can widen too. Transient drag updates fire onWidthChange; the persisted
// commit fires once on pointerup (and on each keyboard nudge).

function setup(overrides: Partial<React.ComponentProps<typeof RailResizeHandle>> = {}) {
  const onWidthChange = vi.fn();
  const onCommit = vi.fn();
  const onCollapse = vi.fn();
  render(
    <RailResizeHandle
      width={224}
      min={224}
      max={480}
      onWidthChange={onWidthChange}
      onCommit={onCommit}
      onCollapse={onCollapse}
      {...overrides}
    />,
  );
  return {
    onWidthChange,
    onCommit,
    onCollapse,
    handle: screen.getByTestId("kb-rail-resize-handle"),
  };
}

describe("RailResizeHandle", () => {
  beforeEach(() => vi.clearAllMocks());

  it("renders the vertical-bar grip", () => {
    setup();
    expect(screen.getByTestId("kb-rail-resize-grip")).toBeInTheDocument();
  });

  it("defaults the accessible name to the KB literal (AC5)", () => {
    const { handle } = setup();
    expect(handle).toHaveAttribute("aria-label", "Resize knowledge base sidebar");
  });

  it("accepts an ariaLabel override for non-KB rails (AC5)", () => {
    const { handle } = setup({ ariaLabel: "Resize sidebar" });
    expect(handle).toHaveAttribute("aria-label", "Resize sidebar");
  });

  it("renders a11y separator semantics", () => {
    const { handle } = setup();
    expect(handle).toHaveAttribute("role", "separator");
    expect(handle).toHaveAttribute("aria-orientation", "vertical");
    expect(handle).toHaveAttribute("aria-valuenow", "224");
    expect(handle).toHaveAttribute("aria-valuemin", "224");
    expect(handle).toHaveAttribute("aria-valuemax", "480");
    expect(handle).toHaveAttribute("tabindex", "0");
  });

  it("fires onWidthChange with the clamped delta during a pointer drag, and commits once on pointerup", () => {
    const { handle, onWidthChange, onCommit } = setup();
    fireEvent.pointerDown(handle, { clientX: 100, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientX: 200, pointerId: 1 }); // +100 → 324
    expect(onWidthChange).toHaveBeenLastCalledWith(324);
    expect(onCommit).not.toHaveBeenCalled();
    fireEvent.pointerUp(handle, { clientX: 200, pointerId: 1 });
    expect(onCommit).toHaveBeenCalledWith(324);
  });

  it("clamps the drag to [min, max] (AC11)", () => {
    const { handle, onWidthChange } = setup();
    fireEvent.pointerDown(handle, { clientX: 100, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientX: 9999, pointerId: 1 }); // way past max
    expect(onWidthChange).toHaveBeenLastCalledWith(480);
    fireEvent.pointerMove(handle, { clientX: -9999, pointerId: 1 }); // way below min
    expect(onWidthChange).toHaveBeenLastCalledWith(224);
  });

  it("ignores pointermove when no drag is in progress", () => {
    const { handle, onWidthChange } = setup();
    fireEvent.pointerMove(handle, { clientX: 400, pointerId: 1 });
    expect(onWidthChange).not.toHaveBeenCalled();
  });

  it("nudges wider on ArrowRight and narrower on ArrowLeft, clamped, committing each step", () => {
    const { handle, onCommit } = setup({ width: 300 });
    fireEvent.keyDown(handle, { key: "ArrowRight" });
    expect(onCommit).toHaveBeenLastCalledWith(316);
    fireEvent.keyDown(handle, { key: "ArrowLeft" });
    expect(onCommit).toHaveBeenLastCalledWith(284);
  });

  it("does not nudge below min via ArrowLeft", () => {
    const { handle, onCommit } = setup({ width: 224 });
    fireEvent.keyDown(handle, { key: "ArrowLeft" });
    expect(onCommit).toHaveBeenLastCalledWith(224);
  });

  // FR3-Alternative: double-click the rail resizer collapses the sidebar (an
  // additive accelerator beside the kept collapse button).

  it("collapses on double-click (AC5)", () => {
    const { handle, onCollapse } = setup();
    fireEvent.doubleClick(handle);
    expect(onCollapse).toHaveBeenCalledTimes(1);
  });

  it("a resize drag does not collapse the rail (AC6) — a drag emits no dblclick", () => {
    // A real resize drag moves the pointer past the browser's click threshold,
    // so it never produces the dblclick that collapse listens for. We model that
    // by driving the full drag gesture WITHOUT a doubleClick event and asserting
    // collapse never fires.
    const { handle, onCollapse } = setup();
    fireEvent.pointerDown(handle, { clientX: 100, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientX: 200, pointerId: 1 }); // 100px drag
    fireEvent.pointerUp(handle, { clientX: 200, pointerId: 1 });
    expect(onCollapse).not.toHaveBeenCalled();
  });

  it("does not commit a no-op width when the rail did not actually move (AC6)", () => {
    const { handle, onCommit } = setup();
    fireEvent.pointerDown(handle, { clientX: 100, pointerId: 1 });
    fireEvent.pointerUp(handle, { clientX: 100, pointerId: 1 }); // no movement
    expect(onCommit).not.toHaveBeenCalled();
  });

  it("does not throw on double-click when onCollapse is not provided", () => {
    const onWidthChange = vi.fn();
    const onCommit = vi.fn();
    render(
      <RailResizeHandle
        width={224}
        min={224}
        max={480}
        onWidthChange={onWidthChange}
        onCommit={onCommit}
      />,
    );
    const handle = screen.getByTestId("kb-rail-resize-handle");
    expect(() => fireEvent.doubleClick(handle)).not.toThrow();
  });
});
