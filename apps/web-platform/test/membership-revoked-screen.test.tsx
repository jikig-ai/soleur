import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { MembershipRevokedScreen } from "@/components/dashboard/membership-revoked-screen";
import { OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT } from "@/lib/ws-client";
import type { MembershipRevokedPreamble } from "@/lib/types";

function dispatchRevoke(detail: MembershipRevokedPreamble | null) {
  window.dispatchEvent(
    new CustomEvent(OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT, { detail }),
  );
}

describe("MembershipRevokedScreen", () => {
  beforeEach(() => {
    // Nothing to reset — the screen reads from window event listener state
    // which is bound on mount.
  });

  it("renders nothing until the membership-revoked window event fires", () => {
    const { container } = render(<MembershipRevokedScreen />);
    expect(container).toBeEmptyDOMElement();
  });

  it("renders terminal screen with org name on event", () => {
    render(<MembershipRevokedScreen />);
    act(() =>
      dispatchRevoke({
        type: "membership_revoked",
        organizationName: "jikigai",
      }),
    );
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(screen.getByText(/You were removed from jikigai/i)).toBeInTheDocument();
  });

  it("falls back to 'this workspace' when org name is null", () => {
    render(<MembershipRevokedScreen />);
    act(() =>
      dispatchRevoke({ type: "membership_revoked", organizationName: null }),
    );
    expect(screen.getByText(/You were removed from this workspace/i)).toBeInTheDocument();
  });

  it("renders a Sign out CTA", () => {
    render(<MembershipRevokedScreen />);
    act(() =>
      dispatchRevoke({
        type: "membership_revoked",
        organizationName: "Acme",
      }),
    );
    const cta = screen.getByRole("link", { name: /sign out/i });
    expect(cta).toBeInTheDocument();
    expect(cta.getAttribute("href")).toBe("/login?signout=1");
  });
});
