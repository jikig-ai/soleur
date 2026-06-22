import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, within } from "@testing-library/react";

// Unit-level guards for the #4810/#4833 follow-up fix: workspace-selector pill
// overflow (Bug 1) + back-arrow / collapse-chevron disambiguation (Bug 2).
//
// The CSS overflow itself is verified by the headless Playwright VRT gate
// (e2e/nav-states-shell.e2e.ts) — jsdom has no layout engine. These tests pin
// the STRUCTURAL invariants jsdom CAN see:
//   - the band's "Back to menu" affordance is NOT a byte-identical duplicate of
//     the layout collapse chevron glyph (the root of the "two arrows" report);
//   - the affordance renders in BOTH the collapsed and expanded band paths
//     (they are separate DOM subtrees — a fix to one can miss the other);
//   - the org-switcher button + solo identity chip carry the width-clamp classes
//     that stop the bordered box painting past the rail edge.

// The FORMER layout collapse-toggle glyph (the panel-rectangle PanelToggleIcon,
// removed when the resize slider took over collapse/expand). Retained here as a
// regression guard: the band's "Back to menu" affordance MUST NOT reuse this
// exact rectangle path — it must stay a clearly distinct back-arrow glyph.
const COLLAPSE_CHEVRON_PATH =
  "M3.75 6.75A2.25 2.25 0 0 1 6 4.5h12a2.25 2.25 0 0 1 2.25 2.25v10.5A2.25 2.25 0 0 1 18 19.5H6a2.25 2.25 0 0 1-2.25-2.25V6.75Z";

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/kb",
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useParams: () => ({}),
}));

const { mockRpc, mockRefreshSession } = vi.hoisted(() => ({
  mockRpc: vi.fn(),
  mockRefreshSession: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    rpc: mockRpc,
    auth: { refreshSession: mockRefreshSession },
  }),
}));

import { WorkspaceContextBand } from "@/components/dashboard/workspace-context-band";
import { OrgSwitcher } from "@/components/dashboard/org-switcher";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

const SOLO: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000aaaa",
  organizationName: "Soleur Workspace",
  workspaceId: "00000000-0000-0000-0000-00000000bbbb",
  role: "owner",
  memberCount: 1,
  isCurrent: true,
    hasLogo: false,
};
const TEAMMATE: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000cccc",
  organizationName: "Acme Studio",
  workspaceId: "00000000-0000-0000-0000-00000000dddd",
  role: "member",
  memberCount: 5,
  isCurrent: false,
    hasLogo: false,
};

beforeEach(() => {
  vi.restoreAllMocks();
});
afterEach(() => {
  vi.unstubAllGlobals();
});

function backChevronPath(container: HTMLElement): string | null {
  const back = within(container).getByTestId("nav-back-chevron");
  return back.querySelector("path")?.getAttribute("d") ?? null;
}

describe("nav back-affordance disambiguation (Bug 2)", () => {
  it("AC4: drilled expanded band renders exactly one back affordance, glyph distinct from the collapse chevron", () => {
    const { container } = render(
      <WorkspaceContextBand pathname="/dashboard/kb" collapsed={false} />,
    );
    const backs = within(container).getAllByTestId("nav-back-chevron");
    expect(backs).toHaveLength(1);
    expect(backs[0]).toHaveAttribute("href", "/dashboard");
    expect(backs[0]).toHaveAccessibleName(/back to menu/i);
    // NOT byte-identical to the layout collapse chevron.
    expect(backChevronPath(container)).not.toBe(COLLAPSE_CHEVRON_PATH);
  });

  it("AC5: drilled COLLAPSED band also renders the back affordance, glyph still distinct", () => {
    const { container } = render(
      <WorkspaceContextBand pathname="/dashboard/kb" collapsed={true} />,
    );
    const back = within(container).getByTestId("nav-back-chevron");
    expect(back).toHaveAttribute("href", "/dashboard");
    expect(backChevronPath(container)).not.toBe(COLLAPSE_CHEVRON_PATH);
  });

  it("AC8: top-level (drill === null) renders NO back affordance", () => {
    const { container } = render(
      <WorkspaceContextBand pathname="/dashboard" collapsed={false} />,
    );
    expect(
      within(container).queryByTestId("nav-back-chevron"),
    ).not.toBeInTheDocument();
  });
});

describe("org-switcher width clamp (Bug 1)", () => {
  it("multi-org switch button carries w-full + min-w-0 so the bordered box cannot overflow the rail", () => {
    render(<OrgSwitcher memberships={[SOLO, TEAMMATE]} />);
    const button = screen.getByRole("button", { name: /switch workspace/i });
    expect(button.className).toContain("w-full");
    expect(button.className).toContain("min-w-0");
    // trailing caret must not force the box wider than its flex parent
    const caret = within(button).getByText("▾");
    expect(caret.className).toContain("shrink-0");
  });

  it("solo identity chip carries w-full + min-w-0 so the chip cannot overflow the rail", () => {
    render(<OrgSwitcher memberships={[SOLO]} />);
    const chip = screen.getByTestId("workspace-identity-static");
    expect(chip.className).toContain("w-full");
    expect(chip.className).toContain("min-w-0");
  });
});

// Phase 2 (#4915): D4 borderless de-box. The switcher trigger sheds its hard
// border (grouping conveyed via spacing/hover elevation), while the width-clamp
// classes (Bug 1 guard) and the multi-org caret affordance are preserved.
describe("org-switcher D4 borderless de-box (Phase 2)", () => {
  it("multi-org trigger is borderless (no border-soleur-border-default) but keeps the caret + width clamp", () => {
    render(<OrgSwitcher memberships={[SOLO, TEAMMATE]} />);
    const button = screen.getByRole("button", { name: /switch workspace/i });
    expect(button.className).not.toContain("border-soleur-border-default");
    // affordance + overflow guards survive the de-box
    expect(within(button).getByText("▾")).toBeInTheDocument();
    expect(button.className).toContain("w-full");
    expect(button.className).toContain("min-w-0");
  });

  it("solo identity chip stays flat — no caret, no hard border (visibly non-interactive)", () => {
    render(<OrgSwitcher memberships={[SOLO]} />);
    const chip = screen.getByTestId("workspace-identity-static");
    expect(chip.className).not.toContain("border-soleur-border-default");
    expect(within(chip).queryByText("▾")).toBeNull();
  });
});
