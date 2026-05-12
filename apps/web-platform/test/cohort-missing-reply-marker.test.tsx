import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
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

beforeEach(() => {
  // Freeze the system clock inside the cohort window so AC1-AC5/AC7-AC8
  // do not silently flip to "marker hidden" once the wall clock crosses
  // COHORT_MARKER_SUNSET (2026-08-11 UTC). Sunset-specific tests override.
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-05-12T12:00:00Z"));
});

afterEach(() => {
  vi.useRealTimers();
});

describe("CohortMissingReplyMarker", () => {
  test("AC1 — renders marker on cohort fixture with locale-formatted created_at", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );

    const marker = screen.getByRole("note", { name: /conversation history note/i });
    expect(marker).toBeInTheDocument();
    expect(marker.textContent).toMatch(/started/i);
    // Year is always present in Intl output. The marker MUST also have
    // run a real formatter — raw ISO would expose timezone separators
    // that `Intl.DateTimeFormat(undefined, { year, month, day })` never
    // emits. This catches a regression that drops month/day options.
    expect(marker.textContent).toContain("2026");
    expect(marker.textContent).not.toContain("2026-05-08T10:00:00Z");
    expect(marker.textContent).not.toContain("T10:00");
  });

  test("AC2 — hides marker on healed thread (assistant reply present)", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={[...cohortMessages, assistantTextMsg("a1", "reply")]}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC3 — hides marker on post-fix thread (createdAt == upper bound, exclusive)", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-12T00:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC4 — hides marker on pre-window thread", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-04T23:59:00Z"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC5 — hides marker during active streaming regardless of message-list match", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={true}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC5b — hides marker across the stopping substate too (review #3653)", () => {
    // chat-surface passes isTurnInFlight={streamState !== "idle"}, so a
    // Stop-mid-turn (`streaming → stopping → idle`) cannot flash the marker
    // during the `stopping` window. The prop is a single boolean; we prove
    // the contract holds in the only state the component sees.
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={true}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC6 — hides marker after sunset (2026-08-11 UTC)", () => {
    vi.setSystemTime(new Date("2026-08-11T00:00:01Z"));
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC7 — hides marker when createdAt is malformed", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="not-a-date"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC7b — hides marker when createdAt is null (unhydrated)", () => {
    render(
      <CohortMissingReplyMarker
        createdAt={null}
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("AC8 — exposes role='note' with aria-label and carries no interactive elements", () => {
    const { container } = render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={cohortMessages}
        isTurnInFlight={false}
      />,
    );

    const marker = screen.getByRole("note", { name: /conversation history note/i });
    expect(marker).toBeInTheDocument();
    expect(container.querySelectorAll("button, a, input, textarea, select, [role='button']").length).toBe(0);
  });

  test("hides marker when messages array is empty (no user prompts to attest to)", () => {
    render(
      <CohortMissingReplyMarker
        createdAt="2026-05-08T10:00:00Z"
        messages={[]}
        isTurnInFlight={false}
      />,
    );
    expect(screen.queryByRole("note")).toBeNull();
  });
});
