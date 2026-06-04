import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
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

import { OrgSwitcherContainer } from "@/components/dashboard/org-switcher-container";

// RQ2: the switch performs a HARD navigation to /dashboard (window.location
// .assign), NOT a soft router.push and NOT reload() — see executeSwitch.
const assignMock = vi.fn();

async function openAndSelectAcme() {
  // open the dropdown
  fireEvent.click(await screen.findByRole("button", { name: /switch workspace/i }));
  // click the non-current row
  const rows = screen.getAllByTestId("org-row");
  const acmeRow = rows.find((r) => within(r).queryByText("Acme Studio"));
  if (!acmeRow) throw new Error("Acme row not found");
  fireEvent.click(acmeRow);
}

describe("OrgSwitcherContainer — workspace switch write-path (3.10)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
    mockRefreshSession.mockResolvedValue({
      data: {
        session: {
          user: { app_metadata: { current_workspace_id: ACME.workspaceId } },
        },
      },
      error: null,
    });
    Object.defineProperty(window.location, "assign", {
      configurable: true,
      value: assignMock,
    });
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) => {
        if (url.includes("active-repo")) {
          return Promise.resolve({
            ok: true,
            json: () =>
              Promise.resolve({
                workspaceId: JIKIGAI.workspaceId,
                repoUrl: "https://github.com/jikig-ai/soleur",
                repoName: "jikig-ai/soleur",
                repoStatus: "connected",
                fellBackToSolo: false,
              }),
          });
        }
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ memberships: [JIKIGAI, ACME] }),
        });
      }),
    );
  });

  it("folds the active repo name into the pill face (data plumbing via useActiveRepo)", async () => {
    render(<OrgSwitcherContainer />);
    const pill = await screen.findByRole("button", {
      name: /switch workspace/i,
    });
    const subtitle = await within(pill).findByTestId("live-repo-badge");
    expect(subtitle).toHaveTextContent("jikig-ai/soleur");
  });

  it("selecting a workspace shows a confirm step BEFORE switching (no immediate RPC)", async () => {
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    // confirm affordance appears, RPC not yet called
    expect(await screen.findByTestId("workspace-switch-confirm")).toBeTruthy();
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("confirming calls set_current_workspace_id with the target workspaceId, refreshes, HARD-navigates to /dashboard", async () => {
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    await vi.waitFor(() => {
      expect(mockRpc).toHaveBeenCalledWith("set_current_workspace_id", {
        p_workspace_id: ACME.workspaceId,
      });
    });
    await vi.waitFor(() => {
      expect(mockRefreshSession).toHaveBeenCalled();
      // RQ2: neutral landing + RSC re-render under the new JWT. Asserts the
      // hard-nav mechanism, not a soft router.push.
      expect(assignMock).toHaveBeenCalledWith("/dashboard");
    });
  });

  it("cancel aborts the switch — no RPC, no navigation", async () => {
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /cancel/i }));
    expect(screen.queryByTestId("workspace-switch-confirm")).toBeNull();
    expect(mockRpc).not.toHaveBeenCalled();
    expect(assignMock).not.toHaveBeenCalled();
  });

  it("RPC failure surfaces a failed state with a retry that re-issues the switch (also hard-navigates)", async () => {
    mockRpc.mockResolvedValueOnce({ error: { message: "permission denied" } });
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    const retry = await screen.findByRole("button", { name: /retry/i });
    expect(assignMock).not.toHaveBeenCalled();

    // second attempt succeeds — the retry path shares executeSwitch, so it
    // must ALSO land on the neutral /dashboard route (AC2 covers both paths).
    fireEvent.click(retry);
    await vi.waitFor(() => {
      expect(assignMock).toHaveBeenCalledWith("/dashboard");
    });
  });
});
