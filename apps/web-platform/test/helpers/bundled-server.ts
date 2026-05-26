// Shared harness for bundled-server regression tests.
//
// Bundles a fixture entry with the EXACT esbuild flags from
// `apps/web-platform/package.json:scripts.build:server`, then spawns
// `node` against the resulting CJS. Used by:
//   - test/pdf-text-extract.bundled-server.test.ts
//   - test/kb-preview-metadata.bundled-server.test.ts
//
// The flag set is parsed at runtime from package.json so that a future
// PR removing `--external:pdfjs-dist` (or any other load-bearing
// external) re-fails the regression tests instead of regressing
// silently in production.

import { build as esbuildBuild } from "esbuild";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

export const SPAWN_TIMEOUT_MS = 25_000;
export const VITEST_TIMEOUT_MS = 45_000;
// Encode the invariant: the vitest per-test timeout must comfortably
// exceed the spawn timeout + esbuild compile + Node start overhead.
if (VITEST_TIMEOUT_MS <= SPAWN_TIMEOUT_MS) {
  throw new Error(
    `VITEST_TIMEOUT_MS (${VITEST_TIMEOUT_MS}) must exceed SPAWN_TIMEOUT_MS (${SPAWN_TIMEOUT_MS}) + bundling overhead`,
  );
}

const APP_ROOT = join(__dirname, "..", "..");
const TEST_BUNDLE_DIR = join(APP_ROOT, "dist", "test-bundle");

interface BuildServerScriptConfig {
  externals: string[];
  target: string;
  format: "cjs" | "esm";
}

export function parseBuildServerScript(): BuildServerScriptConfig {
  const pkgPath = join(APP_ROOT, "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as {
    scripts?: Record<string, string>;
  };
  const script = pkg.scripts?.["build:server"];
  if (!script) throw new Error("package.json missing scripts.build:server");

  const externals = Array.from(
    script.matchAll(/--external:([^\s]+)/g),
    (m) => m[1],
  );
  const target = script.match(/--target=([^\s]+)/)?.[1];
  if (!target) throw new Error("build:server missing --target=");

  const format: "cjs" | "esm" = script.includes("--format=esm") ? "esm" : "cjs";

  // Load-bearing flag for the production server bundle. If a future PR
  // drops it, the bundled-server regression tests must re-fail RED with
  // `ReferenceError: DOMMatrix is not defined` — not silently pass on a
  // mis-parsed script string.
  if (!externals.includes("pdfjs-dist")) {
    throw new Error(
      "build:server is missing --external:pdfjs-dist — see knowledge-base/project/plans/2026-05-07-fix-pdfjs-dommatrix-bundled-server-plan.md",
    );
  }

  return { externals, target, format };
}

export interface BundledExecResult {
  stdout: string;
  stderr: string;
  status: number | null;
  /** Parsed JSON between <<<RESULT_BEGIN>>>...<<<RESULT_END>>> delimiters, or null if absent. */
  parsed: unknown;
}

const RESULT_DELIMITER_RE = /<<<RESULT_BEGIN>>>(.*?)<<<RESULT_END>>>/s;

/**
 * Bundle `entry` with the production `build:server` flag set, exec the
 * resulting CJS via Node, and return the stdout/stderr/status plus the
 * parsed JSON the entry wrote between `<<<RESULT_BEGIN>>>...<<<RESULT_END>>>`.
 */
export async function bundleAndExec(
  entry: string,
  prefix: string,
): Promise<BundledExecResult> {
  // dist/ is gitignored; the per-call mkdtempSync subdir is removed in
  // `finally`. SIGINT/OOM-killed runs may leak the subdir, but parallel
  // vitest workers MUST NOT rmSync the shared parent — that races with
  // sibling bundles in flight.
  const cfg = parseBuildServerScript();
  // Outfile lives inside `apps/web-platform/dist/` so Node's upward
  // node_modules resolution finds the externalized packages
  // (@sentry/nextjs, pino, pdfjs-dist, etc.).
  mkdirSync(TEST_BUNDLE_DIR, { recursive: true });
  const tmp = mkdtempSync(join(TEST_BUNDLE_DIR, `${prefix}-`));
  const outfile = join(tmp, "entry-bundle.cjs");

  try {
    await esbuildBuild({
      entryPoints: [entry],
      bundle: true,
      platform: "node",
      target: cfg.target,
      outfile,
      external: cfg.externals,
      format: cfg.format,
      logLevel: "silent",
    });

    const res = spawnSync(process.execPath, [outfile], {
      encoding: "utf8",
      timeout: SPAWN_TIMEOUT_MS,
      cwd: APP_ROOT,
    });

    const stdout = res.stdout ?? "";
    const stderr = res.stderr ?? "";
    const m = stdout.match(RESULT_DELIMITER_RE);
    const parsed: unknown = m ? JSON.parse(m[1]) : null;

    return { stdout, stderr, status: res.status, parsed };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
