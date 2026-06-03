import { describe, it, expect, vi, beforeEach } from "vitest";

// Regression guard for feat-fix-multi-user-feature-not-visible.
//
// The Settings "Members" tab (+ "Team Activity") is gated server-side by
// resolveMembersTab: an authenticated user with a resolved current org AND the
// team-workspace-invite flag ON. Any single gate failing hides BOTH tabs with
// no error — the silent failure that prompted the ops@jikigai.com report. The
// fix adds an observability emit when a *member* (not a solo user) resolves a
// null org, so the next disappearance surfaces in Sentry instead of via the
// user. These tests pin (a) the composition / emit branch — the heart of the
// fix — and (b) the membership-probe contract.

// --- mock the resolveMembersTab seams (composition tests) -------------------
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/feature-flags/server", () => ({ isTeamWorkspaceInviteEnabled: vi.fn() }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));

import { resolveMembersTab } from "@/server/members-tab";
import { userHasWorkspaceMembership } from "@/server/workspace-resolver";
import { createClient } from "@/lib/supabase/server";
import { isTeamWorkspaceInviteEnabled } from "@/lib/feature-flags/server";
import { reportSilentFallback } from "@/server/observability";

const ORG = "1a8045bf-6718-43c9-887b-0c0652ca75c3";
const USER = { id: "754ee124-706a-4f21-a4f4-e828257b0380" };

// Minimal supabase double mirroring the live PostgREST fluent API: the chain is
// the awaitable, terminal methods resolve `{ data, error }`. `from` branches on
// table so resolveCurrentOrganizationId (user_session_state) and
// userHasWorkspaceMembership (workspace_members) read distinct fixtures.
function fakeSupabase(opts: {
  user: { id: string } | null;
  orgId: string | null;
  memberRows: unknown[];
}) {
  return {
    auth: { getUser: async () => ({ data: { user: opts.user }, error: null }) },
    from(table: string) {
      if (table === "user_session_state") {
        const chain: Record<string, unknown> = {
          select: () => chain,
          eq: () => chain,
          maybeSingle: async () => ({
            data: opts.orgId == null ? null : { current_organization_id: opts.orgId },
            error: null,
          }),
        };
        return chain;
      }
      if (table === "workspace_members") {
        const chain: Record<string, unknown> = {
          select: () => chain,
          eq: () => chain,
          limit: async () => ({ data: opts.memberRows, error: null }),
        };
        return chain;
      }
      throw new Error(`unexpected table: ${table}`);
    },
  };
}

describe("resolveMembersTab — gate composition + silent-failure emit", () => {
  beforeEach(() => {
    vi.mocked(createClient).mockReset();
    vi.mocked(isTeamWorkspaceInviteEnabled).mockReset();
    vi.mocked(reportSilentFallback).mockReset();
  });

  function arrange(opts: { user?: { id: string } | null; orgId: string | null; memberRows?: unknown[]; flagOn?: boolean }) {
    vi.mocked(createClient).mockResolvedValue(
      fakeSupabase({ user: opts.user ?? USER, orgId: opts.orgId, memberRows: opts.memberRows ?? [] }) as never,
    );
    vi.mocked(isTeamWorkspaceInviteEnabled).mockResolvedValue(opts.flagOn ?? false);
  }

  it("shows the tab when org resolves AND flag is ON; no emit", async () => {
    arrange({ orgId: ORG, flagOn: true });
    const tab = await resolveMembersTab();
    expect(tab).toEqual({ href: "/dashboard/settings/team", label: "Members" });
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("hides the tab when the flag is OFF (gate #3); no emit", async () => {
    arrange({ orgId: ORG, flagOn: false });
    expect(await resolveMembersTab()).toBeNull();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("emits a silent-failure signal when a MEMBER resolves a null org (gate #2)", async () => {
    arrange({ orgId: null, memberRows: [{ workspace_id: "w" }] });
    expect(await resolveMembersTab()).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({
      feature: "settings-members-tab",
      op: "resolveMembersTab",
      extra: { userId: USER.id },
    });
  });

  it("stays SILENT for a legitimately org-less non-member (null org, no membership)", async () => {
    arrange({ orgId: null, memberRows: [] });
    expect(await resolveMembersTab()).toBeNull();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns null with no DB/flag work when there is no authenticated user", async () => {
    arrange({ user: null, orgId: null });
    expect(await resolveMembersTab()).toBeNull();
    expect(isTeamWorkspaceInviteEnabled).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});

describe("userHasWorkspaceMembership — integrity-surface discriminator", () => {
  // Recursive chain mock mirrors the live PostgREST fluent API: every chained
  // call returns the same object; the terminal awaited value is the row set.
  function mockSupabase(rows: unknown[] | null, error: unknown = null) {
    const chain = {
      select: () => chain,
      eq: () => chain,
      limit: () => Promise.resolve({ data: rows, error }),
    };
    return { from: vi.fn(() => chain) };
  }

  it("true when the user has >=1 membership row", async () => {
    expect(await userHasWorkspaceMembership("u", mockSupabase([{ workspace_id: "w" }]))).toBe(true);
  });

  it("false when the user has zero membership rows", async () => {
    expect(await userHasWorkspaceMembership("u", mockSupabase([]))).toBe(false);
  });

  it("false when data is null without an error (PostgREST empty-result shape)", async () => {
    expect(await userHasWorkspaceMembership("u", mockSupabase(null))).toBe(false);
  });

  it("false (fail-quiet) on a query error — never blocks the render path", async () => {
    expect(await userHasWorkspaceMembership("u", mockSupabase(null, { message: "boom" }))).toBe(false);
  });
});
