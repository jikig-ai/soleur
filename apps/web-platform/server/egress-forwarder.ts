// feat-open-web-egress (#9534) — per-dispatch localhost forwarder lifecycle.
//
// The Squid CONNECT gateway lives on the soleur-egress0 bridge and requires
// a per-session token (`<token-file>` exists under the ro-mounted token dir).
// Sandbox Runtime only chains to a host-side loopback proxy — measured in
// the Phase-0 spike (spec TR7): the sandboxed child runs in its own netns
// and cannot dial the container loopback; its traffic reaches the forwarder
// only via SRT's in-netns proxy → upstream chain, which presents the
// spawned-CLI env's `HTTP_PROXY` URL credentials upstream verbatim. The
// forwarder therefore also authenticates inbound callers: the session token
// rides the proxy-URL password, so only the subprocess holding this
// session's env can use this port.
//
// Lifecycle: spawned per cold dispatch (`realSdkQueryFactory`), killed on
// every close path (`handleCcCloseQuery`), and force-killed on a warm-path
// entitlement re-resolve that flips false (toggle-off revokes live access —
// the toggle copy promises exactly that). The forwarder additionally carries
// a ppid watchdog so a dispatcher crash orphans nothing; the startup reaper
// below covers the ppid-reparent hole (a dead dispatcher's forwarder gets
// reparented to init, so the watchdog's ppid probe still resolves — reaping
// is the only teardown that survives a full process restart).

import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("egress-forwarder");

/** Host-side dir shared with the gateway (ro-mounted there). Lazy-read so
 *  tests can point EGRESS_TOKEN_DIR at a tmpdir. */
function egressTokenDir(): string {
  return process.env.EGRESS_TOKEN_DIR ?? "/var/lib/soleur/egress-tokens";
}
/** Baked into the image by PR-A (Dockerfile COPY infra/egress-forwarder.mjs
 *  → /app/infra/egress-forwarder.mjs). The default is cwd-relative
 *  (process.cwd() = /app in the image, apps/web-platform in dev/test) — an
 *  absolute literal here gets statically traced by Turbopack as a module to
 *  bundle and fails the production build ("Can't resolve '/app/infra/…'").
 *  Lazy-read for the same test-override reason. */
function forwarderPath(): string {
  return (
    process.env.EGRESS_FORWARDER_PATH ??
    join(process.cwd(), "infra", "egress-forwarder.mjs")
  );
}
/** How long to wait for the forwarder's `egress-forwarder-listening <port>` line. */
const READY_TIMEOUT_MS = 5_000;

export interface EgressForwarderHandle {
  /** Kernel-assigned loopback port the CLI subprocess must proxy through. */
  port: number;
  /** The session token — inbound auth for the forwarder and the gateway. */
  token: string;
  /** Forwarder pid, for the per-dispatch entitlement log. */
  pid: number;
}

interface RegistryEntry extends EgressForwarderHandle {
  proc: ChildProcess;
}

/** conversationId → live forwarder. One forwarder per conversation (a Query
 *  spans many turns; the entitlement is per-session, not per-dispatch). */
const egressForwarders = new Map<string, RegistryEntry>();

/** Test/QA hook: is a forwarder registered for this conversation? */
export function hasEgressForwarder(conversationId: string): boolean {
  return egressForwarders.has(conversationId);
}

/**
 * Mint a session token, write its token file (that's what makes the gateway
 * accept it), spawn the forwarder bound to 127.0.0.1:0, and read the
 * kernel-assigned port back from stdout. Throws on ANY step failure — the
 * caller degrades `allowWebEgress` to false rather than emit a dead config.
 */
export async function spawnEgressForwarder(
  conversationId: string,
  workspaceId: string,
): Promise<EgressForwarderHandle> {
  // base64url: filename-safe AND header-safe — the token is a token-dir
  // filename on one side and a proxy-URL password on the other.
  const token = randomBytes(24).toString("base64url");
  mkdirSync(egressTokenDir(), { recursive: true, mode: 0o700 });
  // The gateway's auth helper checks <dir>/<password> exists — the file's
  // existence IS the credential validity window. Mode 0600: container-root
  // only; the sandboxed agent reads neither the dir nor the file
  // (denyRead covers the mount point on the entitled session).
  writeFileSync(join(egressTokenDir(), token), `${workspaceId}\n`, {
    mode: 0o600,
  });

  const env: NodeJS.ProcessEnv = {
    PATH: process.env.PATH ?? "/usr/local/bin:/usr/bin:/bin",
    NODE_ENV: process.env.NODE_ENV,
    EGRESS_SESSION_TOKEN: token,
    EGRESS_WORKSPACE_ID: workspaceId,
  };
  const proc: ChildProcess = spawn("node", [forwarderPath()], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });

  const entry: RegistryEntry = { proc, token, port: 0, pid: proc.pid ?? 0 };
  egressForwarders.set(conversationId, entry);

  // Mid-session forwarder death = live egress silently dead for the
  // entitled session. Mirror to Sentry (the session continues zero-egress —
  // same fail-closed shape as a spawn failure, just later).
  proc.on("exit", (code, signal) => {
    if (egressForwarders.get(conversationId)?.proc === proc) {
      log.warn(
        {
          feature: "egress-forwarder",
          op: "forwarder-exit",
          conversationId,
          workspaceId,
          port: entry.port,
          code,
          signal,
        },
        "egress-forwarder exited mid-session",
      );
      // Expected teardown kills the proc AFTER deleting the registry entry,
      // so reaching this branch means an unexpected exit — mirror it.
      reportSilentFallback(new Error("egress forwarder exited mid-session"), {
        feature: "egress-forwarder",
        op: "forwarder-exit",
        extra: { conversationId, workspaceId, port: entry.port, code, signal },
      });
    }
  });

  try {
    entry.port = await new Promise<number>((resolve, reject) => {
      let settled = false;
      const fail = (err: unknown) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(err);
        }
      };
      const timer = setTimeout(
        () => fail(new Error("egress forwarder did not report a bound port")),
        READY_TIMEOUT_MS,
      );
      let buf = "";
      proc.stdout!.on("data", (d: Buffer) => {
        buf += d.toString("utf8");
        const m = /egress-forwarder-listening (\d+)/.exec(buf);
        if (m && !settled) {
          settled = true;
          clearTimeout(timer);
          resolve(Number(m[1]));
        }
      });
      proc.once("error", fail);
      proc.once("exit", (code) =>
        fail(new Error(`egress forwarder exited before bind (code ${code})`)),
      );
      proc.stderr!.on("data", (d: Buffer) => {
        // Forwarder stderr is operational chatter (never the token) — log it
        // so a bind failure is diagnosable, at debug volume.
        log.debug(
          {
            feature: "egress-forwarder",
            op: "stderr",
            conversationId,
            line: d.toString("utf8").trim(),
          },
          "egress-forwarder stderr",
        );
      });
    });
  } catch (err) {
    egressForwarders.delete(conversationId);
    proc.kill();
    rmSync(join(egressTokenDir(), token), { force: true });
    throw err;
  }

  return { port: entry.port, token, pid: entry.pid };
}

/**
 * Kill a conversation's forwarder and delete its token file (the file is the
 * gateway-side validity window — deleting it revokes even a late replay).
 * Idempotent + fail-open: teardown must never throw into a close path.
 */
export function teardownEgressForwarder(conversationId: string): void {
  const entry = egressForwarders.get(conversationId);
  if (!entry) return;
  egressForwarders.delete(conversationId);
  try {
    entry.proc.kill("SIGTERM");
  } catch (err) {
    reportSilentFallback(err, {
      feature: "egress-forwarder",
      op: "teardown-kill",
      extra: { conversationId, pid: entry.pid },
    });
  }
  try {
    rmSync(join(egressTokenDir(), entry.token), { force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "egress-forwarder",
      op: "teardown-token",
      extra: { conversationId },
    });
  }
}

/**
 * Dispatcher-startup orphan reaper. A dispatcher restart reparents a live
 * forwarder to init, so the forwarder's own ppid watchdog keeps passing —
 * the reaper is the only teardown that survives a full process restart.
 * Kill every egress-forwarder.mjs process not in the live registry and
 * remove every token file not in the registry. Called once at dispatcher
 * startup, when the registry is definitionally empty. Best-effort + never
 * throws.
 */
export function reapOrphanEgressForwarders(): void {
  const liveTokens = new Set(
    Array.from(egressForwarders.values(), (e) => e.token),
  );
  const livePids = new Set(
    Array.from(egressForwarders.values(), (e) => e.pid),
  );

  // Kill stray forwarder processes (cmdline match — the platform's own proc
  // tree, not an in-sandbox /proc read).
  try {
    for (const pidEntry of readdirSync("/proc")) {
      if (!/^\d+$/.test(pidEntry)) continue;
      const pid = Number(pidEntry);
      if (livePids.has(pid) || pid === process.pid) continue;
      let cmdline = "";
      try {
        cmdline = readFileSync(`/proc/${pid}/cmdline`, "latin1");
      } catch {
        continue;
      }
      if (!cmdline.includes("egress-forwarder.mjs")) continue;
      try {
        process.kill(pid, "SIGTERM");
        log.info(
          { feature: "egress-forwarder", op: "reap", pid },
          "egress-forwarder: reaped orphan process",
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "egress-forwarder",
          op: "reap-kill",
          extra: { pid },
        });
      }
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "egress-forwarder",
      op: "reap-scan",
    });
  }

  // Remove stale token files. The file's existence is the gateway-side
  // validity window — a stale file would keep a dead session's credential
  // valid until the next cleanup.
  try {
    for (const f of readdirSync(egressTokenDir())) {
      if (liveTokens.has(f)) continue;
      rmSync(join(egressTokenDir(), f), { force: true });
      log.info(
        { feature: "egress-forwarder", op: "reap-token", tokenFile: f.length },
        "egress-forwarder: removed stale token file",
      );
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "egress-forwarder",
      op: "reap-tokens",
    });
  }
}
