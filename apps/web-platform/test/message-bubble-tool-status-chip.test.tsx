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
// #9515 — consolidated working box: the tool step now renders as the
// ActivityTrail's `live-narration` line inside the bubble (the body's
// ToolStatusChip is suppressed so the label can never double).
describe("MessageBubble tool_use live-step line (consolidated box)", () => {
  test("the live line carries the label inside the activity trail", () => {
    const { getByTestId, queryByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Reading knowledge-base/overview/foo.pdf"
      />,
    );
    const line = getByTestId("live-narration");
    expect(line).toHaveTextContent("Reading knowledge-base/overview/foo.pdf");
    // One label, one surface — the body's ToolStatusChip is suppressed while
    // the trail's live line owns the current step (the motivating double-label
    // bug; a deleted suppressToolStatus would ship green without this pin).
    expect(queryByTestId("tool-status-chip")).not.toBeInTheDocument();
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

  // Regression (#4852 + inverse fix #4855-class): #4852 added bare
  // `whitespace-nowrap` to stop a short status label ("Routing to the right
  // experts…") wrapping prematurely. But with the bubble's `max-w` cap +
  // `min-w-0` ancestor chain, `nowrap` left no degree of freedom for a label
  // *wider* than the cap — it overflowed the card's right border. The fix
  // swaps `nowrap` for the wrap-capable `[overflow-wrap:anywhere]` idiom
  // already used on the streaming body (message-bubble.tsx:269): short labels
  // still stay single-line (the `min-w-0` chain, not nowrap, is what prevented
  // #4852's premature wrap), long labels wrap at the cap instead of spilling.
  //
  // jsdom returns 0 for layout values (constitution line 312), so the actual
  // no-overflow proof lives in Playwright (cc-soleur-go-bubbles.e2e.ts). Here
  // we only assert the className mechanism: the wrap-capable class is present
  // and the overflow-forcing `whitespace-nowrap` is gone.
  test("label span carries the wrap-capable mechanism (not overflow-forcing nowrap)", () => {
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Routing to the right experts..."
      />,
    );
    const line = getByTestId("live-narration");
    const labelSpan = Array.from(line.children).find(
      (el) => el.tagName === "SPAN" && el.textContent?.length,
    ) as HTMLElement;
    expect(labelSpan.className).toContain("[overflow-wrap:anywhere]");
    expect(labelSpan.className).not.toContain("whitespace-nowrap");
  });
});
