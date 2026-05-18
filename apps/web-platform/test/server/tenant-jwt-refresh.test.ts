import { describe, it, expect, beforeEach, vi } from "vitest";

// Unit tests for `getFreshTenantClient` auto-remint at TTL/4 and the
// `mintFounderJwt` claim shape (PR-B §1.3, Resolution C #3363).
//
// Stubs `getServiceClient()` (auth.admin.getUserById, auth.admin.generateLink,
// auth.verifyOtp, rpc) and `createClient` from supabase-js so the test stays
// in-memory. The integration test in `agent-runner.tenant-isolation.test.ts`
// covers the live-DB cross-tenant invariant.
//
// Resolution C (#3363) substrate:
//   - Node holds no signing material. Mints go through GoTrue:
//       admin.generateLink({type:"magiclink", email}) → verifyOtp({token_hash,type:"email"})
//   - The Custom Access Token Hook (migration 047) calls `precheck_jwt_mint`
//     itself and injects jti/aud/exp/iat into the issued JWT. Node MUST NOT
//     call `precheck_jwt_mint` directly — assertions below enforce that.
//   - Cache remint boundary is TTL/4 (was TTL/2 under HS256).

// `vi.hoisted` per cq-test-fixtures-synthesized-only and the work skill's
// "vi.hoisted from the start" guidance — `vi.mock` factories are hoisted
// above module-load, so any shared state must be hoisted too.
const mocks = vi.hoisted(() => {
  // --- base64url helpers (duplicated inside vi.hoisted because hoisted code
  // cannot reference module-scope helpers).
  const b64url = (s: string): string =>
    Buffer.from(s, "utf8")
      .toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const synthesizeJwt = (
    header: Record<string, unknown>,
    payload: Record<string, unknown>,
  ): string =>
    `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}.dummy`;

  const rpcCalls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const generateLinkCalls: Array<Record<string, unknown>> = [];
  const verifyOtpCalls: Array<Record<string, unknown>> = [];
  const getUserByIdCalls: Array<string> = [];

  const emailMap = new Map<string, string>();

  // Default-good mint config; tests override via setMintResult / setMintFailure.
  type MintConfig = {
    sub?: string;
    role?: string;
    aud?: string;
    jti?: string;
    exp?: number;
    iat?: number;
    alg?: string;
    kid?: string;
    omitJti?: boolean;
    // override for the access_token returned by verifyOtp directly
    accessToken?: string;
  };
  let mintConfig: MintConfig = {};

  type FailureStage = "generateLink" | "verifyOtp" | "getUserById" | null;
  let failureStage: FailureStage = null;
  let failureError: { message: string } | null = null;

  const createdClients: Array<{ token: string }> = [];

  const buildJwt = (overrides: MintConfig): string => {
    const iat = overrides.iat ?? 1900000000;
    const ttlImpliedExp = iat + 600;
    const payload: Record<string, unknown> = {
      sub: overrides.sub ?? "00000000-0000-0000-0000-00000000aaaa",
      role: overrides.role ?? "authenticated",
      aud: overrides.aud ?? "soleur-runtime",
      iss: "https://test-project.supabase.co/auth/v1",
      exp: overrides.exp ?? ttlImpliedExp,
      iat,
    };
    if (!overrides.omitJti) {
      payload.jti =
        overrides.jti ?? "11111111-1111-1111-1111-111111111111";
    }
    const header = {
      alg: overrides.alg ?? "ES256",
      kid: overrides.kid ?? "3605e4cb-db60-461d-a122-969e7671f66b",
      typ: "JWT",
    };
    return synthesizeJwt(header, payload);
  };

  return {
    rpcCalls,
    generateLinkCalls,
    verifyOtpCalls,
    getUserByIdCalls,
    createdClients,
    // --- API for tests ---
    setEmail: (userId: string, email: string) => {
      emailMap.set(userId, email);
    },
    setMintResult: (cfg: MintConfig) => {
      mintConfig = cfg;
      failureStage = null;
      failureError = null;
    },
    setMintFailure: (
      stage: "generateLink" | "verifyOtp" | "getUserById",
      error: { message: string },
    ) => {
      failureStage = stage;
      failureError = error;
    },
    // --- Internal accessors used by vi.mock factories ---
    _getEmail: (userId: string) =>
      emailMap.get(userId) ?? `${userId}@soleur.test`,
    _getMintConfig: () => mintConfig,
    _getFailure: () => ({ stage: failureStage, error: failureError }),
    _buildJwt: buildJwt,
    reset: () => {
      rpcCalls.length = 0;
      generateLinkCalls.length = 0;
      verifyOtpCalls.length = 0;
      getUserByIdCalls.length = 0;
      createdClients.length = 0;
      emailMap.clear();
      mintConfig = {};
      failureStage = null;
      failureError = null;
    },
  };
});

vi.mock("@/server/observability", () => ({
  mirrorWithDebounce: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test-project.supabase.co",
  getServiceClient: () => ({
    rpc: vi.fn(async (fn: string, args: Record<string, unknown>) => {
      mocks.rpcCalls.push({ fn, args });
      // PR-E #3887: deny-probe RPC fires on every cache-hit and post-mint
      // boundary. Default to "not denied" so the mint+cache assertions
      // remain semantically meaningful. Tests that need to assert deny
      // behavior live in `tenant-jwt-deny.tenant-isolation.test.ts`.
      if (fn === "is_jti_denied") return { data: false, error: null };
      // Resolution C: Node MUST NOT call any other RPC (notably
      // precheck_jwt_mint). Return a benign shape so any leaked call shows
      // up as an `mocks.rpcCalls` entry the assertions can detect.
      return { data: null, error: { message: "unexpected_rpc" } };
    }),
    auth: {
      admin: {
        getUserById: vi.fn(async (userId: string) => {
          mocks.getUserByIdCalls.push(userId);
          const f = mocks._getFailure();
          if (f.stage === "getUserById") {
            return { data: null, error: f.error };
          }
          return {
            data: {
              user: { id: userId, email: mocks._getEmail(userId) },
            },
            error: null,
          };
        }),
        generateLink: vi.fn(async (args: Record<string, unknown>) => {
          mocks.generateLinkCalls.push(args);
          const f = mocks._getFailure();
          if (f.stage === "generateLink") {
            return { data: null, error: f.error };
          }
          return {
            data: {
              properties: {
                hashed_token: "syn-hashed-token-aaaaaaaaaaaaaaaa",
                action_link:
                  "https://test-project.supabase.co/auth/v1/verify?...",
              },
              user: {
                id: (args.email as string) ?? "unknown",
                email: args.email as string,
              },
            },
            error: null,
          };
        }),
      },
      verifyOtp: vi.fn(async (args: Record<string, unknown>) => {
        mocks.verifyOtpCalls.push(args);
        const f = mocks._getFailure();
        if (f.stage === "verifyOtp") {
          return { data: null, error: f.error };
        }
        const cfg = mocks._getMintConfig();
        const access_token = cfg.accessToken ?? mocks._buildJwt(cfg);
        return {
          data: {
            session: {
              access_token,
              refresh_token: "syn-refresh-token-not-used",
            },
          },
          error: null,
        };
      }),
    },
  }),
  createServiceClient: () => ({
    rpc: vi.fn(async () => ({ data: false, error: null })),
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
      return {
        from: () => ({}),
        auth: {},
        rpc: async () => ({ data: null, error: null }),
      };
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
const FOUNDER_A_EMAIL = "founder-a@soleur.test";
const FOUNDER_B_EMAIL = "founder-b@soleur.test";

/**
 * Resolution C (#3363): mint-count = generateLink-count. The Custom Access
 * Token Hook on the database side calls `precheck_jwt_mint` itself, but
 * from Node's perspective each mint corresponds to exactly one
 * `auth.admin.generateLink` invocation.
 */
const mintCalls = () => mocks.generateLinkCalls;

beforeEach(() => {
  mocks.reset();
  _resetTenantCache();
  vi.useRealTimers();
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
  mocks.setEmail(FOUNDER_A, FOUNDER_A_EMAIL);
  mocks.setEmail(FOUNDER_B, FOUNDER_B_EMAIL);
  // Default mint config — good JWT for FOUNDER_A.
  mocks.setMintResult({ sub: FOUNDER_A });
});

describe("mintFounderJwt — claim shape (Resolution C — asymmetric substrate)", () => {
  it("Node does NOT call precheck_jwt_mint RPC directly (hook owns it) and calls generateLink with type='magiclink'+founder email", async () => {
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "11111111-1111-1111-1111-111111111111",
      exp: 1900000600,
      iat: 1900000000,
    });

    await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    // Node-side never calls precheck_jwt_mint — the hook owns it.
    const precheckCalls = mocks.rpcCalls.filter(
      (c) => c.fn === "precheck_jwt_mint",
    );
    expect(precheckCalls).toHaveLength(0);

    // generateLink was called once with type='magiclink' and the founder's email.
    expect(mocks.generateLinkCalls).toHaveLength(1);
    expect(mocks.generateLinkCalls[0]).toMatchObject({
      type: "magiclink",
      email: FOUNDER_A_EMAIL,
    });
    // verifyOtp was called once with type='email' (NOT 'magiclink' —
    // deprecated for verifyOtp per Razikus/PKCE-fix article).
    expect(mocks.verifyOtpCalls).toHaveLength(1);
    expect(mocks.verifyOtpCalls[0]).toMatchObject({ type: "email" });
  });

  it("decoded JWT payload has sub=founderId, role=authenticated, aud=soleur-runtime, iss=<project-url>/auth/v1, jti from hook, exp/iat from hook", async () => {
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "abcdabcd-abcd-abcd-abcd-abcdabcdabcd",
      exp: 1900000600,
      iat: 1900000000,
    });

    const { jwt } = await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    // Decode the payload (middle segment, base64url).
    const [header, payload, signature] = jwt.split(".");
    expect(header).toBeTruthy();
    expect(payload).toBeTruthy();
    expect(signature).toBeTruthy();

    const decoded = JSON.parse(
      Buffer.from(
        payload.replace(/-/g, "+").replace(/_/g, "/"),
        "base64",
      ).toString("utf8"),
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

    // Header should be ES256 (asymmetric) — not HS256.
    const decodedHeader = JSON.parse(
      Buffer.from(
        header.replace(/-/g, "+").replace(/_/g, "/"),
        "base64",
      ).toString("utf8"),
    );
    expect(decodedHeader.alg).toBe("ES256");
    expect(decodedHeader.alg).not.toBe("HS256");
    expect(decodedHeader.typ).toBe("JWT");
    expect(typeof decodedHeader.kid).toBe("string");
  });

  it("throws RuntimeAuthError{cause:rotation} when verifyOtp surfaces 'mint_rate_exceeded' from the hook", async () => {
    mocks.setMintFailure("verifyOtp", {
      message: "Error running hook URI: mint_rate_exceeded (SQLSTATE 45001)",
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "rotation",
    });
  });

  it("throws RuntimeAuthError{cause:jwt_mint} when generateLink returns {data:null,error}", async () => {
    mocks.setMintFailure("generateLink", { message: "network failed" });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });
});

describe("getFreshTenantClient — auto-remint at TTL/4", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-06T12:00:00.000Z"));
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "11111111-1111-1111-1111-111111111111",
      exp: 1900000600,
      iat: 1900000000,
    });
  });

  it("first call mints a JWT and caches the client", async () => {
    const client = await getFreshTenantClient(FOUNDER_A);
    expect(client).toBeTruthy();
    expect(mintCalls()).toHaveLength(1);
    expect(mocks.createdClients).toHaveLength(1);
    expect(mocks.createdClients[0].token).toMatch(/^[\w-]+\.[\w-]+\.[\w-]+$/);
  });

  it("second call within TTL/4 returns the cached client (no remint)", async () => {
    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(1);

    // Advance 100s — well below TTL/4 (150s for a 600s TTL).
    vi.advanceTimersByTime(100_000);

    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(1); // still 1, not 2
  });

  it("call after TTL/4 elapsed remints and updates the cache", async () => {
    // Distinct jti per mint so the resigned JWT is genuinely different.
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "11111111-1111-1111-1111-111111111111",
      exp: 1900000600,
      iat: 1900000000,
    });

    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(1);

    // Advance past TTL/4 (150s for default 600s TTL) — 301s is well past.
    // Change the mint result so the fresh mint produces a distinct JWT.
    vi.advanceTimersByTime(301_000);
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "22222222-2222-2222-2222-222222222222",
      exp: 1900000901,
      iat: 1900000301,
    });

    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(2);
    expect(mocks.createdClients).toHaveLength(2);
    expect(mocks.createdClients[1].token).not.toBe(
      mocks.createdClients[0].token,
    );
  });

  it("caches per founderId — A and B do not share the cache slot", async () => {
    mocks.setMintResult({ sub: FOUNDER_A });
    await getFreshTenantClient(FOUNDER_A);
    mocks.setMintResult({ sub: FOUNDER_B });
    await getFreshTenantClient(FOUNDER_B);
    expect(mintCalls()).toHaveLength(2);
    // Each mint targeted the correct founder's email.
    expect(mintCalls().map((c) => c.email)).toEqual([
      FOUNDER_A_EMAIL,
      FOUNDER_B_EMAIL,
    ]);

    // Reading A again at t<TTL/4 must NOT remint — B's mint must not bust
    // A's cache slot.
    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(2);
  });

  // Resolution C (#3363, plan §1.3): TTL/4 boundary post-rewrite. With
  // ttlSec=600, entries cached at t=0 are stale at t=150 (NOT t=300).
  it("[Resolution C] TTL/4 boundary — t=149 reuses cache, t=151 reminta (TTL=600 ⇒ TTL/4=150)", async () => {
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0000",
      exp: 1900000600,
      iat: 1900000000,
    });

    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(1);

    // t=149s — JUST below TTL/4. Must reuse the cache (no new mint).
    vi.advanceTimersByTime(149_000);
    mocks.setMintResult({
      sub: FOUNDER_A,
      jti: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001",
      exp: 1900000750,
      iat: 1900000150,
    });
    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(1); // still 1 — cache hit at t<TTL/4

    // Advance to t=151s — JUST past TTL/4. Must remint.
    vi.advanceTimersByTime(2_000);
    await getFreshTenantClient(FOUNDER_A);
    expect(mintCalls()).toHaveLength(2); // remint fired at t>TTL/4
  });

  it("[Resolution C] generateLink failure surfaces as RuntimeAuthError(jwt_mint)", async () => {
    // Plan §1.3 AC2: network-class failure on auth.admin.generateLink
    // surfaces as `RuntimeAuthError(jwt_mint)` — no crash.
    vi.useRealTimers();
    mocks.setMintFailure("generateLink", {
      message: "network: ECONNRESET",
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  it("[Resolution C] GoTrue rate-limit collapse — distinct from precheck 'rotation' cause", async () => {
    // Plan §1.3 AC3: GoTrue's per-IP rate-limit (default 10/hour TOKEN_REFRESH,
    // 10/hour EMAIL_SENT) is structurally distinct from the
    // `precheck_jwt_mint` ceiling. The former maps to `cause:jwt_mint`,
    // the latter to `cause:rotation`.
    vi.useRealTimers();

    mocks.setMintFailure("verifyOtp", {
      message: "rate_limit exceeded — GoTrue 429",
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  it("a query started before TTL/4 completes successfully without error (long-running query contract)", async () => {
    // Per plan §1.1: long-running tool calls already started under a stale
    // JWT continue to completion; the next query gets a fresh client.
    // This test models the contract by holding a reference to the cached
    // client across the TTL/4 boundary and asserting no throw — the SUT
    // does not invalidate or detach an in-flight client just because the
    // boundary tripped.
    const longRunningClient = await getFreshTenantClient(FOUNDER_A);

    // Time passes past TTL/4.
    vi.advanceTimersByTime(400_000);

    // The original client reference is still usable (no proxy revocation,
    // no thrown error, no reset).
    expect(() => longRunningClient.from("dummy")).not.toThrow();

    // A new call gets a fresh client.
    const fresh = await getFreshTenantClient(FOUNDER_A);
    expect(fresh).not.toBe(longRunningClient);
  });
});

// Silence unused-import warning when RuntimeAuthError isn't directly referenced
// in any `expect.toBeInstanceOf` here — the `.toMatchObject({name})` form is
// preferred above because it survives prototype-chain mismatches across
// vi.mock boundaries.
void RuntimeAuthError;
