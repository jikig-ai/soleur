/**
 * Unit tests — session-router.ts (epic #5274 Phase 3 Sub-PR 3.B, ADR-068 D0).
 *
 * User-sticky routing: an inbound WS for (workspaceId, userId) is served on the
 * host holding that USER's worktree lease; a session that lands on a non-owner is
 * proxied to the owner over one-way TLS. Covers AC2:
 *   - two users of one workspace resolve to DISTINCT per-user lease keys (D0);
 *   - a control op for a conversation always resolves on its owning host (sticky,
 *     deterministic — no cross-host forwarding);
 *   - placement is decided from the lease BEFORE the upgrade (this module IS the
 *     pre-upgrade decision the ws-handler calls);
 *   - the owning host re-verifies membership before serving a proxied session
 *     (negative: a cross-tenant pair is rejected — AP-2).
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { readHolderMock } = vi.hoisted(() => ({ readHolderMock: vi.fn() }));
vi.mock("@/server/worktree-write-lease", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/worktree-write-lease")>()),
  readWorktreeLeaseHolder: readHolderMock,
}));
const { reportSilentFallbackMock } = vi.hoisted(() => ({ reportSilentFallbackMock: vi.fn() }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: reportSilentFallbackMock }));

import {
  resolveSessionRoute,
  verifyProxiedSessionMembership,
  loadHostRoster,
  resolveHostAddress,
} from "@/server/session-router";
import { resolveWorktreeId } from "@/server/worktree-write-lease";

const WS = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const USER_A = "11111111-1111-1111-1111-111111111111";
const USER_B = "22222222-2222-2222-2222-222222222222";
const HOST_1 = "host-1";
const HOST_2 = "host-2";

function holder(hostId: string) {
  return { hostId, leaseGeneration: 3, heartbeatAt: new Date().toISOString() };
}

beforeEach(() => {
  readHolderMock.mockReset();
  reportSilentFallbackMock.mockReset();
  vi.unstubAllEnvs();
  vi.stubEnv("SOLEUR_HOST_ROSTER", "");
});
afterEach(() => vi.unstubAllEnvs());

describe("resolveSessionRoute — user-sticky placement", () => {
  test("cold session (no live holder) → serve LOCAL (this host acquires + becomes owner)", async () => {
    readHolderMock.mockResolvedValue(null);
    const r = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    expect(r).toEqual({ decision: "local", reason: "cold" });
  });

  test("holder is THIS host → serve LOCAL (owner)", async () => {
    readHolderMock.mockResolvedValue(holder(HOST_1));
    const r = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    expect(r).toEqual({ decision: "local", reason: "owner" });
  });

  test("holder is a PEER in the roster → PROXY to its private IP", async () => {
    vi.stubEnv("SOLEUR_HOST_ROSTER", JSON.stringify({ [HOST_2]: "10.0.1.12" }));
    readHolderMock.mockResolvedValue(holder(HOST_2));
    const r = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    expect(r).toEqual({ decision: "proxy", ownerHostId: HOST_2, ownerAddress: "10.0.1.12" });
  });

  test("holder is a PEER NOT in the roster → owner-unresolved (fail-loud to Sentry)", async () => {
    readHolderMock.mockResolvedValue(holder(HOST_2));
    const r = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    expect(r).toEqual({ decision: "owner-unresolved", ownerHostId: HOST_2 });
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
    expect((reportSilentFallbackMock.mock.calls[0][1] as { feature: string }).feature).toBe(
      "control_plane_route",
    );
  });

  test("keys the lease read on the PER-USER worktree id — two users → distinct keys (D0)", async () => {
    readHolderMock.mockResolvedValue(null);
    await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    await resolveSessionRoute({ workspaceId: WS, userId: USER_B, myHostId: HOST_1 });
    expect(readHolderMock).toHaveBeenNthCalledWith(1, WS, resolveWorktreeId(USER_A));
    expect(readHolderMock).toHaveBeenNthCalledWith(2, WS, resolveWorktreeId(USER_B));
    // Distinct users → distinct worktree ids → distinct lease keys (routable apart).
    expect(resolveWorktreeId(USER_A)).not.toBe(resolveWorktreeId(USER_B));
  });

  test("sticky + deterministic: the same (workspace,user) always resolves to the same owner (no forwarding)", async () => {
    vi.stubEnv("SOLEUR_HOST_ROSTER", JSON.stringify({ [HOST_2]: "10.0.1.12" }));
    readHolderMock.mockResolvedValue(holder(HOST_2));
    const a = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    const b = await resolveSessionRoute({ workspaceId: WS, userId: USER_A, myHostId: HOST_1 });
    expect(a).toEqual(b);
    expect(a).toMatchObject({ decision: "proxy", ownerHostId: HOST_2 });
  });
});

describe("loadHostRoster / resolveHostAddress", () => {
  test("empty/unset roster → {} (single-host: any peer is unresolvable, never a wrong dial)", () => {
    expect(loadHostRoster()).toEqual({});
    expect(resolveHostAddress(HOST_2)).toBeNull();
  });

  test("invalid JSON → {} (fail-safe, does not throw)", () => {
    vi.stubEnv("SOLEUR_HOST_ROSTER", "{not json");
    expect(loadHostRoster()).toEqual({});
  });

  test("valid roster resolves a host id to its private ip", () => {
    vi.stubEnv("SOLEUR_HOST_ROSTER", JSON.stringify({ [HOST_1]: "10.0.1.11", [HOST_2]: "10.0.1.12" }));
    expect(resolveHostAddress(HOST_2)).toBe("10.0.1.12");
    expect(resolveHostAddress("host-unknown")).toBeNull();
  });
});

describe("verifyProxiedSessionMembership (AP-2, fail-closed)", () => {
  function memberStub(result: { data: unknown; error: unknown }) {
    const chain: Record<string, unknown> = {};
    for (const m of ["select", "eq"]) chain[m] = () => chain;
    chain.maybeSingle = () => Promise.resolve(result);
    return { from: () => chain };
  }

  test("solo workspace (workspaceId === userId, N2) → member without any query", async () => {
    const supa = { from: () => { throw new Error("must not query for the solo shortcut"); } };
    expect(await verifyProxiedSessionMembership(USER_A, USER_A, supa)).toBe(true);
  });

  test("a genuine member (row present) → true", async () => {
    const supa = memberStub({ data: { user_id: USER_A }, error: null });
    expect(await verifyProxiedSessionMembership(USER_A, WS, supa)).toBe(true);
  });

  test("NON-member of the proxied workspace → false (cross-tenant proxied session rejected)", async () => {
    const supa = memberStub({ data: null, error: null });
    expect(await verifyProxiedSessionMembership(USER_A, WS, supa)).toBe(false);
  });

  test("DB error → false (fail-CLOSED — never serve a session we cannot authorize)", async () => {
    const supa = memberStub({ data: null, error: { code: "57014" } });
    expect(await verifyProxiedSessionMembership(USER_A, WS, supa)).toBe(false);
    expect(reportSilentFallbackMock).toHaveBeenCalled();
  });
});
