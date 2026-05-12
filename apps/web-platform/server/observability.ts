import { createHash } from "node:crypto";
import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";

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

  // Mirror the structured context into pino so log aggregators (container
  // stdout, Better Stack) also get the same tag vocabulary.
  logger.error({ err, feature, op, ...extra }, message ?? `${feature} silent fallback`);

  // Sentry's namespace shape varies across the dev-server bundle (where
  // captureMessage may be tree-shaken when DSN is unset) and the prod build.
  // Guard so an uninitialized Sentry never throws a TypeError into a caller
  // that fires on server boot (see #3045 plugin-mount-check) — the pino mirror
  // above is the durable signal regardless.
  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { tags, extra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: "error",
        tags,
        extra: { err, ...extra },
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

  logger.warn({ err, feature, op, ...extra }, message ?? `${feature} silent fallback`);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { level: "warning", tags, extra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(message ?? `${feature} silent fallback`, {
        level: "warning",
        tags,
        extra: { err, ...extra },
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
 *   `dispatch:kind-mismatch`, `dispatch:internal-error`.
 * - `kb-document-resolver` family: PDF text-extraction failure classes
 *   (e.g., `extract-pdf:empty-text`, `extract-pdf:oversized-buffer`).
 * - `soleur-go-runner` family: `notify-awaiting-no-active-query`.
 *
 * Each feature picks a distinct `errorClass` so the per-key TTL bucket
 * cannot collide across features for the same user.
 */
export const MIRROR_DEBOUNCE_MS = 5 * 60 * 1000;
const _mirrorLastReportedAt = new Map<string, number>();
// Periodic sweep cadence — drain stale entries older than 2x the TTL on a
// fraction of writes. Cheap amortized O(1) per call when the sweep is
// skipped; O(n) at the sweep threshold. Caps map growth on long-running
// processes that see many distinct `(userId, errorClass)` pairs (e.g.,
// dispatcher firing one-off internal-error mirrors across many users).
const MIRROR_STALE_TTL_MS = 2 * MIRROR_DEBOUNCE_MS;
const MIRROR_SWEEP_INTERVAL = 64;
let _mirrorWriteCount = 0;

export function mirrorWithDebounce(
  err: unknown,
  ctx: SilentFallbackOptions,
  userId: string,
  errorClass: string,
): void {
  const key = `${userId}:${errorClass}`;
  const now = Date.now();
  const last = _mirrorLastReportedAt.get(key);
  if (last !== undefined && now - last < MIRROR_DEBOUNCE_MS) {
    return;
  }
  _mirrorLastReportedAt.set(key, now);
  // Amortized sweep: every ~MIRROR_SWEEP_INTERVAL writes, drop entries
  // whose last-mirror was >2x the TTL ago. Keeps the map size bounded
  // by the steady-state set of recently-active (userId, errorClass)
  // pairs rather than the all-time set.
  _mirrorWriteCount++;
  if (_mirrorWriteCount % MIRROR_SWEEP_INTERVAL === 0) {
    const cutoff = now - MIRROR_STALE_TTL_MS;
    for (const [k, t] of _mirrorLastReportedAt) {
      if (t < cutoff) _mirrorLastReportedAt.delete(k);
    }
  }
  reportSilentFallback(err, ctx);
}

/**
 * Test seam: drain the debounce map between tests so a key set in test A
 * does not silently coalesce test B's first call. Mirrors the existing
 * dispatcher reset pattern; never call from production code.
 */
export function __resetMirrorDebounceForTests(): void {
  _mirrorLastReportedAt.clear();
  _mirrorWriteCount = 0;
}

/**
 * SHA-256(salt || userId) — PII-minimal user identifier for Sentry payloads.
 *
 * `SOLEUR_SENTRY_PII_SALT` MUST be set in production so the hash is
 * unlinkable across deployments without operator access to the salt.
 * In dev/test we fall back to a static literal so single-machine
 * development does not require Doppler-injection just to call
 * `mirrorCrossTenantViolation` from a unit test. Sentry payloads in
 * dev are not load-bearing for the unlinkability invariant.
 */
function hashUserIdForSentry(userId: string): string {
  const salt =
    process.env.SOLEUR_SENTRY_PII_SALT ??
    (process.env.NODE_ENV === "production"
      ? ""
      : "dsar-dev-salt-not-for-prod");
  if (!salt) {
    // Fail-loud in prd if the salt is missing — the alert is the wrong
    // place to surface PII through configuration oversight.
    throw new Error(
      "SOLEUR_SENTRY_PII_SALT not set in production; cannot mirror cross-tenant violation safely.",
    );
  }
  return createHash("sha256")
    .update(salt)
    .update("\x00")
    .update(userId)
    .digest("hex")
    .slice(0, 16); // 64-bit prefix is enough for de-duplication; full hash is overkill.
}

/**
 * Sibling of `mirrorWithDebounce` for the cross-tenant invariant alarm
 * path. Functionally distinct: this never debounces and never returns
 * early. A cross-tenant violation is the highest-severity event class
 * in the DSAR export surface (Art. 33 + Art. 34 notifiable on a single
 * occurrence), so we trade some Sentry quota for guaranteed delivery
 * on every fire.
 *
 * Per plan rev-2 AC22 (sibling shape, does NOT modify
 * `mirrorWithDebounce`'s 2-tuple key — that change deferred to #3638
 * which lands separately). Logs payload tags:
 *   - level: 'fatal'
 *   - sec: true
 *   - dsar: true
 *   - cross_tenant: true
 *   - table: <tableName>
 *
 * userIds are hashed via `hashUserIdForSentry` (SHA-256 + salt) BEFORE
 * the Sentry call so the Sentry retention window never contains raw
 * UUIDs.
 *
 * @param offendingUserId  Owner of the misowned row (or null if the
 *                         row lacked the owner field entirely).
 * @param expectedUserId   The userId the worker scope was set to.
 * @param tableName        Public table the read was issued against.
 * @param err              The CrossTenantViolation (or other) error.
 * @param ctx              Optional extras (jobId, queryShape, etc.).
 */
export function mirrorCrossTenantViolation(
  offendingUserId: string | null,
  expectedUserId: string,
  tableName: string,
  err: unknown,
  ctx: Record<string, unknown> = {},
): void {
  const offendingHash =
    offendingUserId === null ? null : hashUserIdForSentry(offendingUserId);
  const expectedHash = hashUserIdForSentry(expectedUserId);

  const payload = {
    level: "fatal" as const,
    tags: {
      sec: true,
      dsar: true,
      cross_tenant: true,
      table: tableName,
    },
    extra: {
      offendingUserIdHash: offendingHash,
      expectedUserIdHash: expectedHash,
      tableName,
      ...ctx,
    },
  };

  // Mirror to pino first so the alert is visible in container stdout
  // even if Sentry capture fails or is rate-limited.
  logger.error(
    {
      ...payload.extra,
      tags: payload.tags,
      err: err instanceof Error ? { name: err.name, message: err.message } : err,
    },
    "DSAR cross-tenant violation",
  );

  if (err instanceof Error) {
    Sentry.captureException(err, payload);
  } else {
    Sentry.captureMessage("DSAR cross-tenant violation", payload);
  }
}
