/**
 * Tenant JWT deny-list consumer — DB-layer integration test (PR-E #3887).
 *
 * Closes the Art. 5(2) accountability gap left open by PR-B's deny-list
 * primitive (`is_jti_denied` SECURITY DEFINER fn, migration 037) by
 * proving the JWT-mint-path consumer wired in `lib/supabase/tenant.ts`
 * (a) probes the deny-list on every cache-hit / cache-miss surface, (b)
 * evicts and reminta on cache-hit deny, and (c) throws an explicit
 * `RuntimeAuthError(cause="denied_jti")` on cache-miss deny.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Runs against the dev Supabase
 * project; requires `doppler run -p soleur -c dev` to provide
 * SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 * and SUPABASE_JWT_SECRET.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/tenant-jwt-deny.tenant-isolation.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only):
 *   - Synthetic emails matching `tenant-isolation-[a-f0-9]{16}@soleur.test`.
 *   - Email allowlist enforced before any auth.admin.deleteUser call.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import {
  RuntimeAuthError,
  getFreshTenantClient,
  mapRuntimeAuthCauseToErrorCode,
  _peekCachedJti,
  _resetTenantCache,
  _setMintFnForTest,
} from "@/lib/supabase/tenant";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `tenant-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates tenant-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-jwt-deny] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant JWT deny-list consumer (integration)",
  () => {
    let service: SupabaseClient;
    const user = {
      id: "",
      email: syntheticEmail(),
    };

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      if (data.user?.id) user.id = data.user.id;
      expect(user.id).toBeTruthy();
    });

    afterAll(async () => {
      if (!user.id) return;
      assertSynthetic(user.email);
      // Clean any test-inserted deny-list rows for this synthetic founder.
      await service.from("denied_jti").delete().eq("founder_id", user.id);
      await service.auth.admin.deleteUser(user.id);
    });

    beforeEach(async () => {
      _resetTenantCache();
      _setMintFnForTest(null);
      if (user.id) {
        await service.from("denied_jti").delete().eq("founder_id", user.id);
      }
    });

    test("A: fresh mint with empty deny-list returns a usable client", async () => {
      const client = await getFreshTenantClient(user.id);
      expect(client).toBeDefined();
      const jti = await _peekCachedJti(user.id);
      expect(jti).toBeTruthy();
    });

    test("B: cache-hit path with revoked jti evicts cache and reminta", async () => {
      const client1 = await getFreshTenantClient(user.id);
      const jti1 = await _peekCachedJti(user.id);
      expect(jti1).toBeTruthy();

      // Revoke the cached jti.
      const { error } = await service.from("denied_jti").insert({
        jti: jti1!,
        founder_id: user.id,
        reason: "test:cache-hit-revoke",
      });
      expect(error, "denied_jti insert").toBeNull();

      const client2 = await getFreshTenantClient(user.id);
      const jti2 = await _peekCachedJti(user.id);

      // The cache-hit deny-probe must have evicted and remminted: a new
      // client instance bound to a different jti.
      expect(client2).not.toBe(client1);
      expect(jti2).toBeTruthy();
      expect(jti2).not.toBe(jti1);
    });

    test("C: cache-miss with pre-denied jti throws RuntimeAuthError(denied_jti)", async () => {
      // Inject a known jti into the deny-list, override mint to return
      // exactly that jti — forces the structurally-rare "minted-and-already-
      // denied" race deterministically.
      const knownJti = randomUUID();
      const { error: insertError } = await service.from("denied_jti").insert({
        jti: knownJti,
        founder_id: user.id,
        reason: "test:cache-miss-pre-deny",
      });
      expect(insertError, "denied_jti insert").toBeNull();

      _setMintFnForTest(async () => ({
        // The JWT body is opaque to the deny-probe — only `jti` matters.
        jwt: `header.${Buffer.from(JSON.stringify({ jti: knownJti })).toString("base64url")}.signature`,
        ttlSec: 600,
        mintedAt: Date.now(),
        jti: knownJti,
      }));

      await expect(getFreshTenantClient(user.id)).rejects.toMatchObject({
        name: "RuntimeAuthError",
        cause: "denied_jti",
      });

      // Cache must be empty after the reject — the next caller gets a
      // clean cache-miss instead of inheriting the rejected Promise.
      expect(await _peekCachedJti(user.id)).toBeNull();
    });

    test("D: unrelated jti insert does not affect founder's session", async () => {
      const client1 = await getFreshTenantClient(user.id);
      const jti1 = await _peekCachedJti(user.id);

      // Insert an unrelated jti (random UUID, different from cached).
      const noiseJti = randomUUID();
      expect(noiseJti).not.toBe(jti1);
      const { error } = await service.from("denied_jti").insert({
        jti: noiseJti,
        founder_id: user.id,
        reason: "test:noise",
      });
      expect(error).toBeNull();

      const client2 = await getFreshTenantClient(user.id);
      const jti2 = await _peekCachedJti(user.id);

      // Cached jti is NOT on the deny-list → cache-hit returns same client.
      expect(client2).toBe(client1);
      expect(jti2).toBe(jti1);
    });
  },
);

/**
 * Resolution C (#3363) — denied_jti revocation against asymmetric-signed JWTs.
 *
 * Plan §1.2 RED extension: existing tests A-D above are written against the
 * HS256 substrate (Resolution A). Post-Phase 2, `mintFounderJwt` produces
 * asymmetrically-signed JWTs with `jti` injected by the
 * `runtime_jwt_mint_hook` Custom Access Token Hook (migration 047) — not by
 * Node. The deny-list contract is unchanged: `denied_jti` continues to
 * index the JWT's own `jti` claim (no binding-table indirection per ADR-033).
 *
 * Expected RED until Phase 2 wires mintFounderJwt + the hook is registered
 * on dev (see Deploy-Order Runbook step c). Gated by TENANT_INTEGRATION_TEST=1
 * like the suite above.
 *
 * ADDITIVE only — existing tests A-D and the unit shape suite are unchanged.
 */
describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant JWT deny-list consumer — asymmetric substrate (Resolution C, #3363)",
  () => {
    let service: SupabaseClient;
    const user = {
      id: "",
      email: syntheticEmail(),
    };

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      // NOTE: SUPABASE_JWT_SECRET is intentionally NOT required here. The
      // Resolution C substrate retires Node-held signing material.

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      if (data.user?.id) user.id = data.user.id;
      expect(user.id).toBeTruthy();
    });

    afterAll(async () => {
      if (!user.id) return;
      assertSynthetic(user.email);
      await service.from("denied_jti").delete().eq("founder_id", user.id);
      await service.auth.admin.deleteUser(user.id);
    });

    beforeEach(async () => {
      _resetTenantCache();
      _setMintFnForTest(null);
      if (user.id) {
        await service.from("denied_jti").delete().eq("founder_id", user.id);
      }
    });

    test("E: denied_jti revocation against asymmetric-signed JWT — identical contract as HS256 test B", async () => {
      // Plan §1.2 AC1: the JWT under test was minted via mintFounderJwt
      // (Resolution C — asymmetrically signed by Supabase, jti injected by
      // the hook). The deny-list revocation contract is unchanged: insert
      // the jti, the next getFreshTenantClient evicts + reminta.
      const client1 = await getFreshTenantClient(user.id);
      const jti1 = await _peekCachedJti(user.id);
      expect(jti1).toBeTruthy();

      const { error } = await service.from("denied_jti").insert({
        jti: jti1!,
        founder_id: user.id,
        reason: "test:asymmetric-cache-hit-revoke",
      });
      expect(error, "denied_jti insert").toBeNull();

      const client2 = await getFreshTenantClient(user.id);
      const jti2 = await _peekCachedJti(user.id);

      // Same revocation behavior as test B above: cache-hit deny-probe
      // evicts and reminta with a fresh hook-injected jti.
      expect(client2).not.toBe(client1);
      expect(jti2).toBeTruthy();
      expect(jti2).not.toBe(jti1);
    });

    test("F: hook-injected jti matches denied_jti indexed value — no binding-table indirection", async () => {
      // Plan §1.2 AC2: PostgREST sees the SAME jti claim that the hook wrote.
      // `_peekCachedJti` returns the value baked into the JWT by the hook
      // (via the `MintedJwt.jti` boundary mirror); the deny-list indexes
      // that same value. No side-table mapping required (Resolution C
      // decision point recorded in ADR-033).
      const client = await getFreshTenantClient(user.id);
      expect(client).toBeDefined();

      const cachedJti = await _peekCachedJti(user.id);
      expect(cachedJti).toBeTruthy();
      expect(cachedJti).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
      );

      // Insert that exact jti into denied_jti — no transformation, no
      // binding-table lookup. The deny-probe on the NEXT call must observe
      // the same value via `is_jti_denied`.
      const { error: insertError } = await service.from("denied_jti").insert({
        jti: cachedJti!,
        founder_id: user.id,
        reason: "test:hook-injected-jti-identity",
      });
      expect(insertError, "denied_jti insert").toBeNull();

      // Probe directly through the RPC the consumer calls.
      const { data: deniedProbe, error: rpcError } = await service.rpc(
        "is_jti_denied",
        { p_jti: cachedJti! },
      );
      expect(rpcError).toBeNull();
      expect(deniedProbe).toBe(true);

      // And the consumer surface honors it — next call evicts + reminta.
      const client2 = await getFreshTenantClient(user.id);
      const jti2 = await _peekCachedJti(user.id);
      expect(client2).not.toBe(client);
      expect(jti2).not.toBe(cachedJti);
    });
  },
);

describe("RuntimeAuthError shape (unit, no integration env)", () => {
  test("denied_jti cause is structurally distinct from jwt_mint / rotation", () => {
    const e = new RuntimeAuthError("denied_jti", "msg");
    expect(e.name).toBe("RuntimeAuthError");
    expect(e.cause).toBe("denied_jti");
    expect(e.message).toBe("msg");
    expect(e instanceof Error).toBe(true);
  });

  test("mapRuntimeAuthCauseToErrorCode is exhaustive over the 3-value cause union", () => {
    // Pins the cq-union-widening-grep-three-patterns contract: every
    // member of `RuntimeAuthError["cause"]` must map to a stable
    // client-side error-code string. A future cause widening that
    // forgets to extend this mapper is a TS build break, not a silent
    // `undefined` fall-through at every catch site.
    expect(mapRuntimeAuthCauseToErrorCode("denied_jti")).toBe("session_revoked");
    expect(mapRuntimeAuthCauseToErrorCode("rotation")).toBe("auth_throttled");
    expect(mapRuntimeAuthCauseToErrorCode("jwt_mint")).toBe("auth_unavailable");
  });
});
