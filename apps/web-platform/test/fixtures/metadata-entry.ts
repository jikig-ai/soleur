// Bundled-server entry for `kb-preview-metadata.bundled-server.test.ts`.
// See sibling extract-entry.ts for protocol details.

import { Readable } from "node:stream";
import { readPdfMetadata } from "../../server/kb-preview-metadata";
import { TINY_PDF_BUFFER } from "./tiny-pdf";

async function main(): Promise<void> {
  try {
    const stream = Readable.from([TINY_PDF_BUFFER]);
    const result = await readPdfMetadata(stream);
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
