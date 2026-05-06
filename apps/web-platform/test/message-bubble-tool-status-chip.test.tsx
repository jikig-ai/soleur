import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// Removal of the redundant pulsing-dot indicator inside the in-bubble
// `ToolStatusChip` (the bubble's animated border + top-right "Working" pill
// already convey the working state). Scoped via `data-testid="tool-status-chip"`
// per learning 2026-04-18 Pattern 4 — survives Tailwind class refactors.
describe("MessageBubble tool_use ToolStatusChip (no redundant dot)", () => {
  test("renders the chip wrapper with the data-testid hook", () => {
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Reading knowledge-base/overview/foo.pdf"
      />,
    );
    expect(getByTestId("tool-status-chip")).toBeTruthy();
  });

  test("does NOT render an inner pulsing dot inside the chip", () => {
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Reading knowledge-base/overview/foo.pdf"
      />,
    );
    const chip = getByTestId("tool-status-chip");
    expect(chip.querySelector("span.animate-pulse")).toBeNull();
  });

  test("renders the toolLabel verbatim", () => {
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

  test("preserves the surviving working-state cues (Working pill + animated bubble border)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Doing the thing"
      />,
    );
    expect(container.textContent).toContain("Working");
    expect(container.querySelector(".message-bubble-active")).not.toBeNull();
  });
});
