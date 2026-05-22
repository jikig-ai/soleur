import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { userEvent } from "@testing-library/user-event";

import { TodayCard } from "@/components/dashboard/today-card";

// PR-A (#4124) — Component-level click test for GitHubCard + KbDriftCard.
//
// First component-level click test for today-card. Drives the happy and
// degraded paths through the shared `useActionSend()` hook by mocking
// `fetch` and asserting (a) the request body, (b) the resulting
// "Acknowledged" pill state.
//
// Mock policy: method-aware `vi.fn` fetch mock (no MSW) per
// 2026-05-20-happy-dom-ws-fetch-blockade.md. Assertions key off public
// DOM contract (`data-testid` + label text) per
// 2026-05-06-test-public-dom-contract-not-setstate-side-effects.md.

const ORIGINAL_FETCH = globalThis.fetch;

interface MockResponse {
  status: number;
  body: Record<string, unknown>;
}

let nextResponse: MockResponse = { status: 200, body: {} };

beforeEach(() => {
  globalThis.fetch = vi.fn(async () => {
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
  it("happy-path: click 'Spawn review agent' → POST /send → 200 → Acknowledged pill with GitHub link", async () => {
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
      const pill = screen.getByTestId("acknowledged-pill");
      expect(pill).toBeInTheDocument();
      expect(pill.getAttribute("data-pill-state")).toBe("ack");
      expect(pill.getAttribute("href")).toBe(
        "https://github.com/acme/repo/pull/7",
      );
    });

    // POST body is empty for draft_one_click (no typed-confirm payload).
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    const callArgs = (globalThis.fetch as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(callArgs[0]).toBe("/api/dashboard/today/msg-1/send");
    expect((callArgs[1] as RequestInit).method).toBe("POST");
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

  it("409 already_sent → renders Acknowledged pill (soft success)", async () => {
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
      const pill = screen.getByTestId("acknowledged-pill");
      expect(pill).toBeInTheDocument();
      // No artifact URL available on already_sent, so pill state is pending.
      expect(pill.getAttribute("data-pill-state")).toBe("pending");
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
  it("happy-path: click 'Fix link' → POST /send → 200 → Acknowledged (pending artifact) pill", async () => {
    // kb_drift link-* refs deadletter at the Inngest function as
    // malformed_source_ref until PR-B; the route still returns 200 with
    // an empty artifact_view_url so the card renders the pending pill.
    nextResponse = {
      status: 200,
      body: {
        id: "as-2",
        action_class: "knowledge.kb_drift",
        tier: "draft_one_click",
        action_send_id: "as-2",
        artifact_view_url: "",
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
      expect(pill.getAttribute("data-pill-state")).toBe("pending");
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
