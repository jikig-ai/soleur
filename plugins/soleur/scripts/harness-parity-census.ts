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
 *
 * `--fix` REWRITES TRACKED FILES IN PLACE and is the remedy the gate's own failure message
 * prescribes, so it refuses to run against a dirty working tree unless `--force` is passed.
 * That is not ceremony: a grok slash and a root-relative path are lexically identical after a
 * boundary character (`run /plan` vs `POST /invoice`), so a rewrite CAN consume a real byte,
 * and the result then classifies CANONICAL — meaning the census reports clean and the loss is
 * invisible to the gate. Requiring a clean tree makes every rewrite reviewable with `git diff`
 * and revertible with `git checkout`, which is the only guard that covers the whole class
 * rather than one spelling of it.
 */

import { execFileSync } from "child_process";
import { writeFileSync } from "fs";
import { resolve } from "path";
import { REPO_ROOT, census, fixDoc, formatReport, readIndex, readPopulation } from "../lib/harness-parity";

const args = new Set(process.argv.slice(2));
const mode = args.has("--fix") ? "fix" : args.has("--report") ? "report" : undefined;
if (mode === undefined) {
  console.error("usage: harness-parity-census.ts --report | --fix [--force]");
  process.exit(2);
}

if (mode === "fix" && !args.has("--force")) {
  const dirty = execFileSync("git", ["status", "--porcelain", "--", "plugins/soleur"], {
    cwd: REPO_ROOT,
    encoding: "utf-8",
  }).trim();
  if (dirty.length > 0) {
    console.error(
      [
        "harness-parity --fix: refusing to rewrite a dirty tree — it edits tracked files in place,",
        "and an uncommitted change would be indistinguishable from its own rewrites in `git diff`.",
        "Commit or discard the changes below, then re-run; pass --force to override.",
        "",
        dirty,
      ].join("\n"),
    );
    process.exit(2);
  }
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
      "Run `bun plugins/soleur/scripts/harness-parity-census.ts --fix` for the mechanical shapes (it requires a clean tree, so its rewrites stay reviewable with `git diff`); the rest are hand edits.",
  );
  process.exit(1);
}
