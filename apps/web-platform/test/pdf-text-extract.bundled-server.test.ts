// Regression test: pdfjs-dist must NOT be bundled into the production
// custom-server CJS — Sentry e8225a569fcd4b07a460b5b1bb2a5ee7 fired
// `ReferenceError: DOMMatrix is not defined` from `__init` inside the
// bundled `dist/server/index.cjs` because esbuild's bundler reordered
// pdfjs's legacy module init and the `if (isNodeJS) { ... DOMMatrix
// polyfill }` block ran out of order.
//
// This test exercises the production build path that vitest's normal
// source-only runner cannot reach: it bundles a tiny entry file with the
// EXACT esbuild flags from `package.json:scripts.build:server`, then
// spawns `node` to exec the resulting `.cjs`. The flag set is read from
// package.json so a future drop of `--external:pdfjs-dist` re-fails this
// test instead of regressing silently in prod.

import { describe, it, expect } from "vitest";
import { build as esbuildBuild } from "esbuild";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

interface BuildServerScript {
  externals: string[];
  platform: "node";
  target: string;
  format: undefined; // build:server emits CJS by default — no --format flag
}

function parseBuildServerScript(): BuildServerScript {
  const pkgPath = join(__dirname, "..", "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const script: string = pkg.scripts["build:server"];
  if (!script) throw new Error("package.json missing scripts.build:server");

  const externals: string[] = [];
  for (const match of script.matchAll(/--external:([^\s]+)/g)) {
    externals.push(match[1]);
  }
  const targetMatch = script.match(/--target=([^\s]+)/);
  if (!targetMatch) throw new Error("build:server missing --target");

  return {
    externals,
    platform: "node",
    target: targetMatch[1],
    format: undefined,
  };
}

async function bundleAndExec(entryRelToTest: string): Promise<{
  stdout: string;
  stderr: string;
  status: number | null;
}> {
  const cfg = parseBuildServerScript();
  // Write the bundle inside apps/web-platform/dist/test-bundle/ so Node's
  // upward node_modules resolution finds @sentry/nextjs, pino, etc.
  // (externals declared in build:server). A /tmp outfile would work for
  // the bundling step but spawnSync(node, [outfile]) would fail at
  // require resolution.
  const appRoot = join(__dirname, "..");
  const outDir = join(appRoot, "dist", "test-bundle");
  mkdirSync(outDir, { recursive: true });
  const tmp = mkdtempSync(join(outDir, "extract-"));
  const outfile = join(tmp, "entry-bundle.cjs");
  const entry = join(__dirname, entryRelToTest);

  try {
    await esbuildBuild({
      entryPoints: [entry],
      bundle: true,
      platform: cfg.platform,
      target: cfg.target,
      outfile,
      external: cfg.externals,
      // CJS format matches the production bundle.
      format: "cjs",
      logLevel: "silent",
    });

    const res = spawnSync(process.execPath, [outfile], {
      encoding: "utf8",
      timeout: 25_000,
      cwd: appRoot,
    });

    return {
      stdout: res.stdout ?? "",
      stderr: res.stderr ?? "",
      status: res.status,
    };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

describe("pdf-text-extract bundled-server (production CJS path)", () => {
  it(
    "extracts text from a fixture PDF when bundled with the production build:server flags",
    async () => {
      const result = await bundleAndExec("./fixtures/extract-entry.ts");

      // If RED, the bundle reorders pdfjs's polyfill block and the
      // dynamic import throws `ReferenceError: DOMMatrix is not defined`,
      // which extractPdfText catches and surfaces as
      // `{ error: "lazy_import_failed" }` (with the message mirrored to
      // Sentry in prod). Result is wrapped in delimiters because pino /
      // pdfjs warnings may share stdout.
      const m = result.stdout.match(/<<<RESULT_BEGIN>>>(.*?)<<<RESULT_END>>>/s);
      const parsed = m
        ? (JSON.parse(m[1]) as
            | { text: string; truncated: boolean; pageCount: number }
            | { error: string })
        : { error: "no_stdout" };

      const failureContext = {
        stdout: result.stdout.slice(0, 800),
        stderr: result.stderr.slice(0, 800),
        status: result.status,
      };

      // Capture Sentry-shape ReferenceError so a regression diagnoses
      // itself in CI.
      expect(
        result.stderr.includes("DOMMatrix is not defined"),
        `unexpected DOMMatrix error in bundle: ${JSON.stringify(failureContext)}`,
      ).toBe(false);

      expect(
        "error" in parsed ? parsed.error : null,
        `extract returned error: ${JSON.stringify({ parsed, ...failureContext })}`,
      ).toBeNull();

      if ("text" in parsed) {
        expect(parsed.text).toContain("Hello PDF");
        expect(parsed.pageCount).toBe(1);
      }
    },
    45_000,
  );
});
