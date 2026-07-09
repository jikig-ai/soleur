import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// SOL-49 follow-up — the workspace invite banner must unmount immediately on
// accept (pessimistic-revert) AND mirror non-2xx + thrown errors to Sentry.
// `vi.hoisted` is load-bearing per learning 2026-05-19.
const { mockRefresh, mockPush } = vi.hoisted(() => ({
  mockRefresh: vi.fn(),
  mockPush: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: mockPush }),
}));

import { PendingInviteBanner } from "@/components/dashboard/pending-invite-banner";

const baseProps = {
  invitationId: "inv-1",
  inviterName: "jean",
  workspaceName: "My Workspace",
};

let fetchMock: ReturnType<typeof vi.fn>;
// GAP E/workspace-switch (ADR-067 staleTimes): accept now HARD-navs via
// window.location.assign (accept-invite calls set_current_workspace_id → a
// cross-workspace boundary that must wipe the Router Cache). Decline still uses
// router.refresh (no workspace switch).
const assignMock = vi.fn();
let originalLocation: Location;

beforeEach(() => {
  mockRefresh.mockClear();
  mockPush.mockClear();
  assignMock.mockClear();
  fetchMock = vi.fn(
    async () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  vi.stubGlobal("fetch", fetchMock);
  originalLocation = window.location;
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: { assign: assignMock, pathname: "/dashboard" } as unknown as Location,
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: originalLocation,
  });
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe("PendingInviteBanner — accept", () => {
  it("renders with the inviter and workspace names", () => {
    render(<PendingInviteBanner {...baseProps} />);
    expect(screen.getByText(/jean/)).toBeInTheDocument();
    expect(screen.getByText(/my workspace/i)).toBeInTheDocument();
  });

  it("accept success: banner unmounts AND HARD-navs (window.location.assign) to settings/team", async () => {
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /^accept$/i }));

    expect(screen.queryByRole("button", { name: /^accept$/i })).toBeNull();
    // GAP E/workspace-switch: hard nav (not soft push), no router.refresh.
    expect(assignMock).toHaveBeenCalledWith("/dashboard/settings/team");
    expect(mockPush).not.toHaveBeenCalled();
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  it("accept non-2xx: banner stays mounted, refresh NOT called", async () => {
    fetchMock.mockImplementationOnce(
      async () => new Response(JSON.stringify({ error: "boom" }), { status: 500 }),
    );
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /^accept$/i }));

    expect(screen.getByRole("button", { name: /^accept$/i })).toBeInTheDocument();
    expect(assignMock).not.toHaveBeenCalled();
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  it("accept fetch rejection: banner stays mounted, refresh NOT called", async () => {
    fetchMock.mockRejectedValueOnce(new Error("network"));
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /^accept$/i }));

    expect(screen.getByRole("button", { name: /^accept$/i })).toBeInTheDocument();
    expect(mockRefresh).not.toHaveBeenCalled();
  });
});

describe("PendingInviteBanner — decline", () => {
  it("decline success: banner unmounts AND refresh fires (no navigation)", async () => {
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /^decline$/i }));

    expect(screen.queryByRole("button", { name: /^decline$/i })).toBeNull();
    expect(mockRefresh).toHaveBeenCalledTimes(1);
    expect(mockPush).not.toHaveBeenCalled();
  });

  it("decline non-2xx: banner stays mounted, refresh NOT called", async () => {
    fetchMock.mockImplementationOnce(
      async () => new Response(JSON.stringify({ error: "boom" }), { status: 500 }),
    );
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /^decline$/i }));

    expect(screen.getByRole("button", { name: /^decline$/i })).toBeInTheDocument();
    expect(mockRefresh).not.toHaveBeenCalled();
  });
});

describe("PendingInviteBanner — dismiss", () => {
  it("clicking the X dismisses without calling fetch", async () => {
    render(<PendingInviteBanner {...baseProps} />);
    await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));

    expect(screen.queryByText(/invited you to join/i)).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
