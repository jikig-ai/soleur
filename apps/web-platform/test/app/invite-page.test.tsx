import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// feat-invite-accept-membership-byok (#4715), Phase 4. Two guarantees on the
// public invite page:
//  - FR2 (Art. 13): the shared-data/billing disclosure renders co-temporally
//    with the Accept button (not deferred to onboarding).
//  - spec-flow J7: the terminal "Invitation not available" card offers a
//    forward hop instead of a hard dead-end.

const { mockGetUser, mockRpc } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockRpc: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: mockGetUser } }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: mockRpc }),
}));

vi.mock("@/server/workspace-invitations", () => ({
  hashToken: (t: string) => `hash:${t}`,
}));

// InviteActions is a "use client" component with its own fetch wiring; stub it
// so this test focuses on the server page's disclosure + CTA.
vi.mock("@/app/(public)/invite/[token]/invite-actions", () => ({
  InviteActions: () => <div data-testid="invite-actions" />,
}));

import InvitePage from "@/app/(public)/invite/[token]/page";

const VALID_LOOKUP = {
  ok: true,
  invitation_id: "inv-1",
  workspace_name: "Acme",
  inviter_name: "Dana",
  role: "member",
  invitee_email: "joiner@example.com",
  expires_at: "2026-12-31T00:00:00Z",
};

beforeEach(() => {
  vi.clearAllMocks();
});

function renderPage(token = "tok123") {
  return InvitePage({ params: Promise.resolve({ token }) });
}

describe("invite page — Art. 13 disclosure (FR2)", () => {
  it("renders the shared-data/billing disclosure on a valid invite", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    mockRpc.mockResolvedValue({ data: VALID_LOOKUP, error: null });

    render(await renderPage());

    expect(
      screen.getByText(/share this workspace's data, agents, and billing/i),
    ).toBeInTheDocument();
    expect(screen.getByTestId("invite-actions")).toBeInTheDocument();
  });
});

describe("invite page — terminal card forward CTA (J7)", () => {
  it("authenticated user on an unavailable invite gets a dashboard CTA", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1", email: "u@x.com" } } });
    mockRpc.mockResolvedValue({ data: { ok: false }, error: null });

    render(await renderPage());

    expect(screen.getByText(/Invitation not available/i)).toBeInTheDocument();
    const cta = screen.getByRole("link", { name: /Go to your dashboard/i });
    expect(cta).toHaveAttribute("href", "/dashboard");
  });

  it("anonymous user on an unavailable invite gets a sign-in CTA", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    mockRpc.mockResolvedValue({ data: null, error: null });

    render(await renderPage());

    const cta = screen.getByRole("link", { name: /Sign in/i });
    expect(cta).toHaveAttribute("href", "/login");
  });
});
