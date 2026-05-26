// Synthesizes S2 spike fixture PDFs (KD-2 → AC #16).
//
// Why generated, not sourced from publishers: the parent plan's S2 manifest
// initially referenced "Manning/O'Reilly purchase" copies — per-seat licenses
// forbid redistribution, and even the `.gitignore`d-binary + sourceUrl-in-
// manifest pattern would create a written record pointing at copyrighted
// material. Synthetic content sidesteps that surface entirely (CLO refresh,
// bundle brainstorm KD-2). It also removes the archive.org/Wayback dependency
// the plan's earlier draft introduced for the no-outline fixture.
//
// Outputs (.gitignore'd binaries):
//   apps/web-platform/scripts/spike/fixtures/outline-bearing.pdf
//   apps/web-platform/scripts/spike/fixtures/no-outline.pdf
//
// Prints SHA-256 + byte count + pages + outline-entry count for each fixture.
// Operator (or implementer) pastes the SHA-256 values into
// pdf-outline-fixtures.json before running pdf-outline-coverage.ts.
//
// Run:
//   ./node_modules/.bin/tsx scripts/spike/generate-outline-fixture.ts

import PDFDocument from "pdfkit";
import { createWriteStream } from "node:fs";
import { mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

// ESM-safe __dirname equivalent (root package.json sets "type": "module").
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = path.join(__dirname, "fixtures");

interface OutlineEntry {
  title: string;
  pageStart: number;
}

interface GenerateOptions {
  outPath: string;
  totalPages: number;
  outlineEntries: OutlineEntry[] | null;
}

interface GenerateResult {
  sha256: string;
  bytes: number;
  pages: number;
  entries: number;
}

async function generatePdf(opts: GenerateOptions): Promise<GenerateResult> {
  const doc = new PDFDocument({
    autoFirstPage: false,
    info: { Title: "Soleur S2 spike fixture (synthetic)" },
  });

  const stream = createWriteStream(opts.outPath);
  doc.pipe(stream);

  // Index outline entries by the page they reference. pdfkit's
  // doc.outline.addItem(title) ties the new entry to the CURRENT page,
  // so the page MUST be added before the entry — hence the per-page lookup.
  const outlineMap = new Map<number, OutlineEntry[]>();
  for (const entry of opts.outlineEntries ?? []) {
    const existing = outlineMap.get(entry.pageStart) ?? [];
    existing.push(entry);
    outlineMap.set(entry.pageStart, existing);
  }

  const fillerSentence = "Synthetic spike content; not a real book. ";
  for (let p = 1; p <= opts.totalPages; p++) {
    doc.addPage({
      size: "A4",
      margins: { top: 50, bottom: 50, left: 50, right: 50 },
    });
    for (const entry of outlineMap.get(p) ?? []) {
      doc.outline.addItem(entry.title);
    }
    doc.fontSize(12).text(
      `Page ${p}\n\n${fillerSentence.repeat(40)}`,
      { align: "left" },
    );
  }

  doc.end();
  await new Promise<void>((resolve, reject) => {
    stream.on("finish", () => resolve());
    stream.on("error", reject);
  });

  const buf = await readFile(opts.outPath);
  return {
    sha256: createHash("sha256").update(buf).digest("hex"),
    bytes: buf.length,
    pages: opts.totalPages,
    entries: opts.outlineEntries?.length ?? 0,
  };
}

async function main(): Promise<void> {
  await mkdir(FIXTURES_DIR, { recursive: true });

  // Outline-bearing fixture: 250 pages, 12 top-level chapter entries.
  // Plan constraints:
  //   - ≥10 top-level entries (we have 12) → passes MIN_OUTLINE_ENTRIES = 3
  //   - Last entry starts ≥ 80% into the book: 221/250 = 0.884 → passes
  //     OUTLINE_PAGE_COVERAGE_MIN = 0.8
  //   - Each dest resolves via getDestination → getPageIndex (pdfkit emits
  //     explicit destination arrays for outline items added against the
  //     current page; extractPdfOutline's resolveStartPage0 accepts both
  //     string-named and explicit-array forms)
  //   - 200-500 page band (we have 250)
  const outlineEntries: OutlineEntry[] = [
    { title: "Chapter 1: Introduction", pageStart: 1 },
    { title: "Chapter 2: Foundations", pageStart: 21 },
    { title: "Chapter 3: Core Concepts", pageStart: 41 },
    { title: "Chapter 4: Implementation Patterns", pageStart: 61 },
    { title: "Chapter 5: Advanced Topics", pageStart: 81 },
    { title: "Chapter 6: Performance", pageStart: 101 },
    { title: "Chapter 7: Security", pageStart: 121 },
    { title: "Chapter 8: Testing", pageStart: 141 },
    { title: "Chapter 9: Deployment", pageStart: 161 },
    { title: "Chapter 10: Operations", pageStart: 181 },
    { title: "Chapter 11: Case Studies", pageStart: 201 },
    { title: "Chapter 12: Future Directions", pageStart: 221 },
  ];
  const outlineBearing = await generatePdf({
    outPath: path.join(FIXTURES_DIR, "outline-bearing.pdf"),
    totalPages: 250,
    outlineEntries,
  });
  console.log("outline-bearing.pdf:");
  console.log(`  sha256: ${outlineBearing.sha256}`);
  console.log(`  bytes:  ${outlineBearing.bytes}`);
  console.log(`  pages:  ${outlineBearing.pages}`);
  console.log(`  entries: ${outlineBearing.entries}`);
  const lastStart = outlineEntries[outlineEntries.length - 1].pageStart;
  console.log(
    `  coverage: ${(lastStart / outlineBearing.pages).toFixed(3)} ` +
      `(${lastStart}/${outlineBearing.pages}; ≥0.8 required)`,
  );

  // No-outline fixture: 100 pages, no /Outlines tree. Asserts the
  // resolver falls through to too_many_pages bridge. Synthetic but
  // sufficient for the spike — the test under examination is "does
  // pdfjs.getOutline() return null/[]?", not "does our heuristic
  // generalize to scanned books." Scanned-book heuristic generalization
  // is a post-launch telemetry question (parent plan post-merge AC #20).
  const noOutline = await generatePdf({
    outPath: path.join(FIXTURES_DIR, "no-outline.pdf"),
    totalPages: 100,
    outlineEntries: null,
  });
  console.log("\nno-outline.pdf:");
  console.log(`  sha256: ${noOutline.sha256}`);
  console.log(`  bytes:  ${noOutline.bytes}`);
  console.log(`  pages:  ${noOutline.pages}`);
  console.log(`  entries: ${noOutline.entries}`);
}

main().catch((err) => {
  console.error("Generator crashed:", err);
  process.exit(1);
});
