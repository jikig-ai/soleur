import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { act, fireEvent, render } from "@testing-library/react";
import { ChatInput } from "@/components/chat/chat-input";

// Phase 0 RED — AC #21: chat-input draft persistence is debounced (250ms
// trailing), flushes on unmount, and cancels on draftKey change.

describe("ChatInput — draft persistence debounce (AC #21)", () => {
  beforeEach(() => {
    try {
      sessionStorage.clear();
    } catch {
      /* noop */
    }
    vi.useFakeTimers({ shouldAdvanceTime: false });
  });

  afterEach(() => {
    vi.useRealTimers();
    try {
      sessionStorage.clear();
    } catch {
      /* noop */
    }
  });

  const commonProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  function setTextareaValue(el: HTMLTextAreaElement, value: string) {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      "value",
    )!.set!;
    setter.call(el, value);
    fireEvent.input(el);
  }

  it("coalesces rapid typing into <=1 setItem within the 250ms window", () => {
    const setSpy = vi.spyOn(Storage.prototype, "setItem");
    render(
      <ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />,
    );
    const ta = document.querySelector("textarea") as HTMLTextAreaElement;

    act(() => {
      setTextareaValue(ta, "h");
      setTextareaValue(ta, "he");
      setTextareaValue(ta, "hel");
      setTextareaValue(ta, "hell");
      setTextareaValue(ta, "hello");
    });

    // Within the debounce window, no setItem has landed for the draft key.
    const earlyDraftWrites = setSpy.mock.calls.filter(
      (c) => c[0] === "kb.chat.draft:knowledge-base/a.md",
    );
    expect(earlyDraftWrites.length).toBe(0);

    // After 250ms the trailing write fires exactly once with the final value.
    act(() => {
      vi.advanceTimersByTime(260);
    });
    const draftWrites = setSpy.mock.calls.filter(
      (c) => c[0] === "kb.chat.draft:knowledge-base/a.md",
    );
    expect(draftWrites.length).toBe(1);
    expect(draftWrites[0][1]).toBe("hello");

    setSpy.mockRestore();
  });

  it("flushes pending write on unmount (final keystroke reaches storage)", () => {
    const { unmount } = render(
      <ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />,
    );
    const ta = document.querySelector("textarea") as HTMLTextAreaElement;
    act(() => {
      setTextareaValue(ta, "pending");
    });
    // Unmount BEFORE the 250ms timer would fire.
    unmount();
    expect(
      sessionStorage.getItem("kb.chat.draft:knowledge-base/a.md"),
    ).toBe("pending");
  });
});
