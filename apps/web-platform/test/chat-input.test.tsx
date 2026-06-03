import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ChatInput } from "@/components/chat/chat-input";

describe("ChatInput", () => {
  const defaultProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  function setup(overrides = {}) {
    const props = { ...defaultProps, ...overrides };
    // Reset mocks
    Object.values(props).forEach((fn) => {
      if (typeof fn === "function" && "mockClear" in fn) {
        (fn as ReturnType<typeof vi.fn>).mockClear();
      }
    });
    return render(<ChatInput {...props} />);
  }

  it("renders a textarea with placeholder", () => {
    setup();
    expect(screen.getByPlaceholderText(/ask your team/i)).toBeInTheDocument();
  });

  it("rejects empty messages on Enter", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox");
    await userEvent.click(textarea);
    await userEvent.keyboard("{Enter}");
    expect(onSend).not.toHaveBeenCalled();
  });

  it("rejects whitespace-only messages on Enter", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "   ");
    await userEvent.keyboard("{Enter}");
    expect(onSend).not.toHaveBeenCalled();
  });

  it("sends message on Enter and clears input", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "hello world");
    await userEvent.keyboard("{Enter}");
    expect(onSend).toHaveBeenCalledWith("hello world");
    expect(textarea).toHaveValue("");
  });

  it("does not send on Shift+Enter (allows newline)", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "line 1");
    await userEvent.keyboard("{Shift>}{Enter}{/Shift}");
    expect(onSend).not.toHaveBeenCalled();
  });

  it("calls onAtTrigger when @ is typed", async () => {
    const onAtTrigger = vi.fn();
    setup({ onAtTrigger });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "@");
    expect(onAtTrigger).toHaveBeenCalledWith("", expect.any(Number));
  });

  it("calls onAtTrigger with query when @cm is typed", async () => {
    const onAtTrigger = vi.fn();
    setup({ onAtTrigger });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "@cm");
    // The last call should have query "cm"
    const lastCall = onAtTrigger.mock.calls[onAtTrigger.mock.calls.length - 1];
    expect(lastCall[0]).toBe("cm");
  });

  it("calls onAtDismiss when typing moves past the @-mention", async () => {
    const onAtDismiss = vi.fn();
    setup({ onAtDismiss });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "hello ");
    // onAtDismiss is called for each character that isn't an @-trigger
    expect(onAtDismiss).toHaveBeenCalled();
  });

  it("shows mobile @ button below md breakpoint", () => {
    setup();
    const button = screen.getByLabelText("Mention a leader");
    expect(button).toBeInTheDocument();
    // The md:hidden class is a Tailwind concern — just verify the button exists
  });

  it("disables textarea and send button when disabled prop is true", () => {
    setup({ disabled: true });
    const textarea = screen.getByRole("textbox");
    expect(textarea).toBeDisabled();
    const sendButton = screen.getByLabelText("Send message");
    expect(sendButton).toBeDisabled();
  });

  it("disables send button when input is empty", () => {
    setup();
    const sendButton = screen.getByLabelText("Send message");
    expect(sendButton).toBeDisabled();
  });

  it("sends message via send button click", async () => {
    const onSend = vi.fn();
    setup({ onSend });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "click send");
    const sendButton = screen.getByLabelText("Send message");
    await userEvent.click(sendButton);
    expect(onSend).toHaveBeenCalledWith("click send");
  });

  it("does not send on Enter when atMentionVisible is true", async () => {
    const onSend = vi.fn();
    setup({ onSend, atMentionVisible: true });
    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "hello");
    await userEvent.keyboard("{Enter}");
    expect(onSend).not.toHaveBeenCalled();
  });

  it("textarea has auto-growing height constraints", () => {
    setup();
    const textarea = screen.getByRole("textbox");
    expect(textarea.className).toContain("min-h-[36px]");
    expect(textarea.className).toContain("max-h-[140px]");
  });

  // Focus styling (AC6): the composer must NOT use the gold emphasized border
  // on focus-within, and must keep a visible but neutral focus affordance.
  // jsdom cannot evaluate the global @layer base :focus-visible box-shadow, so
  // the inner-ring removal (AC1a) is verified by className-token absence on the
  // textarea + the AC8 screenshot, not by getComputedStyle.
  it("composer container has a neutral (non-gold) focus-within affordance", () => {
    setup();
    const textarea = screen.getByRole("textbox");
    const container = textarea.closest("div.rounded-xl") as HTMLElement;
    expect(container).not.toBeNull();
    // No gold outer border on focus.
    expect(container.className).not.toContain("focus-within:border-soleur-border-emphasized");
    // Still has a visible, neutral focus-within border.
    expect(container.className).toContain("focus-within:border-soleur-text-muted");
  });

  it("textarea suppresses the inherited global gold focus ring", () => {
    setup();
    const textarea = screen.getByRole("textbox");
    expect(textarea.className).toContain("focus-visible:shadow-none");
  });
});
