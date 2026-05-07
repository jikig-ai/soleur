// Regression test: pdfjs-dist must NOT be bundled into the production
// custom-server CJS — Sentry e8225a569fcd4b07a460b5b1bb2a5ee7 fired
// `ReferenceError: DOMMatrix is not defined` from `__init` inside the
// bundled `dist/server/index.cjs` because esbuild's bundler reordered
// pdfjs's legacy module init and the `if (isNodeJS) { ... DOMMatrix
// polyfill }` block ran out of order.
//
// Exercises the production build path that vitest's normal source-only
// runner cannot reach: the shared `bundleAndExec` helper bundles a
// fixture entry with the EXACT esbuild flags from
// `package.json:scripts.build:server` (parsed at runtime — drop
// `--external:pdfjs-dist` and the helper throws), then spawns Node
// against the resulting CJS.

import { describe, expect, it } from "vitest";
import { join } from "node:path";
import {
  bundleAndExec,
  VITEST_TIMEOUT_MS,
} from "./helpers/bundled-server";
import {
  BELOW_PDFJS_ENGINES_FLOOR,
  emitPdfjsEngineFloorDiagnostic,
} from "./helpers/engines-floor";

// Engine-floor guard (#3439). See `test/helpers/engines-floor.ts` and the
// sibling `pdf-text-extract.test.ts` for the rationale — the bundled CJS
// also imports pdfjs-dist and trips the same `process.getBuiltinModule`
// floor on Node <22.3.
emitPdfjsEngineFloorDiagnostic("pdf-text-extract.bundled-server.test");

interface PdfExtractOk {
  text: string;
  truncated: boolean;
  pageCount: number;
}
interface PdfExtractError {
  error: string;
}

describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("pdf-text-extract bundled-server (production CJS path)", () => {
  it(
    "extracts text from a fixture PDF when bundled with the production build:server flags",
    async () => {
      const entry = join(__dirname, "fixtures", "extract-entry.ts");
      const result = await bundleAndExec(entry, "extract");

      const ctx = {
        stdout: result.stdout.slice(0, 800),
        stderr: result.stderr.slice(0, 800),
        status: result.status,
      };

      // Pre-fix the bundled CJS threw `ReferenceError: DOMMatrix is not
      // defined` from `__init` — assert that exact Sentry-shape error
      // never surfaces in stderr so a regression diagnoses itself.
      expect(
        result.stderr.includes("DOMMatrix is not defined"),
        `unexpected DOMMatrix error: ${JSON.stringify(ctx)}`,
      ).toBe(false);

      // Loud, positive assertion: extract succeeded with the expected
      // shape. A `if ("text" in parsed)` guard would silently pass when
      // the entry returned `{ error: "..." }`.
      expect(
        result.parsed,
        `extract returned wrong shape: ${JSON.stringify({ parsed: result.parsed, ...ctx })}`,
      ).toMatchObject({
        text: expect.stringContaining("Hello PDF"),
        pageCount: 1,
        truncated: false,
      } satisfies Partial<PdfExtractOk>);
      expect(
        (result.parsed as PdfExtractError | PdfExtractOk),
        "extract should not surface error branch",
      ).not.toHaveProperty("error");
    },
    VITEST_TIMEOUT_MS,
  );
});
