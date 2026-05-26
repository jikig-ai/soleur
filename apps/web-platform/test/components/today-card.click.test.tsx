import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { userEvent } from "@testing-library/user-event";

import { TodayCard } from "@/components/dashboard/today-card";

// PR-A (#4124) — Component-level click test for GitHubCard + KbDriftCard.
// PR-B (#4379) — Updated to mock supabase/client because TodayCard now
// renders <LeaderLoopStatus> after non-degraded acknowledgment; that
// component subscribes to Realtime + polls the action_sends row. The
// pill assertion now keys off LeaderLoopStatus' state-matrix "done"
// branch when artifact + reversal_handles exist, or on the inline
// AcknowledgedPill when degraded is set.
//
// Mock policy: method-aware `vi.fn` fetch mock (no MSW) per
// 2026-05-20-happy-dom-ws-fetch-blockade.md. Assertions key off public
// DOM contract (`data-testid` + label text) per
// 2026-05-06-test-public-dom-contract-not-setstate-side-effects.md.

const { createClientMock } = vi.hoisted(() => ({
  createClientMock: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: createClientMock,
}));

function buildNoOpSupabaseClient() {
  const fromChain: Record<string, unknown> = {};
  Object.assign(fromChain, {
    select: vi.fn(() => fromChain),
    eq: vi.fn(() => fromChain),
    maybeSingle: vi.fn(() => Promise.resolve({ data: null, error: null })),
  });
  const channel: Record<string, unknown> = {};
  Object.assign(channel, {
    on: vi.fn(() => channel),
    subscribe: vi.fn(() => channel),
  });
  return {
    from: vi.fn(() => fromChain),
    channel: vi.fn(() => channel),
    removeChannel: vi.fn(),
  };
}

const ORIGINAL_FETCH = globalThis.fetch;

interface MockResponse {
  status: number;
  body: Record<string, unknown>;
}

let nextResponse: MockResponse = { status: 200, body: {} };

beforeEach(() => {
  createClientMock.mockReset();
  createClientMock.mockImplementation(buildNoOpSupabaseClient);
  globalThis.fetch = vi.fn(async (input: string | URL | Request) => {
    const url = typeof input === "string" ? input : input.toString();
    // LeaderLoopStatus pulls /cost on mount + on every Realtime UPDATE.
    // Keep it harmless so the pill / state-matrix assertions key off the
    // /send response only.
    if (url.endsWith("/cost")) {
      return new Response(
        JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(JSON.stringify(nextResponse.body), {
      status: nextResponse.status,
      headers: { "Content-Type": "application/json" },
    });
  }) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("GitHubCard onClick (PR-A)", () => {
  it("happy-path: click 'Spawn review agent' → POST /send → 200 → LeaderLoopStatus mounts (acknowledged_starting)", async () => {
    // PR-B: with PR-A's pill replaced by LeaderLoopStatus on non-degraded
    // sends, the immediate 200 response renders the panel in
    // "acknowledged_starting" state; the action_sends row drives further
    // transitions (covered in leader-loop-status.test.tsx).
    nextResponse = {
      status: 200,
      body: {
        id: "as-1",
        action_class: "engineering.pr_review_pending",
        tier: "draft_one_click",
        action_send_id: "as-1",
        artifact_view_url: "https://github.com/acme/repo/pull/7",
      },
    };

    render(
      <TodayCard
        id="msg-1"
        source="github"
        sourceRef="pr-acme:repo:7"
        owningDomain="engineering"
        draftPreview="fix: leak in foo path"
        urgency="normal"
      />,
    );

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Let CTO spawn a PR-review agent/));

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel).toBeInTheDocument();
      expect(panel.getAttribute("data-state-kind")).toBe(
        "acknowledged_starting",
      );
    });

    // /send POST is the first call; subsequent /cost calls are LeaderLoopStatus
    // pull on mount + Realtime UPDATE refreshes.
    const sendCalls = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.filter(
      (c) => String(c[0]).endsWith("/send"),
    );
    expect(sendCalls).toHaveLength(1);
    expect((sendCalls[0][1] as RequestInit).method).toBe("POST");
  });

  it("403 no_active_grant → renders scope-grant copy", async () => {
    nextResponse = {
      status: 403,
      body: {
        error: "no_active_grant",
        deny_reason: "no_scope_grant",
        action_class: "engineering.pr_review_pending",
      },
    };

    render(
      <TodayCard
        id="msg-1"
        source="github"
        sourceRef="pr-acme:repo:7"
        owningDomain="engineering"
        draftPreview="fix: leak in foo path"
        urgency="normal"
      />,
    );

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Let CTO spawn a PR-review agent/));

    await waitFor(() => {
      expect(
        screen.getByText(/You need a scope grant first/),
      ).toBeInTheDocument();
    });
    // Pill does NOT render — operator still has the spawn button.
    expect(screen.queryByTestId("acknowledged-pill")).toBeNull();
  });

  it("409 already_sent → soft-success mounts LeaderLoopStatus (acknowledged_starting)", async () => {
    // PR-B: 409 still flips acknowledged=true and (since degraded is unset)
    // renders LeaderLoopStatus instead of the inline pending pill.
    nextResponse = {
      status: 409,
      body: { error: "already_sent", message_id: "msg-1" },
    };

    render(
      <TodayCard
        id="msg-1"
        source="github"
        sourceRef="pr-acme:repo:7"
        owningDomain="engineering"
        draftPreview="fix: leak in foo path"
        urgency="normal"
      />,
    );

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Let CTO spawn a PR-review agent/));

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel).toBeInTheDocument();
      expect(panel.getAttribute("data-state-kind")).toBe(
        "acknowledged_starting",
      );
    });
  });

  it("200 with degraded:'enqueue_failed' → 'Acknowledged (queued)' pill", async () => {
    nextResponse = {
      status: 200,
      body: {
        id: "as-1",
        action_class: "engineering.pr_review_pending",
        tier: "draft_one_click",
        action_send_id: "as-1",
        artifact_view_url: "https://github.com/acme/repo/pull/7",
        degraded: "enqueue_failed",
      },
    };

    render(
      <TodayCard
        id="msg-1"
        source="github"
        sourceRef="pr-acme:repo:7"
        owningDomain="engineering"
        draftPreview="fix: leak in foo path"
        urgency="normal"
      />,
    );

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Let CTO spawn a PR-review agent/));

    await waitFor(() => {
      const pill = screen.getByTestId("acknowledged-pill");
      expect(pill).toBeInTheDocument();
      expect(pill.getAttribute("data-pill-state")).toBe("queued");
      expect(pill.textContent).toMatch(/Acknowledged \(queued/);
    });
  });
});

describe("KbDriftCard onClick (PR-A)", () => {
  it("happy-path: click 'Fix link' → POST /send → 200 with degraded:'no_artifact_in_pr_a' → no_artifact pill", async () => {
    // kb_drift link-* refs don't carry an (owner, repo, number) GitHub
    // target; the route returns 200 with degraded:"no_artifact_in_pr_a"
    // and skips the Inngest dispatch entirely (avoids the
    // malformed_source_ref deadletter + Sentry spam). The card renders
    // the explicit no_artifact pill rather than the misleading pending
    // pill. PR-B (#4360) handles per-class resolution.
    nextResponse = {
      status: 200,
      body: {
        id: "as-2",
        action_class: "knowledge.kb_drift",
        tier: "draft_one_click",
        action_send_id: "as-2",
        artifact_view_url: "",
        degraded: "no_artifact_in_pr_a",
      },
    };

    render(
      <TodayCard
        id="msg-2"
        source="kb-drift"
        sourceRef="link-deadbeef00000000"
        owningDomain="knowledge"
        draftPreview="Broken link in foo.md → missing.md"
        urgency="normal"
      />,
    );

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/^Fix link$/));

    await waitFor(() => {
      const pill = screen.getByTestId("acknowledged-pill");
      expect(pill).toBeInTheDocument();
      expect(pill.getAttribute("data-pill-state")).toBe("no_artifact");
      expect(pill.textContent).toMatch(/PR-B/);
    });

    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(callArgs[0]).toBe("/api/dashboard/today/msg-2/send");
  });

  it("Buttons are NOT disabled at initial render (PR-A removed the 'Wires in PR-H+1' lock)", () => {
    render(
      <TodayCard
        id="msg-2"
        source="kb-drift"
        sourceRef="link-deadbeef00000000"
        owningDomain="knowledge"
        draftPreview="Broken link"
        urgency="normal"
      />,
    );
    const btn = screen.getByLabelText(/^Fix link$/);
    expect(btn).not.toBeDisabled();
    expect(btn.getAttribute("aria-disabled")).not.toBe("true");
    // The pre-PR-A button carried title="Wires in PR-H+1"; the new
    // button has no title attribute at all.
    const title = btn.getAttribute("title");
    expect(title === null || !/Wires in PR-H/.test(title)).toBe(true);
  });

  it("GitHubCard 'Spawn review agent' button is NOT disabled at initial render", () => {
    render(
      <TodayCard
        id="msg-1"
        source="github"
        sourceRef="pr-acme:repo:7"
        owningDomain="engineering"
        draftPreview="fix: leak"
        urgency="normal"
      />,
    );
    const btn = screen.getByLabelText(/Let CTO spawn a PR-review agent/);
    expect(btn).not.toBeDisabled();
    expect(btn.getAttribute("aria-disabled")).not.toBe("true");
  });
});
