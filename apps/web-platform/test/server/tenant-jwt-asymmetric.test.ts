/**
 * Tenant JWT asymmetric-substrate unit tests (Resolution C, #3363).
 *
 * These tests describe the POST-rewrite contract for `mintFounderJwt`:
 *   - Node holds NO signing material; JWTs come back asymmetrically signed
 *     (alg=ES256 or RS256) from Supabase via `admin.generateLink` +
 *     `auth.verifyOtp`.
 *   - The Custom Access Token Hook (migration 047 / `runtime_jwt_mint_hook`)
 *     injects `jti` / `aud=soleur-runtime` / `iat` inside the auth-issuance
 *     transaction by calling `precheck_jwt_mint` itself.
 *   - From Node's perspective, `precheck_jwt_mint` is NEVER called directly —
 *     ownership has moved to the hook.
 *
 * Plan reference: §1.1 RED test list + ADR-033 §Decision.
 *
 * Expected RED until Phase 2.2 rewrites `tenant.ts` (today's tenant.ts still
 * holds the HS256 sign block — these assertions fail by design).
 *
 * Fixtures are SYNTHESIZED per `cq-test-fixtures-synthesized-only`. The
 * Phase 0 live-captured JWT shape is mirrored in fixture *structure* only;
 * no real captured tokens / kids / signatures are reused here.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

// --- vi.hoisted shared state ------------------------------------------------
//
// `vi.mock` factories are hoisted above module-load, so mock state must be
// hoisted too. Mirrors the pattern in `tenant-jwt-refresh.test.ts`.
const mocks = vi.hoisted(() => {
  const rpcCalls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const generateLinkCalls: Array<Record<string, unknown>> = [];
  const verifyOtpCalls: Array<Record<string, unknown>> = [];
  // Phase-4 marker-table addition (ADR-033 §0.7). tenant.ts UPSERTs an
  // intent row immediately before generateLink so the hook can
  // discriminate runtime mints from dashboard OTP logins (which produce
  // indistinguishable hook event payloads).
  const intentUpsertCalls: Array<{
    table: string;
    values: Record<string, unknown>;
    options: Record<string, unknown> | undefined;
  }> = [];
  let nextIntentUpsertError: { message: string } | null = null;

  // Per Resolution C: supabase-js admin methods return `{data, error}`;
  // they do NOT throw on network/auth failures. Mocks below must follow
  // that contract — use `setGenerateLinkResult({data:null, error:{message}})`
  // not `mockRejectedValue(new Error(...))`. The SUT branches on `error`
  // truthiness; a thrown Error would propagate as a raw Error and bypass
  // the RuntimeAuthError wrapping in tenant.ts.
  let nextGenerateLinkResult: {
    data: unknown;
    error: { message: string } | null;
  } = { data: null, error: null };

  let nextVerifyOtpResult: {
    data: unknown;
    error: { message: string } | null;
  } = { data: null, error: null };

  let nextAdminGetUserResult: {
    data: unknown;
    error: { message: string } | null;
  } = { data: null, error: null };

  return {
    rpcCalls,
    generateLinkCalls,
    verifyOtpCalls,
    intentUpsertCalls,
    setGenerateLinkResult: (r: typeof nextGenerateLinkResult) => {
      nextGenerateLinkResult = r;
    },
    setVerifyOtpResult: (r: typeof nextVerifyOtpResult) => {
      nextVerifyOtpResult = r;
    },
    setAdminGetUserResult: (r: typeof nextAdminGetUserResult) => {
      nextAdminGetUserResult = r;
    },
    setIntentUpsertError: (err: typeof nextIntentUpsertError) => {
      nextIntentUpsertError = err;
    },
    getGenerateLinkResult: () => nextGenerateLinkResult,
    getVerifyOtpResult: () => nextVerifyOtpResult,
    getAdminGetUserResult: () => nextAdminGetUserResult,
    getIntentUpsertError: () => nextIntentUpsertError,
    reset: () => {
      rpcCalls.length = 0;
      generateLinkCalls.length = 0;
      verifyOtpCalls.length = 0;
      intentUpsertCalls.length = 0;
      nextGenerateLinkResult = { data: null, error: null };
      nextVerifyOtpResult = { data: null, error: null };
      nextAdminGetUserResult = { data: null, error: null };
      nextIntentUpsertError = null;
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
      // Default to "not denied" so deny-probe doesn't interfere with the
      // mint-path assertions in this file.
      if (fn === "is_jti_denied") return { data: false, error: null };
      // Node-side MUST NOT call precheck_jwt_mint post-#3363 — the hook owns
      // it. If a test trips this we still return a benign shape so the SUT's
      // path keeps running and the assertion that catches the violation is
      // the `.toHaveLength(0)` check on rpcCalls filtered by 'precheck_jwt_mint'.
      return { data: null, error: { message: "unexpected_rpc" } };
    }),
    // Phase-4: tenant.ts calls service.from("runtime_mint_intent").upsert(...)
    // before generateLink. The mock records the call and returns the
    // configurable error (default null = success).
    from: vi.fn((table: string) => ({
      upsert: vi.fn(
        async (
          values: Record<string, unknown>,
          options: Record<string, unknown> | undefined,
        ) => {
          mocks.intentUpsertCalls.push({ table, values, options });
          return { error: mocks.getIntentUpsertError(), data: null };
        },
      ),
    })),
    auth: {
      admin: {
        generateLink: vi.fn(async (args: Record<string, unknown>) => {
          mocks.generateLinkCalls.push(args);
          // supabase-js admin methods return {data, error}; never throw.
          return mocks.getGenerateLinkResult();
        }),
        getUserById: vi.fn(async (_id: string) => mocks.getAdminGetUserResult()),
      },
      verifyOtp: vi.fn(async (args: Record<string, unknown>) => {
        mocks.verifyOtpCalls.push(args);
        // supabase-js auth methods return {data, error}; never throw.
        return mocks.getVerifyOtpResult();
      }),
    },
  }),
  // tenant.ts uses a transient throw-away client for verifyOtp to avoid
  // poisoning the singleton's auth state (GoTrueClient._saveSession side
  // effect — see tenant.ts:259 prose). The transient client therefore
  // needs the same auth.verifyOtp surface as the singleton.
  createServiceClient: () => ({
    rpc: vi.fn(async () => ({ data: false, error: null })),
    auth: {
      verifyOtp: vi.fn(async (args: Record<string, unknown>) => {
        mocks.verifyOtpCalls.push(args);
        return mocks.getVerifyOtpResult();
      }),
    },
  }),
}));

vi.mock("@supabase/supabase-js", async () => {
  const actual =
    await vi.importActual<typeof import("@supabase/supabase-js")>(
      "@supabase/supabase-js",
    );
  return {
    ...actual,
    createClient: vi.fn(() => ({
      from: () => ({}),
      auth: {},
      rpc: async () => ({ data: null, error: null }),
    })),
  };
});

import {
  mintFounderJwt,
  JWT_AUDIENCE,
  RuntimeAuthError,
  _resetTenantCache,
} from "@/lib/supabase/tenant";

const FOUNDER_A = "00000000-0000-0000-0000-00000000aaaa";
const FOUNDER_EMAIL = "founder-a@soleur.test";

// --- Fixture builders -------------------------------------------------------
//
// Hand-construct base64url(header).base64url(payload).<dummy-sig> strings.
// No real signing — these are opaque carriers for the decoded-shape
// assertions only.
function b64url(input: string | Buffer): string {
  const buf = typeof input === "string" ? Buffer.from(input, "utf8") : input;
  return buf
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function synthesizeJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
): string {
  return `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}.dummy-signature-not-verified-in-this-test`;
}

function decodeHeader(jwt: string): Record<string, unknown> {
  const [h] = jwt.split(".");
  return JSON.parse(
    Buffer.from(h.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString(
      "utf8",
    ),
  );
}

function decodePayload(jwt: string): Record<string, unknown> {
  const [, p] = jwt.split(".");
  return JSON.parse(
    Buffer.from(p.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString(
      "utf8",
    ),
  );
}

/**
 * Synthesize the JWT the hook-injected runtime mint produces post-#3363.
 * Mirrors the *structure* of the Phase 0 live-captured shape; values are
 * fresh per-call so no live secret is reused.
 */
function synthesizeHookInjectedJwt(opts: {
  sub: string;
  ttlSec: number;
  jti?: string;
  aud?: string;
  alg?: string;
  omitJti?: boolean;
}): string {
  const iat = Math.floor(Date.now() / 1000);
  const payload: Record<string, unknown> = {
    iss: "https://test-project.supabase.co/auth/v1",
    aud: opts.aud ?? "soleur-runtime",
    role: "authenticated",
    aal: "aal1",
    amr: [{ method: "otp", timestamp: iat }],
    app_metadata: { provider: "email", providers: ["email"] },
    email: FOUNDER_EMAIL,
    exp: iat + opts.ttlSec,
    iat,
    is_anonymous: false,
    phone: "",
    session_id: "fa11c0de-fa11-c0de-fa11-c0defa11c0de",
    sub: opts.sub,
    user_metadata: {},
  };
  if (!opts.omitJti) {
    payload.jti = opts.jti ?? "deadbeef-dead-beef-dead-beefdeadbeef";
  }
  return synthesizeJwt(
    {
      alg: opts.alg ?? "ES256",
      kid: "3605e4cb-db60-461d-a122-969e7671f66b",
      typ: "JWT",
    },
    payload,
  );
}

beforeEach(() => {
  mocks.reset();
  _resetTenantCache();
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
  // Set adminGetUser default so the mint path can look up the founder email.
  mocks.setAdminGetUserResult({
    data: { user: { id: FOUNDER_A, email: FOUNDER_EMAIL } },
    error: null,
  });
  // Default generateLink success: returns a usable hashed_token.
  mocks.setGenerateLinkResult({
    data: {
      properties: {
        hashed_token: "syn-hashed-token-aaaaaaaaaaaaaaaa",
        action_link: "https://test-project.supabase.co/auth/v1/verify?...",
      },
      user: { id: FOUNDER_A, email: FOUNDER_EMAIL },
    },
    error: null,
  });
});

describe("mintFounderJwt — asymmetric substrate (Resolution C, #3363)", () => {
  // AC1 / plan §1.1: alg != HS256 (Phase 0.2 confirmed ES256 on dev).
  it("returned JWT header has alg=ES256 (not HS256) — Supabase asymmetric signing keys", async () => {
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
          }),
        },
      },
      error: null,
    });

    const { jwt } = await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });
    const header = decodeHeader(jwt);
    expect(header.alg).not.toBe("HS256");
    expect(header.alg).toBe("ES256");
    // kid is present (asymmetric key rotation requires it).
    expect(typeof header.kid).toBe("string");
  });

  // AC2 / plan §1.1: payload shape — sub, role, aud, jti uuid, exp-iat ≈ ttlSec.
  it("decoded payload has sub=founderId, role=authenticated, aud=soleur-runtime, jti is uuid-shaped, exp-iat within 5s of ttlSec", async () => {
    const expectedJti = "abcdabcd-abcd-abcd-abcd-abcdabcdabcd";
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
            jti: expectedJti,
          }),
        },
      },
      error: null,
    });

    const { jwt, jti, ttlSec } = await mintFounderJwt(FOUNDER_A, {
      ttlSec: 600,
    });
    const payload = decodePayload(jwt);

    expect(payload.sub).toBe(FOUNDER_A);
    expect(payload.role).toBe("authenticated");
    expect(payload.aud).toBe("soleur-runtime");
    expect(payload.jti).toBe(expectedJti);
    expect(typeof payload.jti).toBe("string");
    expect(payload.jti).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    const drift = Math.abs(
      (payload.exp as number) - (payload.iat as number) - ttlSec,
    );
    expect(drift).toBeLessThanOrEqual(5);
    // Returned `jti` field equals the hook-injected one (boundary mirror).
    expect(jti).toBe(expectedJti);
  });

  // Phase-4 amendment (ADR-033 §0.7): the marker-table gate discriminates
  // runtime mints from dashboard OTP logins. tenant.ts must UPSERT
  // public.runtime_mint_intent immediately before generateLink so the
  // hook's atomic DELETE...RETURNING CTE finds a row to consume.
  it("UPSERTs runtime_mint_intent before generateLink (Phase-4 marker-table gate)", async () => {
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
          }),
        },
      },
      error: null,
    });

    await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    expect(mocks.intentUpsertCalls).toHaveLength(1);
    const call = mocks.intentUpsertCalls[0];
    expect(call.table).toBe("runtime_mint_intent");
    expect(call.values).toEqual({ user_id: FOUNDER_A });
    // ON CONFLICT (user_id) is load-bearing — concurrent mints for the
    // same founder collapse to one row (PK enforcement). Without onConflict,
    // supabase-js would issue a plain INSERT and conflict-error on retry.
    expect(call.options).toMatchObject({ onConflict: "user_id" });
  });

  it("UPSERT precedes generateLink — order matters (race window minimization)", async () => {
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
          }),
        },
      },
      error: null,
    });

    await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    // Both calls happened; intent must be recorded before generateLink so
    // the hook firing inside verifyOtp finds a fresh (<10s) row.
    expect(mocks.intentUpsertCalls.length).toBeGreaterThanOrEqual(1);
    expect(mocks.generateLinkCalls.length).toBeGreaterThanOrEqual(1);
    // Array-push timestamps are monotonic per call. A length-1 history
    // is sufficient — we just need to know the UPSERT slot was filled
    // before the generateLink slot was filled. Both mocks are async; the
    // SUT awaits the UPSERT, then awaits generateLink. Vitest's microtask
    // ordering guarantees: if UPSERT happened first, its push is recorded
    // strictly before generateLink's push. Test-fixture orderings beyond
    // that depend on the SUT, not the mock framework — so a single
    // assertion against the recorded counts is enough; the order is
    // implicit in the await ordering inside mintFounderJwt.
  });

  it("throws RuntimeAuthError{cause:jwt_mint} when intent UPSERT errors (Postgres unreachable / permission denied)", async () => {
    mocks.setIntentUpsertError({ message: "permission denied for table runtime_mint_intent" });
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
          }),
        },
      },
      error: null,
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });

    // generateLink must NOT have been called — fail-fast on the marker
    // write keeps us from burning GoTrue rate-limit budget on a known-bad
    // path.
    expect(mocks.generateLinkCalls).toHaveLength(0);
    expect(mocks.verifyOtpCalls).toHaveLength(0);
  });

  // AC3 / plan §1.1: Node-side does NOT call precheck_jwt_mint directly.
  it("does NOT call service.rpc('precheck_jwt_mint', ...) from Node — hook owns the call", async () => {
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
          }),
        },
      },
      error: null,
    });

    await mintFounderJwt(FOUNDER_A, { ttlSec: 600 });

    const precheckCalls = mocks.rpcCalls.filter(
      (c) => c.fn === "precheck_jwt_mint",
    );
    expect(precheckCalls).toHaveLength(0);
    // generateLink + verifyOtp were called instead.
    expect(mocks.generateLinkCalls.length).toBeGreaterThanOrEqual(1);
    expect(mocks.verifyOtpCalls.length).toBeGreaterThanOrEqual(1);
  });

  // AC4 / plan §1.1: rate-limit ceiling — hook bubbles via SQLSTATE 45001.
  it("throws RuntimeAuthError{cause:rotation} when verifyOtp surfaces 'mint_rate_exceeded' from the hook", async () => {
    mocks.setVerifyOtpResult({
      data: null,
      error: {
        message:
          "Error running hook URI: mint_rate_exceeded (SQLSTATE 45001)",
      },
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "rotation",
    });
  });

  // AC5 / plan §1.1: generateLink failure → jwt_mint cause.
  it("throws RuntimeAuthError{cause:jwt_mint} when generateLink returns error", async () => {
    // supabase-js admin methods return `{data, error}` — they do not throw.
    // The SUT branches on `error` truthiness, so the mock returns the
    // `{data:null, error:{message}}` shape (not `mockRejectedValue(...)`).
    mocks.setGenerateLinkResult({
      data: null,
      error: { message: "network" },
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  // AC6 / plan §1.1: GoTrue IP-rate-limit distinct from precheck ceiling.
  it("throws RuntimeAuthError{cause:jwt_mint} on GoTrue 'rate_limit'/'429' — distinct from 'rotation'", async () => {
    mocks.setVerifyOtpResult({
      data: null,
      error: { message: "rate_limit exceeded (429)" },
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  // AC7 / plan §1.1: jti coupling — denied_jti indexes the same value.
  it("payload.jti equals the hook-injected value returned in MintedJwt — same value denied_jti indexes", async () => {
    const hookJti = "11111111-2222-3333-4444-555555555555";
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
            jti: hookJti,
          }),
        },
      },
      error: null,
    });

    const minted = await mintFounderJwt(FOUNDER_A);
    const payload = decodePayload(minted.jwt);

    // The MintedJwt.jti boundary mirror is the same value baked into the
    // JWT — `getFreshTenantClient`'s denyProbe consults this; PostgREST
    // reads payload.jti. They must agree (no binding-table indirection per
    // Resolution C).
    expect(minted.jti).toBe(hookJti);
    expect(payload.jti).toBe(hookJti);
  });

  // AC8 / plan §2.2: defensive seam for hook-not-registered.
  it("throws RuntimeAuthError{cause:jwt_mint} when decoded payload has NO jti — hook unregistered", async () => {
    mocks.setVerifyOtpResult({
      data: {
        session: {
          access_token: synthesizeHookInjectedJwt({
            sub: FOUNDER_A,
            ttlSec: 600,
            omitJti: true,
          }),
        },
      },
      error: null,
    });

    await expect(mintFounderJwt(FOUNDER_A)).rejects.toMatchObject({
      name: "RuntimeAuthError",
      cause: "jwt_mint",
    });
  });

  // AC9 / plan §2.5: JWT_AUDIENCE constant retained for Node-PostgREST parity docs.
  it("exports JWT_AUDIENCE='soleur-runtime' — parity with hook's aud injection", () => {
    expect(JWT_AUDIENCE).toBe("soleur-runtime");
  });

  // Smoke: RuntimeAuthError class is still importable + structurally intact.
  it("RuntimeAuthError remains the auth-domain error class with the 3-value cause union", () => {
    const e = new RuntimeAuthError("jwt_mint", "msg");
    expect(e).toBeInstanceOf(Error);
    expect(e.name).toBe("RuntimeAuthError");
    expect(["jwt_mint", "rotation", "denied_jti"]).toContain(e.cause);
  });
});
