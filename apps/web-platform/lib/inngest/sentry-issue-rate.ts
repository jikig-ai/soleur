// Pure helpers for the `sentry-issue-rate` named-check (#5417 follow-on;
// event-scheduled-reminder.ts CHECK_REGISTRY). Lives in lib/ so it is unit-
// testable WITHOUT the handler's octokit/Inngest mocks, and carries no
// server-only import. The handler owns the actual fetch + env read + close
// decision; this file owns the security-load-bearing validation + math.
//
// Security invariants encoded here (verified by the live Phase-0 probe):
//   - `tag` is a single Sentry search term `key:value`, strict-regex validated,
//     so a crafted `tag` cannot inject `&`/`?`/`#`/whitespace/`..` into the
//     Sentry query string (defense-in-depth with URLSearchParams encoding).
//   - `window_hours` is bounded [1,168] so a spurious "pass" cannot be
//     manufactured by asking for an enormous window that dilutes the rate.
//   - `max_per_day` must be finite and > 0.

const TAG_RE = /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$/;
export const MIN_WINDOW_HOURS = 1;
export const MAX_WINDOW_HOURS = 168; // 7 days — the issue-stats `stat=14d` daily-bucket ceiling.

export interface SentryRateParams {
  /** A single Sentry search term `key:value` (e.g. `event_type:server-startup`). */
  tag: string;
  /** Threshold: PASS iff events/day <= maxPerDay. Finite, > 0. */
  maxPerDay: number;
  /** Lookback window in hours, bounded [1,168]. */
  windowHours: number;
  /** When true AND the verdict is `pass`, the handler closes report_to_issue. */
  closeOnPass: boolean;
}

export type ParseResult =
  | { ok: true; value: SentryRateParams }
  | { ok: false; reason: string };

/** Validate the `named-check` `params` for the `sentry-issue-rate` check.
 *  Returns a stable `reason` on rejection (doubles as the fail-closed body tag). */
export function parseSentryRateParams(
  params: Record<string, unknown> | undefined,
): ParseResult {
  if (!params || typeof params !== "object") {
    return { ok: false, reason: "missing-params" };
  }
  const { tag, max_per_day: maxPerDay, window_hours: windowHours } = params;
  // `..` is never a legitimate Sentry tag value (single dots in `release:1.2.3`
  // are fine); reject the traversal shape explicitly as defense-in-depth even
  // though the value is URLSearchParams-encoded into the query (not a path).
  if (typeof tag !== "string" || !TAG_RE.test(tag) || tag.includes("..")) {
    return { ok: false, reason: "invalid-tag" };
  }
  if (
    typeof maxPerDay !== "number" ||
    !Number.isFinite(maxPerDay) ||
    maxPerDay <= 0
  ) {
    return { ok: false, reason: "invalid-max-per-day" };
  }
  if (
    typeof windowHours !== "number" ||
    !Number.isInteger(windowHours) ||
    windowHours < MIN_WINDOW_HOURS ||
    windowHours > MAX_WINDOW_HOURS
  ) {
    return { ok: false, reason: "invalid-window-hours" };
  }
  return {
    ok: true,
    value: {
      tag,
      maxPerDay,
      windowHours,
      closeOnPass: params.close_on_pass === true,
    },
  };
}

/** Build a Sentry API URL from a trusted `host` (env), a literal `path`, and a
 *  query record. `URL` + `searchParams.set` percent-encode every value, so an
 *  untrusted `tag` in `query` cannot break out of the query string. */
export function buildSentryUrl(
  host: string,
  path: string,
  query: Record<string, string>,
): string {
  const url = new URL(`https://${host}${path}`);
  for (const [k, v] of Object.entries(query)) {
    url.searchParams.set(k, v);
  }
  return url.toString();
}

/** Sum the last `ceil(windowHours/24)` DAILY buckets of an issue-stats series
 *  (`[[unixSeconds, count], ...]`, as returned by `GET …/issues/{id}/stats/?stat=14d`)
 *  and derive events/day over the window. Non-finite counts collapse to 0. */
export function computeRatePerDay(
  buckets: Array<[number, number]>,
  windowHours: number,
): { sum: number; days: number; ratePerDay: number } {
  const days = windowHours / 24;
  const n = Math.max(1, Math.ceil(days));
  const tail = buckets.slice(-n);
  const sum = tail.reduce(
    (acc, b) => acc + (Array.isArray(b) && Number.isFinite(b[1]) ? b[1] : 0),
    0,
  );
  const ratePerDay = days > 0 ? sum / days : sum;
  return { sum, days, ratePerDay };
}
