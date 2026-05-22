import { describe, it, expect, vi } from "vitest";
import { resolveIdentity } from "./identity";
import { ANON_IDENTITY } from "./server";

type AuthGetUserResult = {
  data: { user: { id: string } | null };
  error: { message: string } | null;
};

type UsersRowResult = {
  data: { role: unknown } | null;
  error: { message: string } | null;
};

function fakeSupabase(opts: {
  auth: AuthGetUserResult;
  usersRow?: UsersRowResult;
}) {
  const single = vi.fn().mockResolvedValue(
    opts.usersRow ?? { data: { role: "prd" }, error: null },
  );
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  const from = vi.fn().mockReturnValue({ select });
  return {
    auth: { getUser: vi.fn().mockResolvedValue(opts.auth) },
    from,
  } as unknown as Parameters<typeof resolveIdentity>[0];
}

describe("resolveIdentity", () => {
  it("returns ANON_IDENTITY when no auth user", async () => {
    const supabase = fakeSupabase({ auth: { data: { user: null }, error: null } });
    await expect(resolveIdentity(supabase)).resolves.toEqual(ANON_IDENTITY);
  });

  it("returns ANON_IDENTITY when auth.getUser errors", async () => {
    const supabase = fakeSupabase({
      auth: { data: { user: null }, error: { message: "boom" } },
    });
    await expect(resolveIdentity(supabase)).resolves.toEqual(ANON_IDENTITY);
  });

  it("returns { userId, role: 'dev' } when row says dev", async () => {
    const supabase = fakeSupabase({
      auth: { data: { user: { id: "abc" } }, error: null },
      usersRow: { data: { role: "dev" }, error: null },
    });
    await expect(resolveIdentity(supabase)).resolves.toEqual({
      userId: "abc",
      role: "dev",
    });
  });

  it("defaults to prd role on missing users row", async () => {
    const supabase = fakeSupabase({
      auth: { data: { user: { id: "abc" } }, error: null },
      usersRow: { data: null, error: { message: "no row" } },
    });
    await expect(resolveIdentity(supabase)).resolves.toEqual({
      userId: "abc",
      role: "prd",
    });
  });

  it("defaults to prd for any unrecognised role value (fail-safe)", async () => {
    const supabase = fakeSupabase({
      auth: { data: { user: { id: "abc" } }, error: null },
      usersRow: { data: { role: "admin" }, error: null },
    });
    await expect(resolveIdentity(supabase)).resolves.toEqual({
      userId: "abc",
      role: "prd",
    });
  });
});
