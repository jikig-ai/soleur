#!/usr/bin/env bun
// CLI wrapper for the sync coverage summary (#7332, plan Phase 3). Pure logic
// lives in ../lib/kb-coverage.ts; this file owns the filesystem and stdout.
//
// Writes knowledge-base/project/kb-coverage.md and prints the same
// SOLEUR_KB_SYNC_PRODUCERS marker to stdout — observability layer 7
// (`cli-stdout-artifact`). Both surfaces carry a byte-identical field set; a
// drift guard in the test suite pins that, because the plan's
// discoverability_test greps the ARTIFACT and would otherwise silently start
// verifying something other than what the run reported.
//
// Counts arrive as flags rather than being re-derived here, so the marker reports
// what the run actually produced instead of what a second pass rediscovers.
//
// Usage:
//   bun plugins/soleur/scripts/write-kb-coverage.ts \
//     [--root <repo>] [--c4-elements N] [--c4-relationships N] \
//     [--domain-model-rows N] [--degraded "<reason>"]...

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import {
  type ProducerCounts,
  assessCoverage,
  formatErrorMarker,
  formatProducersMarker,
  renderCoverageMarkdown,
} from "../lib/kb-coverage";

const KB_DIR = "knowledge-base";
const OUT_REL = "project/kb-coverage.md";

function parseIntFlag(args: string[], name: string): number {
  const i = args.indexOf(name);
  if (i === -1 || i + 1 >= args.length) return 0;
  const n = Number.parseInt(args[i + 1], 10);
  // A malformed count must not silently become a plausible-looking 0 — the marker
  // is the run's only durable record, so a garbage input is reported, not coerced.
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`${name} expects a non-negative integer, got "${args[i + 1]}"`);
  }
  return n;
}

function parseDegraded(args: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--degraded" && i + 1 < args.length) out.push(args[i + 1]);
  }
  return out;
}

export function writeCoverage(root: string, counts: Omit<ProducerCounts, "coverage_present" | "coverage_expected">, degraded: string[]): string {
  const kbRoot = join(root, KB_DIR);
  const entries = assessCoverage(kbRoot);

  const full: ProducerCounts = {
    ...counts,
    coverage_present: entries.filter((e) => e.present).length,
    coverage_expected: entries.length,
  };

  const outPath = join(kbRoot, OUT_REL);
  mkdirSync(join(outPath, ".."), { recursive: true });
  writeFileSync(outPath, renderCoverageMarkdown(entries, full, degraded));

  return formatProducersMarker(full);
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  try {
    const rootIdx = args.indexOf("--root");
    const root = rootIdx !== -1 && rootIdx + 1 < args.length ? args[rootIdx + 1] : process.cwd();
    console.log(
      writeCoverage(
        root,
        {
          c4_elements: parseIntFlag(args, "--c4-elements"),
          c4_relationships: parseIntFlag(args, "--c4-relationships"),
          domain_model_rows: parseIntFlag(args, "--domain-model-rows"),
        },
        parseDegraded(args),
      ),
    );
  } catch (err) {
    console.log(formatErrorMarker("coverage", String((err as Error)?.message ?? err)));
    process.exit(1);
  }
}
