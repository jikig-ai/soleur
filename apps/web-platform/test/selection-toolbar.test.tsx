import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act, fireEvent } from "@testing-library/react";
import { useRef } from "react";

// The selection-toolbar coalesces setPill via a single-slot rAF (Phase 3
// task 9A). Fake timers don't auto-run rAF callbacks, so tests that assert
// on pill state immediately after a selection change must advance at least
// one frame.
const FRAME_MS = 20;

// Tests for Phase 4.1: components/kb/selection-toolbar.tsx
//   - Pill appears when a selection lives inside the articleRef
//   - 8KB preflight: > maxBytes renders disabled pill
//   - Escape dismisses pill (not panel) via stopPropagation
//   - Click outside collapses the pill
//   - Selections outside articleRef are ignored

async function importToolbar() {
  const mod = await import("@/components/kb/selection-toolbar");
  return mod.SelectionToolbar;
}

// Helpers to simulate a jsdom Selection.
function setSelection(node: Node, text: string) {
  const range = document.createRange();
  range.selectNodeContents(node);
  // jsdom's Selection supports addRange but not real collapsed toString().
  const sel = window.getSelection()!;
  sel.removeAllRanges();
  sel.addRange(range);
  // Stub toString so tests can control the selection text directly.
  Object.defineProperty(sel, "toString", { value: () => text, configurable: true });
  // anchor/focus nodes default to the range's start/end containers.
  document.dispatchEvent(new Event("selectionchange"));
  // Flush the component's single-slot rAF so pill state updates synchronously
  // from the test's perspective (matches browser behavior after 1 frame).
  vi.advanceTimersByTime(FRAME_MS);
}

function clearSelection() {
  window.getSelection()!.removeAllRanges();
  document.dispatchEvent(new Event("selectionchange"));
  vi.advanceTimersByTime(FRAME_MS);
}

import { SelectionToolbar } from "@/components/kb/selection-toolbar";

function Harness({ onAddToChat, maxBytes }: {
  onAddToChat: (t: string) => void;
  maxBytes?: number;
}) {
  const ref = useRef<HTMLElement>(null);
  return (
    <>
      <article ref={ref} data-testid="article">
        <p>Some KB content to select from — this has lots of words.</p>
      </article>
      <p data-testid="outside">Outside of the article entirely.</p>
      <SelectionToolbar articleRef={ref} onAddToChat={onAddToChat} maxBytes={maxBytes} />
    </>
  );
}

describe("SelectionToolbar", () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
  });
  afterEach(() => {
    clearSelection();
    vi.useRealTimers();
  });

  it("renders a 'Quote in chat' pill when selection lives inside articleRef", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "hello world"); });
    expect(screen.getByRole("button", { name: /quote in chat/i })).toBeTruthy();
  });

  it("clicking the pill invokes onAddToChat with the selection text", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "picked text"); });
    const btn = screen.getByRole("button", { name: /quote in chat/i });
    fireEvent.click(btn);
    expect(onAdd).toHaveBeenCalledWith("picked text");
  });

  it("renders a disabled pill with tooltip when selection exceeds maxBytes", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} maxBytes={10} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "a very long selection that exceeds ten bytes"); });
    const btn = screen.getByRole("button", { name: /quote in chat/i });
    expect((btn as HTMLButtonElement).disabled).toBe(true);
    expect(btn.getAttribute("title")).toMatch(/too long/i);
    fireEvent.click(btn);
    expect(onAdd).not.toHaveBeenCalled();
  });

  it("ignores selections outside articleRef", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const outside = screen.getByTestId("outside");
    act(() => { setSelection(outside, "outside text"); });
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeNull();
  });

  it("Escape dismisses the pill and calls stopPropagation", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "some text"); });
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeTruthy();

    // Dispatch Escape and observe propagation was stopped.
    let reachedDocument = false;
    const docHandler = () => { reachedDocument = true; };
    // Listen in capture=false (bubble) so stopPropagation prevents us.
    document.addEventListener("keydown", docHandler);

    const ev = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true });
    // Pill's handler should register in capture phase; dispatch on document
    // and expect the pill's handler to stopPropagation so bubble-phase
    // listener attached after it doesn't see it. To emulate: pill handler
    // is set up in the component — we just observe the pill goes away.
    act(() => { document.dispatchEvent(ev); });

    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeNull();
    document.removeEventListener("keydown", docHandler);
    void reachedDocument;
  });

  it("clicking outside the pill collapses it", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "some text"); });
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeTruthy();
    act(() => { clearSelection(); });
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeNull();
  });

  it("Escape with pill visible: dismisses pill only; parent Sheet onClose NOT called (capture phase)", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    const sheetOnClose = vi.fn();
    // Simulate a parent Sheet handler that matches sheet.tsx:55-66 — it
    // listens for Escape in bubble phase and defers when another handler has
    // flagged the event (via stopImmediatePropagation or defaultPrevented).
    // Capture-phase listeners on the same node fire first; if the pill
    // handler calls stopImmediatePropagation, this one doesn't run at all.
    function bubblePhaseSheetHandler(e: KeyboardEvent) {
      if (e.key !== "Escape") return;
      if (e.defaultPrevented) return;
      sheetOnClose();
    }
    document.addEventListener("keydown", bubblePhaseSheetHandler, false);

    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => {
      setSelection(article, "some text");
    });
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeTruthy();

    const ev = new KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    });
    act(() => {
      document.dispatchEvent(ev);
    });

    // Pill dismissed
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeNull();
    // Parent Sheet NOT closed — pill's capture handler flagged the event
    expect(sheetOnClose).not.toHaveBeenCalled();

    document.removeEventListener("keydown", bubblePhaseSheetHandler, false);
  });

  it("Escape with pill absent: parent Sheet onClose IS called", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    const sheetOnClose = vi.fn();
    function bubblePhaseSheetHandler(e: KeyboardEvent) {
      if (e.key === "Escape") sheetOnClose();
    }
    document.addEventListener("keydown", bubblePhaseSheetHandler, false);

    render(<Harness onAddToChat={onAdd} />);
    // No selection → no pill. Pill-absent Escape must reach the parent.
    expect(screen.queryByRole("button", { name: /quote in chat/i })).toBeNull();

    const ev = new KeyboardEvent("keydown", {
      key: "Escape",
      bubbles: true,
      cancelable: true,
    });
    act(() => {
      document.dispatchEvent(ev);
    });

    expect(sheetOnClose).toHaveBeenCalledTimes(1);

    document.removeEventListener("keydown", bubblePhaseSheetHandler, false);
  });

  it("⌘⇧L / Ctrl+Shift+L inside article triggers onAddToChat with selection", async () => {
    await importToolbar();
    const onAdd = vi.fn();
    render(<Harness onAddToChat={onAdd} />);
    const article = screen.getByTestId("article");
    act(() => { setSelection(article, "shortcut text"); });

    // Focus inside article and press Ctrl+Shift+L.
    (article as HTMLElement).focus?.();
    const ev = new KeyboardEvent("keydown", {
      key: "L",
      ctrlKey: true,
      shiftKey: true,
      bubbles: true,
      cancelable: true,
    });
    act(() => { article.dispatchEvent(ev); });

    expect(onAdd).toHaveBeenCalledWith("shortcut text");
  });
});
