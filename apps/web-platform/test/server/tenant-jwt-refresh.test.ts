import { describe, it, expect, beforeEach, vi } from "vitest";

// Unit tests for `getFreshTenantClient` auto-remint at TTL/2 and the
// `mintFounderJwt` claim shape (PR-B §1.3, Resolution A #3363).
//
// Stubs `getServiceClient().rpc("precheck_jwt_mint", ...)` and
// `createClient` from supabase-js so the test stays in-memory. The
// integration test in `agent-runner.tenant-isolation.test.ts` covers
// the live-DB cross-tenant invariant.

// `vi.hoisted` per cq-test-fixtures-synthesized-only and the work skill's
// "vi.hoisted from the start" guidance — `vi.mock` factories are hoisted
// above module-load, so any shared state must be hoisted too.
const mocks = vi.hoisted(() => {
  const rpcCalls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  let nextRpcResult: {
    data: unknown;
    error: { message: string } | null;
  } = { data: null, error: null };

  const createdClients: Array<{ token: string }> = [];

  return {
    rpcCalls,
    setRpcResult: (r: typeof nextRpcResult) => {
      nextRpcResult = r;
    },
    createdClients,
    getRpcResult: () => nextRpcResult,
    reset: () => {
      rpcCalls.length = 0;
      createdClients.length = 0;
      nextRpcResult = { data: null, error: null };
    },
  };
});

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test-project.supabase.co",
  getServiceClient: () => ({
    rpc: vi.fn(async (fn: string, args: Record<string, unknown>) => {
      mocks.rpcCalls.push({ fn, args });
      return mocks.getRpcResult();
    }),
  }),
  createServiceClient: () => ({
    rpc: vi.fn(async (fn: string, args: Record<string, unknown>) => {
      mocks.rpcCalls.push({ fn, args });
      return mocks.getRpcResult();
    }),
  }),
}));

vi.mock("@supabase/supabase-js", async () => {
  const actual =
    await vi.importActual<typeof import("@supabase/supabase-js")>(
      "@supabase/supabase-js",
    );
  return {
    ...actual,
    createClient: vi.fn((_url: string, _key: string, opts?: unknown) => {
      const headers =
        (opts as { global?: { headers?: Record<string, string> } } | undefined)
          ?.global?.headers ?? {};
      const auth = headers.Authorization ?? headers.authorization ?? "";
      const token = auth.replace(/^Bearer\s+/i, "");
      mocks.createdClients.push({ token });
      // Minimal stub — the SUT's getFreshTenantClient does not call any
      // SupabaseClient method itself; it only returns the client to the
      // caller.
      return { from: () => ({}), auth: {}, rpc: async () => ({ data: null, error: null }) };
    }),
  };
});

import {
  mintFounderJwt,
  getFreshTenantClient,
  RuntimeAuthError,
  _resetTenantCache,
} from "@/lib/supabase/tenant";

const FOUNDER_A = "00000000-0000-0000-0000-00000000aaaa";
const FOUNDER_B = "00000000-0000-0000-0000-00000000bbbb";

const TEST_SECRET =
  "test-secret-for-unit-tests-must-be-long-enough-for-hmac-min-32";

beforeEach(() => {
  mocks.reset();
  _resetTenantCache();
  vi.useRealTimers();
  process.env.SUPABASE_JWT_SECRET = TEST_SECRET;
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
});

describe("mintFounderJwt — claim shape (Resolution A)", () => {
  it("calls precheck_jwt_mint RPC with founder_id + ttl_sec", async () => {
    mocks.setRpcResult({
      data: [
        { jti: "11111111-1111-1111-1111-111111111111", exp_epoch: 1900000600, iat_epoch: 1900000000 },
      ],
      error: null,
    });

    await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    expect(mocks.rpcCalls).toHaveLength(1);
    expect(mocks.rpcCalls[0]).toEqual({
      fn: "precheck_jwt_mint",
      args: { p_founder_id: FOUNDER_A, p_ttl_sec: 600 },
    });
  });

  it("decoded JWT payload has sub=founderId, role=authenticated, aud=soleur-runtime, iss=<project-url>/auth/v1, jti from RPC, exp/iat from RPC", async () => {
    mocks.setRpcResult({
      data: [
        { jti: "abcdabcd-abcd-abcd-abcd-abcdabcdabcd", exp_epoch: 1900000600, iat_epoch: 1900000000 },
      ],
      error: null,
    });

    const { jwt } = await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    // Decode the payload (middle segment, base64url).
    const [header, payload, signature] = jwt.split(".");
    expect(header).toBeTruthy();
    expect(payload).toBeTruthy();
    expect(signature).toBeTruthy();

    const decoded = JSON.parse(
      Buffer.from(payload.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString(
        "utf8",
      ),
    );
    expect(decoded).toMatchObject({
      sub: FOUNDER_A,
      role: "authenticated",
      aud: "soleur-runtime",
      iss: "https://test-project.supabase.co/auth/v1",
      jti: "abcdabcd-abcd-abcd-abcd-abcdabcdabcd",
      exp: 1900000600,
      iat: 1900000000,
    });

    // Header should be HS256 + JWT.
    const decodedHeader = JSON.parse(
      Buffer.from(header.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString(
        "utf8",
      ),
    );
    expect(decodedHeader).toEqual({ alg: "HS256", typ: "JWT" });
  });

  it("signature verifies against SUPABASE_JWT_SECRET (HS256)", async () => {
    const { createHmac } = await import("node:crypto");

    mocks.setRpcResult({
      data: [
        { jti: "11111111-1111-1111-1111-111111111111", exp_epoch: 1900000600, iat_epoch: 1900000000 },
      ],
      error: null,
    });

    const { jwt } = await mintFounderJwt(FOUNDER_A);
    const [h, p, sig] = jwt.split(".");

    const expectedSig = createHmac("sha256", TEST_SECRET)
      .update(`${h}.${p}`)
      .digest("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    expect(sig).toBe(expectedSig);
  });

  it("throws RuntimeAuthError{cause:rotation} on mint_rate_exceeded RPC error", async () => {
    mocks.setRpcResult({
      data: null,
      error: { message: "mint_rate_exceeded" },
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "rotation",
    });
  });

  it("throws RuntimeAuthError{cause:jwt_mint} on other RPC errors", async () => {
    mocks.setRpcResult({
      data: null,
      error: { message: "connection failed" },
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  it("throws RuntimeAuthError when SUPABASE_JWT_SECRET is missing", async () => {
    delete process.env.SUPABASE_JWT_SECRET;

    mocks.setRpcResult({
      data: [
        { jti: "11111111-1111-1111-1111-111111111111", exp_epoch: 1900000600, iat_epoch: 1900000000 },
      ],
      error: null,
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toBeInstanceOf(RuntimeAuthError);
  });
});

describe("getFreshTenantClient — auto-remint at TTL/2", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-06T12:00:00.000Z"));
    mocks.setRpcResult({
      data: [
        { jti: "11111111-1111-1111-1111-111111111111", exp_epoch: 1900000600, iat_epoch: 1900000000 },
      ],
      error: null,
    });
  });

  it("first call mints a JWT and caches the client", async () => {
    const client = await getFreshTenantClient(FOUNDER_A);
    expect(client).toBeTruthy();
    expect(mocks.rpcCalls).toHaveLength(1);
    expect(mocks.createdClients).toHaveLength(1);
    expect(mocks.createdClients[0].token).toMatch(/^[\w-]+\.[\w-]+\.[\w-]+$/);
  });

  it("second call within TTL/2 returns the cached client (no remint)", async () => {
    await getFreshTenantClient(FOUNDER_A);
    expect(mocks.rpcCalls).toHaveLength(1);

    // Advance 100s — well below TTL/2 (300s for a 600s TTL).
    vi.advanceTimersByTime(100_000);

    await getFreshTenantClient(FOUNDER_A);
    expect(mocks.rpcCalls).toHaveLength(1); // still 1, not 2
  });

  it("call after TTL/2 elapsed remints and updates the cache", async () => {
    // Distinct jti per RPC call so the resigned JWT is genuinely different.
    let mintCount = 0;
    mocks.setRpcResult({
      data: [
        {
          jti: "11111111-1111-1111-1111-111111111111",
          exp_epoch: 1900000600,
          iat_epoch: 1900000000,
        },
      ],
      error: null,
    });

    await getFreshTenantClient(FOUNDER_A);
    expect(mocks.rpcCalls).toHaveLength(1);

    // Advance past TTL/2 (300s for default 600s TTL) AND change the RPC
    // result so the fresh mint produces a distinct JWT.
    vi.advanceTimersByTime(301_000);
    mintCount++;
    mocks.setRpcResult({
      data: [
        {
          jti: "22222222-2222-2222-2222-222222222222",
          exp_epoch: 1900000901,
          iat_epoch: 1900000301,
        },
      ],
      error: null,
    });

    await getFreshTenantClient(FOUNDER_A);
    expect(mocks.rpcCalls).toHaveLength(2);
    expect(mocks.createdClients).toHaveLength(2);
    expect(mocks.createdClients[1].token).not.toBe(
      mocks.createdClients[0].token,
    );
    expect(mintCount).toBe(1);
  });

  it("caches per founderId — A and B do not share the cache slot", async () => {
    await getFreshTenantClient(FOUNDER_A);
    await getFreshTenantClient(FOUNDER_B);
    expect(mocks.rpcCalls).toHaveLength(2);
    expect(mocks.rpcCalls.map((c) => c.args.p_founder_id)).toEqual([
      FOUNDER_A,
      FOUNDER_B,
    ]);

    // Reading A again at t<TTL/2 must NOT remint — B's mint must not bust
    // A's cache slot.
    await getFreshTenantClient(FOUNDER_A);
    expect(mocks.rpcCalls).toHaveLength(2);
  });

  it("a query started before TTL/2 completes successfully without error (long-running query contract)", async () => {
    // Per plan §1.1: long-running tool calls already started under a stale
    // JWT continue to completion; the next query gets a fresh client.
    // This test models the contract by holding a reference to the cached
    // client across the TTL/2 boundary and asserting no throw — the SUT
    // does not invalidate or detach an in-flight client just because the
    // boundary tripped.
    const longRunningClient = await getFreshTenantClient(FOUNDER_A);

    // Time passes past TTL/2.
    vi.advanceTimersByTime(400_000);

    // The original client reference is still usable (no proxy revocation,
    // no thrown error, no reset).
    expect(() => longRunningClient.from("dummy")).not.toThrow();

    // A new call gets a fresh client.
    const fresh = await getFreshTenantClient(FOUNDER_A);
    expect(fresh).not.toBe(longRunningClient);
  });
});
