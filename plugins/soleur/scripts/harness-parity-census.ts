#!/usr/bin/env bun
/**
 * Harness-parity census over the plugin doc population (ADR-226, #8299).
 *
 * Usage:
 *   bun plugins/soleur/scripts/harness-parity-census.ts --report   # print every non-canonical site; exit 1 if any
 *   bun plugins/soleur/scripts/harness-parity-census.ts --fix      # rewrite the mechanical shapes in place (idempotent)
 *
 * The gate is `plugins/soleur/test/harness-parity-tree.test.ts`; this CLI is the author's
 * inner loop and the remediation tool. `--fix` inverts only `/soleur:x`, `$soleur:x`,
 * `@agent-soleur:x` and grok `/x` for a known skill; bare agent leaves, `@agent-<leaf>`
 * mentions and grok stems in prose are hand edits (the sentence around them changes).
 */

import { writeFileSync } from "fs";
import { resolve } from "path";
import { REPO_ROOT, census, fixDoc, formatReport, readIndex, readPopulation } from "../lib/harness-parity";

const args = new Set(process.argv.slice(2));
const mode = args.has("--fix") ? "fix" : args.has("--report") ? "report" : undefined;
if (mode === undefined) {
  console.error("usage: harness-parity-census.ts --report | --fix");
  process.exit(2);
}

const index = readIndex();
const docs = readPopulation();

if (mode === "fix") {
  let changed = 0;
  for (const doc of docs) {
    const fixed = fixDoc(doc.text, index, doc.regionPolicy);
    if (fixed !== doc.text) {
      writeFileSync(resolve(REPO_ROOT, doc.path), fixed);
      changed += 1;
      console.log(`fixed ${doc.path}`);
    }
  }
  const after = census(readPopulation(), index);
  console.log(`harness-parity --fix: ${changed} docs rewritten; ${after.noncanonical.length} non-canonical sites remain (hand edits)`);
  process.exit(0);
}

const result = census(docs, index);
console.log(formatReport(result));
if (result.noncanonical.length > 0 || result.errors.length > 0) {
  console.log(
    `\nRED: ${result.noncanonical.length} non-canonical sites, ${result.errors.length} marker errors. ` +
      "Run `bun plugins/soleur/scripts/harness-parity-census.ts --fix` for the mechanical shapes; the rest are hand edits.",
  );
  process.exit(1);
}
