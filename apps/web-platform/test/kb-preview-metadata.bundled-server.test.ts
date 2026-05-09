// Sibling regression test of pdf-text-extract.bundled-server.test.ts —
// see that file for protocol details. This test exercises the
// `readPdfMetadata` path (kb_share_preview, #2322) which used the same
// lazy `await import("pdfjs-dist/legacy/build/pdf.mjs")` long before
// `extractPdfText` was added. The bug has likely been latent here at
// WARN level via `warnSilentFallback({ op: "preview-pdf-parse" })`.

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

// Engine-floor guard (#3439). The bundled CJS imports pdfjs-dist for the
// `readPdfMetadata` path; same `process.getBuiltinModule` floor as
// extractPdfText. See `test/helpers/engines-floor.ts`.
emitPdfjsEngineFloorDiagnostic("kb-preview-metadata.bundled-server.test");

interface PdfPreviewShape {
  kind: "pdf";
  numPages: number;
  width: number;
  height: number;
}

describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("kb-preview-metadata bundled-server (production CJS path)", () => {
  it(
    "reads PDF metadata from a fixture when bundled with the production build:server flags",
    async () => {
      const entry = join(__dirname, "fixtures", "metadata-entry.ts");
      const result = await bundleAndExec(entry, "metadata");

      const ctx = {
        stdout: result.stdout.slice(0, 800),
        stderr: result.stderr.slice(0, 800),
        status: result.status,
      };

      expect(
        result.stderr.includes("DOMMatrix is not defined"),
        `unexpected DOMMatrix error: ${JSON.stringify(ctx)}`,
      ).toBe(false);

      // Loud, positive assertion: metadata extracted with the expected
      // shape. Pre-fix this path returned `null` via warnSilentFallback.
      expect(
        result.parsed,
        `metadata returned wrong shape: ${JSON.stringify({ parsed: result.parsed, ...ctx })}`,
      ).toMatchObject({
        kind: "pdf",
        numPages: 1,
      } satisfies Partial<PdfPreviewShape>);
    },
    VITEST_TIMEOUT_MS,
  );
});
