import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// AC4c (drill-authority): segmentToDrillLevel is the SOLE source of "is this
// route drilled into kb|settings|chat". No raw drill-detection literal
// `pathname.startsWith("/dashboard/(kb|settings|chat)")` (closing quote right
// after the segment — the drill idiom) may survive outside the helper.
//
// The trailing-slash form `.startsWith("/dashboard/kb/")` is path EXTRACTION
// (which KB file is open), a distinct concern, and is intentionally excluded.

const ROOT = dirname(dirname(fileURLToPath(import.meta.url))); // apps/web-platform
const SCAN_DIRS = ["app", "components", "hooks"];
const HELPER = "hooks/segment-to-drill-level.ts";

// Drill-detection literal: segment immediately followed by the closing quote.
const DRILL_LITERAL = /\.startsWith\(\s*["']\/dashboard\/(kb|settings|chat)["']\s*\)/;

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, acc);
    else if (/\.(tsx|ts)$/.test(p) && !/\.test\.tsx?$/.test(p)) acc.push(p);
  }
  return acc;
}

const FILES = SCAN_DIRS.flatMap((d) => walk(join(ROOT, d)));

describe("drill-state authority (AC4c)", () => {
  it("no drill-detection startsWith literal survives outside segmentToDrillLevel", () => {
    const offenders = FILES.filter((f) => {
      const rel = f.slice(ROOT.length + 1);
      if (rel === HELPER) return false;
      return DRILL_LITERAL.test(readFileSync(f, "utf8"));
    }).map((f) => f.slice(ROOT.length + 1));
    expect(offenders).toEqual([]);
  });
});
