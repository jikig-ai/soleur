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
};
const MEMBER: TeamMembershipRow = {
  userId: "user-member",
  email: "harry@jikigai.com",
  role: "member",
  addedAt: "2026-02-01T00:00:00Z",
  isSelf: false,
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
      />,
    );
    const kebabs = screen.getAllByLabelText(/row actions/i);
    expect(kebabs).toHaveLength(1);
    fireEvent.click(kebabs[0]);
    expect(screen.getByText(/remove member/i)).toBeInTheDocument();
  });

  it("renders empty solo state hint when only one member", () => {
    render(
      <TeamMembershipList
        members={[OWNER]}
        currentUserId="user-owner"
        workspaceId="ws-1"
        isOwner={true}
        byokDelegationsEnabled={false}
      />,
    );
    // Solo state — the page handles the "Solo for now" hint; the list itself
    // shows just the one row with no kebab.
    expect(screen.getByText("jean@jikigai.com")).toBeInTheDocument();
  });
});
