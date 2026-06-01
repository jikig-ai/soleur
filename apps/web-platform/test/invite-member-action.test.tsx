import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { InviteMemberAction } from "@/components/settings/invite-member-action";

// RBAC gating: inviting a member is an owner-only action (the
// /api/workspace/invite-member route 403s a non-owner). The "+ Invite member"
// trigger must be hidden from Members so the UI matches the server boundary,
// mirroring the isOwner gating convention used by PendingInvitesList and
// DelegationToggle.
describe("InviteMemberAction RBAC gating", () => {
  it("Owner (isOwner=true): renders the '+ Invite member' trigger", () => {
    render(<InviteMemberAction workspaceId="ws-1" isOwner={true} />);
    expect(
      screen.getByRole("button", { name: /invite member/i }),
    ).toBeInTheDocument();
  });

  it("Member (isOwner=false): renders nothing (trigger hidden)", () => {
    const { container } = render(
      <InviteMemberAction workspaceId="ws-1" isOwner={false} />,
    );
    expect(
      screen.queryByRole("button", { name: /invite member/i }),
    ).not.toBeInTheDocument();
    expect(container).toBeEmptyDOMElement();
  });
});
