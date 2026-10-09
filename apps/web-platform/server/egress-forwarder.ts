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
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { connect as netConnect } from "node:net";
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
    join(/* turbopackIgnore: true */ process.cwd(), "infra", "egress-forwarder.mjs")
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
  /** The workspace the entitlement (and token) was minted for — the warm-path
   *  re-resolve must key on THIS, not the user's current active workspace. */
  workspaceId: string;
}

/** conversationId → live forwarder. One forwarder per conversation (a Query
 *  spans many turns; the entitlement is per-session, not per-dispatch). */
const egressForwarders = new Map<string, RegistryEntry>();

/** Test/QA hook: is a forwarder registered for this conversation? */
export function hasEgressForwarder(conversationId: string): boolean {
  return egressForwarders.has(conversationId);
}

/** The workspace a live forwarder was minted for (undefined when none). */
export function egressForwarderWorkspaceId(
  conversationId: string,
): string | undefined {
  return egressForwarders.get(conversationId)?.workspaceId;
}

/** Gateway dial target. The bootstrap collision-probes 172.31.100-103.0/24
 *  and publishes the winner to `<token dir>/.gw-target` ("host:port") — the
 *  shared dir is already the app's rw / gateway's ro channel, so no new mount
 *  is needed. Env vars override (tests); the file beats the hardcoded default
 *  so a fallback-subnet host never dials a phantom. */
function egressGwTarget(): { host: string; port: number } {
  if (process.env.EGRESS_GW_HOST || process.env.EGRESS_GW_PORT) {
    return {
      host: process.env.EGRESS_GW_HOST ?? "172.31.100.2",
      port: Number(process.env.EGRESS_GW_PORT ?? 8443),
    };
  }
  try {
    const line = readFileSync(
      join(egressTokenDir(), ".gw-target"),
      "utf8",
    ).trim();
    const m = /^([0-9.]+):([0-9]+)$/.exec(line);
    if (m) return { host: m[1], port: Number(m[2]) };
  } catch {
    /* absent/unreadable → fall through to the pinned default */
  }
  return { host: "172.31.100.2", port: 8443 };
}

/** Fail-fast liveness probe: an entitled session on a host whose gateway is
 *  down or absent must degrade to zero-egress at spawn, not discover it on
 *  the first CONNECT (silent dead egress under a paid entitlement). A bare
 *  TCP connect is enough — the forwarder's own dial is the same transport. */
function assertGatewayReachable(host: string, port: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const sock = netConnect({ host, port, timeout: 2_000 }, () => {
      sock.destroy();
      resolve();
    });
    const fail = () => {
      sock.destroy();
      reject(new Error(`egress gateway unreachable at ${host}:${port}`));
    };
    sock.once("error", fail);
    sock.once("timeout", fail);
  });
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
  // A second spawn for the same conversation (supersede / stale-resume edge)
  // must not orphan the first child and its still-valid token file.
  teardownEgressForwarder(conversationId);

  // Dead gateway = fail fast (the caller degrades to zero-egress) instead of
  // logging "forwarder bound" for a session whose every CONNECT dies at the
  // gw dial. This runs BEFORE the token file is minted — a probe throw must
  // not orphan a live gateway credential outside the registry (the teardown
  // path only reaches entries that were registered).
  const gw = egressGwTarget();
  await assertGatewayReachable(gw.host, gw.port);

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
    EGRESS_GW_HOST: gw.host,
    EGRESS_GW_PORT: String(gw.port),
  };
  let proc: ChildProcess;
  try {
    proc = spawn(process.execPath, [forwarderPath()], {
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (err) {
    // A spawn throw leaves the minted token file un-registered — delete it;
    // existence IS the gateway credential.
    rmSync(join(egressTokenDir(), token), { force: true });
    throw err;
  }

  const entry: RegistryEntry = {
    proc,
    token,
    port: 0,
    pid: proc.pid ?? 0,
    workspaceId,
  };
  egressForwarders.set(conversationId, entry);

  // Mid-session forwarder death = live egress silently dead for the
  // entitled session. Mirror to Sentry (the session continues zero-egress —
  // same fail-closed shape as a spawn failure, just later).
  proc.on("exit", (code, signal) => {
    if (egressForwarders.get(conversationId)?.proc === proc) {
      egressForwarders.delete(conversationId);
      // Delete the orphaned token file too — existence IS the gateway
      // credential; don't leave it valid for a listener that no longer
      // exists.
      try {
        rmSync(join(egressTokenDir(), entry.token), { force: true });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "egress-forwarder",
          op: "exit-token-cleanup",
          extra: { conversationId },
        });
      }
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
      let buf = "";
      const onStdout = (d: Buffer) => {
        buf += d.toString("utf8");
        const m = /egress-forwarder-listening (\d+)/.exec(buf);
        if (m && !settled) {
          settled = true;
          clearTimeout(timer);
          // The child emits exactly one line — drop the handler so later
          // stdout noise doesn't accumulate `buf` for the child's life.
          proc.stdout!.off("data", onStdout);
          resolve(Number(m[1]));
        }
      };
      const fail = (err: unknown) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          proc.stdout!.off("data", onStdout);
          reject(err);
        }
      };
      const timer = setTimeout(
        () => fail(new Error("egress forwarder did not report a bound port")),
        READY_TIMEOUT_MS,
      );
      proc.stdout!.on("data", onStdout);
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
    // Identity-guard: a superseded spawn's reject must not delete the newer
    // registry entry (concurrent-spawn race — same conversationId).
    if (egressForwarders.get(conversationId)?.proc === proc) {
      egressForwarders.delete(conversationId);
    }
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
  // tree, not an in-sandbox /proc read). /proc is Linux-only — macOS dev
  // boots have no reaper to run (the ppid watchdog still covers the local
  // kill path there). Topology note: this scan assumes ONE dispatcher per
  // pid namespace — under an in-container rolling restart it would reap a
  // draining dispatcher's live forwarders (deployment is one app container
  // per host, and a PID-1 dispatcher death takes the namespace with it).
  try {
    for (const pidEntry of existsSync("/proc") ? readdirSync("/proc") : []) {
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
  // valid until the next cleanup. No dir = nothing to reap (dev/test hosts
  // never create it — skip without emitting a Sentry mirror).
  if (!existsSync(egressTokenDir())) return;
  try {
    for (const f of readdirSync(egressTokenDir())) {
      // Dotfiles are not tokens — `.gw-target` is the bootstrap's published
      // gateway address and must survive the sweep.
      if (f.startsWith(".") || liveTokens.has(f)) continue;
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
