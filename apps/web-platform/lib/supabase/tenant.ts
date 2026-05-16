/**
 * Tenant-scoped Supabase client factory for the server-side agentic runtime
 * (PR-B #3244, plan §1.1 / §1.4).
 *
 * Resolution A (#3363): Node holds SUPABASE_JWT_SECRET and signs runtime
 * JWTs locally with HS256. The DB-resident `precheck_jwt_mint` RPC supplies
 * the claim values that need atomic DB coordination — `jti` (random UUID),
 * `exp_epoch`, `iat_epoch` — and gates per-founder rate (60 mints/hour
 * rolling window). Node combines those with static claims (`sub`, `role`,
 * `aud`, `iss`) and signs.
 *
 * The legacy HS256 substrate is a known operational footgun (see #3363 for
 * the migration to Supabase asymmetric signing keys). Acceptable for the
 * closed-preview alpha; planned removal post-PR-D.
 *
 * Hand-rolled HS256 sign rationale: jose / jsonwebtoken would each add
 * ~30-100KB of dependency surface for a single 8-line function. byok.ts
 * (the existing precedent) uses raw node:crypto for AES-256-GCM. HS256
 * is structurally simpler — header.payload.hmac with no verification
 * round-trip on this side (PostgREST verifies). No timing-attack surface
 * exists on the SIGN path; the equality-comparison failure modes that
 * motivate vetted libraries apply only to verifiers.
 *
 * Residuals to address in follow-ups:
 *   - aud=soleur-runtime is structurally distinct on the wire but PostgREST
 *     does not enforce aud by default. Dashboard-replay prevention requires
 *     middleware-level aud filtering. See #3363 for the eventual fix.
 *   - V8 string interning of the JWT secret + signed token. Bounded by
 *     process lifetime; mitigated by the pino+sentry redaction allowlist
 *     (apps/web-platform/server/sensitive-keys.ts).
 */

import { createHmac } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getServiceClient, serverUrl } from "./service";

export type UserId = string;

export interface MintFounderJwtOpts {
  /** Token TTL in seconds. Default 600 (10min). The cache reminta at TTL/2. */
  ttlSec?: number;
}

export interface MintedJwt {
  jwt: string;
  ttlSec: number;
  /** Wall-clock ms when this JWT was minted (Date.now() snapshot). */
  mintedAt: number;
}

/**
 * Auth-domain error class. Distinct from `ByokLeaseError` (BYOK-domain) and
 * `RlsDenyError` (data-access-domain) per plan §1.6 / type-design F4.
 *
 * Causes:
 *   - "jwt_mint": signing failed, RPC failed, or claim shape malformed
 *   - "rotation": rate-limit exceeded (60 mints/hour ceiling tripped)
 *   - "denied_jti": cached JWT's jti landed in `public.denied_jti`
 */
export class RuntimeAuthError extends Error {
  // `cause` shadows the standard Error.cause to keep the auth-domain
  // discriminant on the surface. The standard ErrorOptions.cause is not
  // used here; we intentionally do not chain wrapped errors so the public
  // surface stays sanitized.
  public readonly cause: "jwt_mint" | "rotation" | "denied_jti";

  constructor(cause: "jwt_mint" | "rotation" | "denied_jti", message: string) {
    super(message);
    this.name = "RuntimeAuthError";
    this.cause = cause;
  }
}

const DEFAULT_TTL_SEC = 600;
const JWT_AUDIENCE = "soleur-runtime";

/** base64url encoder (RFC 4648 §5) — JWT spec requires URL-safe alphabet, no padding. */
function b64url(input: Buffer | string): string {
  const buf = typeof input === "string" ? Buffer.from(input, "utf8") : input;
  return buf
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function getJwtSecret(): string {
  const secret = process.env.SUPABASE_JWT_SECRET;
  if (!secret) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }
  return secret;
}

function getAnonKey(): string {
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!key) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }
  return key;
}

/** iss claim — canonical Supabase issuer URL. Required for issuer-rotation observability. */
function getIssuer(): string {
  return `${serverUrl()}/auth/v1`;
}

/**
 * Mint a fresh founder-scoped JWT.
 *
 * Calls `public.precheck_jwt_mint(p_founder_id, p_ttl_sec)` for atomic
 * rate-limit + jti generation, then HS256-signs the JWT with
 * `SUPABASE_JWT_SECRET`.
 *
 * @throws {RuntimeAuthError} cause="rotation" on rate-limit ceiling.
 * @throws {RuntimeAuthError} cause="jwt_mint" on RPC error or malformed row.
 */
export async function mintFounderJwt(
  userId: UserId,
  opts: MintFounderJwtOpts = {},
): Promise<MintedJwt> {
  const ttlSec = opts.ttlSec ?? DEFAULT_TTL_SEC;
  const service = getServiceClient();

  const { data, error } = await service.rpc("precheck_jwt_mint", {
    p_founder_id: userId,
    p_ttl_sec: ttlSec,
  });

  if (error) {
    if (error.message.includes("mint_rate_exceeded")) {
      throw new RuntimeAuthError(
        "rotation",
        "Authentication unavailable; retry shortly",
      );
    }
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  // RPC returns `RETURNS TABLE(...)` — supabase-js surfaces this as an array
  // of rows. Defensive: handle both shapes.
  const row = Array.isArray(data) ? data[0] : data;
  if (
    !row ||
    typeof row.jti !== "string" ||
    typeof row.exp_epoch !== "number" ||
    typeof row.iat_epoch !== "number"
  ) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  const payload = {
    sub: userId,
    role: "authenticated",
    aud: JWT_AUDIENCE,
    iss: getIssuer(),
    jti: row.jti,
    exp: row.exp_epoch,
    iat: row.iat_epoch,
  };

  // HS256: header.payload.HMAC-SHA256(header.payload, secret).
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(payload));
  const signingInput = `${header}.${body}`;
  const signature = b64url(
    createHmac("sha256", getJwtSecret()).update(signingInput).digest(),
  );

  return {
    jwt: `${signingInput}.${signature}`,
    ttlSec,
    mintedAt: Date.now(),
  };
}

/**
 * Build a fresh `SupabaseClient` bound to a tenant-scoped JWT.
 *
 * Private to this module — callers use `getFreshTenantClient` instead so
 * the auto-remint boundary is consistently applied (per Kieran P1.1).
 */
function createTenantClient(jwt: string): SupabaseClient {
  return createClient(serverUrl(), getAnonKey(), {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

interface CacheEntry {
  jwt: string;
  mintedAt: number;
  ttlSec: number;
  client: SupabaseClient;
}

/**
 * Process-local per-userId cache of `Promise<CacheEntry>`.
 *
 * Storing the in-flight Promise (not the resolved value) is the load-
 * bearing dedup: concurrent cold callers (e.g., `Promise.all([lease.getApiKey(),
 * getUserServiceTokens(userId)])` at session start) await the same
 * pending mint instead of each consuming a slot from the 60/hr ceiling.
 * Entries are remminted when `now - mintedAt > ttlSec/2` (Kieran P1.1
 * boundary). In-flight queries holding the previous client reference
 * continue to completion (PostgREST's resultset is unaffected by
 * subsequent header changes).
 */
const cache = new Map<UserId, Promise<CacheEntry>>();

/**
 * Get a tenant-scoped Supabase client for the given founder, transparently
 * reminting the underlying JWT when it crosses the TTL/2 freshness
 * boundary.
 *
 * This is the only public boundary call sites should use for tenant-data
 * reads/writes. Long-running tool calls already holding the previous
 * client reference continue to completion; the next call gets a fresh
 * client.
 *
 * @throws {RuntimeAuthError} on remint failure (rate-limit, RPC error,
 *   missing secret).
 */
export async function getFreshTenantClient(
  userId: UserId,
): Promise<SupabaseClient> {
  const now = Date.now();
  const inflight = cache.get(userId);

  if (inflight) {
    // Settled or in-flight — peek the resolved freshness if settled,
    // otherwise let the second concurrent caller share the same mint.
    // We can't synchronously inspect a Promise's state; the simplest
    // dedup is to await and then re-validate freshness. Cost on a hot
    // path is one extra microtask vs the alternative double-mint.
    const entry = await inflight;
    if (now - entry.mintedAt < (entry.ttlSec * 1000) / 2) {
      return entry.client;
    }
    // Stale — fall through to remint.
  }

  const minting: Promise<CacheEntry> = (async () => {
    const minted = await mintFounderJwt(userId, { ttlSec: DEFAULT_TTL_SEC });
    return {
      jwt: minted.jwt,
      mintedAt: minted.mintedAt,
      ttlSec: minted.ttlSec,
      client: createTenantClient(minted.jwt),
    };
  })();
  cache.set(userId, minting);

  try {
    const entry = await minting;
    return entry.client;
  } catch (err) {
    // Don't keep a rejected Promise in the cache — every subsequent
    // caller would re-throw the same error without retrying the mint.
    if (cache.get(userId) === minting) cache.delete(userId);
    throw err;
  }
}

/**
 * Test-only cache reset. Public so unit tests can isolate state without
 * touching internals. Callers in production code MUST NOT use this.
 */
export function _resetTenantCache(): void {
  cache.clear();
}
