// Bundled-server entry for `pdf-text-extract.bundled-server.test.ts`.
// esbuild bundles this file with the EXACT flags from
// `package.json:scripts.build:server`, then `node` execs the resulting
// CJS. Stdout is JSON-parsed by the test.
//
// This file MUST NOT import vitest or any test helpers — it is bundled
// standalone and run outside the test harness.

import { extractPdfText } from "../../server/pdf-text-extract";
import { TINY_PDF_BUFFER } from "./tiny-pdf";

// Result is wrapped in delimiters because pino, pdfjs warnings, and
// Sentry init may also write to stdout. The test extracts the JSON
// between <<<RESULT_BEGIN>>> and <<<RESULT_END>>>.
async function main(): Promise<void> {
  try {
    const result = await extractPdfText(TINY_PDF_BUFFER, 8000);
    process.stdout.write(
      `<<<RESULT_BEGIN>>>${JSON.stringify(result)}<<<RESULT_END>>>`,
    );
  } catch (err) {
    process.stdout.write(
      `<<<RESULT_BEGIN>>>${JSON.stringify({
        error: "uncaught",
        message: (err as Error)?.message ?? String(err),
      })}<<<RESULT_END>>>`,
    );
    process.exit(2);
  }
}

void main();
