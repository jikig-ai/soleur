import { describe, it, expect, vi } from "vitest";
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
) {
  const from = vi.fn().mockReturnValue(
    mockQueryChain<{ role: unknown } | null>(rowResult.data, rowResult.error),
  );
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
  it("returns ANON_IDENTITY when no auth user", async () => {
    await expect(resolveIdentity(fakeSupabase(null))).resolves.toEqual(ANON_IDENTITY);
  });

  it("returns ANON_IDENTITY when auth.getUser errors", async () => {
    await expect(
      resolveIdentity(fakeSupabase(null, { data: { role: "prd" }, error: null }, { message: "boom" })),
    ).resolves.toEqual(ANON_IDENTITY);
  });

  it("returns { userId, role: 'dev' } when row says dev", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: { role: "dev" }, error: null })),
    ).resolves.toEqual({ userId: "abc", role: "dev" });
  });

  it("defaults to prd role on missing users row (preserves userId)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: null, error: { message: "no row" } })),
    ).resolves.toEqual({ userId: "abc", role: "prd" });
  });

  it("defaults to prd for any unrecognised role value (fail-safe)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: { role: "admin" }, error: null })),
    ).resolves.toEqual({ userId: "abc", role: "prd" });
  });
});
