// Per-user write throttle + error classifier for the Workstream write endpoints
// (ADR-109 / AC15). ONE module-scoped SlidingWindowCounter is shared by POST and
// PATCH so a runaway MCP-agent write loop (or a double-fire) is bounded across
// BOTH verbs, protecting against GitHub SECONDARY rate limits. Keyed on the
// authenticated user.id (stable per account, unlike IP). Single-instance
// assumption inherited from rate-limiter.ts (Hetzner single node).

import {
  SlidingWindowCounter,
  startPruneInterval,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import { WorkstreamWriteError } from "@/server/workstream/mutate-workstream-issue";

const WRITE_PER_MIN = parseInt(
  process.env.WORKSTREAM_WRITE_RATE_LIMIT_PER_MIN ?? "30",
  10,
);

const counter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: WRITE_PER_MIN,
});
startPruneInterval(counter);

/** True when the caller is within budget (and records the hit). A rejection is
 *  mirrored as a Sentry breadcrumb (rate-limit hits are an exempt expected
 *  state per cq-silent-fallback-must-mirror-to-sentry). */
export function checkWorkstreamWriteRate(userId: string): boolean {
  const ok = counter.isAllowed(userId);
  if (!ok) logRateLimitRejection("workstream-write", userId);
  return ok;
}

/** Test-only: reset the shared throttle between tests. */
export function __resetWorkstreamWriteThrottleForTest(): void {
  counter.reset();
}

/**
 * Map a thrown write error to an HTTP status + stable code. A typed
 * WorkstreamWriteError carries its own status; a raw octokit RequestError
 * carries `.status` (403 = read-only install → surface honestly, no retry loop;
 * 404 = gone; 422 = validation). Everything else is a fail-loud 502.
 */
export function classifyWriteError(e: unknown): { status: number; code: string } {
  if (e instanceof WorkstreamWriteError) {
    return { status: e.status, code: e.code };
  }
  const raw = (e as { status?: unknown } | null)?.status;
  const status = typeof raw === "number" ? raw : 0;
  if (status === 403) return { status: 403, code: "forbidden_readonly" };
  if (status === 404) return { status: 404, code: "not_found" };
  if (status === 422) return { status: 422, code: "invalid" };
  return { status: 502, code: "workstream_write_error" };
}
