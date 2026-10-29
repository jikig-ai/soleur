/**
 * #4672 task 3.1: the away-user landing surface sends the decision over HTTP and changes the card only on the server's
 * answer. Fail closed: a non-OK, a malformed answer and a network error all end in the static error with the card unchanged.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ApprovalLanding } from "@/components/approvals/approval-landing";
import { canonicalizeAction } from "@/server/approval/canonical";
import { renderApprovalView } from "@/server/approval/render";
import { SAMPLES, TOOLS } from "../approval/fixtures";

const ID = "00000000-0000-4000-8000-000000000006";
const s = SAMPLES[TOOLS.emailSend];
const view = renderApprovalView(canonicalizeAction(TOOLS.emailSend, s.input, s.server));

// Created long ago: the agent's 5 minute wait is over, so an approval is a late one.
const initial = {
  status: "pending" as const,
  expiresAt: "2099-01-01T00:00:00Z",
  createdAt: "2026-10-28T10:00:00Z",
  decidedAt: null,
  decidedByViewer: false,
};

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn();
  global.fetch = fetchMock as unknown as typeof fetch;
});
afterEach(cleanup);

const json = (body: unknown, ok = true, status = 200) => ({ ok, status, json: async () => body });
const state = () => screen.getByTestId("approval-request-card").getAttribute("data-approval-state");

describe("ApprovalLanding", () => {
  it("renders the shared card in the landing layout with the 'agent stopped waiting' sub-line", () => {
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    expect(state()).toBe("pending_owner");
    expect(screen.getByTestId("approval-subline").textContent).toContain("stopped waiting after 5 minutes");
    expect(screen.getByRole("button", { name: "Approve" }).className).toContain("w-full");
  });

  it("POSTs the closed decision to the decide route with no user field, then shows the late-approved state", async () => {
    fetchMock.mockResolvedValue(json({ outcome: "decided", approval: { status: "approved", decided_at: "2026-10-28T12:00:00Z" } }));
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`/api/approvals/${ID}/decide`);
    expect(init.method).toBe("POST");
    expect(JSON.parse(init.body as string)).toEqual({ decision: "approve" });
    await waitFor(() => expect(state()).toBe("approved_late"));
    expect(screen.getByTestId("approval-decided-label").textContent).toContain("by you");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("deny settles to the denied state", async () => {
    fetchMock.mockResolvedValue(json({ outcome: "decided", approval: { status: "rejected", decided_at: "2026-10-28T12:00:00Z" } }));
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Deny" }));
    });
    await waitFor(() => expect(state()).toBe("denied"));
  });

  it("an overdue request answers 'expired': the card shows expired, never approved", async () => {
    fetchMock.mockResolvedValue(json({ outcome: "expired", approval: { status: "expired", decided_at: null } }));
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    await waitFor(() => expect(state()).toBe("expired"));
  });

  it("a closed conversation answers 'closed': nothing is recorded and the card says so", async () => {
    fetchMock.mockResolvedValue(json({ outcome: "closed", approval: { status: "pending", decided_at: null } }));
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    await waitFor(() => expect(state()).toBe("conversation_closed"));
  });

  it("the loser of a two-Owner race sees the already-decided state", async () => {
    fetchMock.mockResolvedValue(json({ outcome: "conflict", approval: { status: "rejected", decided_at: "2026-10-28T11:00:00Z" } }));
    render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    await waitFor(() => expect(state()).toBe("already_decided"));
  });

  for (const [name, impl] of [
    ["a non-OK answer", () => Promise.resolve(json({ error: "Not found" }, false, 404))],
    ["a 500", () => Promise.resolve(json({ error: "Internal error" }, false, 500))],
    ["a malformed answer", () => Promise.resolve(json({ outcome: "banana" }))],
    ["a network error", () => Promise.reject(new TypeError("fetch failed"))],
  ] as const) {
    it(`${name}: static error, card unchanged, buttons unlocked (no optimistic approved state)`, async () => {
      fetchMock.mockImplementation(impl);
      render(<ApprovalLanding approvalId={ID} view={view} initial={initial} requestCount={1} />);
      await act(async () => {
        fireEvent.click(screen.getByRole("button", { name: "Approve" }));
      });
      await waitFor(() => expect(screen.getByTestId("approval-decide-error")).toBeTruthy());
      expect(state()).toBe("pending_owner");
      expect((screen.getByRole("button", { name: "Approve" }) as HTMLButtonElement).disabled).toBe(false);
    });
  }

  it("renders the details-removed card for a scrubbed row (no buttons)", () => {
    render(<ApprovalLanding approvalId={ID} view={null} initial={{ ...initial, status: "expired", decidedAt: null }} requestCount={1} />);
    expect(state()).toBe("details_removed");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("an expired-after-approval row renders the calm 04H state", () => {
    render(<ApprovalLanding approvalId={ID} view={view} initial={{ ...initial, status: "expired", decidedAt: "2026-10-28T10:01:00Z" }} requestCount={1} />);
    expect(state()).toBe("expired_after_approval");
  });
});
