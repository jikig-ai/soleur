import { createHmac } from "node:crypto";
import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";

const SENTRY_USERID_PEPPER = process.env.SENTRY_USERID_PEPPER;

// Boot warning so operators can spot misconfigured pepper. Fires once per
// Node worker process at module init (N×workers warnings under horizontal
// scale-out — operationally intentional: every worker that lacks the pepper
// is in the degraded `pepper_unset`-sentinel mode and operators want to see
// each one). Tests covering this surface live in
// `observability.test.ts` (pepper-set happy path) +
// `observability-pepper-unset.test.ts` (fail-closed sentinel via vitest
// per-file worker-isolated module-init env).
if (!SENTRY_USERID_PEPPER) {
  // eslint-disable-next-line no-console -- intentional boot warning
  console.warn(
    "[observability] SENTRY_USERID_PEPPER not set — userId will emit as 'pepper_unset' sentinel (fail-closed pseudonymization).",
  );
}

/**
 * Pseudonymize a user identifier for Sentry / pino emission.
 *
 * - HMAC-SHA256, full 64-hex digest (fits Sentry's ~200-char tag-value limit).
 * - Returns `"pepper_unset"` sentinel when pepper is absent: pre-PR baseline
 *   shipped raw userId; fail-closed sentinel preserves operator visibility
 *   without leaking PII. The sentinel collides across all users by design
 *   (surfaced via boot warning above) so a real degraded mode is detectable.
 * - Optional `pepper` arg lets operator-side hash-lookup scripts compute
 *   prior-pepper hashes during a future rotation without re-engineering this
 *   module (no `SENTRY_USERID_PEPPER_PREVIOUS` env var loaded here — added
 *   the day a rotation is scheduled).
 */
export function hashUserId(userId: string, pepper = SENTRY_USERID_PEPPER): string {
  if (!pepper) return "pepper_unset";
  return createHmac("sha256", pepper).update(userId).digest("hex");
}

/**
 * Rename `userId` → `userIdHash` (via `hashUserId`) on an emit `extra`
 * payload. Both silent-fallback helpers share this so the rename signal
 * lives in one place. Returns `extra` unchanged when no `userId` key is
 * present. Null/undefined `userId` values resolve to the sentinel
 * `"pepper_unset_null"` to avoid hashing the empty-string literal — which
 * would collide every nullable-userId emit under a single hash.
 */
function hashExtraUserId(
  extra: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!extra || typeof extra !== "object" || !("userId" in extra)) return extra;
  const { userId: rawUserId, ...rest } = extra as { userId?: unknown } & Record<string, unknown>;
  if (rawUserId == null) return { ...rest, userIdHash: "pepper_unset_null" };
  return { ...rest, userIdHash: hashUserId(String(rawUserId)) };
}

/**
 * Single source of truth for the literal app-origin used when
 * `NEXT_PUBLIC_APP_URL` is unset. Matches prod; used by every
 * `reportSilentFallback`-guarded fallback site so a future domain rename
 * is a one-line change here (plus a Doppler update) rather than a repo-wide
 * grep + 6-file edit.
 */
export const APP_URL_FALLBACK = "https://app.soleur.ai";

/**
 * Options for a silent-fallback capture.
 *
 * - `feature`: required tag — used for Sentry search/filtering. Use the route
 *   or module short name (e.g. `"kb-share"`, `"stripe-webhook"`).
 * - `op`: optional sub-operation — adds a second tag for narrowing
 *   (e.g. `"create"`, `"revoke"`, `"checkout.session.completed"`).
 * - `extra`: structured context — userId, path, customerId, etc. Keep values
 *   small (<1 KB each). Pino stdout-only values go here too.
 * - `message`: only used when `err` is not an `Error`. Defaults to
 *   `"<feature> silent fallback"`. Ignored when `err instanceof Error`.
 */
export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: Record<string, unknown>;
  message?: string;
}

/**
 * Mirror a silent-fallback branch to Sentry alongside the existing pino log.
 *
 * Use at sites that CATCH an error (or detect a degraded condition) and
 * return a 4xx/5xx while logging. Pino `logger.error` / `logger.warn` goes to
 * container stdout only — invisible in Sentry dashboards. This helper makes
 * the branch observable without changing the response path.
 *
 * - `err instanceof Error` → `Sentry.captureException(err, { tags, extra })`.
 * - `err` is a non-Error value (string, null, missing data) →
 *   `Sentry.captureMessage(message ?? "<feature> silent fallback", …)`.
 *
 * **Skip this helper when:**
 * - The error is EXPECTED (CSRF reject, rate-limit hit, first-time 404).
 * - The error is already handled by Sentry's auto-instrumentation (unhandled
 *   exceptions caught by the framework wrap).
 * - You're re-throwing — Sentry gets it at the framework boundary.
 *
 * Use when:
 * - The code path logs an error and returns a 4xx/5xx/degraded response.
 * - The code path logs a warning about a condition that should never be
 *   common in steady state (like a failed downstream API).
 * - The feature has "silent fallback" semantics — the user sees success but
 *   degraded behavior (e.g. PDF committed without linearization).
 *
 * @example Database insert failure
 * ```ts
 * if (insertError) {
 *   reportSilentFallback(insertError, {
 *     feature: "kb-share",
 *     op: "create",
 *     extra: { userId, documentPath },
 *   });
 *   return NextResponse.json({ error: "Failed" }, { status: 500 });
 * }
 * ```
 *
 * @example Degraded condition (no Error object)
 * ```ts
 * if (!data || data.length === 0) {
 *   reportSilentFallback(null, {
 *     feature: "accept-terms",
 *     op: "record",
 *     message: "User row not found",
 *     extra: { userId },
 *   });
 *   return NextResponse.json({ error: "…" }, { status: 404 });
 * }
 * ```
 */
export function reportSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;

  // Pseudonymize `userId` → `userIdHash` (Recital 26) at the emit boundary.
  // Centralized here so the 40+ call sites continue passing raw `userId` and
  // never need to know about the rename. Renamed (not value-swapped) so log
  // readers can tell at a glance that pseudonymization is in effect.
  const transformedExtra = hashExtraUserId(extra);

  // Mirror the structured context into pino so log aggregators (container
  // stdout, Better Stack) also get the same tag vocabulary.
  logger.error({ err, feature, op, ...transformedExtra }, message ?? `${feature} silent fallback`);

  // Sentry's namespace shape varies across the dev-server bundle (where
  // captureMessage may be tree-shaken when DSN is unset) and the prod build.
  // Guard so an uninitialized Sentry never throws a TypeError into a caller
  // that fires on server boot (see #3045 plugin-mount-check) — the pino mirror
  // above is the durable signal regardless.
  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: "error",
        tags,
        extra: { err, ...transformedExtra },
      });
    }
  } catch {
    // Sentry call failures must never propagate — they would convert a
    // diagnostic mirror into a service-killing exception.
  }
}

/**
 * Warn-level variant. Same contract, but emits at `level: "warning"` —
 * use for degraded-but-expected paths (e.g. a third-party timeout with a
 * graceful fallback) where every occurrence is worth observing but shouldn't
 * count as an error.
 */
export function warnSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;

  // Pseudonymize `userId` → `userIdHash` at the emit boundary (see
  // reportSilentFallback for rationale).
  const transformedExtra = hashExtraUserId(extra);

  logger.warn({ err, feature, op, ...transformedExtra }, message ?? `${feature} silent fallback`);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { level: "warning", tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: "warning",
        tags,
        extra: { err, ...transformedExtra },
      });
    }
  } catch {
    // See reportSilentFallback — Sentry namespace may be partially shimmed
    // in non-prod bundles; pino is the durable signal.
  }
}

/**
 * Per-`(userId, errorClass)` 5-minute TTL on the Sentry mirror.
 *
 * Use at sites where a misconfigured prod or a runaway loop could fire
 * the same silent-fallback condition repeatedly for a single user.
 * Without this, 1 QPS for 24 hours = 86k Sentry events per user — enough
 * to bury other signals. First report mirrors via `reportSilentFallback`
 * unchanged; subsequent calls inside the window for the same key are
 * no-ops. The application path (4xx/5xx/degraded response) is unaffected.
 *
 * **Registry of `errorClass` strings** (extend when adding a caller):
 * - `cc-dispatcher` family: `agent-sandbox:sdk-startup`,
 *   `dispatch:invalid-payload`, `dispatch:invalid-response`,
 *   `dispatch:kind-mismatch`, `dispatch:internal-error`. The
 *   op-slug emit sites in `cc-dispatcher.ts` reference
 *   `CC_OP_SLUGS.*` (e.g., `CC_OP_SLUGS.saveAssistant`,
 *   `CC_OP_SLUGS.persistUserMessage`) — see #3642 F7.
 * - `kb-document-resolver` family: PDF text-extraction failure classes
 *   (e.g., `extract-pdf:empty-text`, `extract-pdf:oversized-buffer`).
 * - `soleur-go-runner` family: `notify-awaiting-no-active-query`.
 *
 * Each feature picks a distinct `errorClass` so the per-key TTL bucket
 * cannot collide across features for the same user.
 */
export const MIRROR_DEBOUNCE_MS = 5 * 60 * 1000;
// Periodic sweep cadence — drain entries older than the dedup window
// (`ttlMs`, the `TtlDedupMap` sweep cutoff) on a fraction of writes. Cheap
// amortized O(1) per call when the sweep is skipped; O(n) at the sweep
// threshold. Caps map growth on long-running processes that see many distinct
// keys. Pre-#3639 used a 2×TTL grace cutoff for `mirrorWithDebounce` to
// retain zombie entries past the dedup window; the consolidated 1×TTL cutoff
// here is functionally equivalent (post-window entries cannot affect dedup
// outcomes) and reclaims memory sooner.
const MIRROR_SWEEP_INTERVAL = 64;

/**
 * #3639 F3 — Generic per-key TTL dedup cache with amortized sweep and
 * optional insertion-order eviction.
 *
 * Both `mirrorWithDebounce` (per-`(userId, errorClass)` 5-min TTL) and
 * `mirrorP0Deduped` (per-`(userId, op, conversationId)` 1-hour TTL with a
 * hard size cap) share identical bookkeeping: a `Map<key, lastTimestamp>`,
 * an "every N writes run an O(n) sweep" amortized eviction, and a
 * `reset()` test seam. Extracting both into one class avoids drift between
 * the two wrappers' bookkeeping (e.g., the sweep interval, the stale-TTL
 * cutoff multiplier, the `clear()` reset semantics).
 *
 * Constructor params:
 * - `ttlMs`: dedup window. `tryClaim` returns `false` if a previous claim
 *   for `key` is within `ttlMs` of `now`.
 * - `sweepInterval`: every `Nth` claim triggers an O(n) sweep dropping
 *   entries older than `ttlMs` (P0 wrapper uses TTL cutoff). Pass
 *   `Infinity` to disable sweeping entirely.
 * - `maxSize` (optional): when present, capacity-bound the map. On insert
 *   that would exceed `maxSize`, evict the oldest entry (Map preserves
 *   insertion order). Used by `mirrorP0Deduped` to bound heap under an
 *   adversarial burst with rotating keys; `mirrorWithDebounce` omits it
 *   to preserve the pre-existing behavior.
 *
 * The wrappers compute sink emission (Sentry / Pino) themselves —
 * `TtlDedupMap` is dedup bookkeeping only, no I/O.
 */
export class TtlDedupMap<K extends string = string> {
  private readonly _lastAt = new Map<K, number>();
  private _writeCount = 0;

  constructor(
    private readonly ttlMs: number,
    private readonly sweepInterval: number,
    private readonly maxSize?: number,
  ) {}

  /**
   * Attempt to claim `key` at time `now`. Returns `true` when the caller
   * holds the slot (first claim within `ttlMs`); `false` if a prior claim
   * is still within the window (caller should skip the side effect).
   *
   * Amortizes a sweep over every `sweepInterval` claims to bound map size.
   * When `maxSize` is set and the map is at capacity, the oldest entry is
   * evicted before insertion (insertion-order eviction via `Map.keys()`).
   */
  tryClaim(key: K, now: number): boolean {
    const last = this._lastAt.get(key);
    if (last !== undefined && now - last < this.ttlMs) return false;
    // Capacity check BEFORE insert: evict oldest if at cap.
    if (this.maxSize !== undefined && this._lastAt.size >= this.maxSize) {
      const oldest = this._lastAt.keys().next().value;
      if (oldest !== undefined) this._lastAt.delete(oldest);
    }
    this._lastAt.set(key, now);
    this._writeCount++;
    if (
      Number.isFinite(this.sweepInterval) &&
      this._writeCount % this.sweepInterval === 0
    ) {
      for (const [k, t] of this._lastAt) {
        if (now - t > this.ttlMs) this._lastAt.delete(k);
      }
    }
    return true;
  }

  /** Test seam: drop all entries + reset the write counter. */
  reset(): void {
    this._lastAt.clear();
    this._writeCount = 0;
  }
}

const _mirrorDebounce = new TtlDedupMap<string>(
  MIRROR_DEBOUNCE_MS,
  MIRROR_SWEEP_INTERVAL,
);

export function mirrorWithDebounce(
  err: unknown,
  ctx: SilentFallbackOptions,
  userId: string,
  errorClass: string,
): void {
  // Dedup key uses raw `userId` — in-process map only, never emitted.
  // `reportSilentFallback` hashes the `userId` field of `ctx.extra` at the
  // emit boundary; no transform needed here.
  if (!_mirrorDebounce.tryClaim(`${userId}:${errorClass}`, Date.now())) return;
  reportSilentFallback(err, ctx);
}

/**
 * Test seam: drain the debounce map between tests so a key set in test A
 * does not silently coalesce test B's first call. Mirrors the existing
 * dispatcher reset pattern; never call from production code.
 */
export function __resetMirrorDebounceForTests(): void {
  _mirrorDebounce.reset();
}

/**
 * Per-`(userId, op, conversationId)` 1-hour TTL on a P0-severity Sentry
 * mirror. Distinct from `mirrorWithDebounce`:
 * - **Dedup key includes `conversationId`** so two cross-tenant attempts
 *   against different conversations from the same user are NOT coalesced.
 * - **TTL is 1 hour, not 5 minutes** — Art. 33(1) gives the controller a
 *   72-hour window to notify the supervisory authority; the 1-hour TTL
 *   provides ~72 distinct samples for the same `(user, op, conv)` triple
 *   within the notifiability window without burying the Sentry stream.
 * - **`level: "fatal"`** — these events represent a write-boundary or
 *   GDPR-category violation, not a degraded fallback. Pages oncall.
 * - **`severity: "breach_attempt"` + `first_seen_at`** are included in the
 *   Sentry `extra` payload so the 72-hour notifiability clock starts at
 *   the FIRST observation, even when subsequent re-fires within the
 *   dedup window are suppressed.
 *
 * Callers:
 * - `cc-dispatcher.ts` — write-boundary sentinel (`assertWriteScope`),
 *   W4-orphan drop (`CC_OP_SLUGS.usageOrphanDropped`).
 *
 * Sentry retention (typically 30-90 days) does NOT satisfy Art. 33(5)'s
 * indefinite breach documentation requirement. A durable audit-log table
 * is tracked separately as D-durable-audit-log (#3603 rev-2 deferral).
 */
export const P0_DEDUP_TTL_MS = 60 * 60 * 1000;
// Hard cap on map size — TTL-only eviction is insufficient under an adversarial
// burst with rotating conversationId values (every entry is fresh, sweep deletes
// nothing). Insertion-order eviction (Map preserves insertion order) caps heap
// regardless of burst rate. Sized to ~1.4 MB worst-case.
const P0_DEDUP_MAX_SIZE = 10_000;
const P0_SWEEP_INTERVAL = 64;

const _p0Dedup = new TtlDedupMap<string>(
  P0_DEDUP_TTL_MS,
  P0_SWEEP_INTERVAL,
  P0_DEDUP_MAX_SIZE,
);

export function mirrorP0Deduped(
  err: Error,
  ctx: { op: string; userId: string; conversationId: string },
): void {
  // Dedup key keeps raw `userId` — in-process map only, never emitted.
  const key = `${ctx.userId}:${ctx.op}:${ctx.conversationId}`;
  const now = Date.now();
  if (!_p0Dedup.tryClaim(key, now)) return;

  const userIdHash = hashUserId(ctx.userId);

  // Pino mirror for container-stdout visibility (same shape as
  // `reportSilentFallback` so log aggregators key off identical fields).
  logger.error(
    { err, op: ctx.op, userIdHash, conversationId: ctx.conversationId },
    `p0 deduped mirror: ${ctx.op}`,
  );

  // Sentry — fatal severity, bypasses `mirrorWithDebounce` 5-min window.
  // `first_seen_at` is the Art. 33(1) 72h-clock anchor.
  try {
    if (typeof Sentry.captureException === "function") {
      Sentry.captureException(err, {
        level: "fatal",
        tags: { op: ctx.op, scope: "p0_deduped", userIdHash },
        extra: {
          op: ctx.op,
          userIdHash,
          conversationId: ctx.conversationId,
          severity: "breach_attempt",
          first_seen_at: new Date(now).toISOString(),
        },
      });
    }
  } catch {
    // Sentry namespace partially shimmed (dev-server bundle) — pino is the
    // durable signal regardless.
  }
}

/**
 * Test seam: drain the P0 dedup map between tests. Naming mirrors
 * `__resetMirrorDebounceForTests` (line above) — both prefix the cache
 * they reset with `Mirror` for parallelism. Never call from production.
 * #3641 — renamed from `__resetP0DedupForTests` to match the
 * `mirror{Debounce,P0Dedup}` naming pair. No deprecation alias kept.
 */
export function __resetMirrorP0DedupForTests(): void {
  _p0Dedup.reset();
}
