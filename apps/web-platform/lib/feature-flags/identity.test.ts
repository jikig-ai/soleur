import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "fs";
import { resolve } from "path";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { resolveIdentity } from "./identity";
import { ANON_IDENTITY } from "./server";
import { mockQueryChain } from "@/test/helpers/mock-supabase";

type AuthUser = { id: string; email?: string | null } | null;

// perf-dashboard-section-load-latency Phase 3: the users select widened to
// `role, subscription_status` and Identity gained `email` (from the auth user)
// + `subscriptionStatus` (from the users row). Both selects now issue in
// Promise.all — concurrent, not serial.
function fakeSupabase(
  authUser: AuthUser,
  rowResult: { data: { role: unknown; subscription_status?: string | null } | null; error: { message: string } | null } = {
    data: { role: "prd", subscription_status: "active" },
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
    return mockQueryChain<{ role: unknown; subscription_status?: string | null } | null>(rowResult.data, rowResult.error);
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

  it("ANON_IDENTITY keeps literal null for the additive fields", async () => {
    // The widened Identity is strictly additive — anonymous identity must
    // carry literal nulls, never "" or a synthetic value.
    expect(ANON_IDENTITY).toEqual({
      userId: null,
      role: "prd",
      orgId: null,
      email: null,
      subscriptionStatus: null,
    });
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
    ).resolves.toMatchObject({ userId: "abc", role: "dev" });
  });

  it("defaults to prd role on missing users row (preserves userId)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: null, error: { message: "no row" } })),
    ).resolves.toMatchObject({ userId: "abc", role: "prd", subscriptionStatus: null });
  });

  it("defaults to prd for any unrecognised role value (fail-safe)", async () => {
    await expect(
      resolveIdentity(fakeSupabase({ id: "abc" }, { data: { role: "admin" }, error: null })),
    ).resolves.toMatchObject({ userId: "abc", role: "prd" });
  });

  it("carries email from the auth user and subscriptionStatus from the users row", async () => {
    await expect(
      resolveIdentity(
        fakeSupabase(
          { id: "abc", email: "founder@acme.test" },
          { data: { role: "dev", subscription_status: "past_due" }, error: null },
        ),
      ),
    ).resolves.toMatchObject({
      userId: "abc",
      role: "dev",
      email: "founder@acme.test",
      subscriptionStatus: "past_due",
    });
  });

  it("returns orgId from workspace_members when row exists", async () => {
    await expect(
      resolveIdentity(
        fakeSupabase(
          { id: "abc", email: "dev@acme.test" },
          { data: { role: "dev", subscription_status: "active" }, error: null },
          null,
          { data: { workspace_id: "ws-123", workspaces: { organization_id: "org-123" } }, error: null },
        ),
      ),
    ).resolves.toEqual({
      userId: "abc",
      role: "dev",
      orgId: "org-123",
      email: "dev@acme.test",
      subscriptionStatus: "active",
    });
  });

  it("returns orgId: null when workspace_members has no row", async () => {
    await expect(
      resolveIdentity(
        fakeSupabase(
          { id: "abc" },
          { data: { role: "prd", subscription_status: "active" }, error: null },
          null,
          { data: null, error: { message: "no row" } },
        ),
      ),
    ).resolves.toEqual({
      userId: "abc",
      role: "prd",
      orgId: null,
      email: null,
      subscriptionStatus: "active",
    });
  });

  it("returns orgId: null for anonymous users", async () => {
    const result = await resolveIdentity(fakeSupabase(null));
    expect(result.orgId).toBeNull();
  });

  it("issues the users + workspace_members selects CONCURRENTLY (Promise.all) after one getUser", async () => {
    // Deferred-promise ordering: hold BOTH selects unresolved, then assert
    // `from("workspace_members")` was already invoked while `users`'s
    // `.single()` was still pending. Under a serial `await users → await
    // members` chain the second from() cannot fire until the first resolves —
    // so seeing both from() calls with nothing resolved proves parallelism.
    const issued: string[] = [];
    const deferred = <T>() => {
      let resolve!: (v: T) => void;
      const promise = new Promise<T>((r) => {
        resolve = r;
      });
      return { promise, resolve };
    };
    const usersDeferred = deferred<{ data: unknown; error: null }>();
    const membersDeferred = deferred<{ data: unknown; error: null }>();

    const makePendingChain = (d: { promise: Promise<unknown> }) => {
      const chain: Record<string, unknown> = {};
      for (const m of ["select", "eq", "order", "limit"]) {
        chain[m] = vi.fn(() => chain);
      }
      chain.single = vi.fn(() => d.promise);
      chain.maybeSingle = vi.fn(() => d.promise);
      chain.then = (onfulfilled?: (v: unknown) => unknown) =>
        d.promise.then(onfulfilled);
      return chain;
    };

    const supabase = {
      auth: {
        getUser: vi.fn().mockResolvedValue({
          data: { user: { id: "abc", email: "x@y.test" } },
          error: null,
        }),
      },
      from: vi.fn((table: string) => {
        issued.push(table);
        return makePendingChain(
          table === "users" ? usersDeferred : membersDeferred,
        );
      }),
    } as unknown as Parameters<typeof resolveIdentity>[0];

    const pending = resolveIdentity(supabase);

    // Exactly one getUser — the auth leg is upstream of the parallel pair.
    expect(supabase.auth.getUser).toHaveBeenCalledTimes(1);

    // Both selects issued before either resolves.
    await vi.waitFor(() => {
      expect(issued).toContain("workspace_members");
    });
    expect(issued).toContain("users");

    usersDeferred.resolve({
      data: { role: "dev", subscription_status: "active" },
      error: null,
    });
    membersDeferred.resolve({
      data: { workspace_id: "ws-1", workspaces: { organization_id: "org-9" } },
      error: null,
    });

    await expect(pending).resolves.toMatchObject({
      userId: "abc",
      role: "dev",
      orgId: "org-9",
    });
  });
});

describe("lib/supabase/server createClient memoization seam", () => {
  it("createClient is wrapped in React cache() so the layout chain dedupes (Phase 3 AC)", () => {
    // React `cache()` memoization is per server-render pass — not observable
    // in a node test (the client build's cache() is a passthrough). What CAN
    // be pinned here is the structural fact the AC depends on: the exported
    // `createClient` flows through `cache(...)`, so `resolveIdentity`'s own
    // cache() dedupes across the root layout → dashboard layout chain
    // (identity keyed on the same client object each pass).
    const src = readFileSync(
      resolve(__dirname, "../supabase/server.ts"),
      "utf-8",
    );
    expect(src).toMatch(/\bcache\s*\(/);
    expect(src).toMatch(/from\s+["']react["']/);
  });
});
