// Server-only: regenerate the precomputed, layouted `model.likec4.json` by
// spawning the preinstalled `likec4` CLI out-of-process. Called from the C4
// write path (writeC4Diagram) after a `.c4` source is committed + synced, so a
// Code-tab Save (or the Concierge edit_c4_diagram tool) actually re-renders the
// diagram instead of leaving a stale layout (#4964, follow-up to #4963 Layer 1).
//
// Modeled on server/pdf-linearize.ts: bounded timeout → SIGKILL, settle-once
// promise, scoped env, concurrency gate, reason-typed result, and a `mkdtemp`
// temp dir cleaned in a `finally`. HOME is added to the env allow-list (npm-
// global `likec4` bin resolution needs it).
//
// VALIDATE-BEFORE-CLOBBER (#4966): `likec4 export json` EXITS 0 even when the
// source has unresolved references (it prints `Could not resolve reference to
// ElementKind named '…'` to stderr but returns 0 and writes an EMPTY-elements
// model). So exit-0 is NOT sufficient evidence of a usable render. We render to
// a temp path, parse it, and only treat it as success when the model has ≥1
// element — then RETURN the validated bytes (the caller commits them and the
// resync pull lands them on disk). An empty/invalid export therefore NEVER
// reaches a commit; it returns `{ ok:false, reason:"empty_model" }` so the
// writer keeps the old JSON and the client shows the honest staleness banner.
//
// OFF-TREE RENDER (#4976): the validated model is NEVER written onto the tracked
// `model.likec4.json` working-tree path. The render produces only a process-temp
// artifact and returns the bytes; the writer commits them via the GitHub
// Contents API and the `op:"manual"` resync pull brings the committed bytes down
// onto the clone (where the GET `/api/kb/c4/project` route reads them). This
// removes the dirty-tree reconcile churn that the in-place publish used to cause
// on every `.c4` save. Mirrors `pdf-linearize.ts`, which likewise returns bytes
// and leaves persistence to its caller.
//
// SECURITY (#8623; ADR-050 amendment 2026-09-24): the tenant workspace is
// UNTRUSTED input — likec4 executes a `likec4.config.{js,…,mts}` found under
// its cwd, honours `.likec4rc` / `likec4.config.json` `include.paths`, and
// follows symlinks, and a sandboxed agent can write any of those into the
// workspace (worktree and `.git`). So this module takes NO workspace path. Its
// only input is what the injected `stage` function writes into a fresh
// `mkdtemp` directory under the server-private `c4RenderStagingRoot()` (never
// os.tmpdir(), which is shared with the agent sandbox's uid) — in production
// `stageCommittedC4Sources`, which fetches only the regular-file LikeC4 source
// blobs of the committed diagrams subtree from GitHub. The spawn's cwd is that
// stage directory; the `-o` target sits beside it, outside the likec4 input.
// Staging runs BEFORE a render slot is taken and under its own deadline, so a
// slow GitHub never holds a slot. The argv is fixed and the env is an
// allow-list, so no secret reaches the child's own environment. stdout stays
// non-TTY (`stdio: ignore`), which with the in-container check keeps likec4's
// `check-update` (execa `preferLocal`, searches `node_modules/.bin` upward from
// cwd) from running — do NOT add `CI=true` to the env: likec4 then switches
// reporter and the writer's `Could not resolve …` diagnostic match breaks.
//
// SANDBOX (#8696; ADR-050 amendment "render child sandboxed; wasm layout
// pinned"): the child runs inside bubblewrap with an allowlisted root (`/usr`
// plus three `/etc` files), no network, no `/proc` (Docker masks it, and the
// parent's would expose the server's environ), a cleared environment, a
// read-only `/` and `/dev`, sized tmpfs for everything writable except the
// `/c4-out` bind, and `no_new_privs`. Inside bwrap likec4's `isInsideContainer()`
// is false, so its detached `check-update` may start — it has no network and
// dies with the pid namespace. A sandbox that cannot start fails the render
// CLOSED (`sandbox_error`); only a non-production process may opt out
// (`C4_RENDER_SANDBOX=off`). The host never trusts what the child leaves in
// `/c4-out`: the model is read through a no-follow, size-capped fd
// (readRenderOutput), and the stage is removed only after every sandbox
// process has exited. `--no-use-dot` pins wasm layout: in a container likec4
// otherwise picks the absent graphviz `dot` and exports ZERO views.
//
// No `import "server-only"` (same reason as c4-writer.ts): this module is
// bundled into the WS/custom server via the Concierge tool's import chain, and
// esbuild cannot resolve the `server-only` guard package. Server-only by
// construction (spawns a CLI), only imported by server code.
import { spawn } from "node:child_process";
import { constants } from "node:fs";
import {
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  readFile,
  realpath,
  rm,
  writeFile,
} from "node:fs/promises";
import { delimiter, dirname, isAbsolute, join } from "node:path";
import type { Readable } from "node:stream";
import * as Sentry from "@sentry/nextjs";
import { canonicalizeC4Model } from "@/lib/c4-canonical.mjs";
import { C4_MODEL_JSON } from "@/lib/c4-constants";
import { c4RenderStagingRoot } from "@/server/c4-staging-root";
import type { RefusalClass, StageResult } from "@/server/c4-stage-sources";
import logger from "@/server/logger";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";

export type RenderReason =
  | "spawn_error"
  | "non_zero_exit"
  | "timeout"
  // The export resolved but produced a model with zero elements — the user's
  // source is broken (typically a missing spec.c4). Distinct from io_error so
  // the writer surfaces a source-fault diagnostic ONLY for this reason.
  | "empty_model"
  // Our own IO failed (mkdtemp / temp read / parse / staging fetch) — NOT the
  // user's source.
  | "io_error"
  // The committed diagrams tree holds something the render refuses to load
  // (a likec4 config, a symlink, a submodule) or exceeds the staging caps
  // (#8623). The user's repo is the cause; `refusalClass` says which.
  | "unsafe_source"
  // The sandbox could not run the child (bwrap setup, launcher missing,
  // binaries unresolvable or outside /usr in production, a sandbox that would
  // not exit). Never the user's source (#8696).
  | "sandbox_error"
  // likec4 exported elements but no views: our layout failed (a successful
  // layout always emits at least `index`), never the user's source.
  | "layout_failed";

/** Low-cardinality Sentry tag: which failure class, so each class opens its
 *  own issue (the message stays fixed per reason for grouping). */
export type DetailClass =
  | "bwrap-setup"
  | "bwrap-enoent"
  | "outside-usr"
  | "not-resolvable"
  | "sandbox-no-exit"
  | "output-rejected"
  | "zero-views"
  | "slot-wait"
  | "likec4-exit"
  | "other";

/** Writes the render's input into `destDir` (which it creates). */
export type StageFn = (destDir: string, signal: AbortSignal) => Promise<StageResult>;

export type RenderFailure =
  | {
      ok: false;
      reason: "unsafe_source";
      refusalClass: RefusalClass;
      path?: string;
      more: number;
      phase: "stage";
      detail?: undefined;
    }
  | {
      ok: false;
      reason: Exclude<RenderReason, "unsafe_source">;
      detail?: string;
      /** Where it failed: fetching the input, or running likec4. */
      phase: "stage" | "spawn";
      detailClass?: DetailClass;
    };

export type RenderResult =
  // `json` is the validated model in the CANONICAL on-disk format (one JSON
  // value per line, view hashes blanked — lib/c4-canonical.mjs, #8542). The
  // repo regenerator and the plugin's sync producer emit the same bytes through
  // the same module, so no writer reformats another's committed file.
  | { ok: true; durationMs: number; json: string; queueWaitMs?: number }
  | RenderFailure;

// Staging fetches over the network; it gets its own budget, separate from the
// spawn's, and runs before a render slot is taken (#8623).
export const STAGE_DEADLINE_MS = 10_000;
export const STAGE_DEADLINE_DETAIL = "stage: deadline";

// A real wasm layout of an 82-view model takes 3.8-7.2 s at 2 CPUs (measured
// 2026-09-24; the old "<1s" was the FAILED `dot` path). 25 s leaves headroom for
// a cold first invocation; see RENDER_BUDGET below for the whole budget.
const RENDER_TIMEOUT_MS = 25_000;
// After SIGKILL, how long to wait for every sandbox process to exit (the
// `close` event) before giving up and leaving the stage for the stale sweep.
const KILL_GRACE_MS = 5_000;

// Preinstalled in the runner image (Dockerfile `npm install -g likec4@1.50.0`).
// Env override exists for tests / local dev only.
const LIKEC4_BIN = process.env.LIKEC4_BIN || "likec4";

/** The sandbox binary, by absolute path — never resolved through PATH. */
export const BWRAP_BIN = "/usr/bin/bwrap";
// util-linux, present in the runner image's base. `choom` runs OUTSIDE the
// sandbox (it needs /proc) and makes the render the OOM killer's first choice
// over the server; `prlimit` runs inside it and caps its process count (the
// limit is per user namespace, so the server's own spawns are unaffected).
const CHOOM_BIN = "/usr/bin/choom";
const PRLIMIT_BIN = "/usr/bin/prlimit";
/** Size of every sandbox tmpfs (/tmp, /c4-home, /dev/shm). A full render uses
 *  under 200 bytes of them (measured); the cap bounds a compromised child. */
export const SANDBOX_TMPFS_BYTES = 64 * 1024 * 1024;
/** likec4 peaks at 13 tasks (threads count); 64 is ~5x that. */
export const SANDBOX_NPROC = 64;
/** bwrap writes JSON status records here; the sandboxed child cannot reach it. */
const STATUS_FD = 3;
const SANDBOX_OUT = "/c4-out/model.likec4.json";
/** Largest model file the host will read. The writer's 4 MB cap still bounds
 *  what it commits; this bounds what a compromised child can make us read. */
export const RAW_MODEL_READ_CAP = 20 * 1024 * 1024;
// Stderr the host keeps (the detail string uses the first 512 bytes; the pipe
// keeps draining after that so the child never blocks on it).
const STDERR_KEEP = 512;

// Concurrency gate — caps concurrent wasm-layout subprocesses per replica so
// peak RAM stays bounded under burst saves. Default 2, env-overridable via
// C4_RENDER_CONCURRENCY, clamped to [1, 16]. Captured at module load (ops
// changes require a container restart, the intended path). Mirrors
// pdf-linearize.ts's POOL_SIZE. The counter lives on `globalThis`: this module
// is bundled twice into one process (the custom server via the Concierge tool,
// and the Next route), and a per-bundle counter would allow twice the renders.
const POOL_SIZE = (() => {
  const raw = Number(process.env.C4_RENDER_CONCURRENCY);
  if (!Number.isFinite(raw) || raw < 1) return 2;
  return Math.min(Math.floor(raw), 16);
})();
/** How long a render waits for a slot before giving up (load, not a defect). */
export const SLOT_WAIT_MS = 10_000;
export const RENDER_SLOT_WAIT_DETAIL = "render slot wait";
// Budget before the model commit, worst case: stage 10 s + slot wait 10 s +
// spawn 25 s + kill grace 5 s (timeout path only) + rm (<= 3 x 100 ms) ~ 50.3 s,
// inside the PUT route's maxDuration=60 (a hint only; the custom server does not
// enforce it). STAGE_SETTLE_GRACE_MS is spent only after a stage deadline, a
// path that never spawns.

type Pool = { inFlight: number; waiters: Array<() => void> };
const POOL_KEY = Symbol.for("soleur.c4RenderPool");

function pool(): Pool {
  const g = globalThis as unknown as Record<symbol, Pool | undefined>;
  return (g[POOL_KEY] ??= { inFlight: 0, waiters: [] });
}

/** Resolves true with a slot held, or false after SLOT_WAIT_MS. */
function acquire(): Promise<boolean> {
  const p = pool();
  if (p.inFlight < POOL_SIZE) {
    p.inFlight++;
    return Promise.resolve(true);
  }
  return new Promise<boolean>((resolve) => {
    const grant = () => {
      clearTimeout(timer);
      p.inFlight++;
      resolve(true);
    };
    const timer = setTimeout(() => {
      const i = p.waiters.indexOf(grant);
      if (i >= 0) p.waiters.splice(i, 1);
      resolve(false);
    }, SLOT_WAIT_MS);
    p.waiters.push(grant);
  });
}

function release(): void {
  const p = pool();
  p.inFlight--;
  const next = p.waiters.shift();
  if (next) next();
}

// Private `?`-substitution copy (keeps likec4 stderr readable in the detail
// string). lib/log-sanitize.ts's doc comment forbids folding this in.
function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?");
}

// Internal spawn result — `stderr` is carried even on exit 0 so the caller can
// fold likec4's `Could not resolve …` diagnostics into an `empty_model` detail.
type SpawnResult =
  | { ok: true; durationMs: number; stderr: string }
  | {
      ok: false;
      reason: "spawn_error" | "non_zero_exit" | "timeout" | "sandbox_error";
      detail?: string;
      detailClass: DetailClass;
    };

/** Production renders run sandboxed, always; elsewhere `C4_RENDER_SANDBOX=off`
 *  selects a direct spawn (hosts without bwrap). */
function sandboxed(): boolean {
  return process.env.NODE_ENV === "production" || process.env.C4_RENDER_SANDBOX !== "off";
}

function underUsr(p: string): boolean {
  return p === "/usr" || p.startsWith("/usr/");
}

type Binaries = { nodeBin: string; likec4Entry: string; extraRoBinds: string[] };
// Memoized on SUCCESS only, so a transient failure is retried on the next render.
let binaries: Binaries | null = null;

/** Resolve node and the likec4 entry script to real paths, lazily (never at
 *  import). `extraRoBinds` are their install prefixes when not under /usr
 *  (a CI runner's node lives under /opt/hostedtoolcache). */
async function resolveBinaries(): Promise<Binaries | null> {
  if (binaries) return binaries;
  try {
    const nodeBin = await realpath(process.execPath);
    let likec4Entry: string | null = null;
    if (isAbsolute(LIKEC4_BIN)) {
      likec4Entry = await realpath(LIKEC4_BIN);
    } else {
      for (const d of (process.env.PATH ?? "").split(delimiter)) {
        if (!d) continue;
        try {
          likec4Entry = await realpath(join(d, LIKEC4_BIN));
          break;
        } catch {
          // not in this PATH entry
        }
      }
    }
    if (!likec4Entry) return null;
    const extra: string[] = [];
    for (const p of [dirname(dirname(nodeBin)), dirname(dirname(likec4Entry))]) {
      if (underUsr(p) || extra.some((e) => p === e || p.startsWith(`${e}/`))) continue;
      extra.push(p);
    }
    binaries = { nodeBin, likec4Entry, extraRoBinds: extra };
    return binaries;
  } catch {
    return null;
  }
}

/** The command the sandbox runs: a fixed likec4 export writing only to /c4-out. */
export function renderCommand(nodeBin: string, likec4Entry: string): string[] {
  return [
    PRLIMIT_BIN, `--nproc=${SANDBOX_NPROC}`, "--",
    nodeBin, likec4Entry, "export", "json", "--no-use-dot", "-o", SANDBOX_OUT, ".",
  ];
}

/**
 * The bwrap argv for one render. Pure. `stageDir` holds `src/` (bound
 * read-only at STABLE_SOURCE_ROOT, the cwd) and `out/` (the only writable bind
 * from the host). Setup ops run in order, so the two `--remount-ro` come after
 * every mount. `command` exists so a test can run a payload through exactly the
 * same sandbox; the render always passes `renderCommand(…)`.
 */
export function buildLikeC4SandboxArgv(o: {
  stageDir: string;
  nodeBin: string;
  extraRoBinds: readonly string[];
  command: readonly string[];
}): string[] {
  const size = String(SANDBOX_TMPFS_BYTES);
  const path = [...new Set([dirname(o.nodeBin), "/usr/local/bin", "/usr/bin", "/bin"])].join(":");
  return [
    "--die-with-parent",
    "--new-session",
    "--unshare-user",
    "--unshare-pid",
    "--unshare-net",
    "--unshare-ipc",
    "--unshare-uts",
    "--json-status-fd", String(STATUS_FD),
    "--ro-bind", "/usr", "/usr",
    "--symlink", "usr/bin", "/bin",
    "--symlink", "usr/lib", "/lib",
    "--symlink", "usr/lib64", "/lib64",
    "--symlink", "usr/sbin", "/sbin",
    "--ro-bind", "/etc/ld.so.cache", "/etc/ld.so.cache",
    // likec4 calls os.userInfo() at import; without passwd it crashes.
    "--ro-bind", "/etc/passwd", "/etc/passwd",
    "--ro-bind", "/etc/group", "/etc/group",
    "--dev", "/dev",
    "--size", size, "--tmpfs", "/dev/shm",
    "--size", size, "--tmpfs", "/tmp",
    "--size", size, "--tmpfs", "/c4-home",
    // After the tmpfs mounts, so a prefix under /tmp (a dev install) is not
    // hidden by them. Never set in production (the /usr pin).
    ...o.extraRoBinds.flatMap((p) => ["--ro-bind", p, p]),
    "--ro-bind", join(o.stageDir, "src"), STABLE_SOURCE_ROOT,
    "--bind", join(o.stageDir, "out"), "/c4-out",
    "--remount-ro", "/dev",
    "--remount-ro", "/",
    "--chdir", STABLE_SOURCE_ROOT,
    "--clearenv",
    "--setenv", "PATH", path,
    "--setenv", "HOME", "/c4-home",
    "--setenv", "TMPDIR", "/tmp",
    "--setenv", "LANG", "C.UTF-8",
    "--",
    ...o.command,
  ];
}

/**
 * Read the child's model output without trusting it: open with O_NOFOLLOW
 * (a planted symlink fails with ELOOP) and O_NONBLOCK (a FIFO cannot hang
 * us), then read only a regular file within RAW_MODEL_READ_CAP, from the same
 * fd. No pre-open lstat (that reopens a check-then-use window). Hard links into
 * /c4-out fail with EXDEV (link(2) across mounts).
 */
export async function readRenderOutput(
  outDir: string,
): Promise<{ ok: true; raw: string } | { ok: false; why: string }> {
  let fh: Awaited<ReturnType<typeof open>>;
  try {
    fh = await open(
      join(outDir, C4_MODEL_JSON),
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code;
    if (code === "ELOOP") return { ok: false, why: "symlink" };
    if (code === "ENOENT") return { ok: false, why: "absent" };
    return { ok: false, why: `open failed (${code ?? "unknown"})` };
  }
  try {
    const st = await fh.stat();
    if (!st.isFile()) return { ok: false, why: "not a regular file" };
    if (st.size > RAW_MODEL_READ_CAP) return { ok: false, why: "too large" };
    const raw = await fh.readFile({ encoding: "utf8" });
    if (Buffer.byteLength(raw, "utf8") > RAW_MODEL_READ_CAP) return { ok: false, why: "too large" };
    return { ok: true, raw };
  } catch (err) {
    return { ok: false, why: `read failed (${(err as NodeJS.ErrnoException)?.code ?? "unknown"})` };
  } finally {
    await fh.close().catch(() => {});
  }
}

/**
 * Regenerate `model.likec4.json` by staging the render input with `stage` into
 * a private directory, then running the preinstalled `likec4` CLI in the
 * sandbox (`likec4 export json --no-use-dot -o /c4-out/model.likec4.json .`,
 * cwd = the staged sources). VALIDATE the produced model has elements AND
 * views, and on success RETURN the validated bytes as `json` — the caller
 * commits them. The tracked working-tree `model.likec4.json` is never written
 * by this path (#4976), and no workspace path is ever read (#8623). An
 * empty/invalid export returns `{ ok:false }` with no `json`.
 */
export async function renderC4Model(stage: StageFn): Promise<RenderResult> {
  const root = c4RenderStagingRoot();
  const dir = await mkdir(root, { recursive: true, mode: 0o700 })
    .then(() => verifyPrivateRoot(root))
    .then(() => sweepStaleStages(root))
    .then(() => mkdtemp(join(root, "c4-render-")))
    .catch(() => null);
  if (!dir) {
    return { ok: false, reason: "io_error", detail: "staging root unavailable", phase: "stage" };
  }
  const srcDir = join(dir, "src");
  // Set when a sandbox process may still be alive: the stage is then left for
  // the stale sweep rather than removed under it.
  const cleanup = { keep: false };
  let stageSettled: Promise<unknown> = Promise.resolve();
  try {
    const run = runStage(stage, srcDir);
    stageSettled = run.settled;
    const staged = await run.result;
    if (!staged.ok) {
      return staged.reason === "unsafe_source"
        ? { ...staged, phase: "stage" }
        : { ok: false, reason: staged.reason, detail: staged.detail, phase: "stage" };
    }
    // The render slot is held only around the spawn.
    const waitStart = Date.now();
    if (!(await acquire())) {
      return {
        ok: false,
        reason: "timeout",
        detail: RENDER_SLOT_WAIT_DETAIL,
        phase: "spawn",
        detailClass: "slot-wait",
      };
    }
    const queueWaitMs = Date.now() - waitStart;
    try {
      // Re-verify the stage just before the spawn: exactly the files the stage
      // reported, regular files and directories only. The staging root is
      // unreachable from the agent sandbox; this makes the input guarantee
      // local instead of resting on that alone.
      if (!(await stageMatches(srcDir, staged.paths))) {
        return { ok: false, reason: "io_error", detail: "stage: contents changed before render", phase: "stage" };
      }
      const res = await renderToValidatedModel(dir, cleanup);
      return res.ok ? { ...res, queueWaitMs } : res;
    } finally {
      release();
    }
  } finally {
    // After a deadline the stage's in-flight work can still be finishing; give
    // it a bounded moment to settle so the removal below does not race a late
    // write (which would leave staged sources behind).
    await Promise.race([stageSettled, new Promise((r) => setTimeout(r, STAGE_SETTLE_GRACE_MS))]);
    // Trailing .catch so cleanup can never reject the resolved result (mirrors
    // pdf-linearize.ts). Removes the staged input and the temp output alike.
    if (!cleanup.keep) {
      await rm(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 }).catch(() => {});
    }
  }
}

const STAGE_SETTLE_GRACE_MS = 2_000;
/** Stand-in for the per-render stage path inside rendered file:// URIs. */
export const STABLE_SOURCE_ROOT = "/c4-sources";

// A render holds its stage for at most the stage deadline + a render-slot wait
// + the spawn timeout; a stage older than this was left by a crashed process.
const STALE_STAGE_MS = 10 * 60_000;

/** Best-effort: remove stage dirs a crashed render left behind (they hold
 *  another tenant's committed sources). Never fails the render. */
async function sweepStaleStages(root: string): Promise<void> {
  try {
    const now = Date.now();
    for (const d of await readdir(root, { withFileTypes: true })) {
      if (!d.isDirectory() || !d.name.startsWith("c4-render-")) continue;
      const p = join(root, d.name);
      const st = await lstat(p).catch(() => null);
      if (st && now - st.mtimeMs > STALE_STAGE_MS) {
        await rm(p, { recursive: true, force: true }).catch(() => {});
      }
    }
  } catch {
    // Sweep is hygiene only.
  }
}

/** The staging root must be a real directory we own — not a symlink planted
 *  in its place, and not someone else's directory. */
async function verifyPrivateRoot(root: string): Promise<void> {
  const st = await lstat(root);
  const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
  if (!st.isDirectory() || st.isSymbolicLink() || (uid !== undefined && st.uid !== uid)) {
    throw new Error("staging root is not a private directory");
  }
}

/** True when `srcDir` holds exactly `expected` (relative paths) as regular
 *  files, with nothing but directories besides. */
async function stageMatches(srcDir: string, expected: string[]): Promise<boolean> {
  const want = new Set(expected);
  const seen = new Set<string>();
  const walk = async (dir: string, rel: string): Promise<boolean> => {
    for (const d of await readdir(dir, { withFileTypes: true })) {
      const r = rel ? `${rel}/${d.name}` : d.name;
      if (d.isDirectory()) {
        if (!(await walk(join(dir, d.name), r))) return false;
      } else if (d.isFile() && want.has(r)) {
        seen.add(r);
      } else {
        return false;
      }
    }
    return true;
  };
  try {
    return (await walk(srcDir, "")) && seen.size === want.size;
  } catch {
    return false;
  }
}

type StageRun = { result: Promise<StageResult>; settled: Promise<unknown> };

/** Run `stage` under STAGE_DEADLINE_MS; on deadline, abort its in-flight work. */
function runStage(stage: StageFn, srcDir: string): StageRun {
  const ac = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<StageResult>((resolve) => {
    timer = setTimeout(() => {
      ac.abort(new Error(STAGE_DEADLINE_DETAIL));
      resolve({ ok: false, reason: "timeout", detail: STAGE_DEADLINE_DETAIL });
    }, STAGE_DEADLINE_MS);
  });
  const work = Promise.resolve()
    .then(() => stage(srcDir, ac.signal))
    .catch(
      (err): StageResult => ({
        ok: false,
        reason: "io_error",
        detail: sanitizeForLog(`stage: ${err instanceof Error ? err.message : String(err)}`).slice(0, 200),
      }),
    );
  const result = Promise.race([work, deadline]).finally(() => clearTimeout(timer));
  return { result, settled: work };
}

async function renderToValidatedModel(
  dir: string,
  cleanup: { keep: boolean },
): Promise<RenderResult> {
  // The validated bytes are RETURNED, never published onto the tracked path
  // (#4976), so an invalid render never clobbers the previously-good committed
  // model. The output dir sits OUTSIDE the sources, so it is not likec4 input.
  const srcDir = join(dir, "src");
  const outDir = join(dir, "out");
  try {
    const sandbox = sandboxed();
    const bins = await resolveBinaries();
    if (!bins) {
      return {
        ok: false,
        phase: "spawn",
        reason: sandbox ? "sandbox_error" : "spawn_error",
        detail: "likec4 not resolvable",
        detailClass: "not-resolvable",
      };
    }
    if (process.env.NODE_ENV === "production") {
      // A stray LIKEC4_BIN (or an image change) can never widen the sandbox:
      // in production every binary it runs, and every bind, is under /usr.
      let bw: string | null = null;
      try {
        bw = await realpath(BWRAP_BIN);
      } catch {
        return { ok: false, phase: "spawn", reason: "sandbox_error", detail: "bwrap not resolvable", detailClass: "bwrap-enoent" };
      }
      if (
        !underUsr(bw) ||
        !underUsr(bins.nodeBin) ||
        !underUsr(bins.likec4Entry) ||
        bins.extraRoBinds.length > 0
      ) {
        return { ok: false, phase: "spawn", reason: "sandbox_error", detail: "binary outside /usr", detailClass: "outside-usr" };
      }
    }
    await mkdir(outDir, { mode: 0o700 });
    const spec = sandbox
      ? {
          cmd: CHOOM_BIN,
          args: [
            "-n", "1000", "--", BWRAP_BIN,
            ...buildLikeC4SandboxArgv({
              stageDir: dir,
              nodeBin: bins.nodeBin,
              extraRoBinds: bins.extraRoBinds,
              command: renderCommand(bins.nodeBin, bins.likec4Entry),
            }),
          ],
          cwd: dir,
        }
      : {
          cmd: bins.nodeBin,
          args: [bins.likec4Entry, "export", "json", "--no-use-dot", "-o", join(outDir, C4_MODEL_JSON), "."],
          cwd: srcDir,
        };
    const run = await runLikeC4(spec.cmd, spec.args, spec.cwd, dir, sandbox, cleanup);
    if (!run.ok) return { ...run, phase: "spawn" };

    // exit 0 — but likec4 exits 0 on unresolved references too, so validate
    // the raw read first; canonicalization happens only after the gate.
    const out = await readRenderOutput(outDir);
    if (!out.ok) {
      return {
        ok: false,
        phase: "spawn",
        reason: "io_error",
        detail: `model output rejected: ${out.why}`,
        detailClass: "output-rejected",
      };
    }
    let raw = out.raw;
    let model: { elements?: unknown; views?: unknown };
    try {
      model = JSON.parse(raw) as { elements?: unknown; views?: unknown };
    } catch (err) {
      return {
        ok: false,
        phase: "spawn",
        reason: "io_error",
        detail: sanitizeForLog(
          `model parse failed: ${
            err instanceof Error ? err.message : String(err)
          } ${run.stderr}`.slice(0, 512),
        ),
        detailClass: "other",
      };
    }

    // Gate on a NON-EMPTY plain object of elements. `elements` is untrusted CLI
    // output — a non-empty string/array would make a bare `Object.keys(…)` non-
    // zero and let a malformed export through (the exact clobber this prevents).
    const elementCount = plainObjectSize(model.elements);
    if (elementCount === 0) {
      // The diagnostic IS the captured stderr (the `Could not resolve …` lines);
      // gate on element count, never on stderr substring (wording can drift
      // across likec4 patch versions).
      return {
        ok: false,
        phase: "spawn",
        reason: "empty_model",
        detail: run.stderr || "model has no elements",
        detailClass: "other",
      };
    }
    // Views gate: a successful layout always emits at least `index` (measured,
    // even for a source with no `views {}` block), so zero views is OUR layout
    // failing — never commit it over the good model.
    if (plainObjectSize(model.views) === 0) {
      return {
        ok: false,
        phase: "spawn",
        reason: "layout_failed",
        detail: sanitizeForLog(`model has ${elementCount} elements and no views ${run.stderr}`.slice(0, 512)),
        detailClass: "zero-views",
      };
    }

    // Validated — canonicalize (AFTER the gate, never instead of it) and return
    // the bytes; the caller commits them and the resync pull lands them on disk.
    // The tracked working-tree file is never written. A canonicalize failure is
    // our own IO-class fault, not the user's source, so it maps to io_error.
    // A relative `icon` resolves to a file:// URI under the sources root. In the
    // sandbox that root is already STABLE_SOURCE_ROOT; on the direct path it is
    // the random stage dir, so replace it with the stable token and the
    // committed model neither changes on every save nor discloses the layout.
    raw = raw.split(srcDir).join(STABLE_SOURCE_ROOT);
    let json: string;
    try {
      json = canonicalizeC4Model(raw);
    } catch (err) {
      return {
        ok: false,
        phase: "spawn",
        reason: "io_error",
        detail: sanitizeForLog(
          `canonicalize failed: ${err instanceof Error ? err.message : String(err)}`.slice(0, 512),
        ),
        detailClass: "other",
      };
    }
    return { ok: true, durationMs: run.durationMs, json };
  } catch (err) {
    return {
      ok: false,
      phase: "spawn",
      reason: "io_error",
      detail: sanitizeForLog(err instanceof Error ? err.message : String(err)),
      detailClass: "other",
    };
  }
}

function plainObjectSize(v: unknown): number {
  return v && typeof v === "object" && !Array.isArray(v) ? Object.keys(v).length : 0;
}

function runLikeC4(
  cmd: string,
  args: string[],
  cwd: string,
  home: string,
  sandbox: boolean,
  cleanup: { keep: boolean },
): Promise<SpawnResult> {
  return new Promise((resolve) => {
    const start = Date.now();
    let settled = false;
    let timedOut = false;
    let graceTimer: ReturnType<typeof setTimeout> | undefined;
    const settle = (r: SpawnResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(graceTimer);
      resolve(r);
    };
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
      // Settle on `close`, which fires only once every process holding the
      // stderr pipe (every sandbox process) is gone, so the stage is never
      // removed while one can still write into it. If it never comes, keep the
      // stage for the stale sweep.
      graceTimer = setTimeout(() => {
        cleanup.keep = true;
        settle({ ok: false, reason: "sandbox_error", detail: "sandbox did not exit", detailClass: "sandbox-no-exit" });
      }, KILL_GRACE_MS);
    }, RENDER_TIMEOUT_MS);

    // bwrap's (or, on the direct path, likec4's) OWN environment is the same
    // scoped allow-list as pdf-linearize.ts; no secrets reach it. HOME is the
    // private per-render dir, never the server's (#8623 structural review).
    // Inside the sandbox the child gets only the `--setenv` set.
    const env = {
      ...Object.fromEntries(
        (["PATH", "LANG", "LC_ALL", "TMPDIR"] as const)
          .map((k) => [k, process.env[k]] as const)
          .filter(([, v]) => v !== undefined),
      ),
      HOME: home,
    } as unknown as NodeJS.ProcessEnv;

    // Fixed argv (the only variable parts are the private stage paths and the
    // resolved binaries). No user input in argv.
    const child = spawn(cmd, args, {
      cwd,
      env,
      stdio: sandbox ? ["ignore", "ignore", "pipe", "pipe"] : ["ignore", "ignore", "pipe"],
    });

    const stderrChunks: Buffer[] = [];
    let stderrBytes = 0;
    child.stderr?.on("data", (c: Buffer) => {
      if (stderrBytes >= STDERR_KEEP) return;
      stderrChunks.push(c);
      stderrBytes += c.length;
    });
    // `{ "exit-code": N }` is written by bwrap only after the child it set up
    // has run. Its absence on a non-zero exit means the sandbox itself failed —
    // a signal the child cannot forge (it has no access to this fd), unlike a
    // `bwrap:` line on stderr.
    let status = "";
    (child.stdio?.[STATUS_FD] as Readable | null | undefined)?.on("data", (c: Buffer) => {
      if (status.length < 4096) status += c.toString("utf8");
    });
    child.on("error", (err: NodeJS.ErrnoException) =>
      settle(
        sandbox
          ? {
              ok: false,
              reason: "sandbox_error",
              detail: sanitizeForLog(err.message),
              detailClass: err.code === "ENOENT" ? "bwrap-enoent" : "other",
            }
          : { ok: false, reason: "spawn_error", detail: err.message, detailClass: "other" },
      ),
    );
    child.on("close", (code: number | null, signal: string | null) => {
      // Capture stderr on EVERY exit — likec4 prints `Could not resolve …`
      // validation errors to stderr even when it exits 0, and the caller folds
      // them into the `empty_model` diagnostic.
      const stderr = sanitizeForLog(
        Buffer.concat(stderrChunks).toString("utf8").slice(0, 512),
      );
      if (timedOut) {
        settle({ ok: false, reason: "timeout", detail: `exceeded ${RENDER_TIMEOUT_MS}ms`, detailClass: "other" });
        return;
      }
      if (code === 0) {
        settle({ ok: true, durationMs: Date.now() - start, stderr });
        return;
      }
      const exitPart = code === null ? `signal=${signal}` : `exit=${code}`;
      if (sandbox && code !== null && !/"exit-code"/.test(status)) {
        settle({ ok: false, reason: "sandbox_error", detail: `${exitPart} stderr=${stderr}`, detailClass: "bwrap-setup" });
        return;
      }
      settle({
        ok: false,
        reason: "non_zero_exit",
        detail: `${exitPart} stderr=${stderr}`,
        detailClass: "likec4-exit",
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Boot self-probe (#8696): a REAL render of a fixed fixture through the one
// spawn site and the exact render argv, in the real container under the real
// seccomp + AppArmor profile, so a sandbox break is visible at container start
// rather than on the next tenant save. Report-only; never gates a deploy.
// ---------------------------------------------------------------------------
const PROBE_SOURCE = `specification {
  element actor
  element system
}
model {
  u = actor 'User'
  s = system 'System'
  u -> s 'uses'
}
views {
  view index {
    include *
  }
}
`;

const PROBE_STAGE: StageFn = async (destDir) => {
  await mkdir(destDir, { recursive: true, mode: 0o700 });
  await writeFile(join(destDir, "model.c4"), PROBE_SOURCE, { mode: 0o600 });
  return { ok: true, paths: ["model.c4"], sourceKey: "c4-sandbox-probe" };
};

/** Probe the render sandbox once. Never throws. Called from the server's
 *  `listen` callback in production, never awaited. */
export async function verifyC4RenderSandboxOnce(): Promise<void> {
  try {
    const res = await renderC4Model(PROBE_STAGE);
    if (res.ok) {
      const views = plainObjectSize((JSON.parse(res.json) as { views?: unknown }).views);
      logger.info(
        { event: "c4_render_sandbox_probe", ok: true, durationMs: res.durationMs, views },
        "kb/c4: render sandbox self-probe ok",
      );
      // Info-level pino lines never reach Better Stack (Vector ships WARN+), so
      // the success signal is a Sentry info event, like `server-startup`.
      try {
        Sentry.captureMessage("c4 render sandbox probe ok", {
          level: "info",
          tags: { event_type: "c4-sandbox-probe" },
          extra: { durationMs: res.durationMs, views },
        });
      } catch {
        // Sentry must never break the probe.
      }
    } else {
      reportSilentFallback(null, {
        feature: "c4-rerender",
        op: "sandbox-selfprobe",
        message: `c4 render sandbox self-probe failed: ${res.reason}`,
        tags: {
          reason: res.reason,
          detail_class: res.reason === "unsafe_source" ? "other" : (res.detailClass ?? "other"),
        },
        extra: { detail: res.detail },
      });
    }
  } catch (err) {
    reportSilentFallback(null, {
      feature: "c4-rerender",
      op: "sandbox-selfprobe",
      message: "c4 render sandbox self-probe threw",
      extra: { err: String(err) },
    });
  }
  await reportInheritableFds();
}

const O_CLOEXEC_BIT = 0o2000000;

/** Any file/dir fd >= 3 the server holds WITHOUT close-on-exec would be
 *  inherited by a spawned child. Reports the count only, never paths. */
async function reportInheritableFds(): Promise<void> {
  let count = 0;
  try {
    for (const name of await readdir("/proc/self/fdinfo")) {
      const fd = Number(name);
      if (!Number.isInteger(fd) || fd < 3) continue;
      let info = "";
      try {
        info = await readFile(`/proc/self/fdinfo/${name}`, "utf8");
      } catch {
        continue;
      }
      const m = /^flags:\s*([0-7]+)/m.exec(info);
      if (!m || (parseInt(m[1], 8) & O_CLOEXEC_BIT) !== 0) continue;
      let target: string | null = null;
      try {
        target = await realpath(`/proc/self/fd/${name}`);
      } catch {
        target = null; // pipe/socket/anon inode, or already closed
      }
      if (target?.startsWith("/")) count++;
    }
  } catch {
    return; // no /proc (not Linux): nothing to report
  }
  if (count > 0) {
    warnSilentFallback(null, {
      feature: "c4-rerender",
      op: "sandbox-selfprobe-fds",
      message: "c4 render sandbox self-probe: server holds inheritable file descriptors",
      extra: { count, kinds: ["file-or-dir"] },
    });
  }
}
