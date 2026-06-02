import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// Removal of the redundant pulsing-dot indicator inside the in-bubble
// `ToolStatusChip`. The bubble's animated border + top-right "Working" pill
// already convey the working state. Structural assertion (chip has exactly
// one child = the label span) is durable against Tailwind-class refactors
// (`motion-safe:animate-pulse`, CSS modules, etc.).
describe("MessageBubble tool_use ToolStatusChip (no redundant dot)", () => {
  test("chip contains exactly one child (the label span) — no inner indicator", () => {
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Reading knowledge-base/overview/foo.pdf"
      />,
    );
    const chip = getByTestId("tool-status-chip");
    expect(chip.children).toHaveLength(1);
    expect(chip.children[0].textContent).toBe("Reading knowledge-base/overview/foo.pdf");
  });

  test("renders the toolLabel verbatim in the bubble", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Reading knowledge-base/overview/foo.pdf"
      />,
    );
    expect(container.textContent).toContain("Reading knowledge-base/overview/foo.pdf");
  });

  test("renders the surviving 'Working' pill text", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Doing the thing"
      />,
    );
    expect(container.textContent).toContain("Working");
  });

  test("preserves the message-bubble-active animated-border class", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Doing the thing"
      />,
    );
    expect(container.querySelector(".message-bubble-active")).not.toBeNull();
  });

  // Regression (#4852): the short status label ("Routing to the right
  // experts…") wrapped onto two lines even when horizontal space was
  // available. The label span must be `whitespace-nowrap` so the bubble
  // grows to its natural single-line width instead of wrapping.
  test("label span is whitespace-nowrap (no unnecessary wrap of short status text)", () => {
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Routing to the right experts..."
      />,
    );
    const chip = getByTestId("tool-status-chip");
    const labelSpan = chip.children[0] as HTMLElement;
    expect(labelSpan.className).toContain("whitespace-nowrap");
  });
});
