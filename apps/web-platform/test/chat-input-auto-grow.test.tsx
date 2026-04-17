import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, act } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ChatInput } from "@/components/chat/chat-input";

/**
 * Tests for auto-growing textarea behavior.
 *
 * The textarea should:
 * - Start at 1 line (~44px)
 * - Grow to match content up to 5 lines (~100px)
 * - Scroll internally beyond 5 lines
 * - Reset to 1 line on submit
 * - Resize immediately on paste
 * - Resize on programmatic value changes (quote insertion)
 */

describe("ChatInput auto-grow", () => {
  const defaultProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  beforeEach(() => {
    sessionStorage.clear();
    vi.restoreAllMocks();
  });

  function setup(overrides = {}) {
    const props = { ...defaultProps, ...overrides };
    Object.values(props).forEach((fn) => {
      if (typeof fn === "function" && "mockClear" in fn) {
        (fn as ReturnType<typeof vi.fn>).mockClear();
      }
    });
    return render(<ChatInput {...props} />);
  }

  it("textarea has min-height and max-height constraints instead of fixed height", () => {
    setup();
    const textarea = screen.getByRole("textbox");
    // Should NOT have any fixed h-[*px] class (min-h-/max-h- are ok)
    expect(textarea.className).not.toMatch(/(?<![-\w])h-\[\d+px\]/);
    // Should have min-h and max-h constraints
    expect(textarea.className).toMatch(/min-h-\[72px\]/);
    expect(textarea.className).toMatch(/max-h-\[140px\]/);
  });

  it("textarea has overflow-y auto for internal scrolling", () => {
    setup();
    const textarea = screen.getByRole("textbox");
    expect(textarea.className).toContain("overflow-y-auto");
  });

  it("adjusts height via style when value changes", async () => {
    setup();
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

    // Simulate scrollHeight being larger than default
    Object.defineProperty(textarea, "scrollHeight", {
      get: () => 72,
      configurable: true,
    });

    await userEvent.type(textarea, "line 1\nline 2\nline 3");

    // The useLayoutEffect should set style.height based on scrollHeight
    expect(textarea.style.height).toBeTruthy();
  });

  it("caps height at 140px even when content is taller", async () => {
    setup();
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

    // Simulate scrollHeight exceeding max
    Object.defineProperty(textarea, "scrollHeight", {
      get: () => 300,
      configurable: true,
    });

    await userEvent.type(textarea, "a\nb\nc\nd\ne\nf\ng\nh");

    // Height should be capped at 140px
    expect(textarea.style.height).toBe("140px");
  });

  it("resets height on submit (value cleared)", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

    // Type multi-line content
    Object.defineProperty(textarea, "scrollHeight", {
      get: () => 72,
      configurable: true,
    });
    await userEvent.type(textarea, "line 1\nline 2");

    // After submit, scrollHeight returns to single-line
    Object.defineProperty(textarea, "scrollHeight", {
      get: () => 44,
      configurable: true,
    });
    await userEvent.keyboard("{Enter}");

    // Height should reset after value clears
    expect(textarea.style.height).toBe("44px");
  });

  it("adjusts height on programmatic value change via quote insertion", async () => {
    const quoteRef = { current: null } as React.MutableRefObject<
      import("@/components/chat/chat-input").ChatInputQuoteHandle | null
    >;
    setup({ quoteRef });
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

    // Simulate scrollHeight after quote
    Object.defineProperty(textarea, "scrollHeight", {
      get: () => 66,
      configurable: true,
    });

    // Insert quote programmatically
    act(() => {
      quoteRef.current?.insertQuote("This is a quoted block of text");
    });

    // useLayoutEffect should fire and set height
    expect(textarea.style.height).toBeTruthy();
  });
});
