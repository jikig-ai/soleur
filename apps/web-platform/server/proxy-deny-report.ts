// proxy-deny-report.ts — bounded deny reporting for the owner-side session relay
// (#12288, ADR-323). Leaf module: imports only the logger and the Sentry mirror.
//
// Every refused connection or hello on the relay port routes through `record(reason)`.
// A flood from a hostile or misconfigured private-net host can therefore neither drown the
// Sentry project nor hide the first events of a new incident: at most DENY_MAX_EVENTS events
// per reason per window are mirrored, the rest only increment an exact counter, and a window
// that suppressed anything ends with exactly ONE summary event {reason, denied, suppressed}.
//
// It also owns the `relay_hello_window accepted=<n> denied=<n> suppressed=<n>` pino line (one
// per window that saw any hello activity). The serve-gate probe (`relay_peer_probe`) sends no
// hello, so that line is the only off-host way to see that a SIGNED round trip happened. The
// line carries counts only and does not match the `relay_probe proxy_state=` or
// `relay_peer_probe peer=` alert filters.
//
// Extras are an enum, counts and the supplied peer address / authenticated id pair. An
// unauthenticated reason never carries a byte derived from the hello.

import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("proxy-deny-report");

export const DENY_MAX_EVENTS = 5;
export const DENY_WINDOW_MS = 60_000;

export type DenyReason =
  | "peer"
  | "size"
  | "shape"
  | "mac"
  | "skew"
  | "replay"
  | "full"
  | "membership"
  // Sender-side (proxying host) refusals: the client is closed before any dial. They share the cap and
  // the counter, but are NOT part of the owner's relay_hello_window line (that line counts hellos).
  | "no_key"
  | "bad_ids"
  | "bad_port";

const SENDER_SIDE: ReadonlySet<DenyReason> = new Set<DenyReason>(["no_key", "bad_ids", "bad_port"]);

type Report = (err: unknown, opts: { feature: "control_plane_route"; op: string; message?: string; extra?: Record<string, unknown> }) => void;

export interface DenyReporterOptions {
  maxEvents?: number;
  windowMs?: number;
  report?: Report;
  now?: () => number;
  /** Schedules the window-end flush. The default is an unref'd setTimeout. */
  setTimer?: (fn: () => void, ms: number) => void;
}

interface Bucket {
  start: number;
  denied: number;
  reported: number;
  suppressed: number;
}

function opFor(reason: DenyReason): string {
  if (reason === "no_key") return "proxyClientToOwner.no-hello-key";
  if (reason === "bad_ids") return "proxyClientToOwner.bad-ids";
  if (reason === "bad_port") return "proxyClientToOwner.bad-port";
  if (reason === "peer") return "createProxyServer.peer-deny";
  if (reason === "membership") return "createProxyServer.ap2-deny";
  return "createProxyServer.hello-deny";
}

function messageFor(reason: DenyReason): string {
  switch (reason) {
    case "peer":
      return "proxy connection from a non-peer private IP — rejected before handshake";
    case "membership":
      return "proxied session failed AP-2 membership re-verify — cross-tenant/ stale route rejected";
    case "no_key":
      return "proxy hello key unavailable — client closed without dialing the owner";
    case "bad_ids":
      return "proxy hello ids are not canonical UUIDs — client closed without dialing the owner";
    case "bad_port":
      return "SOLEUR_PROXY_PORT is not a valid port — client closed without dialing the owner";
    default:
      return `proxy hello refused (${reason})`;
  }
}

const defaultSetTimer = (fn: () => void, ms: number): void => {
  const t = setTimeout(fn, ms);
  if (typeof t === "object" && t && "unref" in t) (t as { unref: () => void }).unref();
};

export function createDenyReporter(opts: DenyReporterOptions = {}) {
  const maxEvents = opts.maxEvents ?? DENY_MAX_EVENTS;
  const windowMs = opts.windowMs ?? DENY_WINDOW_MS;
  const report: Report = opts.report ?? (reportSilentFallback as unknown as Report);
  const now = opts.now ?? Date.now;
  const setTimer = opts.setTimer ?? defaultSetTimer;

  const buckets = new Map<DenyReason, Bucket>();
  const lifetime = new Map<DenyReason, { denied: number; reported: number; suppressed: number }>();
  let acceptedTotal = 0;
  let win: { start: number; accepted: number; denied: number; suppressed: number } | null = null;

  function flushBucket(reason: DenyReason, b: Bucket): void {
    if (buckets.get(reason) === b) buckets.delete(reason);
    if (b.suppressed > 0) {
      report(new Error(`proxy relay denies suppressed (${reason})`), {
        feature: "control_plane_route",
        op: `${opFor(reason)}-summary`,
        extra: { reason, denied: b.denied, suppressed: b.suppressed },
      });
    }
  }

  function flushWindow(w: NonNullable<typeof win>): void {
    if (win === w) win = null;
    if (w.accepted + w.denied > 0) {
      log.warn(
        { accepted: w.accepted, denied: w.denied, suppressed: w.suppressed },
        `relay_hello_window accepted=${w.accepted} denied=${w.denied} suppressed=${w.suppressed}`,
      );
    }
  }

  function bucketFor(reason: DenyReason): Bucket {
    let b = buckets.get(reason);
    if (b && now() - b.start >= windowMs) {
      flushBucket(reason, b);
      b = undefined;
    }
    if (!b) {
      const fresh: Bucket = { start: now(), denied: 0, reported: 0, suppressed: 0 };
      b = fresh;
      buckets.set(reason, fresh);
      setTimer(() => {
        if (buckets.get(reason) === fresh) flushBucket(reason, fresh);
      }, windowMs);
    }
    return b;
  }

  function windowFor(): NonNullable<typeof win> {
    if (win && now() - win.start >= windowMs) flushWindow(win);
    if (!win) {
      const fresh = { start: now(), accepted: 0, denied: 0, suppressed: 0 };
      win = fresh;
      setTimer(() => {
        if (win === fresh) flushWindow(fresh);
      }, windowMs);
    }
    return win;
  }

  return {
    /** Count one refusal; mirror it to Sentry only while the per-reason cap allows. */
    record(reason: DenyReason, extra?: Record<string, unknown>): void {
      const b = bucketFor(reason);
      const w = SENDER_SIDE.has(reason) ? null : windowFor();
      const life = lifetime.get(reason) ?? { denied: 0, reported: 0, suppressed: 0 };
      lifetime.set(reason, life);
      b.denied++;
      if (w) w.denied++;
      life.denied++;
      if (b.reported < maxEvents) {
        b.reported++;
        life.reported++;
        report(new Error(messageFor(reason)), {
          feature: "control_plane_route",
          op: opFor(reason),
          extra: { reason, ...(extra ?? {}) },
        });
        return;
      }
      b.suppressed++;
      if (w) w.suppressed++;
      life.suppressed++;
    },
    /** Count one hello that passed every check and was handed to the session attach. */
    recordAccepted(): void {
      acceptedTotal++;
      windowFor().accepted++;
    },
    acceptedCount(): number {
      return acceptedTotal;
    },
    counters(reason: DenyReason): { denied: number; reported: number; suppressed: number } {
      return { ...(lifetime.get(reason) ?? { denied: 0, reported: 0, suppressed: 0 }) };
    },
    reset(): void {
      buckets.clear();
      lifetime.clear();
      acceptedTotal = 0;
      win = null;
    },
  };
}

/** Module default used by session-proxy.ts. Tests that use it call `__resetDenyReporterForTests`. */
export const denyReporter = createDenyReporter();

export function __resetDenyReporterForTests(): void {
  denyReporter.reset();
}
