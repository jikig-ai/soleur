import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { PendingInvitesList } from "@/components/settings/pending-invites-list";

// FR1 (owner-gated Cancel control) + FR2 (server-confirmed optimistic removal —
// no silent no-op). feat-cancel-pending-invite, #4634.

const INVITE = {
  id: "inv-1",
  invitee_email: "jean.deruelle@gmail.com",
  role: "member",
  expires_at: new Date(Date.now() + 6 * 86400_000).toISOString(),
  created_at: new Date().toISOString(),
};

const originalFetch = global.fetch;

beforeEach(() => {
  vi.restoreAllMocks();
});
afterEach(() => {
  global.fetch = originalFetch;
});

describe("PendingInvitesList — Cancel action", () => {
  test("renders no Cancel control when isOwner=false", () => {
    render(<PendingInvitesList invites={[INVITE]} workspaceId="ws-1" isOwner={false} />);
    expect(screen.getByText(INVITE.invitee_email)).toBeTruthy();
    expect(screen.queryByRole("button", { name: /cancel/i })).toBeNull();
  });

  test("owner sees a Cancel control per row", () => {
    render(<PendingInvitesList invites={[INVITE]} workspaceId="ws-1" isOwner={true} />);
    expect(screen.getByRole("button", { name: /cancel/i })).toBeTruthy();
  });

  test("removes the row only after the server confirms {ok:true}", async () => {
    global.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    ) as unknown as typeof fetch;

    render(<PendingInvitesList invites={[INVITE]} workspaceId="ws-1" isOwner={true} />);
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    await waitFor(() => {
      expect(screen.queryByText(INVITE.invitee_email)).toBeNull();
    });
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/workspace/cancel-invite",
      expect.objectContaining({ method: "POST" }),
    );
  });

  test("restores the row and surfaces an error when the server returns 500", async () => {
    global.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ error: "rpc_failed" }), { status: 500 }),
    ) as unknown as typeof fetch;

    render(<PendingInvitesList invites={[INVITE]} workspaceId="ws-1" isOwner={true} />);
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    // Row must remain (no silent no-op) and an error must be visible.
    await waitFor(() => {
      expect(screen.getByText(/couldn't cancel|could not cancel|failed|try again/i)).toBeTruthy();
    });
    expect(screen.getByText(INVITE.invitee_email)).toBeTruthy();
  });
});
