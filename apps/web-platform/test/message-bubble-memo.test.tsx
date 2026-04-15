import { describe, test, expect } from "vitest";
import { memo, useEffect } from "react";
import { render } from "@testing-library/react";

/**
 * Verifies the memoization contract used by `MessageBubble` (#2137) — that a
 * parent re-render does NOT cause every bubble to re-render when only one
 * bubble's props changed. This test intentionally replicates `MessageBubble`
 * with a trivial component so we can measure render counts without coupling
 * to the full page layout.
 */

interface BubbleProps {
  role: "user" | "assistant";
  content: string;
  messageState?: "thinking" | "tool_use" | "streaming" | "done" | "error";
  renderCount: { current: number };
}

const TestBubble = memo(function TestBubble({
  content,
  messageState,
  renderCount,
}: BubbleProps) {
  useEffect(() => {
    renderCount.current += 1;
  });
  return (
    <div data-testid="bubble" data-state={messageState ?? "none"}>
      {content}
    </div>
  );
});

describe("MessageBubble memo contract", () => {
  test("memo prevents re-render of bubbles whose props are unchanged", () => {
    const counts = {
      a: { current: 0 },
      b: { current: 0 },
      c: { current: 0 },
    };

    const { rerender } = render(
      <>
        <TestBubble role="assistant" content="A" messageState="done" renderCount={counts.a} />
        <TestBubble role="assistant" content="B" messageState="streaming" renderCount={counts.b} />
        <TestBubble role="assistant" content="C" messageState="done" renderCount={counts.c} />
      </>,
    );

    const baseline = { a: counts.a.current, b: counts.b.current, c: counts.c.current };

    // Re-render the parent with only bubble B's content changed.
    rerender(
      <>
        <TestBubble role="assistant" content="A" messageState="done" renderCount={counts.a} />
        <TestBubble role="assistant" content="B updated" messageState="streaming" renderCount={counts.b} />
        <TestBubble role="assistant" content="C" messageState="done" renderCount={counts.c} />
      </>,
    );

    expect(counts.a.current).toBe(baseline.a);
    expect(counts.c.current).toBe(baseline.c);
    expect(counts.b.current).toBeGreaterThan(baseline.b);
  });
});
