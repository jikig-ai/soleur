import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { TurnSummaryBubble } from "@/components/chat/turn-summary-bubble";

// feat-reasoning-chat-boxes (#5370) — the durable confirmed box renders the
// agent-authored summary as PLAIN TEXT (deepen-plan C-1). NEVER markdown/HTML.

describe("TurnSummaryBubble", () => {
  it("renders the summary text in an emerald confirmed box", () => {
    render(<TurnSummaryBubble content="Fixed the side panel so it stays open." />);
    const box = screen.getByTestId("turn-summary");
    expect(box).toHaveTextContent("Fixed the side panel so it stays open.");
    expect(box.getAttribute("data-message-type")).toBe("turn_summary");
    // Emerald left-accent rail (wireframe 06).
    expect(box.className).toContain("border-l-emerald-500");
  });

  it("renders a <script> payload INERT (no script element, escaped as text)", () => {
    const { container } = render(
      <TurnSummaryBubble content={'<script>alert(1)</script> all done'} />,
    );
    // React escapes the string; no live <script> node is created.
    expect(container.querySelector("script")).toBeNull();
    expect(screen.getByTestId("turn-summary")).toHaveTextContent(
      "<script>alert(1)</script> all done",
    );
  });

  it("renders an <img onerror> payload INERT (no img element)", () => {
    const { container } = render(
      <TurnSummaryBubble content={'<img src=x onerror=alert(1)> done'} />,
    );
    expect(container.querySelector("img")).toBeNull();
    expect(screen.getByTestId("turn-summary")).toHaveTextContent("done");
  });

  it("applies formatAssistantText path scrubbing at render (belt-and-suspenders)", () => {
    render(
      <TurnSummaryBubble content="Saved at /workspaces/11111111-1111-1111-1111-111111111111/x.md ok" />,
    );
    const box = screen.getByTestId("turn-summary");
    expect(box.textContent).not.toContain("/workspaces/");
  });
});
