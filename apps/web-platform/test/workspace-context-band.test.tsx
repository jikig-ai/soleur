import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// next/navigation is only needed because OrgSwitcherContainer's tree is pulled
// in; the band itself takes `pathname` as a prop (no usePathname coupling).
vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard",
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

function stubFetch(memberships: OrgMembershipSummary[], repoName: string | null) {
  vi.stubGlobal(
    "fetch",
    vi.fn((url: string) => {
      if (url.includes("list-memberships")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ memberships }),
        });
      }
      if (url.includes("active-repo")) {
        return Promise.resolve({
          ok: true,
          json: () =>
            Promise.resolve({
              workspaceId: SOLO.workspaceId,
              repoUrl: repoName ? `https://github.com/${repoName}` : null,
              repoName,
              repoStatus: "connected",
              fellBackToSolo: false,
            }),
        });
      }
      return Promise.resolve({ ok: false, json: () => Promise.resolve({}) });
    }),
  );
}

describe("WorkspaceContextBand — persistent workspace identity (AC1/AC4b)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
    stubFetch([SOLO, TEAMMATE], "jikig-ai/soleur");
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("renders the band shell", () => {
    render(<WorkspaceContextBand pathname="/dashboard" />);
    expect(screen.getByTestId("workspace-context-band")).toBeInTheDocument();
  });

  it("shows workspace identity (name + repo) on a DRILLED route (/dashboard/settings/members)", async () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings/members" />);
    // multi-org → interactive switcher chip surfaces the active workspace name
    expect(
      await screen.findByText("Soleur Workspace"),
    ).toBeInTheDocument();
    // repo badge surfaces the active repo
    expect(await screen.findByTestId("live-repo-badge")).toHaveTextContent(
      "jikig-ai/soleur",
    );
  });

  it("AC3/AC7: the repo badge is FOLDED INTO the pill (inside the switcher button), not a standalone row", async () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings/members" />);
    const badge = await screen.findByTestId("live-repo-badge");
    // exactly one element carries the repo string — no duplicate standalone row
    expect(screen.getAllByTestId("live-repo-badge")).toHaveLength(1);
    // and it lives inside the workspace pill (the switcher button)
    const pill = screen.getByRole("button", { name: /switch workspace/i });
    expect(pill).toContainElement(badge);
  });

  it("AC1: the workspace pill renders BEFORE the 'Back to menu' chevron in the DOM", async () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings/members" />);
    const pill = await screen.findByRole("button", {
      name: /switch workspace/i,
    });
    const back = screen.getByTestId("nav-back-chevron");
    // pill precedes back-chevron → DOCUMENT_POSITION_FOLLOWING is set on `back`
    expect(
      pill.compareDocumentPosition(back) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("AC2 (Sidebar-UX Issue 1): the leading pill top room is tightened to pt-2", async () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings/members" />);
    // wait for the band to hydrate the pill
    await screen.findByRole("button", { name: /switch workspace/i });
    const band = screen.getByTestId("workspace-context-band");
    // first child is the pill wrapper; pt-2 (was pt-3) shrinks the gap between
    // the collapse toggle and the workspace switcher card (Issue 1).
    const pillWrapper = band.firstElementChild as HTMLElement;
    expect(pillWrapper.className).toContain("pt-2");
    expect(pillWrapper.className).not.toContain("pt-3");
    const back = screen.getByTestId("nav-back-chevron");
    expect(back.className).toContain("pt-2");
  });

  it("Bug fix (sidebar collapse-toggle overlap): the TOP-LEVEL pill wrapper reserves md:min-h-[64px] so the not-yet-loaded band cannot collapse under the floated toggle", () => {
    // The floated collapse toggle (layout.tsx, `absolute right-3 top-10`, h-6) has
    // a 64px footprint from the aside top (top-10 = 40px + h-6 = 24px). On the
    // top-level route the band's only content is the async pill, which renders
    // null until /api/workspace/list-memberships resolves (OrgSwitcherContainer
    // returns null). With no reserved height the band collapses to ~8px and the
    // nav rises into the toggle's footprint — the toggle paints over "Dashboard".
    // Reserving md:min-h-[64px] on the pill wrapper holds the band open through
    // the in-flight state. jsdom has NO layout engine, so this is a TOKEN tripwire
    // only — the binding overlap proof is the e2e rect-non-intersection gate in
    // nav-states-shell.e2e.ts (ADR-049). Intentionally implementation-coupled
    // (literal token + firstElementChild): if the reserve is re-expressed via a
    // different utility/wrapper, update or delete this tripwire — the e2e is the
    // source of truth.
    render(<WorkspaceContextBand pathname="/dashboard" />);
    const band = screen.getByTestId("workspace-context-band");
    const pillWrapper = band.firstElementChild as HTMLElement;
    expect(pillWrapper.className).toContain("md:min-h-[64px]");
  });

  it("does NOT reserve the min-height on a DRILLED band (drill !== null already exceeds 64px via back-link + section title)", async () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings/members" />);
    await screen.findByRole("button", { name: /switch workspace/i });
    const band = screen.getByTestId("workspace-context-band");
    const pillWrapper = band.firstElementChild as HTMLElement;
    // drill === "settings" → the reserve is scoped out (the guard avoids
    // inflating drilled bands that are already tall).
    expect(pillWrapper.className).not.toContain("md:min-h-[64px]");
  });

  it("Sidebar-UX Issue 3: the section title is spaced off the 'Back to menu' link (pt-3)", () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings" />);
    // The back link (pt-2) and the section heading used to sit in one cramped
    // block; pt-3 on the title row adds a clear inter-row gap (shared band, so
    // this applies to both Settings and Knowledge Base).
    const title = screen.getByTestId("nav-section-title");
    expect(title.className).toContain("pt-3");
    // ...without dropping the existing bottom padding (regression-guard pair).
    expect(title.className).toContain("pb-3");
  });

  it("renders the back chevron SYNCHRONOUSLY on a drilled route (not async-gated)", () => {
    render(<WorkspaceContextBand pathname="/dashboard/kb/engineering/x.md" />);
    // present in the FIRST render — no findBy/await
    const back = screen.getByTestId("nav-back-chevron");
    expect(back).toHaveAttribute("href", "/dashboard");
    expect(back).toHaveAccessibleName(/back to menu/i);
  });

  it("labels the section title on a drilled route", () => {
    render(<WorkspaceContextBand pathname="/dashboard/settings" />);
    expect(screen.getByTestId("nav-section-title")).toHaveTextContent(
      "Settings",
    );
  });

  it("HIDES the back chevron and section title on a non-drill route (top level)", () => {
    render(<WorkspaceContextBand pathname="/dashboard" />);
    expect(screen.queryByTestId("nav-back-chevron")).not.toBeInTheDocument();
    expect(screen.queryByTestId("nav-section-title")).not.toBeInTheDocument();
  });

  it("still hides back chevron on the admin analytics route (allowlist, RQ6)", () => {
    render(<WorkspaceContextBand pathname="/dashboard/admin/analytics" />);
    expect(screen.queryByTestId("nav-back-chevron")).not.toBeInTheDocument();
  });

  it("RQ7: shows a NON-interactive workspace name chip for solo users (no switcher button)", async () => {
    stubFetch([SOLO], "jikig-ai/soleur");
    render(<WorkspaceContextBand pathname="/dashboard/settings" />);
    // name is visible (orientation value) ...
    expect(await screen.findByText("Soleur Workspace")).toBeInTheDocument();
    // ... but there is NO interactive switch affordance (nothing to switch to)
    expect(
      screen.queryByRole("button", { name: /switch workspace/i }),
    ).not.toBeInTheDocument();
  });
});

// Phase 1 (#4915): the collapsed rail band renders the monogram identity tile
// (not the nameless gold swatch). The collapsed band does NOT mount
// OrgSwitcherContainer, so the active workspace name is threaded in as a prop
// (P0-3): the FULL name becomes the tooltip — the authoritative disambiguator
// for two workspaces that share an initial.
describe("WorkspaceContextBand — collapsed monogram identity (Phase 1, #4915)", () => {
  it("renders the monogram tile (non-gold) with the FULL workspace name as the tooltip when collapsed", () => {
    render(
      <WorkspaceContextBand
        pathname="/dashboard/kb"
        collapsed
        activeWorkspaceName="Soleur Workspace"
      />,
    );
    const icon = screen.getByTestId("workspace-identity-icon");
    // full name replaces the static "Active workspace" tooltip (P0-3)
    expect(icon).toHaveAttribute("title", "Soleur Workspace");
    const tile = within(icon).getByTestId("workspace-identity-tile");
    expect(tile).toHaveTextContent("S"); // monogram of "Soleur Workspace"
    expect(tile.className).not.toMatch(/accent-gold/); // FR6: non-gold
  });

  it("falls back to the static 'Active workspace' tooltip before a name is threaded", () => {
    render(<WorkspaceContextBand pathname="/dashboard/kb" collapsed />);
    expect(screen.getByTestId("workspace-identity-icon")).toHaveAttribute(
      "title",
      "Active workspace",
    );
  });

  // Declutter (sidebar-declutter-kiss): the collapsed rail drops the decorative
  // gold repo dot and the single-letter section monogram — both carried no
  // information the rail's icons + identity tile do not already carry. The
  // identity tile (orientation anchor, ADR-047) is the only retained glyph.
  it("does NOT render the decorative gold repo dot or the single-letter section monogram when collapsed", () => {
    render(
      <WorkspaceContextBand
        pathname="/dashboard/kb"
        collapsed
        activeWorkspaceName="Soleur Workspace"
      />,
    );
    // orientation anchor stays...
    expect(screen.getByTestId("workspace-identity-icon")).toBeInTheDocument();
    // ...the two decorative glyphs are gone.
    expect(screen.queryByTestId("live-repo-dot")).toBeNull();
    expect(screen.queryByTestId("nav-section-title")).toBeNull();
  });
});

// Phase 3 (#4915): one back control per state. In the mobile KB doc view the
// kb-content-header already owns a "Back to file tree" affordance, so the band's
// "Back to menu" is suppressed via an explicit `suppressBack` prop (driven by the
// layout, which owns pathname — the band itself never adds a parallel pathname
// check; ADR-047 AC4c).
describe("WorkspaceContextBand — back suppression (Phase 3, #4915)", () => {
  it("suppresses the back affordance when suppressBack is set, keeping identity + section title", () => {
    render(
      <WorkspaceContextBand
        pathname="/dashboard/kb/engineering/x.md"
        variant="mobile"
        suppressBack
      />,
    );
    expect(screen.queryByTestId("nav-back-chevron")).not.toBeInTheDocument();
    // only the back link is suppressed — the section title still renders
    expect(screen.getByTestId("nav-section-title")).toBeInTheDocument();
  });

  it("still renders the back affordance when suppressBack is absent (KB landing / other drills)", () => {
    render(<WorkspaceContextBand pathname="/dashboard/kb" variant="mobile" />);
    expect(screen.getByTestId("nav-back-chevron")).toBeInTheDocument();
  });
});

// Phase 4 (#4915): title ownership per breakpoint. On mobile KB the page body
// owns the "Knowledge Base" title (kb/layout fullWidth header), so the layout
// suppresses the MOBILE band's section-title via suppressSectionTitle to keep
// exactly one title on mobile. Desktop (rail band) keeps the section title.
describe("WorkspaceContextBand — section-title ownership (Phase 4, #4915)", () => {
  it("suppresses the band section title when suppressSectionTitle is set", () => {
    render(
      <WorkspaceContextBand
        pathname="/dashboard/kb"
        variant="mobile"
        suppressSectionTitle
      />,
    );
    expect(screen.queryByTestId("nav-section-title")).not.toBeInTheDocument();
  });

  it("renders the band section title when suppressSectionTitle is absent (default)", () => {
    render(<WorkspaceContextBand pathname="/dashboard/kb" variant="mobile" />);
    expect(screen.getByTestId("nav-section-title")).toBeInTheDocument();
  });
});
