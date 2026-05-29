import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { InviteActions } from "@/app/(public)/invite/[token]/invite-actions";

// next/navigation useRouter is used by the component; stub it.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const BASE = {
  invitationId: "inv-1",
  token: "tok-abc",
  expiresAt: "2026-06-05T00:00:00.000Z",
};

describe("InviteActions — invitee-email gating", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, json: () => Promise.resolve({}) }),
    );
  });

  it("mismatch: authenticated but not the intended invitee → Accept disabled, neutral notice, no raw code", () => {
    render(
      <InviteActions
        {...BASE}
        isAuthenticated={true}
        isIntendedInvitee={false}
        inviteeEmail="intended@jikigai.com"
        signedInEmail="someone.else@jikigai.com"
      />,
    );

    const accept = screen.getByRole("button", { name: /accept invitation/i });
    expect(accept).toBeDisabled();

    // The invited email is surfaced so the user knows which account to use.
    expect(screen.getByText(/intended@jikigai\.com/i)).toBeInTheDocument();

    // The raw server reason code must never render.
    expect(screen.queryByText(/not_intended_invitee/i)).toBeNull();

    // The red error box (failed-action styling) must NOT be the mismatch surface.
    expect(document.querySelector(".bg-red-500\\/10")).toBeNull();
  });

  it("match: authenticated and is the intended invitee → Accept enabled, no mismatch notice", () => {
    render(
      <InviteActions
        {...BASE}
        isAuthenticated={true}
        isIntendedInvitee={true}
        inviteeEmail="intended@jikigai.com"
        signedInEmail="intended@jikigai.com"
      />,
    );

    const accept = screen.getByRole("button", { name: /accept invitation/i });
    expect(accept).not.toBeDisabled();
    expect(screen.queryByText(/signed in as/i)).toBeNull();
  });

  it("unauthenticated → signup CTA unchanged", () => {
    render(
      <InviteActions
        {...BASE}
        isAuthenticated={false}
        isIntendedInvitee={false}
        inviteeEmail="intended@jikigai.com"
        signedInEmail=""
      />,
    );
    expect(
      screen.getByText(/create an account to join/i),
    ).toBeInTheDocument();
  });

  it("humanized error: a defensive 403 not_intended_invitee renders human copy, not the raw code", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ error: "not_intended_invitee" }),
    });
    vi.stubGlobal("fetch", mockFetch);

    render(
      <InviteActions
        {...BASE}
        isAuthenticated={true}
        isIntendedInvitee={true}
        inviteeEmail="intended@jikigai.com"
        signedInEmail="intended@jikigai.com"
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /accept invitation/i }));

    await vi.waitFor(() => {
      expect(mockFetch).toHaveBeenCalled();
    });

    // Raw token must not leak; a human-readable message must appear.
    await vi.waitFor(() => {
      expect(screen.queryByText(/not_intended_invitee/i)).toBeNull();
      expect(
        screen.getByText(/isn't addressed to your account/i),
      ).toBeInTheDocument();
    });
  });
});
