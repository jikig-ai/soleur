import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock the Sentry mirror so the fail-loud branches are observable without a
// real observability surface. The registry imports `./observability`, which
// resolves to the same module id as `@/server/observability` — vi.mock matches
// by resolved id, so this intercepts the registry's import too.
const { reportSilentFallbackSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

import {
  resolveUserWorkspaceBinding,
  setUserWorkspace,
  getUserWorkspace,
  __test_only__,
} from "@/server/agent-session-registry";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";

const USER = "user-abc";
const WS = "workspace-xyz";

beforeEach(() => {
  __test_only__.clear();
  reportSilentFallbackSpy.mockClear();
});

describe("resolveUserWorkspaceBinding — durable binding resolution (AC4, #5240)", () => {
  it("Map hit → returns Map value and never reads the DB (hot path, AC4-hot)", async () => {
    setUserWorkspace(USER, WS);
    const dbRead = vi.fn(async () => "should-not-be-used");

    const result = await resolveUserWorkspaceBinding(USER, dbRead);

    expect(result).toBe(WS);
    expect(dbRead).toHaveBeenCalledTimes(0);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("Map miss + DB returns a workspaceId → rehydrates (writeback) and returns it, no throw (post-restart sim — load-bearing)", async () => {
    // Empty Map simulates a backend process restart before WS-open re-populates
    // it. Today both consumers throw "No workspace binding" here; the durable
    // resolver must rehydrate from the DB instead.
    const dbRead = vi.fn(async () => WS);

    const result = await resolveUserWorkspaceBinding(USER, dbRead);

    expect(result).toBe(WS);
    expect(dbRead).toHaveBeenCalledTimes(1);
    // Writeback: a subsequent consumer in the same connection skips the DB.
    expect(getUserWorkspace(USER)).toBe(WS);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("Map miss + DB returns null → throws fail-loud, fires reportSilentFallback once (op=unresolvable), and does NOT bind to userId", async () => {
    const dbRead = vi.fn(async () => null);

    await expect(resolveUserWorkspaceBinding(USER, dbRead)).rejects.toThrow(
      /no durable binding found/,
    );

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "resolveUserWorkspaceBinding.unresolvable",
    });
    // No solo-fallback: the Map was NOT written with `userId`.
    expect(getUserWorkspace(USER)).toBeUndefined();
  });

  it("Map miss + DB read error (closure throws) → throws fail-loud, fires reportSilentFallback once (op=db-read), and does NOT bind to userId", async () => {
    const dbRead = vi.fn(async () => {
      throw new Error("boom");
    });

    await expect(resolveUserWorkspaceBinding(USER, dbRead)).rejects.toThrow(
      /durable DB read failed/,
    );

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "resolveUserWorkspaceBinding.db-read",
    });
    expect(getUserWorkspace(USER)).toBeUndefined();
  });

  it("rehydrated binding is consumed by the next caller — a second resolve hits the Map and issues no DB read (durable-path writeback contract)", async () => {
    const firstRead = vi.fn(async () => WS);
    expect(await resolveUserWorkspaceBinding(USER, firstRead)).toBe(WS);
    expect(firstRead).toHaveBeenCalledTimes(1);

    // The writeback from the first resolve must make the second a hot Map hit:
    // the second consumer on the same connection never touches the DB.
    const secondRead = vi.fn(async () => "should-not-be-read");
    expect(await resolveUserWorkspaceBinding(USER, secondRead)).toBe(WS);
    expect(secondRead).toHaveBeenCalledTimes(0);
  });
});

describe("readWorkspaceIdFromDb — fail-loud sibling of resolveCurrentWorkspaceId (no ?? userId)", () => {
  // Structural chain mock mirroring ws-deferred-creation.test.ts; the chain is
  // a thenable that awaitChain() awaits to {data, error}.
  function supabaseMock(resolved: {
    data: { current_workspace_id: string | null } | null;
    error: unknown;
  }) {
    const chain: Record<string, unknown> = {};
    chain.select = () => chain;
    chain.eq = () => chain;
    chain.maybeSingle = () => chain;
    chain.then = (onFulfilled: (v: typeof resolved) => unknown) =>
      Promise.resolve(resolved).then(onFulfilled);
    return { from: () => chain };
  }

  it("returns current_workspace_id when the row is present", async () => {
    const sb = supabaseMock({ data: { current_workspace_id: WS }, error: null });
    expect(await readWorkspaceIdFromDb(USER, sb as never)).toBe(WS);
  });

  it("returns null (NOT userId) when the row is absent", async () => {
    const sb = supabaseMock({ data: null, error: null });
    const r = await readWorkspaceIdFromDb(USER, sb as never);
    expect(r).toBeNull();
    expect(r).not.toBe(USER);
  });

  it("returns null when current_workspace_id is null", async () => {
    const sb = supabaseMock({ data: { current_workspace_id: null }, error: null });
    expect(await readWorkspaceIdFromDb(USER, sb as never)).toBeNull();
  });

  it("throws on a DB read error (does NOT swallow, does NOT return userId)", async () => {
    const sb = supabaseMock({ data: null, error: { message: "db fail" } });
    await expect(readWorkspaceIdFromDb(USER, sb as never)).rejects.toBeTruthy();
  });
});
