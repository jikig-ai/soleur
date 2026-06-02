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

  it("RQ7: a solo user (1 org) sees a NON-interactive identity chip with the workspace name, no switcher", () => {
    render(<OrgSwitcher memberships={[JIKIGAI]} />);
    // name visible for orientation
    expect(screen.getByTestId("workspace-identity-static")).toHaveTextContent(
      "jikigai",
    );
    // ...but no interactive switch affordance (nothing to switch to)
    expect(
      screen.queryByRole("button", { name: /switch workspace/i }),
    ).not.toBeInTheDocument();
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

  it("AC4: dropdown menu is left-anchored (no left-clip classes)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    // The clip-prone centered pattern must be gone...
    expect(menu.className).not.toContain("left-1/2");
    expect(menu.className).not.toContain("-translate-x-1/2");
    // ...replaced by the verified left-anchor precedent.
    expect(menu.className).toContain("left-0");
    expect(menu.className).toContain("top-full");
  });

  // AC7 note: the switcher renders whatever organizationName the resolver
  // supplies (covered by the render tests above). The "Untitled" fallback is
  // owned by the resolver, NOT this component — that arm is tested directly in
  // test/org-memberships-resolver.test.ts (feat-one-shot-workspace-untitled-name).
});
