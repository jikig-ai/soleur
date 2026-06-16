import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { ChatInput } from "@/components/chat/chat-input";

// #5394 Layer B (AC4/AC5 view) — the chat composer's repo-setup states. The
// poll controller (auto-transition) is covered by use-active-repo-poll; THIS
// pins the rendered states: disabled "Setting up…" while cloning, re-enabled on
// clear, and the reconnect CTA on error. Test hook is the textarea placeholder
// + structural text/links (per cq-jsdom-no-layout-gated-assertions).

const commonProps = {
  onSend: vi.fn(),
  onAtTrigger: vi.fn(),
  onAtDismiss: vi.fn(),
};

function getTextarea(container: HTMLElement): HTMLTextAreaElement {
  const el = container.querySelector("textarea");
  if (!el) throw new Error("textarea not found");
  return el as HTMLTextAreaElement;
}

describe("ChatInput — repo-setup states (#5394)", () => {
  it("AC4 view: cloning → composer disabled, setting-up placeholder + 'less than a minute' indicator", () => {
    const { container } = render(
      <ChatInput {...commonProps} repoSetupState="cloning" />,
    );
    const textarea = getTextarea(container);
    expect(textarea.disabled).toBe(true);
    expect(textarea.placeholder).toBe("Setting up your repository…");
    expect(container.textContent).toContain(
      "This usually takes less than a minute.",
    );
  });

  it("AC4 view: clearing repoSetupState re-enables the composer + restores the default placeholder", () => {
    const { container, rerender } = render(
      <ChatInput {...commonProps} repoSetupState="cloning" />,
    );
    expect(getTextarea(container).disabled).toBe(true);

    rerender(<ChatInput {...commonProps} repoSetupState={null} />);
    const textarea = getTextarea(container);
    expect(textarea.disabled).toBe(false);
    expect(textarea.placeholder).not.toBe("Setting up your repository…");
    // The setting-up indicator is gone.
    expect(container.textContent).not.toContain(
      "This usually takes less than a minute.",
    );
  });

  it("AC5: error → reconnect CTA linking to /dashboard/settings", () => {
    const { container } = render(
      <ChatInput {...commonProps} repoSetupState="error" />,
    );
    const link = container.querySelector('a[href="/dashboard/settings"]');
    expect(link).not.toBeNull();
    expect(link?.textContent).toMatch(/reconnect/i);
    // The composer is also disabled on error (can't chat against a broken repo).
    expect(getTextarea(container).disabled).toBe(true);
  });

  it("no repoSetupState → normal composer (enabled, default placeholder, no indicator)", () => {
    const { container } = render(<ChatInput {...commonProps} />);
    const textarea = getTextarea(container);
    expect(textarea.disabled).toBe(false);
    expect(container.textContent).not.toContain(
      "This usually takes less than a minute.",
    );
    expect(
      container.querySelector('a[href="/dashboard/settings"]'),
    ).toBeNull();
  });
});
