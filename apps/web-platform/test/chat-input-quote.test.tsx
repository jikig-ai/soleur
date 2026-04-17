import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { useRef } from "react";
import { ChatInput, type ChatInputQuoteHandle } from "@/components/chat/chat-input";

// Phase 4.3: ChatInput exposes an imperative `quoteRef.current.insertQuote(text)`
// that prepends "> text\n\n" to the draft (or inserts at cursor if there is
// already a draft), does NOT auto-send, and briefly flashes an amber ring
// class on the inserted blockquote as a landing confirmation.

// Use the exported handle type so the local harness stays in sync when
// the interface grows (e.g., #2384 5B added `focus()`).
type QuoteHandle = ChatInputQuoteHandle;

function Harness({
  onSend,
  onReady,
  placeholder,
}: {
  onSend: (msg: string) => void;
  onReady?: (h: QuoteHandle) => void;
  placeholder?: string;
}) {
  const quoteRef = useRef<QuoteHandle | null>(null);
  return (
    <>
      <ChatInput
        onSend={onSend}
        onAtTrigger={() => {}}
        onAtDismiss={() => {}}
        quoteRef={quoteRef}
        placeholder={placeholder}
      />
      <button
        type="button"
        data-testid="ready"
        onClick={() => onReady?.(quoteRef.current!)}
      >
        ready
      </button>
    </>
  );
}

describe("ChatInput insertQuote", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  function getTextarea() {
    return document.querySelector("textarea") as HTMLTextAreaElement;
  }

  it("prepends '> <text>\\n\\n' to an empty draft", async () => {
    let handle: QuoteHandle | null = null;
    render(<Harness onSend={vi.fn()} onReady={(h) => { handle = h; }} />);
    screen.getByTestId("ready").click();
    expect(handle).not.toBeNull();
    act(() => { handle!.insertQuote("quoted passage"); });
    const ta = getTextarea();
    expect(ta.value).toBe("> quoted passage\n\n");
  });

  it("inserts at cursor when the draft is non-empty", async () => {
    let handle: QuoteHandle | null = null;
    render(<Harness onSend={vi.fn()} onReady={(h) => { handle = h; }} />);
    screen.getByTestId("ready").click();

    const ta = getTextarea();
    act(() => {
      ta.value = "existing text";
      ta.selectionStart = 8; // between "existing" and " text"
      ta.selectionEnd = 8;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // React controlled value: sync via fireEvent.change style.
    act(() => {
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype,
        "value",
      )!.set!;
      nativeInputValueSetter.call(ta, "existing text");
      ta.dispatchEvent(new Event("input", { bubbles: true }));
      ta.selectionStart = 8;
      ta.selectionEnd = 8;
    });

    act(() => { handle!.insertQuote("QQ"); });
    expect(ta.value).toContain("> QQ\n\n");
    // Must NOT auto-send.
  });

  it("does not auto-send after insert", async () => {
    const onSend = vi.fn();
    let handle: QuoteHandle | null = null;
    render(<Harness onSend={onSend} onReady={(h) => { handle = h; }} />);
    screen.getByTestId("ready").click();
    act(() => { handle!.insertQuote("x"); });
    expect(onSend).not.toHaveBeenCalled();
  });

  it("applies a flash ring class to the textarea briefly", async () => {
    let handle: QuoteHandle | null = null;
    render(<Harness onSend={vi.fn()} onReady={(h) => { handle = h; }} />);
    screen.getByTestId("ready").click();
    act(() => { handle!.insertQuote("hi"); });
    const ta = getTextarea();
    expect(ta.className).toMatch(/ring-(2|amber)/);
    // After ~500ms the ring class is removed.
    act(() => { vi.advanceTimersByTime(600); });
    expect(ta.className).not.toMatch(/\bring-2\b/);
  });

  it("does not leak timers on rapid reinsertion or unmount (#2384 5A)", () => {
    let handle: QuoteHandle | null = null;
    const { unmount } = render(
      <Harness onSend={vi.fn()} onReady={(h) => { handle = h; }} />,
    );
    screen.getByTestId("ready").click();
    // One call primes the pending timer baseline.
    act(() => { handle!.insertQuote("first"); });
    const firstCount = vi.getTimerCount();
    // Four additional rapid calls must NOT grow the pending-timer queue —
    // each call clears the prior timer and re-schedules one fresh one.
    for (let i = 0; i < 4; i++) {
      act(() => { handle!.insertQuote("line " + i); });
    }
    expect(vi.getTimerCount()).toBe(firstCount);
    unmount();
    // Unmount cleanup must cancel every pending timer scheduled by the handle.
    expect(vi.getTimerCount()).toBe(0);
  });

  it("renders the sidebar placeholder when passed through", () => {
    render(
      <Harness
        onSend={vi.fn()}
        placeholder="Ask about this document — ⌘⇧L to quote selection"
      />,
    );
    expect(
      screen.getByPlaceholderText(/ask about this document — ⌘⇧L to quote selection/i),
    ).toBeTruthy();
  });
});
