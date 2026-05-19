/**
 * Tenant-scoped Supabase client factory for the server-side agentic runtime
 * (PR-B #3244, plan §1.1 / §1.4).
 *
 * Resolution C (#3363, this PR): Supabase asymmetric signing keys (ES256).
 * Node holds no signing material. `precheck_jwt_mint` continues to own the
 * atomic rate-limit + jti supply; the `runtime_jwt_mint_hook` Custom Access
 * Token Hook (migration 047) calls it from inside the auth-issuance
 * transaction so the precheck-issued jti lands directly in the JWT's `jti`
 * claim. PostgREST sees the same jti our `denied_jti` table indexes —
 * no binding table required.
 *
 * Mint flow:
 *   1. resolveFounderEmail(userId) — service-role lookup of auth.users.email
 *   2. service.auth.admin.generateLink({type:"magiclink", email}) — produces
 *      a hashed_token without sending email.
 *   3. service.auth.verifyOtp({token_hash, type:"email"}) — exchanges the
 *      hashed token for an asymmetrically-signed JWT. The hook fires
 *      synchronously during issuance (gated on authentication_method='otp')
 *      and injects jti/exp/iat/aud='soleur-runtime'/role='authenticated'
 *      into the claims.
 *   4. decodeJwtPayloadUnsafe(jwt) — extract jti for the cache layer.
 *      No signature verification on this side; PostgREST verifies via the
 *      JWKS endpoint (Supabase-managed asymmetric keys, never leave Supabase).
 *
 * Phase 0.4 pre-commit decision (plan-review panel, empirically validated):
 * the hook gates on `event->>'authentication_method' = 'otp'`. The aud
 * claim is set inside the hook (not injected from Node). The JWT_AUDIENCE
 * constant below is retained for Node-side parity with PostgREST audience
 * validation if it's ever turned on; the hook is the actual write site.
 *
 * Type asymmetry: `type:"magiclink"` for `generateLink`, `type:"email"`
 * for `verifyOtp`. The `magiclink` literal is deprecated for `verifyOtp`
 * (Razikus pattern + Supabase PKCE-fix article). Documented at the call
 * sites below — DO NOT "fix" this asymmetry.
 *
 * Residuals to address in follow-ups:
 *   - aud=soleur-runtime is structurally distinct on the wire but PostgREST
 *     does not enforce aud by default. Dashboard-replay prevention requires
 *     middleware-level aud filtering. Tracked separately.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { mirrorWithDebounce } from "@/server/observability";
import { createServiceClient, getServiceClient, serverUrl } from "./service";

export type UserId = string;

export interface MintFounderJwtOpts {
  /** Token TTL in seconds. Default 600 (10min). The cache remints at TTL/4. */
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

/**
 * Audience claim baked into runtime JWTs by `public.runtime_jwt_mint_hook`
 * (migration 047). Node holds this constant for parity with the hook —
 * future PostgREST-level aud filtering (dashboard-replay defense) reads
 * this value. The hook is the actual write site.
 */
export const JWT_AUDIENCE = "soleur-runtime";

/**
 * `verifyOtp` retry config for GoTrue's `over_request_rate_limit` 429
 * response. Distinct from the precheck-ceiling `mint_rate_exceeded` raise
 * (cause:rotation, no retry — the per-founder ceiling won't clear in
 * seconds) and from generic verifyOtp errors (cause:jwt_mint, no retry —
 * network/malformed-response symptoms don't get better with backoff).
 *
 * Bounded retries smooth transient bursts (concurrent CI runs, prior-hour
 * residue against the dev project's per-instance ceiling). They do NOT
 * fix steady-state ceiling exhaustion — see
 * `knowledge-base/engineering/ops/runbooks/supabase-magiclink-rate-limit.md`
 * for the operational fix.
 */
const DEFAULT_VERIFY_OTP_MAX_RETRIES = 3;
const DEFAULT_VERIFY_OTP_BASE_DELAY_MS = 500;

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

/**
 * Decode a JWT's middle (payload) segment WITHOUT signature verification.
 *
 * Used only to extract claims (`jti`, `exp`) the cache layer needs. The
 * "Unsafe" suffix is load-bearing — a reader sees immediately that this is
 * NOT a JWT verifier. PostgREST verifies the signature on the server side
 * via the JWKS endpoint (Supabase-managed asymmetric keys).
 */
function decodeJwtPayloadUnsafe(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }
  const padded =
    parts[1].replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (parts[1].length % 4)) % 4);
  try {
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }
}

/**
 * Per-process founder-email cache. Resolves `auth.users.id → email` via the
 * Supabase Admin API (service-role only). Cached for the process lifetime;
 * email rotation is rare and invalidation-on-process-restart is acceptable
 * at closed-preview scale. For multi-tenant prod, add a TTL or
 * eviction-on-error (tracked separately).
 */
const emailCache = new Map<UserId, string>();

async function resolveFounderEmail(userId: UserId): Promise<string> {
  const cached = emailCache.get(userId);
  if (cached) return cached;
  const service = getServiceClient();
  const { data, error } = await service.auth.admin.getUserById(userId);
  if (error || !data?.user?.email) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }
  emailCache.set(userId, data.user.email);
  return data.user.email;
}

/**
 * Mint a fresh founder-scoped JWT via Supabase asymmetric signing.
 *
 * Goes through GoTrue's `generateLink + verifyOtp` admin path. The
 * `runtime_jwt_mint_hook` Custom Access Token Hook (migration 047) fires
 * synchronously during issuance, calls `precheck_jwt_mint` for atomic
 * rate-limit + jti supply (SQLSTATE '45001' on ceiling trip, migration
 * 048), and injects jti/exp/iat/aud/role into the JWT claims. Node side
 * never holds a signing key.
 *
 * @throws {RuntimeAuthError} cause="rotation" — precheck rate-limit
 *   ceiling tripped (the hook bubbled `mint_rate_exceeded` from
 *   SQLSTATE 45001 raise via GoTrue).
 * @throws {RuntimeAuthError} cause="jwt_mint" — generateLink failed,
 *   verifyOtp failed, GoTrue rate-limit hit, JWT missing hook-injected
 *   jti (hook unregistered defensive seam), or claim shape malformed.
 */
export async function mintFounderJwt(
  userId: UserId,
  opts: MintFounderJwtOpts = {},
): Promise<MintedJwt> {
  const ttlSec = opts.ttlSec ?? DEFAULT_TTL_SEC;
  const service = getServiceClient();

  const email = await resolveFounderEmail(userId);

  // Mint-intent marker (Phase-4 amendment, ADR-033 §0.7). The empirical
  // probe established that Supabase's hook event payload contains no
  // field discriminating this runtime path from a user-facing dashboard
  // OTP login (signInWithOtp + verifyOtp) — both produce identical
  // aud/amr/exp/app_metadata. Without this marker the hook would
  // silently rewrite dashboard JWTs (10-min auto-logout for end users).
  //
  // Atomicity: the row is UPSERTed (ON CONFLICT DO UPDATE) before the
  // verifyOtp call that triggers the hook. The hook DELETEs the row
  // inside a CTE; only consumption unlocks the mint path. Stale rows
  // (>10s) are ignored by the hook. Residual race: ~700ms window where
  // a concurrent dashboard OTP login for the same founder could steal
  // the intent — self-recovering and bounded to <0.02% under steady
  // state (see migration 049 prose).
  const { error: intentError } = await service
    .from("runtime_mint_intent")
    .upsert({ user_id: userId }, { onConflict: "user_id" });
  if (intentError) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  // generateLink — produces a hashed_token. type='magiclink' here is the
  // template selector; no email is sent (we consume the hashed_token
  // server-side via verifyOtp below).
  const link = await service.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (link.error || !link.data?.properties?.hashed_token) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  // verifyOtp — exchanges the hashed token for an asymmetrically-signed
  // JWT. type='email' (NOT 'magiclink' — the 'magiclink' literal for
  // verifyOtp is deprecated per Razikus pattern + Supabase PKCE-fix
  // article).
  //
  // CRITICAL: verifyOtp mutates the client's in-memory auth state via
  // GoTrueClient._saveSession (auth-js/main/GoTrueClient.js:1125). Even
  // with `persistSession: false`, the resolved session is held in-memory
  // and supabase-js's `_getAccessToken()` will subsequently prefer the
  // saved session.access_token over `supabaseKey` for all RPC/REST calls
  // on that client (see supabase-js/src/SupabaseClient.ts:506-513). If
  // we used the shared `getServiceClient()` singleton here, every
  // post-mint call (notably `denyProbe`'s `is_jti_denied` RPC) would
  // travel under the FOUNDER's tenant JWT — which lacks EXECUTE on the
  // service-role-only deny-probe function (migration 037) and yields
  // `42501 permission denied for function is_jti_denied`. Use a
  // throw-away client for the OTP exchange so the singleton's auth
  // state stays pristine.
  // Bounded retry on GoTrue's structured `over_request_rate_limit` 429
  // code only. The precheck-ceiling raise (`mint_rate_exceeded` in
  // `message`, no `code`) is NOT retried — that's a per-founder ceiling
  // that won't clear in seconds. Generic errors (network, malformed) are
  // NOT retried either — backoff doesn't recover them. See retry config
  // block above + runbook for the steady-state-ceiling caveat.
  const otpClient = createServiceClient();
  const retryConfig = getVerifyOtpRetryConfig();
  let verified: Awaited<ReturnType<typeof otpClient.auth.verifyOtp>>;
  for (let attempt = 0; ; attempt++) {
    verified = await otpClient.auth.verifyOtp({
      token_hash: link.data.properties.hashed_token,
      type: "email",
    });
    const errCode = (verified.error as { code?: string } | null | undefined)
      ?.code;
    if (
      errCode !== "over_request_rate_limit" ||
      attempt >= retryConfig.maxRetries
    ) {
      break;
    }
    // Jittered exponential backoff: base * 2^attempt ± 25%. Random jitter
    // prevents concurrent callers from re-bursting in lockstep.
    const baseDelay = retryConfig.baseDelayMs * Math.pow(2, attempt);
    const jitter = baseDelay * 0.25 * (Math.random() * 2 - 1);
    await sleepMs(Math.max(0, baseDelay + jitter));
  }
  if (verified.error || !verified.data?.session?.access_token) {
    const msg = verified.error?.message ?? "";
    // The hook bubbled the precheck ceiling raise (SQLSTATE 45001,
    // MESSAGE 'mint_rate_exceeded') via GoTrue. Distinct cause for the
    // catch-site mapper.
    if (msg.includes("mint_rate_exceeded")) {
      throw new RuntimeAuthError(
        "rotation",
        "Authentication unavailable; retry shortly",
      );
    }
    // GoTrue rate-limit (after retries exhausted), network failure,
    // malformed response — all collapse to jwt_mint. The catch site logs
    // via mirrorWithDebounce.
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  const jwt = verified.data.session.access_token;

  // Defensive: the hook is supposed to inject jti (precheck-issued UUID)
  // and override exp/iat. If jti is missing or not UUID-shaped, the hook
  // either didn't fire (unregistered, or auth method drift), OR fired but
  // pass-through'd (e.g., concurrent dashboard OTP stole the intent row,
  // ADR-033 §0.7 race window). In either case our `denied_jti` revocation
  // surface would have no anchor — throw rather than return a half-trusted
  // client. The UUID-shape check (vs typeof-string alone) defends against
  // a future Supabase change that adds a non-UUID natural `jti` claim to
  // pass-through JWTs (would silently bypass denied_jti lookup space).
  // Phase 2.8 adds a parallel startup probe in service.ts so unregistered
  // hook failures surface at boot, not just at mint time.
  const payload = decodeJwtPayloadUnsafe(jwt);
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (
    typeof payload.jti !== "string" ||
    !UUID_RE.test(payload.jti) ||
    typeof payload.exp !== "number"
  ) {
    throw new RuntimeAuthError(
      "jwt_mint",
      "Authentication unavailable; retry shortly",
    );
  }

  return {
    jwt,
    ttlSec,
    mintedAt: Date.now(),
    jti: payload.jti,
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
 * Entries are reminted when `now - mintedAt > ttlSec/4` (Resolution C
 * boundary — TTL/2 under HS256 was halved to TTL/4 to keep cache hit-rate
 * high under the ~750ms generateLink+verifyOtp cost; ≤24 mints/hr/founder
 * stays below the precheck_jwt_mint 60/hour ceiling).
 * In-flight queries holding the previous client reference
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

/**
 * Test-only seam — overrides the verifyOtp 429-retry config. Pass `null`
 * to restore defaults. Tests use a tiny `baseDelayMs` (e.g. 1ms) so the
 * retry path is exercised without dilating test runtime. Production
 * callers MUST NOT use this.
 */
interface VerifyOtpRetryConfig {
  maxRetries: number;
  baseDelayMs: number;
}
let __verifyOtpRetryConfigForTest: VerifyOtpRetryConfig | null = null;
export function _setVerifyOtpRetryConfigForTest(
  config: VerifyOtpRetryConfig | null,
): void {
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "_setVerifyOtpRetryConfigForTest is a test-only seam and must not be called in production",
    );
  }
  __verifyOtpRetryConfigForTest = config;
}

function getVerifyOtpRetryConfig(): VerifyOtpRetryConfig {
  return (
    __verifyOtpRetryConfigForTest ?? {
      maxRetries: DEFAULT_VERIFY_OTP_MAX_RETRIES,
      baseDelayMs: DEFAULT_VERIFY_OTP_BASE_DELAY_MS,
    }
  );
}

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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
 * cache TTL/4 ≤ 2.5min). Promote to fail-closed via a circuit-breaker if
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
 * reminting the underlying JWT when it crosses the TTL/4 freshness
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
    } else if (now - entry.mintedAt < (entry.ttlSec * 1000) / 4) {
      // Resolution C (#3363): TTL/4 (was TTL/2 under HS256). The ~750ms
      // p95 generateLink+verifyOtp cost is absorbed at session start
      // (PR-B's ALS lazy-fetch hits cache after the first call). TTL/4
      // = ~150s remint window at ttlSec=600 → ≤24 mints/hour/founder,
      // below the precheck_jwt_mint 60/hour ceiling. See plan §2.5.
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
