import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import { OrgSwitcher } from "@/components/dashboard/org-switcher";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

const JIKIGAI: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000aaaa",
  organizationName: "jikigai",
  workspaceId: "00000000-0000-0000-0000-00000000bbbb",
  role: "owner",
  memberCount: 2,
  isCurrent: true,
};
const ACME: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000cccc",
  organizationName: "Acme Studio",
  workspaceId: "00000000-0000-0000-0000-00000000dddd",
  role: "member",
  memberCount: 5,
  isCurrent: false,
};

describe("OrgSwitcher", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("AC-C: renders nothing when user belongs to only 1 organization", () => {
    const { container } = render(<OrgSwitcher memberships={[JIKIGAI]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("AC-C: renders nothing when memberships list is empty", () => {
    const { container } = render(<OrgSwitcher memberships={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("renders chip with current-org name + role badge when count > 1", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    const trigger = screen.getByRole("button", { name: /switch workspace/i });
    expect(trigger).toBeInTheDocument();
    expect(trigger.textContent).toContain("jikigai");
    expect(trigger.textContent).toContain("Owner");
  });

  it("dropdown lists all memberships with role + member count when chip is clicked", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    expect(within(menu).getByText("Your workspaces")).toBeInTheDocument();
    expect(within(menu).getByText("jikigai")).toBeInTheDocument();
    expect(within(menu).getByText("Acme Studio")).toBeInTheDocument();
    expect(within(menu).getByText(/Owner · 2 members/)).toBeInTheDocument();
    expect(within(menu).getByText(/Member · 5 members/)).toBeInTheDocument();
  });

  it("current org row shows checkmark", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    const currentRow = within(menu)
      .getByText("jikigai")
      .closest("[data-testid='org-row']");
    expect(currentRow).toBeTruthy();
    expect(currentRow?.querySelector("[data-testid='current-mark']")).toBeTruthy();
  });

  it("selecting a non-current org calls onSwitch with that organizationId", () => {
    const onSwitch = vi.fn();
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} onSwitch={onSwitch} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    fireEvent.click(within(menu).getByText("Acme Studio"));
    expect(onSwitch).toHaveBeenCalledWith(ACME.organizationId);
  });

  it("selecting the current org is a no-op (no onSwitch call)", () => {
    const onSwitch = vi.fn();
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} onSwitch={onSwitch} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    fireEvent.click(within(menu).getByText("jikigai"));
    expect(onSwitch).not.toHaveBeenCalled();
  });

  // AC7 (feat-one-shot-workspace-untitled-name): once migration 091 backfills
  // non-NULL names, the resolver's `?? "Untitled"` guard is unreachable. A
  // two-org fixture with real names must render both names and never the
  // "Untitled" sentinel.
  it("AC7: renders real org names, never the 'Untitled' sentinel", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    expect(within(menu).getByText("jikigai")).toBeInTheDocument();
    expect(within(menu).getByText("Acme Studio")).toBeInTheDocument();
    expect(within(menu).queryByText("Untitled")).not.toBeInTheDocument();
  });
});
