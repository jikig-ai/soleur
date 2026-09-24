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
// Residual: the child still runs as the app's uid (bwrap wrapping: #8696).
//
// No `import "server-only"` (same reason as c4-writer.ts): this module is
// bundled into the WS/custom server via the Concierge tool's import chain, and
// esbuild cannot resolve the `server-only` guard package. Server-only by
// construction (spawns a CLI), only imported by server code.
import { spawn } from "node:child_process";
import { lstat, mkdir, mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { canonicalizeC4Model } from "@/lib/c4-canonical.mjs";
import { C4_MODEL_JSON } from "@/lib/c4-constants";
import { c4RenderStagingRoot } from "@/server/c4-staging-root";
import type { RefusalClass, StageResult } from "@/server/c4-stage-sources";

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
  | "unsafe_source";

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
    };

export type RenderResult =
  // `json` is the validated model in the CANONICAL on-disk format (one JSON
  // value per line, view hashes blanked — lib/c4-canonical.mjs, #8542). The
  // repo regenerator and the plugin's sync producer emit the same bytes through
  // the same module, so no writer reformats another's committed file.
  | { ok: true; durationMs: number; json: string }
  | RenderFailure;

// Staging fetches over the network; it gets its own budget, separate from the
// spawn's, and runs before a render slot is taken (#8623).
export const STAGE_DEADLINE_MS = 10_000;
export const STAGE_DEADLINE_DETAIL = "stage: deadline";

// Real prod model exports in <1s (verified 2026-06-05); 25s is a ceiling that
// leaves headroom for a cold first invocation while staying under the PUT
// route's maxDuration=60 (commit + sync + render + commit + sync).
const RENDER_TIMEOUT_MS = 25_000;

// Preinstalled in the runner image (Dockerfile `npm install -g likec4@1.50.0`).
// Env override exists for tests / local dev only.
const LIKEC4_BIN = process.env.LIKEC4_BIN || "likec4";

// Concurrency gate — caps concurrent wasm-layout subprocesses per replica so
// peak RAM stays bounded under burst saves. Default 2, env-overridable via
// C4_RENDER_CONCURRENCY, clamped to [1, 16]. Captured at module load (ops
// changes require a container restart, the intended path). Mirrors
// pdf-linearize.ts's POOL_SIZE.
const POOL_SIZE = (() => {
  const raw = Number(process.env.C4_RENDER_CONCURRENCY);
  if (!Number.isFinite(raw) || raw < 1) return 2;
  return Math.min(Math.floor(raw), 16);
})();

let inFlight = 0;
const waiters: Array<() => void> = [];

function acquire(): Promise<void> {
  if (inFlight < POOL_SIZE) {
    inFlight++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    waiters.push(() => {
      inFlight++;
      resolve();
    });
  });
}

function release(): void {
  inFlight--;
  const next = waiters.shift();
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
      reason: "spawn_error" | "non_zero_exit" | "timeout";
      detail?: string;
    };

/**
 * Regenerate `model.likec4.json` by staging the render input with `stage` into
 * a private directory, then spawning the preinstalled `likec4` CLI
 * (`likec4 export json -o <dir>/model.likec4.json .`) with cwd = `<dir>/src`.
 * VALIDATE the produced model is non-empty, and on success RETURN the
 * validated bytes as `json` — the caller commits them. The tracked working-tree
 * `model.likec4.json` is never written by this path (#4976), and no workspace
 * path is ever read (#8623). An empty/invalid export returns
 * `{ ok:false, reason:"empty_model" }` with no `json`.
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
    await acquire();
    try {
      // Re-verify the stage just before the spawn: exactly the files the stage
      // reported, regular files and directories only. The staging root is
      // unreachable from the agent sandbox; this makes the input guarantee
      // local instead of resting on that alone.
      if (!(await stageMatches(srcDir, staged.paths))) {
        return { ok: false, reason: "io_error", detail: "stage: contents changed before render", phase: "stage" };
      }
      return await renderToValidatedModel(srcDir, dir, join(dir, C4_MODEL_JSON));
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
    await rm(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 }).catch(() => {});
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
  srcDir: string,
  home: string,
  tmpOut: string,
): Promise<RenderResult> {
  // The validated bytes are RETURNED, never published onto the tracked path
  // (#4976), so an invalid render never clobbers the previously-good committed
  // model. `tmpOut` sits OUTSIDE `srcDir`, so it is not part of likec4's input.
  try {
    const run = await runLikeC4(srcDir, home, tmpOut);
    if (!run.ok) return { ...run, phase: "spawn" };

    // exit 0 — but likec4 exits 0 on unresolved references too, so validate
    // the raw read first; canonicalization happens only after the gate.
    let raw: string;
    let model: { elements?: unknown };
    try {
      raw = await readFile(tmpOut, "utf8");
      model = JSON.parse(raw) as { elements?: unknown };
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
      };
    }

    // Gate on a NON-EMPTY plain object of elements. `elements` is untrusted CLI
    // output — a non-empty string/array would make a bare `Object.keys(…)` non-
    // zero and let a malformed export through (the exact clobber this prevents).
    const els = model.elements;
    const elementCount =
      els && typeof els === "object" && !Array.isArray(els)
        ? Object.keys(els).length
        : 0;
    if (elementCount === 0) {
      // The diagnostic IS the captured stderr (the `Could not resolve …` lines);
      // gate on element count, never on stderr substring (wording can drift
      // across likec4 patch versions).
      return {
        ok: false,
        phase: "spawn",
        reason: "empty_model",
        detail: run.stderr || "model has no elements",
      };
    }

    // Validated — canonicalize (AFTER the gate, never instead of it) and return
    // the bytes; the caller commits them and the resync pull lands them on disk.
    // The tracked working-tree file is never written. A canonicalize failure is
    // our own IO-class fault, not the user's source, so it maps to io_error.
    // A relative `icon` resolves to a file:// URI under the stage dir, whose
    // name is random per render; replace that prefix with a stable token so
    // the committed model does not change on every save or disclose the
    // server's staging layout.
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
      };
    }
    return { ok: true, durationMs: run.durationMs, json };
  } catch (err) {
    return {
      ok: false,
      phase: "spawn",
      reason: "io_error",
      detail: sanitizeForLog(err instanceof Error ? err.message : String(err)),
    };
  }
}

function runLikeC4(
  srcDir: string,
  home: string,
  outPath: string,
): Promise<SpawnResult> {
  return new Promise((resolve) => {
    const start = Date.now();
    let settled = false;
    const settle = (r: SpawnResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(r);
    };
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      settle({
        ok: false,
        reason: "timeout",
        detail: `exceeded ${RENDER_TIMEOUT_MS}ms`,
      });
    }, RENDER_TIMEOUT_MS);

    // The same scoped allow-list as pdf-linearize.ts; no secrets reach the
    // child. HOME is the private per-render dir, not the server's: node's
    // module fallback executes `$HOME/.node_modules/<optional dep>` and likec4
    // keeps a config store under `$HOME/.config`, so a real HOME would be one
    // more input outside the stage (#8623 structural review).
    const env = {
      ...Object.fromEntries(
        (["PATH", "LANG", "LC_ALL", "TMPDIR"] as const)
          .map((k) => [k, process.env[k]] as const)
          .filter(([, v]) => v !== undefined),
      ),
      HOME: home,
    } as unknown as NodeJS.ProcessEnv;

    // Fixed argv except the `-o` target, which is a private temp path (from
    // mkdtemp) — never a user-controlled filename. cwd is the private stage
    // dir holding only the staged sources. No user input in argv.
    const child = spawn(
      LIKEC4_BIN,
      ["export", "json", "-o", outPath, "."],
      { cwd: srcDir, env, stdio: ["ignore", "ignore", "pipe"] },
    );

    const stderrChunks: Buffer[] = [];
    child.stderr?.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err: Error) =>
      settle({ ok: false, reason: "spawn_error", detail: err.message }),
    );
    child.on("close", (code: number | null, signal: string | null) => {
      // Capture stderr on EVERY exit — likec4 prints `Could not resolve …`
      // validation errors to stderr even when it exits 0, and the caller folds
      // them into the `empty_model` diagnostic.
      const stderr = sanitizeForLog(
        Buffer.concat(stderrChunks).toString("utf8").slice(0, 512),
      );
      if (code === 0) {
        settle({ ok: true, durationMs: Date.now() - start, stderr });
        return;
      }
      const exitPart = code === null ? `signal=${signal}` : `exit=${code}`;
      settle({
        ok: false,
        reason: "non_zero_exit",
        detail: `${exitPart} stderr=${stderr}`,
      });
    });
  });
}
