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
    hasLogo: false,
};
const ACME: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000cccc",
  organizationName: "Acme Studio",
  workspaceId: "00000000-0000-0000-0000-00000000dddd",
  role: "member",
  memberCount: 5,
  isCurrent: false,
    hasLogo: false,
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

  it("AC4/AC5 (solo): the static chip folds in the repo subtitle and drops the role from the face", () => {
    render(<OrgSwitcher memberships={[JIKIGAI]} repoName="jikig-ai/soleur" />);
    const chip = screen.getByTestId("workspace-identity-static");
    // repo subtitle is the muted second line, inside the chip
    const subtitle = within(chip).getByTestId("live-repo-badge");
    expect(subtitle).toHaveTextContent("jikig-ai/soleur");
    // role no longer clutters the face (it's a solo Owner — no info loss)
    expect(chip.textContent).not.toContain("Owner");
  });

  it("solo chip renders no subtitle when no repo is connected (compact, Open Q1)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI]} repoName={null} />);
    const chip = screen.getByTestId("workspace-identity-static");
    expect(within(chip).queryByTestId("live-repo-badge")).toBeNull();
    expect(chip).toHaveTextContent("jikigai");
  });

  it("AC-C: renders nothing when memberships list is empty", () => {
    const { container } = render(<OrgSwitcher memberships={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("AC3/AC5 (multi-org): the closed chip shows name + repo subtitle, NOT the role on the face", () => {
    render(
      <OrgSwitcher memberships={[JIKIGAI, ACME]} repoName="jikig-ai/soleur" />,
    );
    const trigger = screen.getByRole("button", { name: /switch workspace/i });
    expect(trigger).toBeInTheDocument();
    expect(trigger.textContent).toContain("jikigai");
    // repo subtitle folded into the closed pill face
    const subtitle = within(trigger).getByTestId("live-repo-badge");
    expect(subtitle).toHaveTextContent("jikig-ai/soleur");
    // role moved OFF the face (it now lives only in the dropdown rows)
    expect(trigger.textContent).not.toContain("Owner");
  });

  it("multi-org chip renders no subtitle when no repo is connected (Open Q1)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} repoName={null} />);
    const trigger = screen.getByRole("button", { name: /switch workspace/i });
    expect(within(trigger).queryByTestId("live-repo-badge")).toBeNull();
    expect(trigger.textContent).toContain("jikigai");
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

// Phase 1 (#4915): the gold square swatch is replaced by the pure
// presentational WorkspaceIdentityTile (monogram, non-gold) at all three
// switcher identity sites. FR6: gold is reserved for active-workspace accent +
// the single primary action, not the identity swatch fill.
describe("OrgSwitcher — workspace identity tile wiring (Phase 1, #4915)", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("solo chip renders the monogram tile (first initial of the workspace name)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI]} />);
    const chip = screen.getByTestId("workspace-identity-static");
    expect(within(chip).getByTestId("workspace-identity-tile")).toHaveTextContent(
      "J",
    );
  });

  it("multi-org trigger renders the monogram tile", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    const trigger = screen.getByRole("button", { name: /switch workspace/i });
    expect(
      within(trigger).getByTestId("workspace-identity-tile"),
    ).toHaveTextContent("J");
  });

  it("dropdown rows render tiles; the CURRENT row's tile is ring-distinguished, non-current is flat (preserves current vs non-current distinction without a gold fill)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} />);
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const menu = screen.getByRole("menu");
    const currentRow = within(menu)
      .getByText("jikigai")
      .closest("[data-testid='org-row']") as HTMLElement;
    const otherRow = within(menu)
      .getByText("Acme Studio")
      .closest("[data-testid='org-row']") as HTMLElement;
    const currentTile = within(currentRow).getByTestId("workspace-identity-tile");
    const otherTile = within(otherRow).getByTestId("workspace-identity-tile");
    expect(currentTile).toHaveTextContent("J");
    expect(otherTile).toHaveTextContent("A");
    // current row is visually marked (ring) — non-current is not
    expect(currentTile.className).toContain("ring");
    expect(otherTile.className).not.toContain("ring");
  });

  it("FR6: no gold square swatch fill (bg-soleur-accent-gold-fg/60) survives in the switcher markup", () => {
    const { container } = render(
      <OrgSwitcher memberships={[JIKIGAI, ACME]} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /switch workspace/i }));
    const goldSwatch = Array.from(container.querySelectorAll("*")).find((el) =>
      el.className
        ?.toString()
        .includes("bg-soleur-accent-gold-fg/60"),
    );
    expect(goldSwatch).toBeUndefined();
  });
});

// Collapsed icon-only mode (remount-fix, 2026-06-22): the SAME OrgSwitcher
// instance owns both the full pill and the collapsed icon tile, so a collapse
// toggle is a prop change on a persistent element — the only thing that
// preserves the parent container's fetch + confirm state across the toggle.
describe("OrgSwitcher — collapsed icon-only mode", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("collapsed multi-org renders the identity icon (name as tooltip) with NO `Switch workspace` button or `▾`", () => {
    render(<OrgSwitcher memberships={[JIKIGAI, ACME]} collapsed />);
    const icon = screen.getByTestId("workspace-identity-icon");
    expect(icon).toHaveAttribute("title", "jikigai");
    expect(within(icon).getByTestId("workspace-identity-tile")).toHaveTextContent(
      "J",
    );
    // no switch chrome at 56px
    expect(
      screen.queryByRole("button", { name: /switch workspace/i }),
    ).not.toBeInTheDocument();
    expect(screen.queryByText("▾")).not.toBeInTheDocument();
  });

  it("collapsed solo renders the SAME identity icon (current workspace name)", () => {
    render(<OrgSwitcher memberships={[JIKIGAI]} collapsed />);
    const icon = screen.getByTestId("workspace-identity-icon");
    expect(icon).toHaveAttribute("title", "jikigai");
    // and the non-interactive static chip is NOT rendered in collapsed mode
    expect(screen.queryByTestId("workspace-identity-static")).toBeNull();
  });

  it("collapsed renders nothing when there are zero memberships", () => {
    const { container } = render(<OrgSwitcher memberships={[]} collapsed />);
    expect(container).toBeEmptyDOMElement();
  });

  it("collapsed picks the isCurrent membership for the icon (not just the first)", () => {
    // ACME is isCurrent:false, JIKIGAI isCurrent:true but listed second here
    render(<OrgSwitcher memberships={[ACME, JIKIGAI]} collapsed />);
    expect(screen.getByTestId("workspace-identity-icon")).toHaveAttribute(
      "title",
      "jikigai",
    );
  });
});
