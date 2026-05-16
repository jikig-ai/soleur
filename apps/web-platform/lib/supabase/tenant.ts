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
import { mirrorWithDebounce } from "@/server/observability";
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
  /**
   * The jti claim baked into the JWT. Mirrored at the boundary so the
   * deny-list consumer (`getFreshTenantClient`) can probe `is_jti_denied`
   * without redundantly base64url-decoding the JWT payload.
   */
  jti: string;
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

/**
 * Map a `RuntimeAuthError.cause` to a stable client-side error-code string.
 * Mirrors the `mapByokLeaseCauseToErrorCode` precedent in
 * `apps/web-platform/server/byok-lease.ts` so on-call playbooks and any
 * future per-cause UX can distinguish revocation (`session_revoked`)
 * from rate-limit (`auth_throttled`) from RPC outage / missing-secret
 * (`auth_unavailable`).
 *
 * Per `cq-union-widening-grep-three-patterns`: the exhaustive `switch` +
 * `: never` rail makes a future `cause` widening a TS build break here
 * rather than a silent fall-through to `undefined` at every call site.
 *
 * Catch sites that today collapse all three causes to a generic toast
 * MAY adopt this mapper to emit `extra: { code: mapRuntimeAuthCauseToErrorCode(err.cause) }`
 * on the existing `reportSilentFallback` calls. Widening the user-facing
 * message per cause is out of scope (the sanitized "Authentication
 * unavailable; retry shortly" message is intentional to avoid leaking
 * cause-discriminant info to the user surface — see the docblock on
 * `RuntimeAuthError` above).
 */
export function mapRuntimeAuthCauseToErrorCode(
  cause: RuntimeAuthError["cause"],
): "session_revoked" | "auth_throttled" | "auth_unavailable" {
  switch (cause) {
    case "denied_jti":
      return "session_revoked";
    case "rotation":
      return "auth_throttled";
    case "jwt_mint":
      return "auth_unavailable";
    default: {
      const _exhaustive: never = cause;
      return _exhaustive;
    }
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
    jti: row.jti,
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
  jti: string;
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
 * Test-only seam — replaces the `mintFounderJwt` call inside
 * `getFreshTenantClient`'s cache-miss path for the next call.
 *
 * Required for Test C of `tenant-jwt-deny.tenant-isolation.test.ts`: the
 * deny-check at the cache-miss boundary can only fire when a freshly-
 * minted jti is already on the deny-list — a structurally impossible
 * race under random-UUID minting. The seam lets the test inject a
 * pre-denied jti deterministically.
 *
 * Null default. Production callers MUST NOT use this. Guarded against
 * production use by a `NODE_ENV === "production"` check in
 * `_setMintFnForTest`.
 */
let __mintFnForTest:
  | ((userId: UserId, opts?: MintFounderJwtOpts) => Promise<MintedJwt>)
  | null = null;
export function _setMintFnForTest(
  fn: typeof __mintFnForTest,
): void {
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "_setMintFnForTest is a test-only seam and must not be called in production",
    );
  }
  __mintFnForTest = fn;
}

async function callMint(userId: UserId): Promise<MintedJwt> {
  const fn = __mintFnForTest ?? mintFounderJwt;
  return fn(userId, { ttlSec: DEFAULT_TTL_SEC });
}

/**
 * Cache-eviction guard — delete only if the caller is still the current
 * inflight Promise for `userId`. Three call sites in `getFreshTenantClient`
 * use this: cache-hit deny, post-mint deny throw, and the trailing
 * `catch` that handles thrown mint failures. Centralizing the
 * referential-equality check prevents subtle drift between them (e.g.,
 * a racing caller installing a fresh `minting` after eviction should
 * NOT be clobbered).
 */
function evictIf(userId: UserId, expected: Promise<CacheEntry>): void {
  if (cache.get(userId) === expected) cache.delete(userId);
}

/**
 * Probe the deny-list for `jti`. Returns `true` iff the row exists.
 *
 * Centralizes the RPC call + Sentry mirror so the cache-hit (falls
 * through to remint) and cache-miss (throws) paths in
 * `getFreshTenantClient` share identical observability.
 *
 * Sentry mirrors use `mirrorWithDebounce` (5-min per-key TTL) so a
 * misconfigured RPC or a sustained revocation campaign cannot bury
 * other signals with thousands of identical events. RPC failures —
 * including thrown errors (network reject, malformed client) — are
 * caught and treated as "not denied" (fail-open) so a transient deny-
 * list outage does not lock out every founder; the Sentry mirror is the
 * durable signal that the deny surface is unreachable. **Why fail-open
 * vs fail-closed:** at the `single-user incident` brand-survival
 * threshold for the closed-preview alpha, the user-impact of a
 * wholesale lockout (every founder loses access until a flake clears)
 * dominates the impact of missed revocation latency (bounded by the
 * cache TTL/2 ≤ 5min). Promote to fail-closed via a circuit-breaker if
 * the deny surface drops repeatedly under steady state — Tracked in
 * the deny-list-circuit-breaker follow-up.
 */
async function denyProbe(jti: string, userId: UserId): Promise<boolean> {
  let denied = false;
  try {
    const service = getServiceClient();
    const { data, error } = await service.rpc("is_jti_denied", { p_jti: jti });
    if (error) {
      mirrorWithDebounce(
        error,
        {
          feature: "tenant-jwt",
          op: "is_jti_denied.error",
          extra: { userId, jti },
        },
        userId,
        "is_jti_denied.error",
      );
      return false;
    }
    denied = data === true;
  } catch (err) {
    // Thrown RPC failure — fall-open same as the `{error}` branch and
    // mirror to Sentry. Without this catch, a thrown deny probe on the
    // cache-hit branch would propagate as an uncaught exception out of
    // `getFreshTenantClient` (a different failure mode from the
    // documented `{error}` path).
    mirrorWithDebounce(
      err,
      {
        feature: "tenant-jwt",
        op: "is_jti_denied.error",
        extra: { userId, jti },
      },
      userId,
      "is_jti_denied.error",
    );
    return false;
  }
  if (denied) {
    mirrorWithDebounce(
      null,
      {
        feature: "tenant-jwt",
        op: "is_jti_denied.deny",
        extra: { userId, jti },
      },
      userId,
      "is_jti_denied.deny",
    );
  }
  return denied;
}

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
    // Deny-list check FIRST: a denied jti must not be returned even when
    // the entry is otherwise fresh. On deny: evict + fall through to
    // remint (the next caller for this userId gets a clean cache-miss).
    //
    // Concurrent-callers note: N callers awaiting the same `inflight` may
    // each independently observe `denied=true` and race the eviction. The
    // first wins; the rest no-op via `evictIf`'s referential check. Each
    // racing caller then falls through to its own `minting` Promise at
    // line :337 — the LAST `cache.set` wins. The orphaned mints consume
    // slots from the 60/hr `precheck_jwt_mint` ceiling but cannot return
    // a denied client (post-mint deny probe re-checks). Bounded waste;
    // acceptable at single-founder closed-preview scale.
    if (await denyProbe(entry.jti, userId)) {
      evictIf(userId, inflight);
      // Fall through to the cache-miss path below.
    } else if (now - entry.mintedAt < (entry.ttlSec * 1000) / 2) {
      return entry.client;
    }
    // Stale — fall through to remint.
  }

  const minting: Promise<CacheEntry> = (async () => {
    const minted = await callMint(userId);
    return {
      jwt: minted.jwt,
      mintedAt: minted.mintedAt,
      ttlSec: minted.ttlSec,
      client: createTenantClient(minted.jwt),
      jti: minted.jti,
    };
  })();
  cache.set(userId, minting);

  try {
    const entry = await minting;
    // Post-mint deny probe: a freshly-minted jti landing on the deny-list
    // is a near-zero-probability race (random UUID), but the WORM-audit
    // assertion at Art. 5(2) requires the surface to be closed regardless.
    // On deny: evict + throw `RuntimeAuthError("denied_jti")` so the
    // caller gets an explicit auth-domain failure instead of a silently
    // unusable client.
    if (await denyProbe(entry.jti, userId)) {
      evictIf(userId, minting);
      throw new RuntimeAuthError(
        "denied_jti",
        "Authentication unavailable; retry shortly",
      );
    }
    return entry.client;
  } catch (err) {
    // Don't keep a rejected Promise in the cache — every subsequent
    // caller would re-throw the same error without retrying the mint.
    evictIf(userId, minting);
    throw err;
  }
}

/**
 * Test-only introspection — return the `jti` baked into the cached
 * entry. Returns `null` if no cache entry exists.
 *
 * Reads through the same Promise<CacheEntry> the production path consults,
 * so concurrent test setup that races with a mint sees a consistent view.
 * Production callers MUST NOT use this. Guarded against production use
 * by a `NODE_ENV === "production"` check.
 */
export async function _peekCachedJti(userId: UserId): Promise<string | null> {
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "_peekCachedJti is a test-only seam and must not be called in production",
    );
  }
  const inflight = cache.get(userId);
  if (!inflight) return null;
  const entry = await inflight;
  return entry.jti;
}

/**
 * Test-only cache reset. Public so unit tests can isolate state without
 * touching internals. Callers in production code MUST NOT use this.
 */
export function _resetTenantCache(): void {
  cache.clear();
}
