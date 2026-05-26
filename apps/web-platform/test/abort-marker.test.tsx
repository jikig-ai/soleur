import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// Task 5.2 (RED) — abort marker rendering on MessageBubble.
//
// When a persisted assistant `Message` carries `status === "aborted"`, the
// bubble renders four payload-driven elements in addition to the partial
// `content` text:
//   1. The accumulated partial text (already supplied via `content`).
//   2. A `[stopped by user]` chip.
//   3. Token cost: `usage.input_tokens + usage.output_tokens` and
//      `usage.cost_usd` (or "included in your plan" when null/undefined).
//   4. A chip-list, one chip per `usage.completed_actions[]` entry, that
//      surfaces the tool name. Reuses `<ToolUseChip>` when the shape is
//      compatible (per task 0.4).
//
// All assertions scope to the bubble container so unrelated chrome (the
// "Response complete" checkmark for `state: "done"`, the streaming caret
// for `state: "streaming"`, leader avatar/title) cannot drift counts.

const baseUsage = {
  input_tokens: 1200,
  output_tokens: 340,
  cost_usd: 0.0042,
  completed_actions: [
    { tool_name: "Bash", input_summary: "git status", result_summary: "clean" },
    { tool_name: "Read", input_summary: "lib/foo.ts", result_summary: "ok" },
  ],
};

describe("MessageBubble abort marker (task 5.2)", () => {
  test("renders partial text + [stopped by user] chip when status='aborted'", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="Here is the partial response that"
        leaderId="cto"
        status="aborted"
        usage={baseUsage}
      />,
    );

    // (1) partial text survives
    expect(container.textContent).toContain("Here is the partial response that");
    // (2) [stopped by user] chip
    expect(container.textContent).toContain("[stopped by user]");
  });

  test("renders token count and USD cost from usage payload", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="partial"
        leaderId="cto"
        status="aborted"
        usage={baseUsage}
      />,
    );

    // Total token count = input + output = 1540
    expect(container.textContent).toContain("1540");
    // USD cost rendered (4 decimals — same precision as the in-flight cost
    // chrome in chat-surface.tsx)
    expect(container.textContent).toContain("0.0042");
  });

  test("renders 'included in your plan' when usage.cost_usd is null", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="partial"
        leaderId="cto"
        status="aborted"
        usage={{ ...baseUsage, cost_usd: null }}
      />,
    );

    expect(container.textContent).toContain("included in your plan");
    expect(container.textContent).not.toContain("$");
  });

  test("renders a chip per completed_actions entry, surfacing the tool name", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="partial"
        leaderId="cto"
        status="aborted"
        usage={baseUsage}
      />,
    );

    // Both tool_name values appear in the rendered marker.
    expect(container.textContent).toContain("Bash");
    expect(container.textContent).toContain("Read");
  });

  test("does NOT render the marker when status='complete'", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="hello"
        leaderId="cto"
        status="complete"
        messageState="done"
      />,
    );

    expect(container.textContent).not.toContain("[stopped by user]");
  });

  test("does NOT render the marker when status is undefined (legacy bubbles)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="hello"
        leaderId="cto"
        messageState="done"
      />,
    );

    expect(container.textContent).not.toContain("[stopped by user]");
  });
});
