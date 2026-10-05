import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup, act } from "@testing-library/react";
import React from "react";

// feat-concierge-activity-trail (#9515): render contract for the
// consolidated working box — dimmed priors + bright live line + honest
// Interrupted marker, render-gated so terminal bubbles collapse cleanly.

import { ActivityTrail } from "@/components/chat/activity-trail";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

afterEach(() => cleanup());

describe("ActivityTrail", () => {
  it("renders prior steps dimmed with an overflow marker over the visible cap", () => {
    const activity = Array.from({ length: 8 }, (_, i) => ({
      label: `step-${i}`,
      kind: "tool" as const,
      startedAt: Date.now() - i * 1000,
    }));
    render(
      <ActivityTrail
        activity={activity}
        current={{ label: "Current step", startedAt: Date.now() }}
      />,
    );
    expect(screen.getByText("Current step")).toBeInTheDocument();
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
    // Visible cap is 5 — 3 hidden behind the honest overflow line.
    expect(screen.getByText("…and 3 more steps")).toBeInTheDocument();
    expect(screen.getByText("step-7")).toBeInTheDocument();
    expect(screen.queryByText("step-0")).not.toBeInTheDocument();
  });

  it("renders the live line with elapsed time and no overflow marker when under cap", () => {
    render(
      <ActivityTrail
        activity={[
          { label: "Triage open pull requests", kind: "tool", startedAt: Date.now() - 3000 },
        ]}
        current={{ label: "Checking CI status", startedAt: Date.now() - 1000 }}
      />,
    );
    expect(screen.getByText("Triage open pull requests")).toBeInTheDocument();
    expect(screen.getByTestId("live-narration")).toHaveTextContent(
      "Checking CI status",
    );
    expect(screen.getByTestId("live-narration")).toHaveTextContent("1s");
    expect(screen.queryByText(/more steps/)).not.toBeInTheDocument();
  });

  it("interrupted renders the honest chip and NO live line", () => {
    render(
      <ActivityTrail
        activity={[
          { label: "Reading a file", kind: "tool", startedAt: Date.now() },
        ]}
        current={null}
        interrupted
      />,
    );
    expect(screen.getByTestId("interrupted-chip")).toHaveTextContent(
      "Interrupted",
    );
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
    // The trail is preserved through the interruption.
    expect(screen.getByText("Reading a file")).toBeInTheDocument();
  });

  it("elapsed text is aria-hidden so the ticker never re-announces the region", () => {
    render(
      <ActivityTrail
        activity={[]}
        current={{ label: "Working", startedAt: Date.now() - 5000 }}
      />,
    );
    const region = screen.getByTestId("activity-trail");
    expect(region).toHaveAttribute("aria-live", "polite");
    const hidden = region.querySelectorAll('[aria-hidden="true"]');
    const texts = Array.from(hidden).map((n) => n.textContent).join(" ");
    expect(texts).toContain("5s");
  });

  it("renders nothing but the live line when there are no priors", () => {
    render(
      <ActivityTrail
        activity={undefined}
        current={{ label: "Looking into your billing settings…", startedAt: Date.now() }}
      />,
    );
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });
});

describe("MessageBubble — consolidated working box", () => {
  it("active bubble renders its activity trail inside the box", async () => {
    const { MessageBubble } = await import(
      "@/components/chat/message-bubble"
    );
    render(
      <MessageBubble
        role="assistant"
        content="Working on it"
        messageState="tool_use"
        toolLabel="Checking CI status"
        activity={[
          { label: "Triage open pull requests", kind: "tool", startedAt: Date.now() },
        ]}
        variant="full"
      />,
    );
    expect(screen.getByTestId("activity-trail")).toBeInTheDocument();
    expect(screen.getByText("Triage open pull requests")).toBeInTheDocument();
    expect(screen.getByTestId("live-narration")).toHaveTextContent(
      "Checking CI status",
    );
  });

  it("done bubble does NOT render the trail (render-gated collapse)", async () => {
    const { MessageBubble } = await import(
      "@/components/chat/message-bubble"
    );
    render(
      <MessageBubble
        role="assistant"
        content="Final answer"
        messageState="done"
        activity={[
          { label: "Triage open pull requests", kind: "tool", startedAt: Date.now() },
        ]}
        variant="full"
      />,
    );
    expect(screen.queryByTestId("activity-trail")).not.toBeInTheDocument();
  });

  it("interrupted bubble shows the marker + trail, never a live line", async () => {
    const { MessageBubble } = await import(
      "@/components/chat/message-bubble"
    );
    render(
      <MessageBubble
        role="assistant"
        content="partial"
        interrupted
        activity={[
          { label: "Reading a file", kind: "tool", startedAt: Date.now() },
        ]}
        variant="full"
      />,
    );
    expect(screen.getByTestId("interrupted-chip")).toBeInTheDocument();
    expect(screen.getByText("Reading a file")).toBeInTheDocument();
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
  });

  it("suppressLive (parked gate) hides the live line but keeps the trail", async () => {
    const { MessageBubble } = await import(
      "@/components/chat/message-bubble"
    );
    render(
      <MessageBubble
        role="assistant"
        content="Working on it"
        messageState="tool_use"
        toolLabel="Checking CI status"
        liveNarration="Drafting the summary…"
        activity={[
          { label: "Triage open pull requests", kind: "tool", startedAt: Date.now() },
        ]}
        suppressLive
        variant="full"
      />,
    );
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
    expect(screen.getByText("Triage open pull requests")).toBeInTheDocument();
  });
});
