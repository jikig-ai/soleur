import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// feat-invite-accept-membership-byok (#4715), Phase 7 / spec-flow J3.
// PendingInviteBannerRecovery self-fetches /api/workspace/pending-invites and
// renders PendingInviteBanner on /dashboard (NOT /dashboard/chat, which already
// mounts the banner server-side — no double render).

const { mockPathname, mockPush, mockRefresh, mockReportSilentFallback } =
  vi.hoisted(() => ({
    mockPathname: { value: "/dashboard" },
    mockPush: vi.fn(),
    mockRefresh: vi.fn(),
    mockReportSilentFallback: vi.fn(),
  }));

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname.value,
  useRouter: () => ({ push: mockPush, refresh: mockRefresh }),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

import { PendingInviteBannerRecovery } from "@/components/dashboard/pending-invite-banner-recovery";

const INVITE = {
  id: "inv-9",
  workspace_id: "ws-1",
  workspace_name: "Acme",
  inviter_name: "Dana",
  role: "member",
  expires_at: "2026-12-31",
  created_at: "2026-06-01",
};

function mockFetchInvites(invites: unknown[]) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (typeof url === "string" && url.includes("pending-invites")) {
        return { ok: true, json: async () => ({ invites }) };
      }
      return { ok: true, json: async () => ({}) };
    }),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname.value = "/dashboard";
});
afterEach(() => vi.unstubAllGlobals());

describe("PendingInviteBannerRecovery (#4715 J3)", () => {
  it("shows the banner for a pending-invite user on /dashboard", async () => {
    mockFetchInvites([INVITE]);
    render(<PendingInviteBannerRecovery />);
    expect(await screen.findByText(/invited you to join/i)).toBeTruthy();
    expect(screen.getByText("Dana")).toBeTruthy();
    expect(screen.getByText("Acme")).toBeTruthy();
  });

  it("renders nothing and never fetches on /dashboard/chat (server mount owns it)", async () => {
    mockPathname.value = "/dashboard/chat/abc";
    mockFetchInvites([INVITE]);
    const { container } = render(<PendingInviteBannerRecovery />);
    // Give any stray effect a tick; it must stay empty and skip the fetch.
    await new Promise((r) => setTimeout(r, 10));
    expect(container.firstChild).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("one-click Accept fires the accept-invite RPC", async () => {
    const fetchSpy = vi.fn(async (url: string) => {
      if (url.includes("pending-invites")) {
        return { ok: true, json: async () => ({ invites: [INVITE] }) };
      }
      return { ok: true, json: async () => ({}) };
    });
    vi.stubGlobal("fetch", fetchSpy);

    render(<PendingInviteBannerRecovery />);
    const acceptBtn = await screen.findByRole("button", { name: /^accept$/i });
    await userEvent.click(acceptBtn);

    await waitFor(() =>
      expect(
        fetchSpy.mock.calls.some(([u]) =>
          String(u).includes("/api/workspace/accept-invite"),
        ),
      ).toBe(true),
    );
  });

  it("renders nothing when there are no pending invites", async () => {
    mockFetchInvites([]);
    const { container } = render(<PendingInviteBannerRecovery />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(container.firstChild).toBeNull();
  });
});
