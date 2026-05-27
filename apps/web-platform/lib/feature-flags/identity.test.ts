import { describe, it, expect, vi } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { resolveIdentity } from "./identity";
import { ANON_IDENTITY } from "./server";
import { mockQueryChain } from "@/test/helpers/mock-supabase";

type AuthUser = { id: string } | null;

function fakeSupabase(
  authUser: AuthUser,
  rowResult: { data: { role: unknown } | null; error: { message: string } | null } = {
    data: { role: "prd" },
    error: null,
  },
  authError: { message: string } | null = null,
  workspaceMembersResult: { data: { workspace_id: string; workspaces: { organization_id: string } } | null; error: { message: string } | null } = {
    data: null,
    error: null,
  },
) {
  const from = vi.fn().mockImplementation((table: string) => {
    if (table === "workspace_members") {
      return mockQueryChain<{ workspace_id: string; workspaces: { organization_id: string } } | null>(
        workspaceMembersResult.data,
        workspaceMembersResult.error,
      );
    }
    return mockQueryChain<{ role: unknown } | null>(rowResult.data, rowResult.error);
  });
  return {
    auth: {
      getUser: vi
        .fn()
        .mockResolvedValue({ data: { user: authUser }, error: authError }),
    },
    from,
  } as unknown as Parameters<typeof resolveIdentity>[0];
}

describe("resolveIdentity", () => {
  it("returns ANON_IDENTITY (with orgId: null) when no auth user", async () => {
    await expect(resolveIdentity(fakeSupabase(null))).resolves.toEqual(ANON_IDENTITY);
    await expect(resolveIdentity(fakeSupabase(null))).resolves.toHaveProperty("orgId", null);
  });

  it("returns ANON_IDENTITY when auth.getUser errors", async () => {
    await expect(
      resolveIdentity(fakeSupabase(null, { data: { role: "prd" }, error: null }, { message: "boom" })),
    ).resolves.toEqual(ANON_IDENTITY);
  });

  it("returns { userId, role: 'dev' } when row says dev", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: { role: "dev" }, error: null })),
    ).resolves.toMatchObject({ userId: "abc", role: "dev" });
  });

  it("defaults to prd role on missing users row (preserves userId)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: null, error: { message: "no row" } })),
    ).resolves.toMatchObject({ userId: "abc", role: "prd" });
  });

  it("defaults to prd for any unrecognised role value (fail-safe)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: { role: "admin" }, error: null })),
    ).resolves.toMatchObject({ userId: "abc", role: "prd" });
  });

  it("returns orgId from workspace_members when row exists", async () => {
    await expect(
      resolveIdentity(
        fakeSupabase(
          { id: "abc" },
          { data: { role: "dev" }, error: null },
          null,
          { data: { workspace_id: "ws-123", workspaces: { organization_id: "org-123" } }, error: null },
        ),
      ),
    ).resolves.toEqual({ userId: "abc", role: "dev", orgId: "org-123" });
  });

  it("returns orgId: null when workspace_members has no row", async () => {
    await expect(
      resolveIdentity(
        fakeSupabase(
          { id: "abc" },
          { data: { role: "prd" }, error: null },
          null,
          { data: null, error: { message: "no row" } },
        ),
      ),
    ).resolves.toEqual({ userId: "abc", role: "prd", orgId: null });
  });

  it("returns orgId: null for anonymous users", async () => {
    const result = await resolveIdentity(fakeSupabase(null));
    expect(result.orgId).toBeNull();
  });
});
