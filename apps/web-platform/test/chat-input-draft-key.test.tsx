import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, act } from "@testing-library/react";
import { fireEvent } from "@testing-library/react";
import { ChatInput } from "@/components/chat/chat-input";

// AC5: per-path draft persistence. When `draftKey` is set, the textarea
// value is mirrored to sessionStorage under that key and restored on mount.
// Switching draftKey (doc → doc) rehydrates the other doc's draft.

describe("ChatInput — draftKey (AC5)", () => {
  beforeEach(() => {
    try { sessionStorage.clear(); } catch { /* jsdom only */ }
  });
  afterEach(() => {
    try { sessionStorage.clear(); } catch { /* noop */ }
  });

  const commonProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  function setValue(el: HTMLTextAreaElement, value: string) {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      "value",
    )!.set!;
    setter.call(el, value);
    fireEvent.input(el);
  }

  it("persists draft to sessionStorage under `draftKey` on input", () => {
    render(<ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />);
    const ta = document.querySelector("textarea") as HTMLTextAreaElement;
    act(() => setValue(ta, "draft for A"));
    expect(sessionStorage.getItem("kb.chat.draft:knowledge-base/a.md")).toBe(
      "draft for A",
    );
  });

  it("restores the persisted draft on mount", () => {
    sessionStorage.setItem("kb.chat.draft:knowledge-base/a.md", "previous draft");
    render(<ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />);
    const ta = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(ta.value).toBe("previous draft");
  });

  it("different draftKeys are isolated — Doc A draft stays when Doc B mounts", () => {
    sessionStorage.setItem("kb.chat.draft:knowledge-base/a.md", "A draft");
    sessionStorage.setItem("kb.chat.draft:knowledge-base/b.md", "B draft");

    const { rerender } = render(
      <ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />,
    );
    let ta = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(ta.value).toBe("A draft");

    rerender(
      <ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/b.md" />,
    );
    ta = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(ta.value).toBe("B draft");

    // Doc A's draft still in storage untouched.
    expect(sessionStorage.getItem("kb.chat.draft:knowledge-base/a.md")).toBe("A draft");
  });

  it("clears the draft from storage after a successful send", () => {
    render(<ChatInput {...commonProps} draftKey="kb.chat.draft:knowledge-base/a.md" />);
    const ta = document.querySelector("textarea") as HTMLTextAreaElement;
    act(() => setValue(ta, "some message"));
    act(() => {
      fireEvent.keyDown(ta, { key: "Enter" });
    });
    expect(sessionStorage.getItem("kb.chat.draft:knowledge-base/a.md")).toBeNull();
  });
});
