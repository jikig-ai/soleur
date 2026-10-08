// Outer per-session filesystem wrap for the whole `claude` CLI child
// (#5863, ADR-075 Option B — arm F per the 2026-10-08 spike).
//
// Why this exists: the inner SDK sandbox (buildAgentSandboxConfig + the
// vendored bwrap argv) only bounds per-Bash tool calls. The file tools
// (Read/Write/Edit/Glob/Grep/LS/Notebook*) execute inside the CLI process
// under the in-process realpath hook — unbounded by any mount table. The
// #5862 deny-then-restore masks sibling workspace *content* inside the
// inner sandbox, but sibling *existence* stays observable via stat/mount
// tables, and the file-tool tier sees the full container fs regardless.
// Wrapping the CLI process itself moves the boundary up one level: the
// session's mount namespace never contains sibling workspaces at all.
//
// Arm F shape (measured, spike table in the plan): a MOUNT-NAMESPACE-ONLY
// wrap. Zero `--unshare-*` flags — the vendored inner sandbox unconditionally
// unshares user+pid+net, and nested creation requires the outer userns to own
// those namespaces, which would require outer --unshare-pid (no mountable
// scoped procfs under Docker masked paths — bubblewrap#284) and outer
// --unshare-net (kills CLI egress). Instead bwrap runs in privileged mode
// via file capabilities (`cap_sys_admin+ep` baked in the Dockerfile, cap kept
// in the container bounding set by `--cap-add SYS_ADMIN` at docker run); the
// CLI child post-exec carries only the caller's cap set.
//
// Residuals this does NOT close (tracked): shared container /proc — sibling
// PIDs and `/proc/<pid>/environ` stay visible (#9723); container loopback
// incl. delegated-egress cross-use through sibling socat proxies; abstract
// unix sockets; server-side cross-tenant fs; shared in-process heap (#9773).

import { spawn } from "node:child_process";
import { accessSync, constants, existsSync, realpathSync } from "node:fs";
import path from "node:path";
import { Readable, Writable } from "node:stream";

import type {
  SpawnOptions,
  SpawnedProcess,
} from "@anthropic-ai/claude-agent-sdk";

import { createChildLogger } from "./logger";

const log = createChildLogger("agent-outer-wrap");

/** Real bwrap — never PATH-resolved: the #8752 PATH shim's NEWUSER-deny
 *  filter exists to reject the *inner* sandbox's argv, not to wrap ours. */
export const BWRAP_PATH = "/usr/bin/bwrap";

export interface OuterWrapInputs {
  /** Tenant workspace, bound rw at its real path — the ONLY entry under the
   *  workspaces parent the session ever sees. Omitted for the support
   *  persona (cwd is the plugin root; nothing under the workspaces root is
   *  bound at all). */
  workspacePath?: string;
  /** Session cwd when different from workspacePath (support: pluginPath). */
  cwd?: string;
  /** Session id — log/telemetry only. */
  sessionId?: string;
  /** Deployed plugin root (read-only; the session's CLAUDE_PLUGIN_ROOT). */
  pluginPath?: string;
  /**
   * Override for the platform app root that owns `node_modules` + `infra/`
   * (prod: `/app`). Tests pass a fixture root; the support persona gets the
   * same minimal binds — `knowledge-base/` is never bound for anyone.
   */
  appRoot?: string;
  /**
   * The session $HOME (prod: `/home/soleur`). The wrap creates an empty
   * `--dir` home and narrow-binds only what the CLI needs: the cwd-keyed
   * transcript subtree and the config/credentials files. Sibling tenants'
   * `projects/` slugs are never bound.
   */
  home?: string;
  /** Existence-check override for tests (defaults to fs probes). */
  exists?: (p: string) => boolean;
}

const APP_ROOT = "/app";

/** `~/.claude` entries that carry no tenant data — bound rw so the CLI's
 *  auth refresh / settings writes keep working. `projects/` is deliberately
 *  excluded: it is bound per-slug (below) so sibling transcripts never
 *  appear. Session-scoped dirs (todos/, shell-snapshots/, statsig/, ...)
 *  get fresh `--dir`s — they are per-session state and need no persistence. */
const HOME_STATE_FILES = [".credentials.json", "settings.json"] as const;
const HOME_SESSION_DIRS = [
  "todos",
  "shell-snapshots",
  "statsig",
  "backups",
  "debug",
  "history",
  "file-history",
] as const;

/** The CLI's transcript dir encoding: cwd path with `/` → `-`. */
function claudeProjectSlug(cwd: string): string {
  return cwd.replaceAll("/", "-");
}

function req(p: string, what: string): string {
  // realpathSync both canonicalizes (one value feeds bind source + dest +
  // --chdir + the file-tool hook — no symlink divergence) and fail-closes
  // on a missing source.
  try {
    return realpathSync(p);
  } catch {
    throw new Error(`agent-outer-wrap: required ${what} missing: ${p}`);
  }
}

/**
 * The outer bwrap argv for one session. Pure-ish: it reads the filesystem
 * only to resolve/verify bind sources; emitted flags are deterministic for a
 * given input set. Zero `--unshare-*`, zero secrets on argv (the credential
 * set rides the spawn env — `--setenv KEY=val` would land on
 * `/proc/<pid>/cmdline`, same-uid readable).
 */
export function buildOuterWrapArgv(inputs: OuterWrapInputs): string[] {
  const exists = inputs.exists ?? existsSync;
  const argv: string[] = ["--die-with-parent", "--new-session"];

  // Merged-usr layout + system image (ro). The minimal /etc set covers
  // resolver + TLS + user lookups; directories go via --ro-bind, files via
  // --ro-bind too (bind works for both; --file needs an fd).
  argv.push("--symlink", "usr/bin", "/bin");
  argv.push("--symlink", "usr/sbin", "/sbin");
  argv.push("--symlink", "usr/lib", "/lib");
  argv.push("--symlink", "usr/lib64", "/lib64");
  argv.push("--ro-bind", req("/usr", "system image"), "/usr");
  for (const f of [
    "resolv.conf",
    "hosts",
    "nsswitch.conf",
    "passwd",
    "group",
    "hostname",
  ]) {
    const src = `/etc/${f}`;
    if (exists(src)) argv.push("--ro-bind", src, src);
  }
  for (const d of ["ssl", "terminfo"]) {
    const src = `/etc/${d}`;
    if (exists(src)) argv.push("--ro-bind", src, src);
  }
  argv.push("--dev", "/dev");
  // Shared container procfs — intentional (arm F): a scoped procfs needs a
  // pidns, and the pidns is measured-incompatible with the inner sandbox.
  // #9723 stays an open residual.
  argv.push("--bind", "/proc", "/proc");
  argv.push("--tmpfs", "/tmp");

  const appRoot = inputs.appRoot ?? APP_ROOT;
  if (exists(appRoot)) {
    // node_modules + infra only — the vendored CLI tree, its deps, and the
    // inner shim's bpf artifact. `/app/shared/knowledge-base` is absent by
    // construction for every persona (better than today's deny-mask).
    for (const sub of ["node_modules", "infra", "dist", "package.json"]) {
      const src = path.join(appRoot, sub);
      if (exists(src)) argv.push("--ro-bind", src, src);
    }
  }
  if (inputs.pluginPath) {
    argv.push("--ro-bind", req(inputs.pluginPath, "pluginPath"), inputs.pluginPath);
  }

  // Home: empty dir + narrow binds. The transcript subtree is keyed by the
  // CLI's project-slug of the session cwd — already tenant-scoped.
  const home = inputs.home ?? "/home/soleur";
  const claudeHome = path.join(home, ".claude");
  argv.push("--dir", home);
  argv.push("--dir", claudeHome);
  argv.push("--dir", path.join(claudeHome, "projects"));
  for (const d of HOME_SESSION_DIRS) {
    argv.push("--dir", path.join(claudeHome, d));
  }
  for (const f of HOME_STATE_FILES) {
    const src = path.join(claudeHome, f);
    if (exists(src)) argv.push("--bind", src, src); // rw — credential refresh writes
  }
  for (const f of [".claude.json"]) {
    const src = path.join(home, f);
    if (exists(src)) argv.push("--bind", src, src);
  }

  // The tenant workspace — bound rw at its real path (the parent is never
  // mounted; bwrap creates intermediate dirs). Support persona omits it.
  const ws = inputs.workspacePath ? req(inputs.workspacePath, "workspacePath") : undefined;
  const cwd = inputs.cwd ? req(inputs.cwd, "cwd") : ws;
  if (ws) {
    const slug = claudeProjectSlug(ws);
    const transcriptDir = path.join(claudeHome, "projects", slug);
    if (exists(transcriptDir)) argv.push("--bind", transcriptDir, transcriptDir);
    argv.push("--bind", ws, ws);

    // A linked-worktree `.git` gitfile points outside the workspace; the
    // target gitdir must be bound rw or every git op fails.
    const gitFile = path.join(ws, ".git");
    if (exists(gitFile)) {
      const st = realpathSync(gitFile);
      if (st !== gitFile && exists(st)) argv.push("--bind", st, st);
    }
  }

  if (cwd) argv.push("--chdir", cwd);
  argv.push("--");
  return argv;
}

/** Where the wrap's stderr tail goes when spawn/exec fails. The SDK's
 *  SpawnedProcess carries no stderr channel — we keep a bounded ring and
 *  attach it to emitted errors so `classifySandboxStartupError` still sees
 *  its marker strings. */
const STDERR_RING_BYTES = 64 * 1024;

class StderrRing {
  private chunks: Buffer[] = [];
  private size = 0;
  push(b: Buffer) {
    this.chunks.push(b);
    this.size += b.length;
    while (this.size > STDERR_RING_BYTES && this.chunks.length) {
      const drop = this.chunks[0];
      const over = this.size - STDERR_RING_BYTES;
      if (over >= drop.length) {
        this.size -= drop.length;
        this.chunks.shift();
      } else {
        this.chunks[0] = drop.subarray(over);
        this.size -= over;
      }
    }
  }
  tail(): string {
    return Buffer.concat(this.chunks).toString("utf8");
  }
}

/**
 * Preflight: every bind source + the CLI command must exist BEFORE spawn —
 * a natural ENOENT can hang `query()` (sdk-ts#255), so we return a
 * synthetic already-failed process instead of a dead child.
 */
function preflight(command: string, argv: string[]): string | null {
  try {
    accessSync(BWRAP_PATH, constants.X_OK);
  } catch {
    return `bwrap_missing:${BWRAP_PATH}`;
  }
  try {
    accessSync(command, constants.X_OK);
  } catch {
    return `command_missing:${command}`;
  }
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--") break;
    if (
      flag === "--bind" ||
      flag === "--ro-bind" ||
      flag === "--dev-bind" ||
      flag === "--file"
    ) {
      const src = argv[i + 1];
      if (src && !src.startsWith("--") && !existsSync(src)) {
        return `bind_source_missing:${src}`;
      }
      i += flag === "--file" ? 2 : 1;
    }
  }
  return null;
}

/** A SpawnedProcess that is already dead — for fail-closed construction
 *  errors. Emits `error` then `exit(127)` on nextTick so consumers see the
 *  classified failure, never a hang. */
function syntheticFailedProcess(marker: string): SpawnedProcess {
  const listeners = { exit: [] as Array<(...a: unknown[]) => void>, error: [] as Array<(...a: unknown[]) => void> };
  const proc: SpawnedProcess = {
    stdin: new Writable({ write(_c, _e, cb) { cb(); } }),
    stdout: new Readable({ read() { this.push(null); } }),
    get killed() { return true; },
    get exitCode() { return 127; },
    kill: () => true,
    on(event: "exit" | "error", listener: never) {
      (listeners[event] as Array<never>).push(listener);
      return proc;
    },
    once(event: "exit" | "error", listener: never) {
      (listeners[event] as Array<never>).push(listener);
      return proc;
    },
    off() { return proc; },
  } as SpawnedProcess;
  queueMicrotask(() => {
    for (const l of listeners.error) (l as (e: Error) => void)(new Error(marker));
    for (const l of listeners.exit) (l as (c: number | null, s: null) => void)(127, null);
  });
  return proc;
}

/**
 * The `spawnClaudeCodeProcess` interpose. Returns a factory: given the
 * session's wrap inputs it produces the Options-level spawn function.
 * The wrap argv is built once per dispatch (the session keeps its birth
 * mount table — no mid-session flag flips).
 */
export function makeSandboxedSpawn(
  inputs: OuterWrapInputs,
): (options: SpawnOptions) => SpawnedProcess {
  const wrapArgv = buildOuterWrapArgv(inputs);
  log.info(
    {
      op: "tenant-outer-wrap",
      sessionId: inputs.sessionId,
      workspace: inputs.workspacePath,
      mounts: wrapArgv.length,
    },
    "outer wrap argv built",
  );
  return (options: SpawnOptions): SpawnedProcess => {
    const fail = preflight(options.command, wrapArgv);
    if (fail) {
      log.warn(
        { op: "tenant-outer-wrap", sessionId: inputs.sessionId, outcome: fail },
        "outer wrap spawn refused",
      );
      return syntheticFailedProcess(fail);
    }
    // Env composition: options.env verbatim (it is already the allowlisted
    // buildAgentEnv output — secrets ride env, never argv) + TMPDIR pinned
    // to the session tmpfs. undefined values dropped.
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(options.env)) {
      if (v !== undefined) env[k] = v;
    }
    env.TMPDIR = "/tmp";

    const stderrRing = new StderrRing();
    const child = spawn(BWRAP_PATH, [...wrapArgv, options.command, ...options.args], {
      cwd: inputs.cwd ?? inputs.workspacePath,
      env,
      detached: true, // own pgid → kill(-pid) reaches the whole tree
      stdio: ["pipe", "pipe", "pipe"],
    });
    // stderr must drain continuously or the child blocks at ~64 kB.
    child.stderr?.on("data", (b: Buffer) => stderrRing.push(b));
    const ringTail = () => stderrRing.tail();

    const spawned: SpawnedProcess = {
      stdin: child.stdin as Writable,
      stdout: child.stdout as Readable,
      get killed() { return child.killed; },
      get exitCode() { return child.exitCode; },
      get signalCode() { return child.signalCode; },
      kill(signal: NodeJS.Signals): boolean {
        try {
          return process.kill(-child.pid!, signal);
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code === "ESRCH") return true; // already gone
          return child.kill(signal);
        }
      },
      on(event: "exit" | "error", listener: never): SpawnedProcess {
        if (event === "exit") {
          child.on("exit", (code, signal) => {
            const tail = ringTail();
            if (code !== 0 && tail) {
              log.warn(
                { op: "tenant-outer-wrap", sessionId: inputs.sessionId, outcome: `exit:${code}`, stderrTail: tail.slice(-2000) },
                "outer wrap child exited non-zero",
              );
            }
            (listener as (c: number | null, s: NodeJS.Signals | null) => void)(code, signal);
          });
        } else {
          child.on("error", (err: Error) => {
            const tail = ringTail();
            (listener as (e: Error) => void)(
              tail ? new Error(`${err.message}\nstderr: ${tail.slice(-2000)}`) : err,
            );
          });
        }
        return spawned;
      },
      once(event: "exit" | "error", listener: never): SpawnedProcess {
        if (event === "exit") {
          child.once("exit", (code, signal) =>
            (listener as (c: number | null, s: NodeJS.Signals | null) => void)(code, signal),
          );
        } else {
          child.once("error", (err: Error) =>
            (listener as (e: Error) => void)(
              ringTail() ? new Error(`${err.message}\nstderr: ${ringTail().slice(-2000)}`) : err,
            ),
          );
        }
        return spawned;
      },
      off(event: "exit" | "error", listener: never): SpawnedProcess {
        child.off(event as "exit" | "error", listener as never);
        return spawned;
      },
    } as SpawnedProcess;
    return spawned;
  };
}

/** Rollout gate (env, read at dispatch — never module load; the flag is
 *  read per spawn so a flip never re-wraps an in-flight session, it only
 *  affects new ones). Default off. A workspace allowlist
 *  (`AGENT_OUTER_WRAP_WORKSPACES=id1,id2`) cohorts the first rollout. */
export function outerWrapEnabled(workspaceId?: string): boolean {
  if (process.env.AGENT_OUTER_WRAP !== "1") return false;
  const allow = process.env.AGENT_OUTER_WRAP_WORKSPACES;
  if (!allow) return true;
  if (!workspaceId) return false;
  return allow.split(",").map((s) => s.trim()).includes(workspaceId);
}
