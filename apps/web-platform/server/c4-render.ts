// Server-only: regenerate the precomputed, layouted `model.likec4.json` by
// spawning the preinstalled `likec4` CLI out-of-process. Called from the C4
// write path (writeC4Diagram) after a `.c4` source is committed + synced, so a
// Code-tab Save (or the Concierge edit_c4_diagram tool) actually re-renders the
// diagram instead of leaving a stale layout (#4964, follow-up to #4963 Layer 1).
//
// Modeled verbatim on server/pdf-linearize.ts: bounded timeout → SIGKILL,
// settle-once promise, scoped env, concurrency gate, reason-typed result. The
// only structural deltas are (a) cwd = the scope-guarded diagrams dir (likec4
// exports in place) instead of tempfile paths, and (b) HOME in the env
// allow-list (npm-global `likec4` bin resolution needs it).
//
// SECURITY: the only path that reaches the spawn is `diagramsDir`, derived from
// `workspacePath` + the `C4_DIAGRAMS_DIR` constant — never a user-controlled
// filename. The argv is fixed. So there is no command-injection or scope-escape
// surface here (the write-path scope guard `isC4DiagramPath` already gates which
// file was committed before this runs).
//
// No `import "server-only"` (same reason as c4-writer.ts): this module is
// bundled into the WS/custom server via the Concierge tool's import chain, and
// esbuild cannot resolve the `server-only` guard package. Server-only by
// construction (spawns a CLI), only imported by server code.
import { spawn } from "node:child_process";
import { join } from "node:path";
import { C4_DIAGRAMS_DIR, C4_MODEL_JSON } from "@/lib/c4-constants";

export type RenderReason = "spawn_error" | "non_zero_exit" | "timeout";

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

function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?");
}

/**
 * Regenerate `model.likec4.json` in place under the workspace's diagrams dir by
 * spawning the preinstalled `likec4` CLI (`likec4 export json -o
 * model.likec4.json .`). The JSON is written into the cwd (diagrams dir),
 * exactly where the GET
 * `/api/kb/c4/project` route reads it as `dump` and where the caller commits it.
 */
export async function renderC4Model(
  workspacePath: string,
): Promise<RenderResult> {
  const diagramsDir = join(workspacePath, "knowledge-base", C4_DIAGRAMS_DIR);
  await acquire();
  try {
    return await runLikeC4(diagramsDir);
  } finally {
    release();
  }
}

function runLikeC4(diagramsDir: string): Promise<RenderResult> {
  return new Promise((resolve) => {
    const start = Date.now();
    let settled = false;
    const settle = (r: RenderResult) => {
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

    // Fixed argv — `model.likec4.json` and `.` are constants; the only variable
    // is the cwd (the scope-guarded diagrams dir). No user input in argv.
    const child = spawn(
      LIKEC4_BIN,
      ["export", "json", "-o", C4_MODEL_JSON, "."],
      { cwd: diagramsDir, env, stdio: ["ignore", "ignore", "pipe"] },
    );

    const stderrChunks: Buffer[] = [];
    child.stderr?.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err: Error) =>
      settle({ ok: false, reason: "spawn_error", detail: err.message }),
    );
    child.on("close", (code: number | null, signal: string | null) => {
      if (code === 0) {
        settle({ ok: true, durationMs: Date.now() - start });
        return;
      }
      const exitPart = code === null ? `signal=${signal}` : `exit=${code}`;
      const stderr = sanitizeForLog(
        Buffer.concat(stderrChunks).toString("utf8").slice(0, 512),
      );
      settle({
        ok: false,
        reason: "non_zero_exit",
        detail: `${exitPart} stderr=${stderr}`,
      });
    });
  });
}
