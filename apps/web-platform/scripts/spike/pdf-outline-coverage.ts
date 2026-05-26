// S2 spike for #3436: probe pdfjs `getOutline()` coverage on real-world PDFs.
//
// Gates Phase 2 of `2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md`.
// Operator drops fixture PDFs in `scripts/spike/fixtures/` (see manifest in
// `pdf-outline-fixtures.json`), records SHA-256 in the manifest, then runs:
//
//   doppler run -p soleur -c dev -- ./node_modules/.bin/tsx \
//     scripts/spike/pdf-outline-coverage.ts
//
// GREEN: each fixture matches its expected classification (outline-bearing →
// usable; scanned → fall-through). RED: revisit brainstorm (#3436 may need
// embedding-based retrieval (#3450) instead of chapter-chunking).

import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { extractPdfOutline } from "../../server/pdf-text-extract";

// ESM-safe __dirname (root package.json sets "type": "module"). Fixes a
// pre-existing ESM-incompatibility shipped by PR #3440 that surfaced when
// the spike was first executed in the bundle PR (#3474 follow-through).
const __dirname = path.dirname(fileURLToPath(import.meta.url));

interface FixtureSpec {
  name: string;
  filename: string;
  expected: "usable" | "fall-through";
  minPages?: number;
  maxPages?: number;
  minOutlineEntries?: number;
  minPageCoverage?: number;
  sha256: string;
  sourceUrl: string;
  notes?: string;
}

interface Manifest {
  fixtures: FixtureSpec[];
}

async function main(): Promise<void> {
  const manifestPath = path.join(__dirname, "pdf-outline-fixtures.json");
  const manifest: Manifest = JSON.parse(await readFile(manifestPath, "utf-8"));

  const fixturesDir = path.join(__dirname, "fixtures");
  const results: Array<{
    name: string;
    expected: string;
    actual: string;
    sha256Match: boolean;
    details: Record<string, unknown>;
  }> = [];

  for (const fixture of manifest.fixtures) {
    const filePath = path.join(fixturesDir, fixture.filename);
    let buffer: Buffer;
    try {
      buffer = await readFile(filePath);
    } catch (err) {
      results.push({
        name: fixture.name,
        expected: fixture.expected,
        actual: "missing",
        sha256Match: false,
        details: {
          error: `Fixture not found at ${filePath}. Drop the file there per manifest source URL.`,
          sourceUrl: fixture.sourceUrl,
        },
      });
      continue;
    }

    const actualSha = createHash("sha256").update(buffer).digest("hex");
    const sha256Match = actualSha === fixture.sha256;

    const outlineResult = await extractPdfOutline(buffer);
    let actualClass: string;
    const details: Record<string, unknown> = {
      bytes: buffer.length,
      actualSha,
      expectedSha: fixture.sha256,
    };

    if (outlineResult.ok) {
      actualClass = "usable";
      details.outlineEntries = outlineResult.outline.length;
      details.firstEntries = outlineResult.outline.slice(0, 5).map((c) => ({
        title: c.title,
        startPage: c.startPage,
        endPage: c.endPage,
        depth: c.depth,
      }));
    } else {
      actualClass = `fall-through:${outlineResult.reason}`;
    }

    results.push({
      name: fixture.name,
      expected: fixture.expected,
      actual: actualClass,
      sha256Match,
      details,
    });
  }

  console.log(JSON.stringify({ results }, null, 2));

  const allMatch = results.every(
    (r) =>
      (r.expected === "usable" && r.actual === "usable") ||
      (r.expected === "fall-through" && r.actual.startsWith("fall-through")),
  );
  console.log(
    `\nS2 ${allMatch ? "GREEN" : "RED"}: ${
      allMatch
        ? "Both fixtures match expected classification. Proceed with Phase 2."
        : "At least one fixture deviated. Revisit brainstorm before Phase 2 — chapter-chunking may not be the right v1 design (consider #3450 embedding retrieval)."
    }`,
  );

  process.exit(allMatch ? 0 : 1);
}

main().catch((err) => {
  console.error("Spike crashed:", err);
  process.exit(2);
});
