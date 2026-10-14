// #8611 Fix 3 — every Claude spawn site is capped (`--max-budget-usd`) and throttled.
//
// The population is DERIVED from the functions directory (every file that calls
// `spawnClaudeEval(` or `resolveClaudeBin()`, minus the substrate that defines them), never a
// hand-kept list: a new cron that spawns Claude without a budget must red this suite. The flag
// itself is appended by spawnClaudeEval from the cron name (pinned in
// claude-eval-single-flight.test.ts); here we pin the table and the per-site throttle.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { CLAUDE_BUDGET_USD, CLAUDE_EVAL_THROTTLE, budgetFlags } from "@/server/inngest/cron-budgets";

const FN_DIR = join(__dirname, "../../../server/inngest/functions");
const SUBSTRATE = "_cron-claude-eval-substrate.ts";
const SPAWN_RE = /spawnClaudeEval\(|resolveClaudeBin\(\)/;

// Line and block comments removed, so a commented-out flag or throttle cannot satisfy (or trip) a check.
function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/[^\n]*/g, "$1");
}

function spawnSites(): string[] {
  return readdirSync(FN_DIR)
    .filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts") && f !== SUBSTRATE)
    .filter((f) => SPAWN_RE.test(stripComments(readFileSync(join(FN_DIR, f), "utf8"))))
    .map((f) => f.replace(/\.ts$/, ""))
    .sort();
}

describe("cron budgets — #8611", () => {
  it("derives a non-trivial population (anti-vacuity floor)", () => {
    // 18 spawn sites on 2026-09-23. A scan that finds far fewer is a broken scan, not a clean tree.
    expect(spawnSites().length).toBeGreaterThanOrEqual(18);
  });

  it("the budget map covers exactly the spawn sites (no missing, no stale keys)", () => {
    expect(Object.keys(CLAUDE_BUDGET_USD).sort()).toEqual(spawnSites());
  });

  it("every budget is a finite positive dollar amount", () => {
    for (const [name, usd] of Object.entries(CLAUDE_BUDGET_USD)) {
      expect(Number.isFinite(usd), name).toBe(true);
      expect(usd, name).toBeGreaterThan(0);
    }
  });

  it("no spawn site carries its own budget flag (the substrate derives it from the cron name)", () => {
    // spawnClaudeEval appends --max-budget-usd itself and refuses a caller-supplied one, so a site
    // naming the flag or budgetFlags is either dead or an attempt to override the cap.
    for (const site of spawnSites()) {
      const code = stripComments(readFileSync(join(FN_DIR, `${site}.ts`), "utf8"));
      expect(code, site).not.toMatch(/budgetFlags\(|--max-budget-usd/);
    }
  });

  it("every spawn site's createFunction config carries the shared manual-fire throttle (comments stripped)", () => {
    expect(CLAUDE_EVAL_THROTTLE).toEqual({ limit: 2, period: "1h" });
    for (const site of spawnSites()) {
      const code = stripComments(readFileSync(join(FN_DIR, `${site}.ts`), "utf8"));
      // Exactly one registration per site, and exactly one throttle inside ITS config object.
      expect(code.match(/inngest\.createFunction\(/g), site).toHaveLength(1);
      const config = code.slice(code.indexOf("inngest.createFunction(")).split(/\n\s*\},?\n/)[0]!;
      expect(config, site).toMatch(/\bthrottle:\s*\{\s*\.\.\.CLAUDE_EVAL_THROTTLE\s*\}/);
      expect(config.match(/\bthrottle:/g), site).toHaveLength(1);
    }
  });

  it("the comment stripper removes a commented-out throttle (so the check above cannot be satisfied by one)", () => {
    const src = "inngest.createFunction(\n  {\n    // throttle: { ...CLAUDE_EVAL_THROTTLE },\n    retries: 1,\n  },\n";
    expect(stripComments(src)).not.toMatch(/throttle:/);
  });

  it("budgetFlags renders the CLI flag pair and refuses an unknown site", () => {
    expect(budgetFlags("cron-growth-audit")).toEqual([
      "--max-budget-usd",
      String(CLAUDE_BUDGET_USD["cron-growth-audit"]),
    ]);
    expect(() => budgetFlags("cron-does-not-exist")).toThrow(/no budget/);
  });
});
