// Sliding-window rate limiter for ws-handler `start_session`.
//
// Plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
// Stage 2 §"Files to edit" (ws-handler.ts `start_session` rate limit) /
// Stage 2.5 RED / Stage 2.15 GREEN / Stage 6.11 security smoke.
//
// Two caps layered:
//   (a) Per-user: 10 conversations / hour / userId
//   (b) Per-IP:   30 conversations / hour / IP
//
// Fail-closed on either cap. Returns a structured reason so the ws-handler
// can emit a typed `rate_limited` WS error with a Retry-After hint.
//
// State model: process-local. A container restart drops every window —
// acceptable V1 behavior per plan Stage 5 (rollback story). A distributed
// limiter (Redis ZRANGEBYSCORE) is out of scope.
//
// The single-method `check()` shape enforces atomic consume-on-allow: once
// a caller observes `allowed: true`, the timestamp is already committed.
// Splitting into probe/increment would create a TOCTOU window where two
// concurrent start_session handlers both pass `probe()` before either
// `increment()`s — unacceptable for a cap whose whole point is DoS
// resistance.

export const ONE_HOUR_MS = 60 * 60 * 1000;
export const DEFAULT_PER_USER_PER_HOUR = 10;
export const DEFAULT_PER_IP_PER_HOUR = 30;

export type StartSessionRateCheck =
  | { allowed: true }
  | { allowed: false; reason: "user" | "ip"; retryAfterMs: number };

export interface StartSessionRateLimiter {
  check(args: { userId: string; ip: string }): StartSessionRateCheck;
}

export interface StartSessionRateLimiterOptions {
  perUserPerHour?: number;
  perIpPerHour?: number;
  windowMs?: number;
  now?: () => number;
}

export function createStartSessionRateLimiter(
  opts: StartSessionRateLimiterOptions = {},
): StartSessionRateLimiter {
  const perUserPerHour = opts.perUserPerHour ?? DEFAULT_PER_USER_PER_HOUR;
  const perIpPerHour = opts.perIpPerHour ?? DEFAULT_PER_IP_PER_HOUR;
  const windowMs = opts.windowMs ?? ONE_HOUR_MS;
  const now = opts.now ?? (() => Date.now());

  // Per-key timestamp lists. Each `check()` prunes entries older than
  // `now - windowMs` before counting. A Map grows with distinct users/IPs
  // seen within the window; entries whose lists become empty are deleted
  // during pruning to bound memory.
  const userWindow = new Map<string, number[]>();
  const ipWindow = new Map<string, number[]>();

  function prune(window: Map<string, number[]>, key: string, cutoff: number): number[] {
    const list = window.get(key);
    if (!list) return [];
    const surviving: number[] = [];
    for (const ts of list) {
      if (ts > cutoff) surviving.push(ts);
    }
    if (surviving.length === 0) {
      window.delete(key);
    } else {
      window.set(key, surviving);
    }
    return surviving;
  }

  function retryAfter(list: readonly number[], t: number): number {
    if (list.length === 0) return 0;
    const oldest = list[0] as number;
    return oldest + windowMs - t;
  }

  return {
    check({ userId, ip }): StartSessionRateCheck {
      const t = now();
      const cutoff = t - windowMs;
      const userList = prune(userWindow, userId, cutoff);
      const ipList = prune(ipWindow, ip, cutoff);

      if (userList.length >= perUserPerHour) {
        return {
          allowed: false,
          reason: "user",
          retryAfterMs: Math.max(1, retryAfter(userList, t)),
        };
      }
      if (ipList.length >= perIpPerHour) {
        return {
          allowed: false,
          reason: "ip",
          retryAfterMs: Math.max(1, retryAfter(ipList, t)),
        };
      }

      // Atomic consume: commit the timestamp now, so the caller's
      // observed `allowed: true` cannot race with a second check.
      userList.push(t);
      ipList.push(t);
      userWindow.set(userId, userList);
      ipWindow.set(ip, ipList);
      return { allowed: true };
    },
  };
}
