import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// Bug 2 (plan 2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan.md):
// The error-state failure card's "File an issue" link hardcoded the wrong
// GitHub org slug (`jikigai` — the company-name domain) instead of the
// correct repo slug (`jikig-ai`). Effect: every click on the failure-card
// link landed on a 404. Pin AC2.1 + AC2.2 — positive substring + literal
// negative — so a future regression to the company-name slug fails fast.

describe("MessageBubble error state — File an issue link points to correct GitHub org", () => {
  test("AC2.1: href contains 'github.com/jikig-ai/soleur/issues/new' (with hyphen)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="error"
        toolLabel="Reading book.pdf"
      />,
    );
    const link = container.querySelector<HTMLAnchorElement>(
      '[data-testid="file-issue-link"]',
    );
    expect(link).not.toBeNull();
    expect(link!.getAttribute("href")).toContain(
      "https://github.com/jikig-ai/soleur/issues/new",
    );
  });

  test("AC2.2: href does NOT contain the company-name slug 'github.com/jikigai/' (regression guard)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        messageState="error"
        toolLabel="Reading book.pdf"
      />,
    );
    const link = container.querySelector<HTMLAnchorElement>(
      '[data-testid="file-issue-link"]',
    );
    expect(link).not.toBeNull();
    expect(link!.getAttribute("href")).not.toContain("github.com/jikigai/");
  });
});
