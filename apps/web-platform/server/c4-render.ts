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
// element — then copy it onto the real `model.likec4.json`. An empty/invalid
// export therefore NEVER clobbers the previously-good committed model; it
// returns `{ ok:false, reason:"empty_model" }` so the writer keeps the old JSON
// and the client shows the honest staleness banner.
//
// SECURITY: the only path that reaches the spawn is `diagramsDir`, derived from
// `workspacePath` + the `C4_DIAGRAMS_DIR` constant — never a user-controlled
// filename. The argv is fixed and the `-o` target is a process-temp path from
// `mkdtemp` (never user-controlled). So there is no command-injection or
// scope-escape surface here (the write-path scope guard `isC4DiagramPath`
// already gates which file was committed before this runs).
//
// No `import "server-only"` (same reason as c4-writer.ts): this module is
// bundled into the WS/custom server via the Concierge tool's import chain, and
// esbuild cannot resolve the `server-only` guard package. Server-only by
// construction (spawns a CLI), only imported by server code.
import { spawn } from "node:child_process";
import { mkdtemp, readFile, copyFile, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { C4_DIAGRAMS_DIR, C4_MODEL_JSON } from "@/lib/c4-constants";

export type RenderReason =
  | "spawn_error"
  | "non_zero_exit"
  | "timeout"
  // The export resolved but produced a model with zero elements — the user's
  // source is broken (typically a missing spec.c4). Distinct from io_error so
  // the writer surfaces a source-fault diagnostic ONLY for this reason.
  | "empty_model"
  // Our own IO failed (mkdtemp / parse / copy-publish) — NOT the user's source.
  | "io_error";

export type RenderResult =
  | { ok: true; durationMs: number }
  | { ok: false; reason: RenderReason; detail?: string };

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
 * Regenerate `model.likec4.json` by spawning the preinstalled `likec4` CLI
 * (`likec4 export json -o <temp> .`) with cwd = the workspace's diagrams dir,
 * VALIDATE the produced model is non-empty, and only then copy it onto the real
 * `model.likec4.json` (where the GET `/api/kb/c4/project` route reads it as
 * `dump` and the caller commits it). An empty/invalid export returns
 * `{ ok:false, reason:"empty_model" }` and leaves the real file untouched.
 */
export async function renderC4Model(
  workspacePath: string,
): Promise<RenderResult> {
  const diagramsDir = join(workspacePath, "knowledge-base", C4_DIAGRAMS_DIR);
  await acquire();
  try {
    return await renderToValidatedModel(diagramsDir);
  } finally {
    release();
  }
}

async function renderToValidatedModel(
  diagramsDir: string,
): Promise<RenderResult> {
  // Render to a per-call temp dir (collision-proof under POOL_SIZE concurrency
  // + multi-replica tmpfs; mirrors pdf-linearize.ts). The real model.likec4.json
  // is only touched on validated success, so an invalid render never clobbers
  // the previously-good model.
  const dir = await mkdtemp(join(tmpdir(), "c4-render-")).catch(() => null);
  if (!dir) {
    return { ok: false, reason: "io_error", detail: "mkdtemp failed" };
  }
  const tmpOut = join(dir, C4_MODEL_JSON);
  const realPath = join(diagramsDir, C4_MODEL_JSON);
  // Same-dir (same-filesystem) staging path so the final publish is an atomic
  // `rename` — a crash mid-copy can never truncate the previously-good model.
  // The mkdtemp suffix keeps it collision-proof under the concurrency gate.
  const stagePath = `${realPath}.stage-${basename(dir)}`;
  try {
    const run = await runLikeC4(diagramsDir, tmpOut);
    if (!run.ok) return run;

    // exit 0 — but likec4 exits 0 on unresolved references too, so validate.
    let model: { elements?: unknown };
    try {
      model = JSON.parse(await readFile(tmpOut, "utf8")) as { elements?: unknown };
    } catch (err) {
      return {
        ok: false,
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
        reason: "empty_model",
        detail: run.stderr || "model has no elements",
      };
    }

    // Validated — publish atomically onto the real path the GET reads + the
    // writer commits: copy into the same-dir stage, then rename over.
    await copyFile(tmpOut, stagePath);
    await rename(stagePath, realPath);
    return { ok: true, durationMs: run.durationMs };
  } catch (err) {
    return {
      ok: false,
      reason: "io_error",
      detail: sanitizeForLog(err instanceof Error ? err.message : String(err)),
    };
  } finally {
    // Trailing .catch so cleanup can never reject the resolved result (mirrors
    // pdf-linearize.ts). Clean BOTH the temp dir and any leftover stage file
    // (present only if rename never ran).
    await rm(dir, { recursive: true, force: true }).catch(() => {});
    await rm(stagePath, { force: true }).catch(() => {});
  }
}

function runLikeC4(
  diagramsDir: string,
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

    // HOME is in the allow-list (npm-global bin resolution); otherwise the same
    // scoped allow-list as pdf-linearize.ts. No secrets reach the child.
    const env = Object.fromEntries(
      (["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"] as const)
        .map((k) => [k, process.env[k]] as const)
        .filter(([, v]) => v !== undefined),
    ) as NodeJS.ProcessEnv;

    // Fixed argv except the `-o` target, which is a process-temp path (from
    // mkdtemp) — never a user-controlled filename. cwd is the scope-guarded
    // diagrams dir. No user input in argv.
    const child = spawn(
      LIKEC4_BIN,
      ["export", "json", "-o", outPath, "."],
      { cwd: diagramsDir, env, stdio: ["ignore", "ignore", "pipe"] },
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
