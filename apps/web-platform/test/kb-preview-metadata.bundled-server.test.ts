// Sibling regression test of pdf-text-extract.bundled-server.test.ts —
// see that file for protocol details. This test exercises the
// `readPdfMetadata` path (kb_share_preview, #2322) which used the same
// lazy `await import("pdfjs-dist/legacy/build/pdf.mjs")` long before
// `extractPdfText` was added. The bug has likely been latent here at
// WARN level via `warnSilentFallback({ op: "preview-pdf-parse" })`.

import { describe, it, expect } from "vitest";
import { build as esbuildBuild } from "esbuild";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

function parseExternalsAndTarget(): { externals: string[]; target: string } {
  const pkgPath = join(__dirname, "..", "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const script: string = pkg.scripts["build:server"];
  const externals = Array.from(
    script.matchAll(/--external:([^\s]+)/g),
    (m) => m[1],
  );
  const target = script.match(/--target=([^\s]+)/)?.[1] ?? "node22";
  return { externals, target };
}

async function bundleAndExec(entryRelToTest: string): Promise<{
  stdout: string;
  stderr: string;
  status: number | null;
}> {
  const { externals, target } = parseExternalsAndTarget();
  // Outfile inside apps/web-platform/dist/ so Node's upward node_modules
  // resolution finds @sentry/nextjs, pino, etc. (declared as externals).
  const appRoot = join(__dirname, "..");
  const outDir = join(appRoot, "dist", "test-bundle");
  mkdirSync(outDir, { recursive: true });
  const tmp = mkdtempSync(join(outDir, "metadata-"));
  const outfile = join(tmp, "entry-bundle.cjs");
  const entry = join(__dirname, entryRelToTest);

  try {
    await esbuildBuild({
      entryPoints: [entry],
      bundle: true,
      platform: "node",
      target,
      outfile,
      external: externals,
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

describe("kb-preview-metadata bundled-server (production CJS path)", () => {
  it(
    "reads PDF metadata from a fixture when bundled with the production build:server flags",
    async () => {
      const result = await bundleAndExec("./fixtures/metadata-entry.ts");

      const m = result.stdout.match(/<<<RESULT_BEGIN>>>(.*?)<<<RESULT_END>>>/s);
      const parsed = m
        ? (JSON.parse(m[1]) as
            | { kind: "pdf"; numPages: number; width: number; height: number }
            | null
            | { error: string })
        : null;

      const failureContext = {
        stdout: result.stdout.slice(0, 800),
        stderr: result.stderr.slice(0, 800),
        status: result.status,
      };

      expect(
        result.stderr.includes("DOMMatrix is not defined"),
        `unexpected DOMMatrix error in bundle: ${JSON.stringify(failureContext)}`,
      ).toBe(false);

      // RED before fix: `readPdfMetadata` returns null via warnSilentFallback.
      expect(
        parsed,
        `metadata returned null/error: ${JSON.stringify(failureContext)}`,
      ).not.toBeNull();

      if (parsed && "kind" in parsed) {
        expect(parsed.kind).toBe("pdf");
        expect(parsed.numPages).toBe(1);
      }
    },
    45_000,
  );
});
