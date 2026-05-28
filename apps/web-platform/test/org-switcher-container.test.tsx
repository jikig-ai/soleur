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

const reloadMock = vi.fn();

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
    Object.defineProperty(window.location, "reload", {
      configurable: true,
      value: reloadMock,
    });
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ memberships: [JIKIGAI, ACME] }),
      }),
    );
  });

  it("selecting a workspace shows a confirm step BEFORE switching (no immediate RPC)", async () => {
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    // confirm affordance appears, RPC not yet called
    expect(await screen.findByTestId("workspace-switch-confirm")).toBeTruthy();
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("confirming calls set_current_workspace_id with the target workspaceId, refreshes, reloads", async () => {
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
      expect(reloadMock).toHaveBeenCalled();
    });
  });

  it("cancel aborts the switch — no RPC, no reload", async () => {
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /cancel/i }));
    expect(screen.queryByTestId("workspace-switch-confirm")).toBeNull();
    expect(mockRpc).not.toHaveBeenCalled();
    expect(reloadMock).not.toHaveBeenCalled();
  });

  it("RPC failure surfaces a failed state with a retry that re-issues the switch", async () => {
    mockRpc.mockResolvedValueOnce({ error: { message: "permission denied" } });
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    const retry = await screen.findByRole("button", { name: /retry/i });
    expect(reloadMock).not.toHaveBeenCalled();

    // second attempt succeeds
    fireEvent.click(retry);
    await vi.waitFor(() => {
      expect(reloadMock).toHaveBeenCalled();
    });
  });
});
