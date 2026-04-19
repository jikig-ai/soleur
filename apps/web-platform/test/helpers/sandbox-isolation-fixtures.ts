/**
 * Fixture helpers for cross-workspace isolation tests (MU3, feat-verify-workspace-isolation).
 *
 * Pure node — no SDK imports. See `knowledge-base/project/specs/feat-verify-workspace-isolation/`
 * (spec.md, sdk-probe-notes.md) for the Path C hybrid design and the captured bwrap argv
 * the `spawnBwrap` minimum-viable template derives from.
 */

import { spawn, spawnSync, type ChildProcess, type SpawnSyncReturns } from "node:child_process";
import { randomBytes } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const FIXTURE_PREFIX = "sandbox-iso-";
const FIXTURE_TTL_MS = 24 * 60 * 60 * 1000;

export interface WorkspacePair {
  rootA: string;
  rootB: string;
  /**
   * Host directory that holds both roots as siblings. When set under /workspaces,
   * `spawnBwrap` will add `--tmpfs /workspaces` so the production mount-ordering
   * question (see sdk-probe-notes.md "Ordering-mystery resolution") is exercised.
   */
  parent: string;
  cleanup: () => void;
}

export interface BwrapResult {
  stdout: string;
  stderr: string;
  status: number | null;
  signal: NodeJS.Signals | null;
  /** True when bwrap/socat/etc. failed before the user command executed. Use to gate setup-failure assertions. */
  setupFailed: boolean;
}

export interface SandboxBHandle {
  child: ChildProcess;
  pid: number;
  /** Resolves when the bwrap-wrapped shell has confirmed its marker is in place. */
  ready: Promise<void>;
  kill: () => void;
  waitExit: () => Promise<{ code: number | null; signal: NodeJS.Signals | null }>;
}

export type ProbeTier = "direct" | "query";

export interface ProbeDecision {
  skip: boolean;
  reason?: string;
}

/**
 * Allocate a paired-workspace fixture under os.tmpdir(). If `underWorkspaces`
 * is true AND /workspaces is writable by the current user, place the pair there
 * instead so production mount-ordering can be exercised (see sdk-probe-notes.md).
 */
export function createWorkspacePair(opts: { underWorkspaces?: boolean } = {}): WorkspacePair {
  return createNamedWorkspacePair(["rootA", "rootB"], opts);
}

/**
 * Like createWorkspacePair but lets the caller pick directory names under the
 * shared parent. Use for FR4 prefix-collision fixtures ("user1"/"user10") where
 * the production path shape matters for the isolation property under test.
 */
export function createNamedWorkspacePair(
  names: [string, string],
  opts: { underWorkspaces?: boolean } = {},
): WorkspacePair {
  const wantProduction = opts.underWorkspaces === true;
  const parent = wantProduction && workspacesIsFixtureRoot()
    ? fs.mkdtempSync(path.join("/workspaces", FIXTURE_PREFIX))
    : fs.mkdtempSync(path.join(os.tmpdir(), FIXTURE_PREFIX));
  const [nameA, nameB] = names;
  // Basename hardening: reject anything that can alter argv or path semantics
  // (slashes, dot-dot, leading dash that later tools would parse as a flag,
  // NUL, backslash, or empty string). Review #2610 Sec I2.
  for (const n of [nameA, nameB]) {
    if (!/^[A-Za-z0-9_.][A-Za-z0-9_.-]*$/.test(n) || n === "..") {
      throw new Error(`createNamedWorkspacePair: invalid basename ${JSON.stringify(n)}`);
    }
  }
  const rootA = path.join(parent, nameA);
  const rootB = path.join(parent, nameB);
  fs.mkdirSync(rootA, { recursive: true });
  fs.mkdirSync(rootB, { recursive: true });

  return {
    rootA,
    rootB,
    parent,
    cleanup: () => {
      try {
        fs.rmSync(parent, { recursive: true, force: true });
      } catch {
        // best-effort; rescueStaleFixtures covers leftovers
      }
    },
  };
}

/**
 * Write a marker file inside `root`. Returns the absolute path and the random token
 * written so tests can assert presence/absence by content, not by path (prevents
 * tautological passes if the file is unexpectedly empty).
 */
export function seedMarker(root: string, relPath = "secret.md"): { path: string; token: string } {
  const token = `marker-${randomBytes(8).toString("hex")}`;
  const abs = path.join(root, relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, token, "utf8");
  return { path: abs, token };
}

/**
 * Create a symlink inside `root` whose target is `target` (typically a path outside
 * `root`, used to attempt FR5 escape).
 */
export function linkEscape(
  root: string,
  linkRelPath: string,
  target: string,
): string {
  const linkAbs = path.join(root, linkRelPath);
  fs.mkdirSync(path.dirname(linkAbs), { recursive: true });
  try {
    fs.unlinkSync(linkAbs);
  } catch {
    // no-op if absent
  }
  fs.symlinkSync(target, linkAbs);
  return linkAbs;
}

export interface SpawnBwrapOpts {
  /**
   * Pair metadata enables the production mount-ordering pattern:
   * `--tmpfs <pair.parent>` + re-bind of `root`. This overlays an empty tmpfs
   * at the parent so siblings (rootB when root === rootA) become unreadable,
   * then re-binds `root` so the tmpfs doesn't shadow the intended workspace.
   * Matches the captured SDK argv at /workspaces; works at any parent path.
   */
  pair?: Pick<WorkspacePair, "parent">;
  /** Extra bwrap args appended after the synthesized mount set, before `--`. */
  extraArgs?: string[];
  /** Milliseconds before SIGKILL. Default 10_000. */
  timeoutMs?: number;
  env?: NodeJS.ProcessEnv;
}

/**
 * Direct-spawn bwrap with the minimum-viable argv from sdk-probe-notes.md:
 *
 *   bwrap --new-session --die-with-parent
 *         --ro-bind / /
 *         --bind <root> <root>
 *         [--tmpfs /workspaces if pair.parent is /workspaces/*]
 *         --dev /dev --unshare-pid
 *         -- /bin/bash -c <command>
 *
 * The proxy scaffolding and config-file shields from production are intentionally
 * omitted; this harness tests FS isolation only, not network/peer-config leakage.
 */
export function spawnBwrap(
  root: string,
  command: string,
  opts: SpawnBwrapOpts = {},
): BwrapResult {
  const args = buildBwrapArgs(root, command, opts);
  const result = spawnSync("bwrap", args, {
    encoding: "utf8",
    timeout: opts.timeoutMs ?? 10_000,
    env: opts.env ?? process.env,
  });
  return toBwrapResult(result);
}

export interface SpawnSandboxBOpts extends SpawnBwrapOpts {
  /** Relative marker path to seed and wait for inside rootB before resolving `ready`. */
  markerRelPath?: string;
  /** Maximum milliseconds to wait for the marker to appear. Default 5_000. */
  readyTimeoutMs?: number;
}

/**
 * Launch a long-running bwrap child in `rootB`, used for FR7 /proc/<pid>/environ
 * cross-read attempts. The child runs `sleep infinity` (or caller-supplied command)
 * after seeding a readiness marker. Caller must call `kill()` in afterEach.
 */
export function spawnSandboxB(
  rootB: string,
  opts: SpawnSandboxBOpts = {},
): SandboxBHandle {
  const markerRel = opts.markerRelPath ?? ".ready";
  const markerAbs = path.join(rootB, markerRel);
  try {
    fs.unlinkSync(markerAbs);
  } catch {
    // no-op
  }
  // Shell script inside the sandbox: touch readiness marker, then block.
  const script = `touch ${shellQuote(path.join(rootB, markerRel))} && exec sleep infinity`;
  const args = buildBwrapArgs(rootB, script, opts);
  const child = spawn("bwrap", args, {
    stdio: ["ignore", "pipe", "pipe"],
    env: opts.env ?? process.env,
  });

  const readyTimeout = opts.readyTimeoutMs ?? 5_000;
  const ready = waitForFile(markerAbs, readyTimeout).catch((err) => {
    try {
      child.kill("SIGKILL");
    } catch {
      // no-op
    }
    throw err;
  });

  const waitExit = () =>
    new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((resolve) => {
      if (child.exitCode !== null || child.signalCode !== null) {
        resolve({ code: child.exitCode, signal: child.signalCode });
        return;
      }
      child.once("exit", (code, signal) => resolve({ code, signal }));
    });

  return {
    child,
    pid: child.pid!,
    ready,
    kill: () => {
      try {
        child.kill("SIGKILL");
      } catch {
        // no-op
      }
    },
    waitExit,
  };
}

/**
 * Remove stale fixtures left behind by crashed tests. Only removes directories
 * under os.tmpdir() (or /workspaces when the soleur sentinel is present) whose
 * basename starts with FIXTURE_PREFIX and whose mtime is older than
 * FIXTURE_TTL_MS. Symlinks are never followed — if the entry itself is a
 * symlink, it is skipped. Review #2610 H1 closed this bypass: a symlink at
 * /tmp/sandbox-iso-evil → /tmp/VICTIM-xxx used to pass the realpath + dirname
 * check and get rm -rf'd.
 */
export function rescueStaleFixtures(): { removed: string[] } {
  const allowedRoots = [os.tmpdir()];
  if (workspacesIsFixtureRoot()) allowedRoots.push("/workspaces");
  const removed: string[] = [];
  const cutoff = Date.now() - FIXTURE_TTL_MS;

  for (const root of allowedRoots) {
    let entries: string[];
    try {
      entries = fs.readdirSync(root);
    } catch {
      continue;
    }
    for (const name of entries) {
      if (!name.startsWith(FIXTURE_PREFIX)) continue;
      const full = path.join(root, name);
      // HARD gate: lstat the entry WITHOUT following symlinks. Any symlink —
      // even one resolving inside an allowed root — is refused. Combined with
      // the FIXTURE_PREFIX basename check and the mtime TTL, this restricts
      // rm -rf to real directories we created via fs.mkdtempSync.
      let lstat: fs.Stats;
      try {
        lstat = fs.lstatSync(full);
      } catch {
        continue;
      }
      if (lstat.isSymbolicLink()) continue;
      if (!lstat.isDirectory()) continue;
      if (lstat.mtimeMs > cutoff) continue;
      try {
        fs.rmSync(full, { recursive: true, force: true });
        removed.push(full);
      } catch {
        // best-effort; next run will retry
      }
    }
  }
  return { removed };
}

/**
 * Decide whether to skip based on host capability. Checks:
 *   - bwrap binary (both tiers)
 *   - socat binary (both tiers — per sdk-probe-notes.md §Phase 2B note; a host
 *     without socat means the SDK's real sandbox cannot run, so running
 *     direct-spawn tests in isolation would produce a misleading green signal)
 *   - ANTHROPIC_API_KEY (query tier only)
 *
 * Callers SHOULD still set `sandboxOptions.failIfUnavailable: true` in any
 * query()-tier test config (see #2634) so a test host that slipped past this
 * probe still refuses to run unsandboxed.
 */
export function probeSkip(tier: ProbeTier): ProbeDecision {
  const missing = findMissingCapability(tier);
  if (!missing) return { skip: false };

  // Fail-loud opt-in: on hosts that claim to support the isolation test
  // harness (canary images, dedicated CI runners with bwrap+socat), a silent
  // skip would be indistinguishable from a passing suite — throw instead so
  // the CI log flags the specific missing capability. Default CI runners do
  // NOT set this variable; they skip cleanly (a runner without bwrap cannot
  // exercise the test and there is no silent-green risk to prevent).
  // Review #2610 Arch Rec #1; ship cycle revised after GH Actions runners
  // (no bwrap) hit the universal CI throw.
  if (process.env.SOLEUR_ISOLATION_TEST_HOST === "1") {
    throw new Error(
      `sandbox-isolation: refusing to skip with SOLEUR_ISOLATION_TEST_HOST=1. Missing capability: ${missing}`,
    );
  }
  return { skip: true, reason: missing };
}

function findMissingCapability(tier: ProbeTier): string | null {
  if (!hasBinary("bwrap")) return "bwrap not installed on host";
  if (!hasBinary("socat")) return "socat not installed on host (SDK sandbox unavailable)";
  if (tier === "query" && !process.env.ANTHROPIC_API_KEY) {
    return "ANTHROPIC_API_KEY not set (query-tier requires live SDK)";
  }
  return null;
}

// ---------- internals ----------

function buildBwrapArgs(root: string, command: string, opts: SpawnBwrapOpts): string[] {
  const args: string[] = [
    "--new-session",
    "--die-with-parent",
    "--ro-bind", "/", "/",
    "--bind", root, root,
  ];
  const parent = opts.pair?.parent;
  if (parent) {
    // Production mount-ordering: tmpfs over the parent hides siblings (rootB when
    // root === rootA), then re-assert the child bind so the tmpfs doesn't shadow
    // the intended workspace. See sdk-probe-notes.md §Ordering-mystery. The
    // pre-tmpfs --bind above is shadowed by this tmpfs and preserved here only
    // for argv parity with the captured SDK invocation — do not collapse without
    // re-running FR2/FR5 (see `SpawnBwrapOpts.pair` docs).
    args.push("--tmpfs", parent);
    args.push("--bind", root, root);
  }
  args.push("--dev", "/dev", "--unshare-pid");
  if (opts.extraArgs?.length) args.push(...opts.extraArgs);
  args.push("--", "/bin/bash", "-c", command);
  return args;
}

function toBwrapResult(res: SpawnSyncReturns<string>): BwrapResult {
  const stderr = res.stderr ?? "";
  // Setup-failure signatures are limited to bwrap itself (mount/namespace
  // errors) or exec of the inner program. Shell-level errors from the user
  // command are NOT setup failures — in isolation tests they are the signal
  // (e.g., "No such file or directory" when the deny boundary hides rootB).
  const setupFailed =
    res.error !== undefined ||
    /^bwrap: /m.test(stderr) ||
    /execvp:/m.test(stderr);
  return {
    stdout: res.stdout ?? "",
    stderr,
    status: res.status,
    signal: res.signal,
    setupFailed,
  };
}

function hasBinary(name: string): boolean {
  const res = spawnSync("command", ["-v", name], { shell: "/bin/bash", encoding: "utf8" });
  return res.status === 0 && !!res.stdout.trim();
}

function workspacesRootWritable(): boolean {
  try {
    fs.accessSync("/workspaces", fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Identity (not writability) check for /workspaces as a fixture root. A world-
 * writable /workspaces on a dev box would otherwise let rescueStaleFixtures
 * sweep sandbox-iso-* entries belonging to other users/containers. Gate on a
 * sentinel file (`.soleur-fixture-root`) that CI and supported dev hosts can
 * opt into. Review #2610 H2.
 */
function workspacesIsFixtureRoot(): boolean {
  if (!workspacesRootWritable()) return false;
  try {
    return fs.statSync("/workspaces/.soleur-fixture-root").isFile();
  } catch {
    return false;
  }
}

/**
 * POSIX-safe single-quote escape for interpolating paths into `bash -c`
 * strings. Exported so the direct-tier and query-tier test suites share one
 * implementation (review #2610 H1 code-quality dedupe).
 */
export function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

/**
 * Regex matching the kernel-surfaced denial strings the isolation suite pins
 * on. Shared between FR2/FR4/FR5 to prevent copy-drift across assertions.
 */
export const FS_DENY_RE = /No such file|cannot open|Permission denied/;

async function waitForFile(abs: string, timeoutMs: number): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (fs.existsSync(abs)) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error(`timeout waiting for ${abs} after ${timeoutMs}ms`);
}
