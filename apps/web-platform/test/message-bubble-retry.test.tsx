import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

// Mock observability so formatAssistantText's fallthrough path (invoked on
// every render) does not pull pino/Sentry into the component bundle under test.
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

import { MessageBubble } from "../components/chat/message-bubble";

// ---------------------------------------------------------------------------
// FR5 (#2861): message-bubble render behaviour for retry lifecycle + error.
// jsdom/happy-dom rule (`cq-jsdom-no-layout-gated-assertions`) — assert on
// structure and data-testid hooks only; never on layout values.
// ---------------------------------------------------------------------------

describe("MessageBubble retry + error render (FR5 #2861)", () => {
  test("tool_use bubble with retrying=true shows RetryingChip, not ToolStatusChip", () => {
    const { container, getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Searching code"
        retrying
      />,
    );
    // RetryingChip is present with role="status" + aria-live
    const chip = getByTestId("retrying-chip");
    expect(chip).toBeTruthy();
    expect(chip.getAttribute("aria-live")).toBe("polite");
    expect(chip.textContent).toContain("Retrying…");
    // Last activity label is shown below
    expect(chip.textContent).toContain("Searching code");
    // container reference retained so future assertions (e.g., "no duplicate
    // label") can be added without rewiring the render.
    void container;
  });

  test("tool_use bubble WITHOUT retrying shows normal ToolStatusChip", () => {
    const { container, queryByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="tool_use"
        toolLabel="Exploring project structure"
      />,
    );
    expect(queryByTestId("retrying-chip")).toBeNull();
    expect(container.textContent).toContain("Exploring project structure");
  });

  test("error bubble shows last activity label + File-issue link", () => {
    const { getByTestId, container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="error"
        toolLabel="Searching code"
      />,
    );
    expect(container.textContent).toContain(
      "Agent stopped responding after: Searching code",
    );
    const link = getByTestId("file-issue-link");
    expect(link.getAttribute("href")).toBeTruthy();
    expect((link.getAttribute("href") ?? "").startsWith("https://github.com/")).toBe(true);
    expect(link.getAttribute("target")).toBe("_blank");
    // Rel includes security tokens
    expect(link.getAttribute("rel")).toContain("noopener");
    expect(link.getAttribute("rel")).toContain("noreferrer");
  });

  test("error bubble without toolLabel falls back to 'Working'", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="error"
      />,
    );
    expect(container.textContent).toContain("Agent stopped responding after: Working");
  });
});
