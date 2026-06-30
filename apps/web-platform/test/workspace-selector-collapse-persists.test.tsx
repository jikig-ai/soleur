import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// Load-bearing regression test (Test Strategy #1, plan
// 2026-06-22-fix-sidebar-collapse-workspace-selector-remount):
//
// The bug: WorkspaceContextBand's `collapsed` early-return swapped subtrees, so
// React unmounted OrgSwitcherContainer on every collapse and remounted a fresh
// instance on every expand — re-running its mount effect
// (`fetch("/api/workspace/list-memberships")`) and discarding its local state.
//
// The visible symptom (refetch + flash) is INVISIBLE to a plain happy-dom
// presence assertion (no compositor, presence queries don't observe a remount).
// So the invariant we assert is the mount/fetch LIFECYCLE: a collapse→expand
// toggle fires ZERO additional list-memberships requests. Asserting the
// invariant (no refetch on toggle), not a DOM-presence proxy.

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard",
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useParams: () => ({}),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    rpc: vi.fn(),
    auth: { refreshSession: vi.fn() },
  }),
}));

import { WorkspaceContextBand } from "@/components/dashboard/workspace-context-band";

const SOLEUR: OrgMembershipSummary = {
  organizationId: "00000000-0000-0000-0000-00000000aaaa",
  organizationName: "Soleur Workspace",
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

function countMembershipFetches(fetchSpy: ReturnType<typeof vi.fn>): number {
  return fetchSpy.mock.calls.filter((c) =>
    String(c[0]).includes("list-memberships"),
  ).length;
}

describe("Workspace selector survives a sidebar collapse toggle (no remount/refetch)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchSpy = vi.fn((url: string) => {
      if (url.includes("list-memberships")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ memberships: [SOLEUR, ACME] }),
        });
      }
      if (url.includes("active-repo")) {
        return Promise.resolve({
          ok: true,
          json: () =>
            Promise.resolve({
              workspaceId: SOLEUR.workspaceId,
              repoUrl: "https://github.com/jikig-ai/soleur",
              repoName: "jikig-ai/soleur",
              repoStatus: "connected",
              fellBackToSolo: false,
            }),
        });
      }
      return Promise.resolve({ ok: false, json: () => Promise.resolve({}) });
    });
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("fires the list-memberships fetch exactly ONCE across an expanded → collapsed → expanded cycle", async () => {
    const { rerender } = render(
      <WorkspaceContextBand pathname="/dashboard" collapsed={false} />,
    );
    // expanded mount → the switcher pill renders once its membership fetch resolves
    expect(
      await screen.findByRole("button", { name: /switch workspace/i }),
    ).toBeInTheDocument();
    expect(countMembershipFetches(fetchSpy)).toBe(1);

    // collapse the rail — the container must stay mounted (presentation-only toggle)
    rerender(<WorkspaceContextBand pathname="/dashboard" collapsed />);
    // the collapsed icon-only identity is rendered by the SAME mounted container
    expect(
      await screen.findByTestId("workspace-identity-icon"),
    ).toHaveAttribute("title", "Soleur Workspace");
    expect(countMembershipFetches(fetchSpy)).toBe(1);

    // expand again — still the same instance, still no refetch
    rerender(<WorkspaceContextBand pathname="/dashboard" collapsed={false} />);
    expect(
      await screen.findByRole("button", { name: /switch workspace/i }),
    ).toBeInTheDocument();
    expect(countMembershipFetches(fetchSpy)).toBe(1);
  });
});
