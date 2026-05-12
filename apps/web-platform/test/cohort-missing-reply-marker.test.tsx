import { describe, test, expect, vi, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";

import { CohortMissingReplyMarker } from "../components/chat/cohort-missing-reply-marker";
import type { ChatMessage } from "@/lib/chat-state-machine";

// PR-B (#3603): per-thread cohort marker. Plan
// knowledge-base/project/plans/2026-05-12-feat-cc-transcript-hardening-prb-cohort-marker-plan.md.
// Cohort = conversations created 2026-05-05..2026-05-12 (exclusive upper)
// where every persisted user message has no assistant reply. Marker is
// text-only (CTA dropped per plan-review convergence).

function userTextMsg(id: string, content: string): ChatMessage {
  return { id, role: "user", content, type: "text" };
}

function assistantTextMsg(id: string, content: string): ChatMessage {
  return { id, role: "assistant", content, type: "text", leaderId: "cto" };
}

const cohortMessages: ChatMessage[] = [
  userTextMsg("u1", "first prompt"),
  userTextMsg("u2", "second prompt"),
];

afterEach(() => {
  vi.useRealTimers();
});

describe("CohortMissingReplyMarker", () => {
  test("AC1 — renders marker on cohort fixture with locale-formatted created_at", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );

    const marker = screen.getByRole("note", { name: /conversation history note/i });
    expect(marker).toBeInTheDocument();
    expect(marker.textContent).toMatch(/started/i);
    // `Intl.DateTimeFormat(undefined, { month: "long" })` resolves to the
    // host locale in happy-dom; "May" appears in en-US and most fallbacks
    // for May 8 2026. The bracketed digit-or-month check tolerates locale
    // drift while still proving a real date interpolation.
    expect(marker.textContent).toMatch(/May|2026/);
  });

  test("AC2 — hides marker on healed thread (assistant reply present)", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={[...cohortMessages, assistantTextMsg("a1", "reply")]}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC3 — hides marker on post-fix thread (createdAt == upper bound, exclusive)", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-12T00:00:00Z"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC4 — hides marker on pre-window thread", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-04T23:59:00Z"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC5 — hides marker during active streaming regardless of message-list match", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isStreamingAssistant={true}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC6 — hides marker after sunset (2026-08-11 UTC)", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-11T00:00:01Z"));
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC7 — hides marker when createdAt is malformed", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="not-a-date"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });

  test("AC8 — exposes role='note' with aria-label and carries no interactive elements", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isStreamingAssistant={false}
      />,
    );

    const marker = screen.getByRole("note", { name: /conversation history note/i });
    expect(marker.tagName).toBe("ASIDE");
    expect(container.querySelectorAll("button, a, input, textarea").length).toBe(0);
  });

  test("hides marker when messages array is empty (no user prompts to attest to)", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={[]}
        isStreamingAssistant={false}
      />,
    );
    expect(container.textContent).toBe("");
  });
});
