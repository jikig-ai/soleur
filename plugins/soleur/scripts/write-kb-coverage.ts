#!/usr/bin/env bun
// CLI wrapper for the sync coverage summary (#7332, plan Phase 3). Pure logic lives
// in ../lib/kb-coverage.ts; this file owns the filesystem and stdout.
//
// Writes knowledge-base/project/kb-coverage.md and prints the same
// SOLEUR_KB_SYNC_PRODUCERS marker to stdout — observability layer 7
// (`cli-stdout-artifact`). Both surfaces carry a byte-identical field set.
//
// ‼️ COUNTS ARE DERIVED FROM KB STATE, NOT PASSED IN AS FLAGS.
//
// The first version took `--c4-elements` / `--c4-relationships` /
// `--domain-model-rows` and expected sync.md to thread them from the C4 producer's
// marker. Two things were wrong with that. `parseIntFlag` returned 0 for an ABSENT
// flag, so an unthreaded call emitted `c4_elements=0 c4_relationships=0` — byte
// identical to the plan's headline failure mode, i.e. the exact state this artifact
// exists to detect, forged by forgetting a flag. And sync.md never described the
// hand-off at all, so the threading nobody documented was also the threading nobody
// would do (five review agents independently found this script had no call site).
//
// Deriving removes the failure rather than documenting around it: there is no flag
// to forget, and every field is a function of the tree, which is what makes the
// artifact byte-stable across runs.
//
// `--degraded` is the one genuinely run-scoped input and stays a flag. Its absence
// is honest (no degraded producers) rather than a fabricated zero.
//
// Usage:
//   bun plugins/soleur/scripts/write-kb-coverage.ts [--root <repo>] [--degraded "<reason>"]...

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import {
  type CoverageSources,
  assessCoverage,
  deriveCounts,
  formatErrorMarker,
  formatProducersMarker,
  renderCoverageMarkdown,
} from "../lib/kb-coverage";

const KB_DIR = "knowledge-base";
const OUT_REL = "project/kb-coverage.md";
const MODEL_JSON_REL = "engineering/architecture/diagrams/model.likec4.json";
const REGISTER_REL = "engineering/architecture/domain-model.md";

/** Read a file, or null when absent. Absent is a normal state here, not an error. */
function readOrNull(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

function parseDegraded(args: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--degraded" && i + 1 < args.length) out.push(args[i + 1]);
  }
  return out;
}

export function writeCoverage(root: string, degraded: string[] = []): string {
  const kbRoot = join(root, KB_DIR);
  const entries = assessCoverage(kbRoot);

  const sources: CoverageSources = {
    modelJson: readOrNull(join(kbRoot, MODEL_JSON_REL)),
    registerMarkdown: readOrNull(join(kbRoot, REGISTER_REL)),
  };
  const counts = deriveCounts(entries, sources);

  const outPath = join(kbRoot, OUT_REL);
  mkdirSync(join(outPath, ".."), { recursive: true });
  writeFileSync(outPath, renderCoverageMarkdown(entries, counts, degraded));

  return formatProducersMarker(counts);
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const rootIdx = args.indexOf("--root");
  const root = rootIdx !== -1 && rootIdx + 1 < args.length ? args[rootIdx + 1] : process.cwd();
  try {
    console.log(writeCoverage(root, parseDegraded(args)));
  } catch (err) {
    const reason = String((err as Error)?.message ?? err);
    console.log(formatErrorMarker("coverage", reason));
    // The artifact must carry the failure too — stdout evaporates with the session,
    // and layer 7's whole premise is that the durable half survives it. sync.md
    // promised this and the first version did not do it: the write lived inside the
    // try, so a throw left either no file at all or the PREVIOUS run's file still
    // asserting a clean run.
    try {
      const kbRoot = join(root, KB_DIR);
      const entries = assessCoverage(kbRoot);
      const counts = deriveCounts(entries, { modelJson: null, registerMarkdown: null });
      const outPath = join(kbRoot, OUT_REL);
      mkdirSync(join(outPath, ".."), { recursive: true });
      writeFileSync(
        outPath,
        renderCoverageMarkdown(entries, counts, [`coverage producer failed: ${reason}`]),
      );
    } catch {
      // Best effort. If we cannot write the artifact either, the stdout marker above
      // is the only signal left — but it has already been emitted, so the failure is
      // never silent.
    }
    process.exit(1);
  }
}
