/**
 * Mint a real Supabase asymmetric-signed JWT once per founder, then
 * install a `_setMintFnForTest` shim that returns the cached MintedJwt
 * for all subsequent calls. Pattern lives here to amortize the ~750ms
 * generateLink+verifyOtp cost AND the per-IP/per-email GoTrue rate-limit
 * budget across an entire suite's tests.
 *
 * Resolution C (#3363) substrate replaced HS256 (synchronous Node sign)
 * with async `generateLink + verifyOtp` (Supabase Auth, GoTrue-rate-
 * limited). Each per-test real-mint call burns budget from a global
 * per-IP/per-email throttle that, across 15 tenant-iso suites run
 * serially, cascades into 429 rate-limit-exceeded failures. This helper
 * caps total mint count at ≤2 per suite (one per founder), keeping the
 * cumulative budget below the GoTrue ceiling.
 *
 * The cached JWTs are REAL Supabase-issued tokens (PostgREST verifies via
 * JWKS = required for RLS testing). Only the mint *call frequency* is
 * reduced; signature/jti/aud/role claims are all real-substrate.
 *
 * Usage in a tenant-iso suite's beforeAll, after the founder is created
 * and `userA.id` / `userB.id` are populated:
 *
 *   await installSharedMintCache([userA.id, userB.id]);
 *
 * Per-test beforeEach should NOT call `_setMintFnForTest(null)` — that
 * would re-arm the real mint and burn rate-limit budget. The helper
 * installs a sticky synth-via-cache fn for the suite lifetime.
 *
 * If a test specifically needs real-per-call minting (e.g., the deny
 * suite testing cache-evict-on-revoke), use that file's per-test
 * `_setMintFnForTest(null)` to opt out — but ONLY in suites where
 * `installSharedMintCache` was NOT called. The deny suite
 * (`tenant-jwt-deny.tenant-isolation.test.ts`) is the canonical opt-out
 * site.
 */

import {
  _setMintFnForTest,
  mintFounderJwt,
  type MintedJwt,
  type UserId,
} from "@/lib/supabase/tenant";

export interface InstallSharedMintCacheOpts {
  /** Token TTL in seconds. Default 600 (10min) — matches DEFAULT_TTL_SEC. */
  ttlSec?: number;
}

/**
 * Mint one real JWT per `userId` via `mintFounderJwt`, then install a
 * `_setMintFnForTest` shim that returns the cached `MintedJwt` for any
 * subsequent `callMint` invocation. Returns the populated cache map so
 * callers may inspect or mutate (e.g., set a known jti) for deterministic
 * tests.
 *
 * The shim is SUITE-STICKY: callers should NOT reset it per-test unless
 * they explicitly want to re-arm the real mint path.
 */
export async function installSharedMintCache(
  userIds: UserId[],
  opts: InstallSharedMintCacheOpts = {},
): Promise<Map<UserId, MintedJwt>> {
  const cache = new Map<UserId, MintedJwt>();
  const ttlSec = opts.ttlSec ?? 600;

  for (const userId of userIds) {
    const minted = await mintFounderJwt(userId, { ttlSec });
    cache.set(userId, minted);
  }

  installShimWithMap(cache);
  return cache;
}

/**
 * Variant that takes already-minted JWTs (e.g., when the suite's existing
 * `beforeAll` has called `mintFounderJwt` itself for the `aMint` / `bMint`
 * raw-client setup). Lets existing suites keep their mint statements
 * intact and just register the results for the shim, without burning a
 * second mint per founder. Returns the populated cache map.
 *
 * Suite-sticky semantics identical to `installSharedMintCache`.
 */
export function registerSharedMintCache(
  entries: ReadonlyArray<readonly [UserId, MintedJwt]>,
): Map<UserId, MintedJwt> {
  const cache = new Map<UserId, MintedJwt>(entries);
  installShimWithMap(cache);
  return cache;
}

function installShimWithMap(cache: Map<UserId, MintedJwt>): void {
  _setMintFnForTest(async (userId: UserId) => {
    const cached = cache.get(userId);
    if (!cached) {
      throw new Error(
        `[mint-once] no cached MintedJwt for userId=${userId}; ` +
          "add this userId to the installSharedMintCache / registerSharedMintCache " +
          "call in beforeAll, or call resetSharedMintCache() to opt back into " +
          "real per-call minting.",
      );
    }
    return cached;
  });
}

/**
 * Remove the shim installed by `installSharedMintCache`. After this,
 * `callMint` falls back to the real `mintFounderJwt` path. Most suites
 * won't need this — it's documented for the rare case where a single
 * test inside a suite needs a real fresh mint (currently no such site
 * exists outside `tenant-jwt-deny.tenant-isolation.test.ts`, which never
 * calls `installSharedMintCache` in the first place).
 */
export function resetSharedMintCache(): void {
  _setMintFnForTest(null);
}
