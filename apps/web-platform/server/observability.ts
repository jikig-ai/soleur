import { createHash, createHmac } from "node:crypto";
import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import { sqlStateFromError } from "@/lib/postgres-errors";

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

const SENTRY_TAG_PEPPER = process.env.SENTRY_TAG_PEPPER;

/**
 * BYOK Delegations PR-A (#4232) SS F6: domain-scoped HMAC pepper for
 * Sentry tags that carry delegation / workspace / actor identifiers
 * (`delegation_id_hash`, `workspace_id_hash`, `grantor_user_id_hash`,
 * `grantee_user_id_hash`). Returns a 16-hex prefix — long enough for
 * uniqueness inside the per-delegation alert routes, short enough to
 * fit Sentry's tag-value length comfortably.
 *
 * Separate from `hashUserId` (which uses `SENTRY_USERID_PEPPER`) so
 * pepper rotation for the delegations domain doesn't reshuffle the
 * org-wide userId hash space. Falls back to `"pepper_unset"` sentinel
 * when the env var is missing — same fail-closed pattern as
 * `hashUserId`. The boot warning is intentionally NOT emitted here
 * because the delegations surface is feature-flagged and many envs
 * legitimately run without the pepper until the flag is flipped on.
 */
export function hashUserIdForSentryTag(
  input: string,
  pepper = SENTRY_TAG_PEPPER,
): string {
  if (!pepper) return "pepper_unset";
  return createHmac("sha256", pepper).update(input).digest("hex").slice(0, 16);
}

/**
 * Rename `userId` → `userIdHash` on an emit `extra` payload. Delegates to
 * the shared `renameUserIdToHash` walker in `./userid-pseudonymize` so the
 * rename signal lives in one place across the silent-fallback helpers, the
 * pino `formatters.log` hook (`./logger`), and any future boundary that
 * needs the same transform. Architectural contract: ADR-029 (rename-at-boundary). Note: ADR-028 is the DSAR/cross-tenant pseudonymisation contract (`hashUserIdForSentry`, `mirrorCrossTenantViolation`) — a deliberately distinct primitive (see ADR-029 §I10).
 *
 * Returns `extra` unchanged when no `userId` key is present. Null/undefined
 * `userId` values resolve to the sentinel `"pepper_unset_null"` to avoid
 * hashing the empty-string literal — which would collide every
 * nullable-userId emit under a single hash.
 */
function hashExtraUserId(
  extra: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!extra || typeof extra !== "object") return extra;
  return renameUserIdToHash(extra);
}

/**
 * Promote the pseudonymized `userIdHash` (already hashed by `hashExtraUserId`)
 * to the Sentry event's User interface so affected-users alert conditions
 * (`event_unique_user_frequency`) can count DISTINCT tenants. Sentry counts
 * distinct users from `event.user`, NOT from `extra` — so an emit that carries
 * the tenant only in `extra.userIdHash` is invisible to a "≥K users in T"
 * threshold (the count stays 0). Using the HASH as `user.id` keeps Recital-26
 * pseudonymization intact — no raw id reaches Sentry. Returns `undefined` when
 * no hash is present so events without tenant attribution are unaffected.
 *
 * In prod each tenant gets a distinct HMAC (`SENTRY_USERID_PEPPER` is set), so
 * the count is per-tenant; when the pepper is unset (dev/CI) every user collapses
 * to the `"pepper_unset"` sentinel — harmless, as the affected-users alert only
 * runs against prod. #5875 / ADR-079: the `sandbox_startup_failure` alert is the
 * first user-count alert in `issue-alerts.tf`; before this, tenant identity lived
 * only in `extra` and the threshold was unreachable.
 */
function userScopeFromExtra(
  transformedExtra: Record<string, unknown> | undefined,
): { id: string } | undefined {
  const h = transformedExtra?.userIdHash;
  return typeof h === "string" && h.length > 0 ? { id: h } : undefined;
}

/**
 * Strip line terminators from a human-readable log message so a CR/LF (or
 * unicode line/paragraph separator) cannot forge a fake log line in a
 * downstream plaintext view (js/log-injection). pino JSON-escapes values, but
 * this is the boundary where operator-/error-derived strings become the log
 * `msg`, so neutralize here. Unicode separators are matched via escape
 * sequences only (cq-regex-unicode-separators-escape-only).
 */
function sanitizeLogMessage(message: string): string {
  return message.replace(/[\r\n\u2028\u2029\v\f]+/g, " ");
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
 * - `art33Breach`: when `true`, sets the `art_33_breach = "true"` Sentry tag.
 *   Reserved for GDPR Art. 33 breach surfaces (e.g. a BYOK cross-tenant key
 *   leak) so a dedicated alert rule can route the 72h-notification clock
 *   distinctly from ordinary silent fallbacks (#4364). The SQL comment at
 *   `064_byok_delegations.sql:197` designed this tag; this option wires it.
 */
export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: Record<string, unknown>;
  message?: string;
  art33Breach?: boolean;
  /**
   * Extra promoted Sentry TAGS (searchable), merged alongside the always-promoted
   * `feature`/`op`/`pg_code`/`art_33_breach`. Sentry `extra` is NOT searchable, so
   * a low-cardinality discriminator the operator must QUERY by (e.g. `source`,
   * `gitKind`) belongs here, not only in `extra`. Keep values low-cardinality —
   * tags are indexed. NEVER put PII / raw ids / a raw userId here (tags are not
   * pseudonymized at the boundary the way the `userId` extra key is).
   */
  tags?: Record<string, string>;
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
  const { feature, op, extra, message, art33Breach, tags: extraTags } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  if (art33Breach) tags.art_33_breach = "true";
  // Caller-supplied searchable tags (e.g. `source`, `gitKind`). Merged after the
  // reserved promotions so a caller can never clobber `feature`; low-cardinality
  // by contract (see SilentFallbackOptions.tags).
  if (extraTags) Object.assign(tags, extraTags);

  // Surface a PostgREST/Postgres SQLSTATE (e.g. 42501 insufficient_privilege,
  // 23505 unique_violation) as a queryable `pg_code` tag so on-call can search
  // `pg_code:<sqlstate>` in Sentry instead of reasoning from the wrapper string
  // alone (#4695). Only the code is extracted — `details`/`hint` may embed row
  // values (PII); see sqlStateFromError. No-op for non-Postgres errors.
  const pgCode = sqlStateFromError(err);
  if (pgCode) tags.pg_code = pgCode;

  // Pseudonymize `userId` → `userIdHash` (Recital 26) at the emit boundary.
  // Centralized here so the 40+ call sites continue passing raw `userId` and
  // never need to know about the rename. Renamed (not value-swapped) so log
  // readers can tell at a glance that pseudonymization is in effect.
  const transformedExtra = hashExtraUserId(extra);

  const safeMessage = sanitizeLogMessage(message ?? `${feature} silent fallback`);

  // Mirror the structured context into pino so log aggregators (container
  // stdout, Better Stack) also get the same tag vocabulary.
  logger.error({ err, feature, op, ...transformedExtra }, safeMessage);

  // Sentry's namespace shape varies across the dev-server bundle (where
  // captureMessage may be tree-shaken when DSN is unset) and the prod build.
  // Guard so an uninitialized Sentry never throws a TypeError into a caller
  // that fires on server boot (see #3045 plugin-mount-check) — the pino mirror
  // above is the durable signal regardless.
  // Give the event a per-tenant user identity (the hash) so affected-users
  // alert conditions can count distinct tenants — see userScopeFromExtra.
  const user = userScopeFromExtra(transformedExtra);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { tags, extra: transformedExtra, user });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(safeMessage, {
        level: "error",
        tags,
        extra: { err, ...transformedExtra },
        user,
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
  const { feature, op, extra, message, art33Breach, tags: extraTags } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  if (art33Breach) tags.art_33_breach = "true";
  // Caller-supplied searchable tags (e.g. `source`, `gitKind`). Merged after the
  // reserved promotions so a caller can never clobber `feature`; low-cardinality
  // by contract (see SilentFallbackOptions.tags).
  if (extraTags) Object.assign(tags, extraTags);

  // Surface a PostgREST/Postgres SQLSTATE (e.g. 42501 insufficient_privilege,
  // 23505 unique_violation) as a queryable `pg_code` tag so on-call can search
  // `pg_code:<sqlstate>` in Sentry instead of reasoning from the wrapper string
  // alone (#4695). Only the code is extracted — `details`/`hint` may embed row
  // values (PII); see sqlStateFromError. No-op for non-Postgres errors.
  const pgCode = sqlStateFromError(err);
  if (pgCode) tags.pg_code = pgCode;

  // Pseudonymize `userId` → `userIdHash` at the emit boundary (see
  // reportSilentFallback for rationale).
  const transformedExtra = hashExtraUserId(extra);

  const safeMessage = sanitizeLogMessage(message ?? `${feature} silent fallback`);

  logger.warn({ err, feature, op, ...transformedExtra }, safeMessage);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { level: "warning", tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(safeMessage, {
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
 * Info-level variant. Same contract as `warn`/`reportSilentFallback`, but emits
 * at `level: "info"` — use for an EVERY-RUN structured record that must be
 * queryable in Sentry without SSH (e.g. a cron's reclaim/throughput payload on
 * the HEALTHY path), NOT just on the error/degraded branch. The pino
 * `logger.info` mirror is preserved inside the helper, so callers replacing a
 * bare `logger.info` lose no stdout signal.
 *
 * Because every call emits, prefer this only for low-cardinality periodic
 * signals (e.g. a 6h cron); never a per-request hot path — pair with
 * `mirrorWithDebounce` if a burst is possible. The `info` path normally passes
 * `err = null`, so the `err instanceof Error` branch is effectively unused here,
 * but the signature is kept symmetric with the warn/report pair so a future
 * caller can attach a non-fatal Error. Note: `art33Breach` is intentionally NOT
 * honored — an info-level signal is never a breach (the option is accepted for
 * signature parity but produces no `art_33_breach` tag).
 */
export function infoSilentFallback(
  err: unknown,
  options: SilentFallbackOptions,
): void {
  const { feature, op, extra, message, tags: extraTags } = options;
  const tags: Record<string, string> = { feature };
  if (op) tags.op = op;
  // Sibling-parity bugfix (#6801 M17): `report`/`warn` merge caller `tags` but
  // `info` silently dropped them, so any `tags:` passed to infoSilentFallback
  // never reached Sentry. Mirror the sibling implementations exactly.
  if (extraTags) Object.assign(tags, extraTags);

  // pg_code surfacing kept for parity (no-op when err is null / non-Postgres).
  const pgCode = sqlStateFromError(err);
  if (pgCode) tags.pg_code = pgCode;

  // Pseudonymize `userId` → `userIdHash` at the emit boundary (see
  // reportSilentFallback for rationale). No-op when no `userId` key is present.
  const transformedExtra = hashExtraUserId(extra);

  const safeMessage = sanitizeLogMessage(message ?? `${feature} info`);

  logger.info({ err, feature, op, ...transformedExtra }, safeMessage);

  try {
    if (err instanceof Error) {
      if (typeof Sentry.captureException === "function") {
        Sentry.captureException(err, { level: "info", tags, extra: transformedExtra });
      }
    } else if (typeof Sentry.captureMessage === "function") {
      Sentry.captureMessage(safeMessage, {
        level: "info",
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
 * - `feature-flags` family: `flagsmith:getidentityflags-timeout` (warn-level
 *   via `mirrorWarnWithDebounce`; dedup key is the per-segment snapshot cache
 *   key `${role}:${orgId ?? "__anon__"}`, NOT a userId — see #4571).
 * - `workspace-reconcile-push` family: `workspace-reconcile-push:no-workspace-match`
 *   (warn-level via `mirrorWarnWithDebounce`; dedup key is
 *   `${installationId}:${targetRepoUrl}`, an in-process token, NOT a userId —
 *   the expected zero-workspace skip on every push to a workspace-less install,
 *   debounced so it stops flooding the same alert family as #4571 — see #4597).
 *   Also `ownerless-reconcile` (warn-level via `mirrorWarnWithDebounce`; dedup
 *   key is the `workspace_id`, an in-process token, NOT a userId — a systemic
 *   owner-canary regression would otherwise emit one warn per owner-less
 *   workspace per push; see #4906).
 *   Also `multiple-owners-reconcile` (info-level `Sentry.addBreadcrumb`, NOT a
 *   warn/page — the honest by-design ≥2-owner signal that distinguishes a
 *   legitimate team workspace from owner-canary drift; carries
 *   `{ workspaceId, ownerCount }`; see #5734/#5591).
 *   Also `owner-attribution-probe` (warn-level via `reportSilentFallback`,
 *   emitted only on a transient owner-read DB error — NOT on zero owners;
 *   reconcile falls back to the workspace-keyed audit; see #5734/#5591).
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
 * Warn-level sibling of `mirrorWithDebounce`. Same per-key 5-minute TTL on the
 * **same** `_mirrorDebounce` instance, but emits at `level: "warning"` via
 * `warnSilentFallback` instead of error level. Use for a recovered degraded
 * path that is worth observing but should not page (e.g. a third-party timeout
 * with a graceful fallback) yet could otherwise burst.
 *
 * `key` is an opaque in-process dedup token — never emitted (see the `userId`
 * note above). Sharing the single `_mirrorDebounce` map means a key+errorClass
 * claimed by either helper suppresses the other inside the window; pick a
 * distinct `errorClass` per call site (registry above) so unrelated sites never
 * coalesce. Introduced for the `/login` Flagsmith-timeout flood (#4571).
 */
export function mirrorWarnWithDebounce(
  err: unknown,
  ctx: SilentFallbackOptions,
  key: string,
  errorClass: string,
): void {
  if (!_mirrorDebounce.tryClaim(`${key}:${errorClass}`, Date.now())) return;
  warnSilentFallback(err, ctx);
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
 * - `cost-writer.ts` — BYOK Art. 33 cross-tenant key-leak breach
 *   (`op="cross-tenant-violation"`, `feature`+`art33Breach` tags; #4656).
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
  ctx: {
    op: string;
    userId: string;
    conversationId: string;
    // #4656 items 2+3 — the BYOK Art. 33 breach path routes through this
    // primitive; these tags also serve item-1's rule filter. The
    // `byok_art_33_breach` Sentry rule (issue-alerts.tf) is
    // `filter_match = "all"` on BOTH `feature=byok-delegations` AND
    // `art_33_breach=true`, so BOTH tags must be present or the rule never
    // fires. `feature` mirrors the `reportSilentFallback` tag vocabulary.
    feature?: string;
    art33Breach?: boolean;
    // #4656 item 3 — cross-tenant-leak clock-anchor identifier carried into
    // the Sentry `extra` alongside the inherited `first_seen_at`.
    delegationId?: string;
  },
): void {
  // Dedup key keeps raw `userId` — in-process map only, never emitted.
  // For the BYOK cross-tenant path `userId` is the GRANTOR (the BYOK-key
  // owner whose key leaked) — the correct Art. 33 data-subject anchor, not
  // the offending grantee (`callerUserId`). Two grantees abusing the same
  // grantor's key in the same conversation within the TTL coalesce to one
  // page (same leaked key + same conversation = one incident; the clock has
  // already started); the distinguishing `delegationId` is preserved in the
  // Sentry `extra` for forensic attribution.
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

  const tags: Record<string, string> = {
    op: ctx.op,
    scope: "p0_deduped",
    userIdHash,
  };
  if (ctx.feature) tags.feature = ctx.feature;
  if (ctx.art33Breach) tags.art_33_breach = "true";

  // Sentry — fatal severity, bypasses `mirrorWithDebounce` 5-min window.
  // `first_seen_at` is the Art. 33(1) 72h-clock anchor.
  try {
    if (typeof Sentry.captureException === "function") {
      Sentry.captureException(err, {
        level: "fatal",
        tags,
        extra: {
          op: ctx.op,
          userIdHash,
          conversationId: ctx.conversationId,
          severity: "breach_attempt",
          first_seen_at: new Date(now).toISOString(),
          ...(ctx.delegationId ? { delegationId: ctx.delegationId } : {}),
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

  // Defensive strip: if a caller mistakenly passed raw userId/user_id in
  // `ctx`, drop them before they spread into Sentry's `extra` (pino emit
  // below is already covered by formatters.log via ADR-029, but the
  // Sentry capture path at the bottom bypasses that boundary). The
  // canonical user identifiers for this function are `offendingUserId`
  // and `expectedUserId` — `ctx` is for queryShape/jobId/etc.
  const { userId: _stripUserId, user_id: _stripUserIdSnake, ...safeCtx } = ctx;
  void _stripUserId;
  void _stripUserIdSnake;

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
      ...safeCtx,
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
