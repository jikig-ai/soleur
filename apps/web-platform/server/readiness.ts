import { writeFileSync, unlinkSync } from "fs";
import { join } from "path";
import { randomBytes } from "crypto";
import type { IncomingMessage, ServerResponse } from "http";
import { countWorkspaceDirsAt } from "./session-metrics";
import { reportSilentFallback } from "./observability";
import { isLoopbackHost, isLoopbackPeer } from "./loopback";

// Deep-readiness (#5966, ADR-068 Sharp Edge C1). `/health` is liveness-only
// (hardcoded status:"ok" + a SHARED-Supabase probe) — neither signal reflects
// whether the RESPONDING host's own `/workspaces` block volume is mounted and
// populated. On the ADR-068 multi-host topology each web host serves its own
// host-local `/workspaces`, so a bare web-2 (empty/unmounted, not in rotation)
// returns 200/status:ok — a routing lie. This module answers "can THIS host
// actually serve?" so the drain/undrain tooling (and, at GA, the LB pre-pool
// check) can gate live weight on it. `/health` stays untouched — this is a
// SEPARATE endpoint, physically enforcing the "no mount coupling on /health"
// invariant the blue-green amendment requires (shared Supabase → body coupling
// would eject the sole live origin on a DB blip).
//
// Fail-closed everywhere: any uncertainty (stat error, missing root, unexpected
// throw) → ready:false. A false 2xx on a bare host is a workspace-gone
// incident; a false 503 on web-1 drains the origin. Both are single-user-
// incident class, so every ambiguous branch resolves to not-ready.

export interface ReadinessResponse {
  ready: boolean;
  checks: {
    // Host can create+unlink under WORKSPACES_ROOT — proves the volume is
    // mounted AND writable from inside the container. This is the ONLY signal
    // that actually works here: /workspaces is a docker `-v` bind mount over an
    // overlay root, so the classic st_dev mountpoint check is inert (always
    // distinct) and cannot detect a failed Hetzner volume attach (docker
    // auto-creates the source dir on the host root fs). A write probe catches
    // absent (ENOENT), read-only (EROFS), permission (EACCES) and I/O (EIO).
    workspaces_writable: boolean;
    // ≥1 host-local workspace dir (`.orphaned-`/`.cron`/`lost+found` excluded).
    // Rejects a fresh/empty volume that is writable but carries no state.
    workspaces_populated: boolean;
  };
}

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || "/workspaces";
}

// Write+unlink a probe. The probe is a regular file (not a dir), so
// countWorkspaceDirsAt's isDirectory() filter excludes it from the populated
// count even in the window before unlink (there is no dotfile-name filter — the
// isDirectory() check is what saves it). Opened O_EXCL (`wx`) so it refuses to
// follow a final symlink and fails EEXIST rather than truncating a target
// (CWE-59/CWE-377 defense-in-depth); the 48-bit random name makes a collision
// with a real file a non-event. FAIL CLOSED on any error.
function isWorkspacesWritable(root: string): boolean {
  const probe = join(root, `.readyz-probe-${randomBytes(6).toString("hex")}`);
  try {
    writeFileSync(probe, "", { flag: "wx" });
    return true;
  } catch {
    return false;
  } finally {
    try {
      unlinkSync(probe);
    } catch {
      /* best-effort cleanup — the write may have failed, or a racing sweep
         removed it; either way the writable verdict is already decided. */
    }
  }
}

// Never throws — any internal error resolves to ready:false (fail-closed). The
// route handler wraps this too (belt-and-suspenders), but keeping the builder
// itself total means the boot mirror and any future caller are equally safe.
export function buildReadinessResponse(): ReadinessResponse {
  try {
    // Resolve the root ONCE and pass it into BOTH signals — do NOT call
    // getActiveWorkspaceCount() (it reads a module-load cached root, which would
    // split-brain with the `root` the write probe uses).
    const root = getWorkspacesRoot();
    const workspaces_writable = isWorkspacesWritable(root);
    const workspaces_populated = countWorkspaceDirsAt(root) > 0;
    const ready = workspaces_writable && workspaces_populated;
    return { ready, checks: { workspaces_writable, workspaces_populated } };
  } catch {
    return {
      ready: false,
      checks: { workspaces_writable: false, workspaces_populated: false },
    };
  }
}

// Handle GET /internal/readyz. Loopback-gated: mount/topology state is
// attacker-useful (DoS-tuning, cluster-shape scraping). Behind the CF tunnel the
// socket peer is loopback for ALL relayed traffic, so the Host-header clause
// (isLoopbackHost) is the load-bearing boundary for tunnel traffic; the
// transport-peer clause (isLoopbackPeer) additionally blocks direct off-host TCP
// to the port (the firewall's job too). Both must hold — see ./loopback. On-host
// consumers (drain/undrain tooling, GA pre-pool check) therefore MUST run on
// loopback with a loopback Host header, not probe readyz as a direct off-host LB
// healthcheck.
//
// CONTAINER TOPOLOGY: the prod app runs on the DEFAULT docker bridge with
// `-p 0.0.0.0:3000:3000` (ci-deploy.sh — NOT `--network host`), so a HOST-side
// `curl 127.0.0.1:3000/internal/readyz` arrives with the docker bridge gateway
// (e.g. 172.17.0.1) as its peer, NOT loopback → 403. The on-host ops probes fix
// this by running INSIDE the container (`docker exec … curl 127.0.0.1:3000/...`,
// see workspaces-luks-emit.sh:wl_probe_readyz), where the peer is a genuine
// 127.0.0.1. Do NOT "simplify" by widening isLoopbackPeer to accept the bridge
// gateway: under docker's default userland-proxy the gateway is ALSO the source
// of genuine off-host traffic through the published port, so accepting it would
// collapse this boundary to the attacker-controlled Host header alone.
//
// FAIL CLOSED: the ENTIRE body (gate included) is wrapped so any throw becomes a
// 503, never an escaped uncaught throw → installCrashHandlers() → process.exit(1),
// which would *restart* live web-1 (strictly worse than a 503). `build` is
// injectable purely for testing the catch path; production callers use the default.
export function handleReadyzRequest(
  req: IncomingMessage,
  res: ServerResponse,
  build: () => ReadinessResponse = buildReadinessResponse,
): void {
  try {
    const peerLoopback = isLoopbackPeer(req.socket?.remoteAddress);
    if (!peerLoopback || !isLoopbackHost(req.headers.host)) {
      res.writeHead(403, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "forbidden" }));
      return;
    }
    const readiness = build();
    res.writeHead(readiness.ready ? 200 : 503, {
      "Content-Type": "application/json",
    });
    res.end(JSON.stringify(readiness));
  } catch {
    if (!res.headersSent) {
      res.writeHead(503, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          ready: false,
          checks: { workspaces_writable: false, workspaces_populated: false },
        }),
      );
    }
  }
}

// Latched one-shot boot-time readiness check. verifyPluginMountOnce covers the
// PLUGIN mount, NOT /workspaces (it passes on a bare volume), so a mis-mounted /
// read-only web-1 would otherwise be invisible until a request hit it. This is
// the async/push observability layer the pull-only readyz endpoint lacks: one
// Sentry event at boot, no LB-poll flood. Latched so repeat calls do not flap.
let _bootChecked = false;
export function verifyWorkspacesMountOnce(): void {
  if (_bootChecked) return;
  _bootChecked = true;
  const r = buildReadinessResponse();
  if (!r.ready) {
    reportSilentFallback(null, {
      feature: "workspaces-mount",
      op: "boot-readiness",
      message: "workspaces not ready at boot",
      extra: { checks: r.checks, workspacesRoot: getWorkspacesRoot() },
    });
  }
}
