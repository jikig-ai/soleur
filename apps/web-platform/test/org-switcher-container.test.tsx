import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

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

  it("collapsed renders the icon-only identity (no pill, no switch chrome) and never the confirm dialog", async () => {
    render(<OrgSwitcherContainer collapsed />);
    // icon-only identity from the same data path
    const icon = await screen.findByTestId("workspace-identity-icon");
    expect(icon).toHaveAttribute("title", "jikigai");
    // the switch chrome is suppressed at 56px
    expect(
      screen.queryByRole("button", { name: /switch workspace/i }),
    ).toBeNull();
    // there is no pending switch, so no confirm dialog regardless
    expect(screen.queryByTestId("workspace-switch-confirm")).toBeNull();
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

// #4917 — two-phase-commit treatment of the switch failure. The RPC
// (set_current_workspace_id) and the JWT re-mint (refreshSession) are two
// SEPARATE writes. When the RPC SUCCEEDS but refreshSession THROWS, the durable
// source of truth (user_session_state) already points at the NEW workspace while
// the in-browser JWT still claims the OLD one. The old FSM collapsed both failure
// modes into a single "failed" state offering Retry/Cancel — and Cancel after a
// committed RPC is a silent cross-tenant context switch the user never confirmed.
describe("OrgSwitcherContainer — two-phase-commit failure handling (#4917)", () => {
  const originalOnLine = Object.getOwnPropertyDescriptor(
    window.navigator,
    "onLine",
  );

  function setOnLine(value: boolean) {
    Object.defineProperty(window.navigator, "onLine", {
      configurable: true,
      get: () => value,
    });
  }

  beforeEach(() => {
    vi.clearAllMocks();
    setOnLine(true);
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

  afterEach(() => {
    // In jsdom `navigator.onLine` is a PROTOTYPE getter, so the describe-time
    // getOwnPropertyDescriptor returns undefined. setOnLine installs an OWN
    // getter on the instance — if we only restored on a truthy descriptor, the
    // own getter would leak `onLine === false` into any later-ordered suite
    // sharing this jsdom global. Delete the injected own property when there was
    // no original to restore. (Flagged by test-design + code-quality review.)
    if (originalOnLine) {
      Object.defineProperty(window.navigator, "onLine", originalOnLine);
    } else {
      delete (window.navigator as { onLine?: boolean }).onLine;
    }
  });

  // Test Scenario 1 / AC1 + AC2: post-RPC failure (online) force-completes to
  // /dashboard and never offers a Cancel that returns to the old workspace.
  it("post-RPC failure (online) force-completes to /dashboard with NO Cancel", async () => {
    mockRefreshSession.mockRejectedValueOnce(new Error("token endpoint 500"));
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    await vi.waitFor(() => {
      // converge forward: the server re-reads user_session_state (already
      // committed) and the JWT re-mints on next load.
      expect(assignMock).toHaveBeenCalledWith("/dashboard");
    });
    // no affordance returns the user to the old-workspace idle screen.
    expect(screen.queryByRole("button", { name: /cancel/i })).toBeNull();
    // the divergence is mirrored to Sentry on the post-RPC path specifically
    // (brand-critical) — pin the payload so a stray report elsewhere can't
    // satisfy this assertion.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "workspace-switch",
        op: "refresh-session-post-rpc",
      }),
    );
  });

  // Test Scenario 2 / AC3: pre-RPC failure still offers Retry AND Cancel, and
  // Cancel safely returns to idle (nothing was committed).
  it("pre-RPC failure preserves Retry + Cancel (regression guard)", async () => {
    mockRpc.mockResolvedValueOnce({ error: { message: "permission denied" } });
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    expect(await screen.findByRole("button", { name: /retry/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /cancel/i })).toBeTruthy();
    expect(assignMock).not.toHaveBeenCalled();
    // a committed-RPC Sentry mirror must NOT fire for a pre-RPC failure.
    expect(mockReportSilentFallback).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));
    expect(screen.queryByTestId("workspace-switch-confirm")).toBeNull();
  });

  // Test Scenario 3 / AC4: offline post-RPC messaging is honest — names the
  // target workspace, says the switch is saved / will finish on reconnect, and
  // does NOT claim the switch failed. No Cancel.
  it("post-RPC failure while offline shows honest 'saved / will finish' copy, NO Cancel", async () => {
    setOnLine(false);
    mockRefreshSession.mockRejectedValueOnce(new Error("Failed to fetch"));
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    const dialog = await screen.findByTestId("workspace-switch-confirm");
    await vi.waitFor(() => {
      expect(dialog.textContent).toMatch(/Acme Studio/);
    });
    // honest: names the target + conveys saved/will-finish; never "couldn't switch".
    expect(dialog.textContent).toMatch(/saved|reconnect|finish/i);
    expect(dialog.textContent).not.toMatch(/couldn.?t switch/i);
    // offline → do not blindly navigate (it would hang); converge on Continue.
    expect(assignMock).not.toHaveBeenCalled();
    expect(screen.queryByRole("button", { name: /cancel/i })).toBeNull();
  });

  // Test Scenario 4 / AC5: bounded retry — driving repeated post-RPC failures
  // caps the Try-again affordance and always leaves a terminal converge-forward
  // (Continue) control rather than an infinite Syncing… spin.
  it("post-RPC offline retry is bounded and always exposes a Continue affordance", async () => {
    setOnLine(false);
    mockRefreshSession.mockRejectedValue(new Error("Failed to fetch"));
    render(<OrgSwitcherContainer />);
    await openAndSelectAcme();
    fireEvent.click(await screen.findByRole("button", { name: /^confirm$/i }));

    // first post-RPC failure lands in the offline converge state.
    await screen.findByRole("button", { name: /continue/i });

    // drive several retries; each re-attempt fails (still offline).
    for (let i = 0; i < 5; i++) {
      const retry = screen.queryByRole("button", { name: /try again/i });
      if (!retry) break;
      fireEvent.click(retry);
      // wait for the syncing pass to settle back into the offline state.
      await screen.findByRole("button", { name: /continue/i });
    }

    // bounded: Try-again is eventually withdrawn…
    expect(screen.queryByRole("button", { name: /try again/i })).toBeNull();
    // …but a terminal converge-forward affordance always remains.
    const cont = screen.getByRole("button", { name: /continue/i });
    fireEvent.click(cont);
    expect(assignMock).toHaveBeenCalledWith("/dashboard");
    // never resolves to a stale-labeled Cancel.
    expect(screen.queryByRole("button", { name: /cancel/i })).toBeNull();
    // load-bearing two-phase-commit invariant: the durable RPC commits ONCE.
    // Every offline Try-again re-runs ONLY the refresh phase (attemptRefresh),
    // never re-issuing set_current_workspace_id.
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });
});
