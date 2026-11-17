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
// per window that saw hello activity). The serve-gate probe (`relay_peer_probe`) sends no
// hello, so that line is the only off-host way to see that a SIGNED round trip happened. The
// line carries counts only and does not match the `relay_probe proxy_state=` or
// `relay_peer_probe peer=` alert filters. Pre-hello connection denies (`peer`) and the sender
// side's refusals are bounded like the rest but are NOT hellos, so they stay out of that line.
//
// Events are emitted with a null error and an explicit message: on the Error path
// `reportSilentFallback` logs first, the pino mirror captures the SAME Error instance as
// `feature=pino-mirror`, and Sentry drops the tagged second capture, so the event would arrive
// without its `feature`/`op` tags and `extra` (the fleet-wide defect tracked in #8629; see
// server/anthropic-credit.ts). With a null error the call goes through `captureMessage`.
//
// Extras are an enum, counts, the supplied peer address / authenticated id pair and, for `internal`, the thrown error's CLASS name. An
// unauthenticated reason never carries a byte derived from the hello. `record` never throws:
// a fault in the reporting path must not turn a refusal into an uncaught exception.

import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("proxy-deny-report");

export const DENY_MAX_EVENTS = 5;
export const DENY_WINDOW_MS = 60_000;

export type DenyReason =
  // Owner side, before any hello is accepted.
  | "peer"
  | "hello_timeout"
  | "size"
  | "shape"
  | "mac"
  | "skew"
  | "replay"
  | "full"
  // Owner side, after a valid MAC.
  | "membership"
  | "internal"
  // Sender (proxying host) side: the client is closed before or without a usable owner. They share
  // the cap and the counter but are not part of the owner's relay_hello_window line.
  | "no_key"
  | "no_ca"
  | "bad_ids"
  | "bad_port"
  | "owner_refused";

const REASONS: Record<DenyReason, { op: string; message: string; hello: boolean }> = {
  peer: { op: "createProxyServer.peer-deny", message: "proxy connection from a non-peer private IP — rejected before handshake", hello: false },
  hello_timeout: { op: "createProxyServer.hello-deny", message: "proxy hello not received before the deadline — connection closed", hello: true },
  size: { op: "createProxyServer.hello-deny", message: "proxy hello refused (size)", hello: true },
  shape: { op: "createProxyServer.hello-deny", message: "proxy hello refused (shape)", hello: true },
  mac: { op: "createProxyServer.hello-deny", message: "proxy hello refused (mac)", hello: true },
  skew: { op: "createProxyServer.hello-deny", message: "proxy hello refused (skew)", hello: true },
  replay: { op: "createProxyServer.hello-deny", message: "proxy hello refused (replay)", hello: true },
  full: { op: "createProxyServer.hello-deny", message: "proxy hello refused (replay cache full)", hello: true },
  membership: { op: "createProxyServer.ap2-deny", message: "proxied session failed AP-2 membership re-verify — cross-tenant/ stale route rejected", hello: true },
  internal: { op: "createProxyServer.hello-deny", message: "proxy hello handling failed internally — connection closed", hello: true },
  no_key: { op: "proxyClientToOwner.no-hello-key", message: "proxy hello key unavailable — client closed without dialing the owner", hello: false },
  no_ca: { op: "proxyClientToOwner.no-ca", message: "proxy client CA (PROXY_TLS_CERT) unavailable — client closed without dialing the owner", hello: false },
  bad_ids: { op: "proxyClientToOwner.bad-ids", message: "proxy hello ids are not canonical UUIDs — client closed without dialing the owner", hello: false },
  bad_port: { op: "proxyClientToOwner.bad-port", message: "SOLEUR_PROXY_PORT is not a valid port — client closed without dialing the owner", hello: false },
  owner_refused: { op: "proxyClientToOwner.owner-refused", message: "owner refused the proxied session — client closed", hello: false },
};

type Report = typeof reportSilentFallback;

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

const defaultSetTimer = (fn: () => void, ms: number): void => {
  const t = setTimeout(fn, ms);
  if (typeof t === "object" && t && "unref" in t) (t as { unref: () => void }).unref();
};

export function createDenyReporter(opts: DenyReporterOptions = {}) {
  const maxEvents = opts.maxEvents ?? DENY_MAX_EVENTS;
  const windowMs = opts.windowMs ?? DENY_WINDOW_MS;
  const report: Report = opts.report ?? reportSilentFallback;
  const now = opts.now ?? Date.now;
  const setTimer = opts.setTimer ?? defaultSetTimer;

  const buckets = new Map<DenyReason, Bucket>();
  const lifetime = new Map<DenyReason, { denied: number; reported: number; suppressed: number }>();
  let acceptedTotal = 0;
  let win: { start: number; accepted: number; denied: number; suppressed: number } | null = null;

  function flushBucket(reason: DenyReason, b: Bucket): void {
    if (buckets.get(reason) === b) buckets.delete(reason);
    if (b.suppressed > 0) {
      report(null, {
        feature: "control_plane_route",
        op: `${REASONS[reason].op}-summary`,
        message: `proxy relay denies suppressed (${reason})`,
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
        if (buckets.get(reason) === fresh) safely(() => flushBucket(reason, fresh));
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
        if (win === fresh) safely(() => flushWindow(fresh));
      }, windowMs);
    }
    return win;
  }

  function safely(fn: () => void): void {
    try {
      fn();
    } catch {
      /* a reporting fault must never become an uncaught exception on a refusal path */
    }
  }

  return {
    /** Count one refusal; mirror it to Sentry only while the per-reason cap allows. Never throws. */
    record(reason: DenyReason, extra?: Record<string, unknown>): void {
      safely(() => {
        const meta = REASONS[reason];
        const b = bucketFor(reason);
        const w = meta.hello ? windowFor() : null;
        const life = lifetime.get(reason) ?? { denied: 0, reported: 0, suppressed: 0 };
        lifetime.set(reason, life);
        b.denied++;
        if (w) w.denied++;
        life.denied++;
        if (b.reported < maxEvents) {
          b.reported++;
          life.reported++;
          report(null, {
            feature: "control_plane_route",
            op: meta.op,
            message: meta.message,
            extra: { reason, ...(extra ?? {}) },
          });
          return;
        }
        b.suppressed++;
        if (w) w.suppressed++;
        life.suppressed++;
      });
    },
    /** Count one hello that passed every check and was handed to the session attach. */
    recordAccepted(): void {
      safely(() => {
        acceptedTotal++;
        windowFor().accepted++;
      });
    },
    /** Emit every open summary event and the open window line now (graceful shutdown). */
    flush(): void {
      for (const [reason, b] of [...buckets]) safely(() => flushBucket(reason, b));
      if (win) {
        const w = win;
        safely(() => flushWindow(w));
      }
    },
    counters(reason: DenyReason): { denied: number; reported: number; suppressed: number } {
      return { ...(lifetime.get(reason) ?? { denied: 0, reported: 0, suppressed: 0 }) };
    },
    acceptedCount(): number {
      return acceptedTotal;
    },
    reset(): void {
      buckets.clear();
      lifetime.clear();
      acceptedTotal = 0;
      win = null;
    },
  };
}

/** Module default used by session-proxy.ts. Tests that use it call `denyReporter.reset()`. */
export const denyReporter = createDenyReporter();

export function __resetDenyReporterForTests(): void {
  denyReporter.reset();
}
