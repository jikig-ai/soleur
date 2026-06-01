import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { TeamMembershipList } from "@/components/settings/team-membership-list";
import type { TeamMembershipRow } from "@/server/team-membership-resolver";

const OWNER: TeamMembershipRow = {
  userId: "user-owner",
  email: "jean@jikigai.com",
  role: "owner",
  addedAt: "2026-01-01T00:00:00Z",
  isSelf: true,
  hasEffectiveKey: true,
};
const MEMBER: TeamMembershipRow = {
  userId: "user-member",
  email: "harry@jikigai.com",
  role: "member",
  addedAt: "2026-02-01T00:00:00Z",
  isSelf: false,
  hasEffectiveKey: true,
};

describe("TeamMembershipList", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders rows for each member with email + role badge", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    expect(screen.getByText("jean@jikigai.com")).toBeInTheDocument();
    expect(screen.getByText("harry@jikigai.com")).toBeInTheDocument();
    // "Owner" appears once as the role badge. "Member" appears twice (header
    // column label + role badge) — narrow by border class on the badge.
    expect(screen.getByText("Owner")).toBeInTheDocument();
    const memberBadges = screen
      .getAllByText("Member")
      .filter((el) => el.className.includes("rounded-md"));
    expect(memberBadges).toHaveLength(1);
  });

  it("marks current user with '— (you)'", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    expect(screen.getByText(/—\s*\(you\)/)).toBeInTheDocument();
  });

  it("AC-FLOW4: owner self row has NO kebab menu trigger", () => {
    render(
      <TeamMembershipList
        members={[OWNER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    expect(screen.queryByLabelText(/row actions/i)).not.toBeInTheDocument();
  });

  it("non-self row exposes kebab menu with Remove action", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    const kebabs = screen.getAllByLabelText(/row actions/i);
    expect(kebabs).toHaveLength(1);
    fireEvent.click(kebabs[0]);
    expect(screen.getByText(/remove member/i)).toBeInTheDocument();
  });

  // AC4 (over-gating regression guard): the Owner positive control for Transfer
  // ownership. The Member tests above lock that Transfer stays hidden; this pins
  // the counterpart — an Owner viewing a non-owner member row CAN still reach
  // Transfer ownership. Without it, a regression hiding Transfer from Owners too
  // would pass every other test.
  it("Owner (isOwner=true): non-owner member row exposes Transfer ownership", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    const kebabs = screen.getAllByLabelText(/row actions/i);
    expect(kebabs).toHaveLength(1);
    fireEvent.click(kebabs[0]);
    expect(screen.getByText(/transfer ownership/i)).toBeInTheDocument();
  });

  // RBAC gating: a Member (isOwner=false) viewing the team must NOT see any
  // owner-only affordance. The kebab trigger gates the whole owner-only menu
  // (Remove member + Transfer ownership), so a Member sees no kebab on any
  // non-self row. Owner-only API routes still 403 a Member as defense-in-depth.
  it("Member (isOwner=false): non-self row exposes NO kebab trigger", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-member"
        workspaceId="ws-1"
        isOwner={false}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    // The OWNER row is non-self for this Member; without the gate it would
    // render a kebab. With the gate, no row exposes one.
    expect(screen.queryByLabelText(/row actions/i)).not.toBeInTheDocument();
  });

  // Attempting to open any kebab a Member can reach must surface no owner-only
  // action. The kebab trigger is itself gated, so without the fix the trigger
  // exists, opens, and reveals "Remove member" (RED); with the fix there is no
  // trigger to open (GREEN). Clicking-when-present is load-bearing: a closed
  // menu hides the text regardless of the gate, which would pass vacuously.
  it("Member (isOwner=false): no Remove member action is reachable", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-member"
        workspaceId="ws-1"
        isOwner={false}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    for (const kebab of screen.queryAllByLabelText(/row actions/i)) {
      fireEvent.click(kebab);
    }
    expect(screen.queryByText(/remove member/i)).not.toBeInTheDocument();
  });

  // Regression-lock (already GREEN on main): "Transfer ownership" was already
  // gated by `{isOwner && member.role !== "owner"}`, so a Member never saw it
  // even before this fix. This test does NOT exercise the new `showActions`
  // gate — it pins that the pre-existing gating stays in place.
  it("Member (isOwner=false): no Transfer ownership action is reachable", () => {
    render(
      <TeamMembershipList
        members={[OWNER, MEMBER]}
        currentUserId="user-member"
        workspaceId="ws-1"
        isOwner={false}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    for (const kebab of screen.queryAllByLabelText(/row actions/i)) {
      fireEvent.click(kebab);
    }
    expect(screen.queryByText(/transfer ownership/i)).not.toBeInTheDocument();
  });

  // #4715 Phase 9 — owner "Share a key" prompt for a keyless, undelegated,
  // non-self member (only when byok delegations are enabled).
  const KEYLESS_MEMBER: TeamMembershipRow = {
    userId: "user-keyless",
    email: "joiner@jikigai.com",
    role: "member",
    addedAt: "2026-03-01T00:00:00Z",
    isSelf: false,
    hasEffectiveKey: false,
  };

  function renderWithDelegations(members: TeamMembershipRow[]) {
    return render(
      <TeamMembershipList
        members={members}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={true}
        organizationName="Test Org"
      />,
    );
  }

  it("Share-a-key: keyless + undelegated + non-self member → hint + 'Share a key' + add-own link", () => {
    renderWithDelegations([OWNER, KEYLESS_MEMBER]);
    expect(screen.getByText(/can view the workspace but can't run tasks/i)).toBeInTheDocument();
    expect(screen.getByText(/share a key/i)).toBeInTheDocument();
    expect(screen.getByText(/ask them to add their own/i)).toBeInTheDocument();
  });

  it("Share-a-key: a member already granted a key by me (delegationFromMe) → no prompt", () => {
    const delegated: TeamMembershipRow = {
      ...KEYLESS_MEMBER,
      delegationFromMe: { id: "d1", dailyCapCents: 2000, todaySpentCents: 0, active: true },
    };
    renderWithDelegations([OWNER, delegated]);
    expect(screen.queryByText(/can view the workspace but can't run tasks/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/share a key/i)).not.toBeInTheDocument();
  });

  it("Share-a-key: a member with their own effective key → no prompt", () => {
    renderWithDelegations([OWNER, { ...KEYLESS_MEMBER, hasEffectiveKey: true }]);
    expect(screen.queryByText(/can view the workspace but can't run tasks/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/share a key/i)).not.toBeInTheDocument();
  });

  it("Share-a-key: the owner's own (self) keyless row never prompts", () => {
    renderWithDelegations([{ ...OWNER, hasEffectiveKey: false }]);
    expect(screen.queryByText(/can view the workspace but can't run tasks/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/share a key/i)).not.toBeInTheDocument();
  });

  it("renders empty solo state hint when only one member", () => {
    render(
      <TeamMembershipList
        members={[OWNER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
        organizationName="Test Org"
      />,
    );
    // Solo state — the page handles the "Solo for now" hint; the list itself
    // shows just the one row with no kebab.
    expect(screen.getByText("jean@jikigai.com")).toBeInTheDocument();
  });
});
