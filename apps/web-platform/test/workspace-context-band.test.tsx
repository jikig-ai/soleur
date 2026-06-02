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
};
const TEAMMATE: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000cccc",
  organizationName: "Acme Studio",
  workspaceId: "00000000-0000-0000-0000-00000000dddd",
  role: "member",
  memberCount: 5,
  isCurrent: false,
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
