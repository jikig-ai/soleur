/**
 * #11303 — the review card shows an email body IN FULL (up to 4000 characters), so the question paragraph must wrap an
 * unbroken string, preserve newlines, and the group's accessible name must be a short fixed label (not the whole body).
 */
import { describe, test, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import { ReviewGateCard, REVIEW_GATE_ARIA_LABEL } from "@/components/chat/review-gate-card";

const base = { gateId: "g1", options: ["Approve", "Reject"], onSelect: vi.fn() };

describe("ReviewGateCard — long and multi-line questions", () => {
  test("a 4000-character unbroken string renders in a wrapping paragraph with the short aria-label", () => {
    const question = "A".repeat(4000);
    render(<ReviewGateCard {...base} question={question} />);
    const para = screen.getByText(question);
    expect(para.tagName).toBe("P");
    expect(para.className).toContain("whitespace-pre-wrap");
    expect(para.className).toContain("[overflow-wrap:anywhere]");
    expect(para.className).toContain("min-w-0");
    const group = screen.getByRole("group");
    expect(group).toHaveAttribute("aria-label", "Approval needed");
    expect(REVIEW_GATE_ARIA_LABEL).toBe("Approval needed");
    expect(group.getAttribute("aria-label")).not.toContain("AAAA");
  });

  test("a newline-preserving body keeps its line breaks in the text and uses the pre-wrap class", () => {
    const question = "Agent wants to send a cold email.\nTo: <jo@example.invalid>\n\nBody line one\nBody line two";
    const { container } = render(<ReviewGateCard {...base} question={question} />);
    const para = container.querySelector("p")!;
    expect(para.textContent).toBe(question);
    expect(para.className).toContain("whitespace-pre-wrap");
    expect(screen.getByRole("group")).toHaveAttribute("aria-label", "Approval needed");
  });
});
