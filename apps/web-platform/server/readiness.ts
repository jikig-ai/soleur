import { writeFileSync, unlinkSync } from "fs";
import { join } from "path";
import { randomBytes } from "crypto";
import type { IncomingMessage, ServerResponse } from "http";
import { countWorkspaceDirsAt } from "./session-metrics";
import { reportSilentFallback } from "./observability";

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

// Write+unlink a dotfile probe. The probe is a dotfile AND a file (not a dir),
// so it never inflates the populated count even in the window before unlink.
// FAIL CLOSED on any error.
function isWorkspacesWritable(root: string): boolean {
  const probe = join(root, `.readyz-probe-${randomBytes(6).toString("hex")}`);
  try {
    writeFileSync(probe, "");
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

function isLoopbackPeer(remoteAddress: string | undefined): boolean {
  return (
    remoteAddress === "127.0.0.1" ||
    remoteAddress === "::1" ||
    remoteAddress === "::ffff:127.0.0.1"
  );
}

// Local mirror of index.ts's isLoopbackHost. Kept here (rather than imported
// from index.ts, which imports THIS module → circular) so the readyz handler is
// fully self-contained and unit-testable. Both are trivial pure "is this a
// loopback Host header" checks; the port suffix is stripped so e2e tests that
// hit a non-3000 port still match.
function isLoopbackHostHeader(hostHeader: string | undefined): boolean {
  if (!hostHeader) return false;
  const host = hostHeader.split(":")[0];
  return host === "127.0.0.1" || host === "localhost" || host === "::1";
}

// Handle GET /internal/readyz. Gated to the loopback TRANSPORT PEER
// (socket.remoteAddress — unspoofable off-host) as the primary control, with
// the Host header as a secondary clause; mount/topology state is attacker-
// useful (DoS-tuning, cluster-shape scraping) and the Host header is client-
// supplied. FAIL CLOSED: every path terminates in a JSON response, and the
// try/catch converts any throw to a 503 — an unhandled rejection here would
// reach installCrashHandlers() → process.exit(1), a *restart* of live web-1,
// strictly worse than a 503. `build` is injectable purely for testing the
// catch path; production callers use the default.
export function handleReadyzRequest(
  req: IncomingMessage,
  res: ServerResponse,
  build: () => ReadinessResponse = buildReadinessResponse,
): void {
  const peerLoopback = isLoopbackPeer(req.socket.remoteAddress);
  if (!peerLoopback || !isLoopbackHostHeader(req.headers.host)) {
    res.writeHead(403, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "forbidden" }));
    return;
  }
  try {
    const readiness = build();
    res.writeHead(readiness.ready ? 200 : 503, {
      "Content-Type": "application/json",
    });
    res.end(JSON.stringify(readiness));
  } catch {
    res.writeHead(503, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ready: false, checks: {} }));
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
