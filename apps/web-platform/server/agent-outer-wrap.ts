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
// via file capabilities (`cap_sys_admin,cap_setuid,cap_setgid+ep` baked in
// the Dockerfile, cap kept
// in the container bounding set by `--cap-add SYS_ADMIN` at docker run); the
// CLI child post-exec carries only the caller's cap set.
//
// Residuals this does NOT close (tracked): shared container /proc — sibling
// PIDs and `/proc/<pid>/environ` stay visible (#9723); container loopback
// incl. delegated-egress cross-use through sibling socat proxies; abstract
// unix sockets; server-side cross-tenant fs; shared in-process heap (#9773).

import { spawn, spawnSync } from "node:child_process";
import {
  accessSync,
  constants,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable, Writable } from "node:stream";

import type {
  SpawnOptions,
  SpawnedProcess,
} from "@anthropic-ai/claude-agent-sdk";

import * as Sentry from "@sentry/nextjs";

import { createChildLogger } from "./logger";
import { warnSilentFallback } from "./observability";

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
  /**
   * Override the bwrap binary path (default {@link BWRAP_PATH}). DI seam so
   * tests can exercise the missing-binary fail-closed arm without touching
   * the real `/usr/bin/bwrap`.
   */
  bwrapPath?: string;
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
  // --cap-drop ALL: `--cap-add SYS_ADMIN` on the container put it in the
  // bounding set (the file cap needs it there); on a non-root-USER image
  // Docker may also carry it ambient, which survives exec of any binary
  // without file caps — including the CLI we are about to wrap. Drop the
  // full set so the session can never setns/mount its way back out (the
  // inner sandbox re-acquires whatever it needs inside ITS own userns).
  const argv: string[] = ["--die-with-parent", "--new-session", "--cap-drop", "ALL"];

  // Merged-usr layout + system image (ro). The minimal /etc set covers
  // resolver + TLS + user lookups; directories go via --ro-bind, files via
  // --ro-bind too (bind works for both; --file needs an fd).
  argv.push("--symlink", "usr/bin", "/bin");
  argv.push("--symlink", "usr/sbin", "/sbin");
  argv.push("--symlink", "usr/lib", "/lib");
  argv.push("--symlink", "usr/lib64", "/lib64");
  argv.push("--ro-bind", req("/usr", "system image"), "/usr");
  // Optional platform files: --ro-bind-try (bind-what-exists) keeps the argv
  // host-STABLE — the committed fixture must be a pure function of the
  // builder, and the /etc set varies per distro (Guard-2 host-dependence,
  // review P1). Missing source is simply skipped by bwrap.
  for (const f of [
    "resolv.conf",
    "hosts",
    "nsswitch.conf",
    "passwd",
    "group",
    "hostname",
    "ssl",
    "terminfo",
  ]) {
    argv.push("--ro-bind-try", `/etc/${f}`, `/etc/${f}`);
  }
  argv.push("--dev", "/dev");
  // Shared container procfs — intentional (arm F): a scoped procfs needs a
  // pidns, and the pidns is measured-incompatible with the inner sandbox.
  // #9723 stays an open residual.
  argv.push("--bind", "/proc", "/proc");
  argv.push("--tmpfs", "/tmp");

  const appRoot = inputs.appRoot ?? APP_ROOT;
  if (existsSync(appRoot)) {
    // node_modules + infra only — the vendored CLI tree, its deps, and the
    // inner shim's bpf artifact. `/app/shared/knowledge-base` is absent by
    // construction for every persona (better than today's deny-mask).
    // --ro-bind-try: the sub set is optional per layout; argv stays stable.
    for (const sub of ["node_modules", "infra", "dist", "package.json"]) {
      const src = path.join(appRoot, sub);
      argv.push("--ro-bind-try", src, src);
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
  // Mutable tenant-adjacent sources: lstat-reject SYMLINKS — a planted
  // symlink under $HOME would otherwise bind an arbitrary host file rw at
  // the dest (writes land on the target). A skipped bind just means the
  // file is absent in-wrap (the CLI recreates what it needs).
  const notSymlink = (p: string) => {
    try {
      return !lstatSync(p).isSymbolicLink();
    } catch {
      return true; // ENOENT/race → the try-bind tolerates the absent source
    }
  };
  for (const f of HOME_STATE_FILES) {
    const src = path.join(claudeHome, f);
    if (notSymlink(src)) argv.push("--bind-try", src, src); // rw — credential refresh writes; first-boot sessions may lack them
  }
  for (const f of [".claude.json", ".gitconfig"]) {
    const src = path.join(home, f);
    if (notSymlink(src)) argv.push("--bind-try", src, src);
  }

  // The tenant workspace — bound rw at its real path (the parent is never
  // mounted; bwrap creates intermediate dirs). Support persona omits it.
  const ws = inputs.workspacePath ? req(inputs.workspacePath, "workspacePath") : undefined;
  const cwd = inputs.cwd ? req(inputs.cwd, "cwd") : ws;
  if (ws) {
    const slug = claudeProjectSlug(ws);
    const transcriptDir = path.join(claudeHome, "projects", slug);
    // Existence-gated (unlike the fixed-name home files): the slug encodes
    // the absolute ws path — an unconditional try-bind would make argv vary
    // per tmpdir name and un-pin the fixture. Still lstat-rejects symlinks.
    if (existsSync(transcriptDir) && notSymlink(transcriptDir)) {
      argv.push("--bind-try", transcriptDir, transcriptDir);
    }
    argv.push("--bind", ws, ws);

    // `.git` external-target binds are deliberately ABSENT (review P0): the
    // `.git` content is tenant-controlled — a `gitdir:` pointer or symlink
    // resolving outside the workspace would bind an arbitrary host path rw
    // into the wrap (shadowing the narrow credential binds). No legitimate
    // escaping shape exists: platform readiness heals stranding pointers by
    // re-clone (#5733, ensure-workspace-repo.ts), agent-made worktrees under
    // the workspace resolve inside the ws bind, and submodule pointers land
    // under `<ws>/.git/modules/` — all inside the workspace bind. A
    // stranding shape that reaches the wrap fails git loudly at first op,
    // same as it does un-wrapped.
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
function preflight(bwrapPath: string, command: string, argv: string[]): string | null {
  try {
    accessSync(bwrapPath, constants.X_OK);
  } catch {
    return `bwrap_missing:${bwrapPath}`;
  }
  try {
    accessSync(command, constants.X_OK);
  } catch {
    return `command_missing:${command}`;
  }
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--") break;
    // Strict binds only — the builder emits no --file/--dev-bind (and
    // --file's arg order is fd-first, so indexing it by src would mis-read).
    // --ro-bind-try/--bind-try tolerate a missing source by design; consume
    // the pair without the existence check.
    if (flag === "--bind-try" || flag === "--ro-bind-try") {
      i += 1;
      continue;
    }
    if (flag === "--bind" || flag === "--ro-bind") {
      const src = argv[i + 1];
      if (src && !src.startsWith("--") && !existsSync(src)) {
        return `bind_source_missing:${src}`;
      }
      i += 1;
    }
  }
  return null;
}

/** A SpawnedProcess that is already dead — for fail-closed construction
 *  errors. Emits `error` then `exit(127)` on nextTick so consumers see the
 *  classified failure, never a hang. */
function syntheticFailedProcess(marker: string): SpawnedProcess {
  const listeners = { exit: [] as Array<(...a: unknown[]) => void>, error: [] as Array<(...a: unknown[]) => void> };
  let fired = false;
  const proc: SpawnedProcess = {
    stdin: new Writable({ write(_c, _e, cb) { cb(); } }),
    stdout: new Readable({ read() { this.push(null); } }),
    get killed() { return true; },
    get exitCode() { return 127; },
    get signalCode() { return null; },
    kill: () => true,
    on(event: "exit" | "error", listener: never) {
      if (fired) {
        // The process already reported — replay to late registrants on
        // nextTick so a post-firing listener never hangs (sdk-ts#255 shape).
        const l = listener as (...a: unknown[]) => void;
        queueMicrotask(() =>
          event === "error"
            ? l(mkErr())
            : l(127, null),
        );
      } else {
        (listeners[event] as Array<never>).push(listener);
      }
      return proc;
    },
    once(event: "exit" | "error", listener: never) {
      return (proc.on as (e: "exit" | "error", l: never) => SpawnedProcess)(event, listener);
    },
    off() { return proc; },
  } as SpawnedProcess;
  const mkErr = () =>
    // The error text deliberately carries the SDK's missing-binary preflight
    // phrase so `classifySandboxStartupError` tags it `missing_binary` at the
    // session catch (feature:agent-sandbox — loud, AC5). A bare marker would
    // classify `other`/`bwrap_error` and miss the missing_binary routing.
    new Error(`sandbox required but unavailable (outer wrap: ${marker})`);
  queueMicrotask(() => {
    fired = true;
    for (const l of listeners.error) (l as (e: Error) => void)(mkErr());
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
  const bwrapPath = inputs.bwrapPath ?? BWRAP_PATH;
  log.info(
    {
      feature: "agent-sandbox",
      op: "tenant-outer-wrap",
      sessionId: inputs.sessionId,
      workspace: inputs.workspacePath,
      argvTokens: wrapArgv.length,
      argv: wrapArgv, // secrets-free by construction (test-pinned — no --setenv)
    },
    "outer wrap argv built",
  );
  // Reprovision-parity (plan T2.1): the bind pins ws's realpath at BUILD
  // time; a workspace reprovision between build and spawn swaps the inode
  // under the same path — the session would bind the REPLACED tree while
  // believing it is the provisioned one. Stat again at spawn and log the
  // drift loudly (report-only — the reprovision itself is upstream's call).
  let birth: { dev: number; ino: number } | undefined;
  try {
    const st = inputs.workspacePath ? statSync(inputs.workspacePath) : undefined;
    if (st) birth = { dev: st.dev, ino: st.ino };
  } catch {
    // stat races a reprovision — undefined birth just skips the parity arm.
  }
  return (options: SpawnOptions): SpawnedProcess => {
    const fail = preflight(bwrapPath, options.command, wrapArgv);
    if (fail) {
      log.warn(
        { feature: "agent-sandbox", op: "tenant-outer-wrap", sessionId: inputs.sessionId, outcome: fail },
        "outer wrap spawn refused",
      );
      return syntheticFailedProcess(fail);
    }
    if (birth && inputs.workspacePath) {
      try {
        const now = statSync(inputs.workspacePath);
        if (now.dev !== birth.dev || now.ino !== birth.ino) {
          warnSilentFallback(null, {
            feature: "agent-sandbox",
            op: "tenant-outer-wrap",
            message:
              "agent sandbox outer-wrap: workspace inode drifted between wrap build and spawn — session binds a reprovisioned tree",
            extra: { sessionId: inputs.sessionId, workspace: inputs.workspacePath },
          });
        }
      } catch {
        // ENOENT mid-reprovision — preflight/first-op reports the absence.
      }
    }
    // Env composition: options.env verbatim (it is already the allowlisted
    // buildAgentEnv output — secrets ride env, never argv) + TMPDIR pinned
    // to the session tmpfs. undefined values dropped.
    // Next augments ProcessEnv with a required NODE_ENV — seed it (the
    // allowlisted options.env entry wins when present).
    const env: NodeJS.ProcessEnv = { NODE_ENV: process.env.NODE_ENV };
    for (const [k, v] of Object.entries(options.env)) {
      if (v !== undefined) env[k] = v;
    }
    env.TMPDIR = "/tmp";

    const stderrRing = new StderrRing();
    // options.cwd is deliberately ignored — the mount table + --chdir are
    // keyed off inputs.cwd/workspacePath; honoring per-spawn cwd could
    // chdir into an unbound path (fail-closed) and is never meaningful here.
    const child = spawn(bwrapPath, [...wrapArgv, options.command, ...options.args], {
      cwd: inputs.cwd ?? inputs.workspacePath,
      env,
      detached: true, // own pgid → kill(-pid) reaches the whole tree
      stdio: ["pipe", "pipe", "pipe"],
    });
    // stderr must drain continuously or the child blocks at ~64 kB.
    child.stderr!.on("data", (b: Buffer) => stderrRing.push(b));
    const ringTail = () => stderrRing.tail();

    // Shared exit/error enrichment for BOTH on/once — whichever method the
    // SDK uses must get identical behavior (obs review P2).
    // A non-zero EXIT with a bwrap signature in the tail is a sandbox-posture
    // failure the SDK classifies "other" (no bwrap token in its synthesized
    // "process exited" error) → untagged at the session catch. Emit the
    // feature:agent-sandbox warn here so the ADR-079 zero-signal amplifier
    // stays closed for flag-on sessions. Signal exits (kill -pgid on Stop /
    // deploy swap / idle reap) are routine — NOT failures: `code` is null
    // there, and `null !== 0` would misreport every abort as a failure.
    // The signature is deliberately narrow — bwrap's own refusal lines, not
    // routine "permission denied" chatter the CLI may print.
    const BWRAP_SIG = /bwrap:|operation not permitted/i;
    const emitExit = (code: number | null, signal: NodeJS.Signals | null) => {
      if (signal != null || code === 0 || code == null) return [code, signal] as const;
      const tail = ringTail();
      if (tail) {
        log.warn(
          { feature: "agent-sandbox", op: "tenant-outer-wrap", sessionId: inputs.sessionId, outcome: `exit:${code}`, stderrTail: tail.slice(-2000) },
          "outer wrap child exited non-zero",
        );
        if (BWRAP_SIG.test(tail)) {
          warnSilentFallback(null, {
            feature: "agent-sandbox",
            op: "tenant-outer-wrap",
            message: `agent sandbox outer-wrap child exited ${code} with bwrap signature`,
            extra: { sessionId: inputs.sessionId, outcome: `exit:${code}` },
          });
        }
      }
      return [code, signal] as const;
    };
    const emitError = (err: Error) => {
      const tail = ringTail();
      return tail ? new Error(`${err.message}\nstderr: ${tail.slice(-2000)}`) : err;
    };

    // wrapper↔caller listener pairs — `off` must remove OUR wrapper, not the
    // caller's listener (which was never registered on the child).
    const wrappers = new Map<never, unknown>();

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
          const w = (code: number | null, signal: NodeJS.Signals | null) => {
            const [c, s] = emitExit(code, signal);
            (listener as (c: number | null, s: NodeJS.Signals | null) => void)(c, s);
          };
          wrappers.set(listener, w);
          child.on("exit", w);
        } else {
          const w = (err: Error) =>
            (listener as (e: Error) => void)(emitError(err));
          wrappers.set(listener, w);
          child.on("error", w);
        }
        return spawned;
      },
      once(event: "exit" | "error", listener: never): SpawnedProcess {
        if (event === "exit") {
          const w = (code: number | null, signal: NodeJS.Signals | null) => {
            const [c, s] = emitExit(code, signal);
            (listener as (c: number | null, s: NodeJS.Signals | null) => void)(c, s);
          };
          wrappers.set(listener, w);
          child.once("exit", w);
        } else {
          const w = (err: Error) =>
            (listener as (e: Error) => void)(emitError(err));
          wrappers.set(listener, w);
          child.once("error", w);
        }
        return spawned;
      },
      off(event: "exit" | "error", listener: never): SpawnedProcess {
        const w = wrappers.get(listener);
        if (w) {
          wrappers.delete(listener);
          child.off(event as never, w as never);
        }
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

// ---------------------------------------------------------------------------
// Realized-isolation boot probe (#5863 T3.2, plan Guard 1)
//
// The deploy canary measures the wrap INSIDE the canary container; this probe
// measures it inside the PROD container at boot — the file-cap'd bwrap posture
// is only known-good once a real namespace has been built on the running host.
// Opt-in (AGENT_OUTER_WRAP_BOOT_PROBE=1): it is a spawn at boot, not per
// session, so it stays behind its own flag even while the rollout flag is off.
// ---------------------------------------------------------------------------

/** The shared isolation payload — the same script the founder check and the
 *  canary replay pipe into `bash -s`. Two layouts: dev
 *  `apps/web-platform/server/../scripts`, prod bundle
 *  `/app/dist/server/../../scripts` → `/app/scripts` (Dockerfile COPY). */
const INNER_PROBE_PATH = ["..", path.join("..", "..")]
  .map((up) =>
    path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      up,
      "scripts",
      "tenant-isolation-inner-probe.sh",
    ),
  )
  .find((p) => existsSync(p));

export interface RealizedIsolationProbe {
  /** The wrap built + the payload ran to a verdict (isolation_ok seen). */
  ok: boolean;
  /** Which bwrap path built the namespace: file-cap'd mountns (`privileged`)
   *  or the implicit-userns fallback (`userns`) — the arm measured fatal to
   *  the inner sandbox in Phase 0, so prod expects `privileged`. */
  elevation?: "privileged" | "userns";
  /** bwrap/payload detail on failure (marker, never full output). */
  reason?: string;
}

/**
 * Build a synthetic two-tenant tree, wrap it with the real argv builder, and
 * run the shared payload inside — the SAME assertion set the founder check
 * and deploy canary use (no independently drifting copy). Runs the emitted
 * argv VERBATIM: on the prod image /usr/bin/bwrap is file-cap'd, so zero
 * --unshare-* is exactly what production spawns. Never throws.
 */
export function probeRealizedIsolation(
  deps: { bwrapPath?: string; makeRoot?: () => string; probePath?: string } = {},
): RealizedIsolationProbe {
  const root = (deps.makeRoot ?? (() => mkdtempSync(path.join(tmpdir(), "aow-realized-"))))();
  try {
    const own = path.join(root, "workspaces", "ws-aaaa");
    const sibling = path.join(root, "workspaces", "ws-bbbb");
    const home = path.join(root, "home", "soleur");
    const plugin = path.join(root, "plugin");
    mkdirSync(own, { recursive: true });
    mkdirSync(sibling, { recursive: true });
    writeFileSync(path.join(sibling, "marker.txt"), "sibling\n");
    mkdirSync(home, { recursive: true });
    mkdirSync(plugin, { recursive: true });
    const probePath = deps.probePath ?? INNER_PROBE_PATH;
    if (!probePath) return { ok: false, reason: "probe_path_missing" };
    const argv = buildOuterWrapArgv({ workspacePath: own, home, pluginPath: plugin });
    const res = spawnSync(
      deps.bwrapPath ?? BWRAP_PATH,
      [...argv, "/bin/bash", "-s", "--", path.dirname(own), own, sibling],
      {
        input: readFileSync(probePath, "utf8"),
        encoding: "utf8",
        timeout: 30_000,
      },
    );
    if (res.error)
      return {
        ok: false,
        reason: `bwrap_spawn_${((res.error as NodeJS.ErrnoException).code ?? "error").toLowerCase()}`,
      };
    const out = `${res.stdout ?? ""}`;
    const elevation = /^elevation=(privileged|userns)$/m.exec(out)?.[1] as
      | RealizedIsolationProbe["elevation"]
      | undefined;
    if (res.status === 0 && out.includes("isolation_ok"))
      return { ok: true, elevation };
    if (/operation not permitted/i.test(`${res.stderr ?? ""}`)) {
      return { ok: false, reason: "bwrap_operation_not_permitted" };
    }
    if (/^FAIL:/m.test(out)) return { ok: false, reason: "isolation_probe_failed" };
    if (res.status === 0) return { ok: false, reason: "probe_output_missing" };
    return { ok: false, reason: `bwrap_exit_${res.status ?? "null"}` };
  } catch (err) {
    return { ok: false, reason: `probe_error:${String(err).slice(0, 120)}` };
  } finally {
    try {
      rmSync(root, { recursive: true, force: true });
    } catch {
      // best-effort — a leaked empty dir under tmpfs is not a finding.
    }
  }
}

/**
 * Opt-in boot self-probe (AGENT_OUTER_WRAP_BOOT_PROBE=1): run the realized
 * probe once and emit the verdict — `log.info` on pass,
 * `warnSilentFallback` (Sentry warn + Better Stack) on fail, tagged
 * `feature:agent-sandbox` / `op:outer-wrap-realized-probe`. Never throws;
 * called un-awaited next to the other boot probes in index.ts.
 */
export function verifyOuterWrapRealizedIsolation(
  env: Record<string, string | undefined> = process.env,
  deps: { probe?: () => RealizedIsolationProbe } = {},
): void {
  try {
    if (env.AGENT_OUTER_WRAP_BOOT_PROBE !== "1") return;
    const p = (deps.probe ?? probeRealizedIsolation)();
    if (p.ok && p.elevation === "privileged") {
      log.info(
        { feature: "agent-sandbox", op: "outer-wrap-realized-probe", ...p },
        "agent-sandbox: outer-wrap realized-isolation probe ok",
      );
      // Same success-fork parity as verifyAgentSandboxHardening: info is
      // journald-only on Vector, so the prod file-cap measurement must land
      // on Sentry to be off-box queryable (the probe exists to measure).
      try {
        Sentry.captureMessage("agent sandbox outer-wrap realized probe ok", {
          level: "info",
          tags: { event_type: "agent-sandbox-outer-wrap-realized-probe" },
          extra: { ...p },
        });
      } catch {
        // Sentry must never break the probe.
      }
      return;
    }
    if (p.ok) {
      // The table held but bwrap took the implicit-userns fallback — the
      // file-cap path did not elevate on THIS host. An outer userns is
      // fatal to the inner sandbox (Phase 0): warn, same severity as a fail.
      warnSilentFallback(null, {
        feature: "agent-sandbox",
        op: "outer-wrap-realized-probe",
        message:
          "agent sandbox outer-wrap realized probe: isolation held but bwrap took the userns fallback — file-cap posture not measured",
        extra: { ...p },
      });
      return;
    }
    warnSilentFallback(null, {
      feature: "agent-sandbox",
      op: "outer-wrap-realized-probe",
      message: "agent sandbox outer-wrap realized-isolation probe failed",
      extra: { ...p },
    });
  } catch (err) {
    warnSilentFallback(err, {
      feature: "agent-sandbox",
      op: "outer-wrap-realized-probe",
      message: "agent sandbox outer-wrap realized-isolation probe threw",
    });
  }
}
