// proxy-listener-status.ts — the relay's OWN bind, reported from inside the
// process (#12167, ADR-068 section (c)(3)).
//
// The cf-lb-overlay serve arm flips web-2's load-balancer weight 0 -> 1, but its
// gate chain only shape-checks SOLEUR_PROXY_BIND (the real value is per-host and
// resolved on-host by ci-deploy.sh), and the bind log line in session-proxy.ts is
// info-level and does not reach Better Stack. So bind was unprovable off-host.
// This module records what `createProxyServer` decided (the server, or WHY there
// is none) and a reporter emits one fixed-grammar warn-level line per minute that
// a separate step reads from Better Stack by host_name. No new HTTP endpoint.
//
// The reporter reads `server.listening` / `server.address()` AT EMIT TIME, never
// at start: the listen callback is asynchronous, and a listener that later errors
// or closes must show up in the next line, not be frozen at its boot state.
//
// Leaf module on purpose (type-only imports besides the logger): readiness.ts
// reads `getProxyStatus()` for its non-gating `proxy` block, and the reporter
// takes the populated bit as an injected reader, so there is no import cycle.

import type { Server as HttpsServer } from "node:https";
import { createChildLogger } from "./logger";
import { warnSilentFallback } from "./observability";

const FEATURE = "proxy-listener-status";

export type ProxyState =
  | "listening"
  | "disabled"
  | "no_bind"
  | "no_allowlist"
  | "error";

export type ProxyDisabledReason = "disabled" | "no_bind" | "no_allowlist" | "error";

export interface ProxyStatus {
  state: ProxyState;
  /** Bound address while listening; `none` otherwise. */
  addr: string;
  /** Bound port while listening; 0 otherwise. */
  port: number;
}

type Recorded =
  | { kind: "reason"; reason: ProxyDisabledReason }
  | { kind: "server"; server: HttpsServer };

// Before createProxyServer has run, the relay is simply not enabled.
let recorded: Recorded = { kind: "reason", reason: "disabled" };

/** createProxyServer: the relay is not enabled on this host, and why. */
export function recordProxyNotStarted(reason: ProxyDisabledReason): void {
  recorded = { kind: "reason", reason };
}

/**
 * createProxyServer: the server object that is (about to be) listening. A listen
 * failure (EADDRNOTAVAIL, EADDRINUSE, ...) needs no separate flag: the server then
 * never reports `listening`, and `getProxyStatus` derives `error` from that.
 */
export function recordProxyServer(server: HttpsServer): void {
  recorded = { kind: "server", server };
}

/** Test seam: module-level state would otherwise leak between cases. */
export function __resetProxyListenerStatusForTests(): void {
  recorded = { kind: "reason", reason: "disabled" };
}

/**
 * Current status, derived from the live server NOW. A recorded server that is not
 * listening (listen failed, or has not completed yet, or was closed) is `error`:
 * from the outside, "relay not bound" is the only fact that matters. Never throws.
 */
export function getProxyStatus(): ProxyStatus {
  try {
    if (recorded.kind === "reason") {
      return { state: recorded.reason, addr: "none", port: 0 };
    }
    const { server } = recorded;
    if (server.listening) {
      const a = server.address();
      if (a && typeof a === "object" && typeof a.address === "string") {
        return { state: "listening", addr: a.address, port: a.port };
      }
    }
    return { state: "error", addr: "none", port: 0 };
  } catch {
    return { state: "error", addr: "none", port: 0 };
  }
}

/**
 * The closed-grammar line the evidence collector reads:
 * `relay_probe proxy_state=<listening|disabled|no_bind|no_allowlist|error> addr=<ip|none> port=<n> workspaces_populated=<0|1>`.
 * Only enum words, an IP literal (or `none`), an integer and one bit: no free text,
 * no error message, nothing a user or a path could reach.
 */
export function formatRelayProbeLine(
  status: ProxyStatus,
  workspacesPopulated: boolean,
): string {
  const port = Number.isInteger(status.port) && status.port >= 0 && status.port <= 65535 ? status.port : 0;
  return `relay_probe proxy_state=${status.state} addr=${status.addr} port=${port} workspaces_populated=${workspacesPopulated ? 1 : 0}`;
}

export const PROXY_REPORT_INTERVAL_MS = 60_000;
// The listen callback is asynchronous (an IP literal still goes through
// dns.lookup), so an emit at t=0 would report a healthy relay as not bound.
const INITIAL_EMIT_DELAY_MS = 1_000;

export interface ProxyListenerReporterDeps {
  /** Read-only populated state (readiness.ts isWorkspacesPopulated): NO write probe. */
  readWorkspacesPopulated: () => boolean;
  intervalMs?: number;
}

/** Read the live state and emit one warn-level line. Never throws. */
export function emitProxyListenerStatusOnce(
  deps: Pick<ProxyListenerReporterDeps, "readWorkspacesPopulated">,
): void {
  let populated = false;
  try {
    populated = deps.readWorkspacesPopulated();
  } catch (err) {
    warnSilentFallback(err, {
      feature: FEATURE,
      op: "read-populated",
      message: "workspaces populated read failed; reporting 0",
    });
  }
  const status = getProxyStatus();
  // warn level on purpose: info-level lines do not reach Better Stack (measured
  // 2026-11-05); warn is the level the quiet-window and git_data_store= lines ship
  // at. The child logger is created here, not at module load, so importing this
  // module for readiness alone never touches the logger.
  createChildLogger("proxy-listener").warn(
    { proxyState: status.state, addr: status.addr, port: status.port, workspacesPopulated: populated },
    formatRelayProbeLine(status, populated),
  );
}

/**
 * Emit the relay line shortly after boot and then every minute. Timers are unref'd
 * and every tick is fenced: observability must never take the process down or block
 * shutdown. Returns the interval so SIGTERM can clear it.
 */
export function startProxyListenerReporter(
  deps: ProxyListenerReporterDeps,
): NodeJS.Timeout {
  const tick = () => {
    try {
      emitProxyListenerStatusOnce(deps);
    } catch (err) {
      warnSilentFallback(err, {
        feature: FEATURE,
        op: "emit",
        message: "relay probe line emit failed",
      });
    }
  };
  setTimeout(tick, INITIAL_EMIT_DELAY_MS).unref();
  const timer = setInterval(tick, deps.intervalMs ?? PROXY_REPORT_INTERVAL_MS);
  timer.unref();
  return timer;
}
