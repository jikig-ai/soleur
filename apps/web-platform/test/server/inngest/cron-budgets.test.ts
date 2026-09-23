// #8611 Fix 3 — every Claude spawn site carries a per-run `--max-budget-usd` ceiling.
//
// The population is DERIVED from the functions directory (every file that calls
// `spawnClaudeEval(` or `resolveClaudeBin()`, minus the substrate that defines them), never a
// hand-kept list: a new cron that spawns Claude without a budget must red this suite.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { CLAUDE_BUDGET_USD, budgetFlags } from "@/server/inngest/cron-budgets";

const FN_DIR = join(__dirname, "../../../server/inngest/functions");
const SUBSTRATE = "_cron-claude-eval-substrate.ts";
const SPAWN_RE = /spawnClaudeEval\(|resolveClaudeBin\(\)/;

function spawnSites(): string[] {
  return readdirSync(FN_DIR)
    .filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts") && f !== SUBSTRATE)
    .filter((f) => SPAWN_RE.test(readFileSync(join(FN_DIR, f), "utf8")))
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

  it("every spawn site spreads its OWN budget into its flags", () => {
    for (const site of spawnSites()) {
      const src = readFileSync(join(FN_DIR, `${site}.ts`), "utf8");
      // Anchored on the call shape with the site's own key: a copy-pasted sibling key must red.
      expect(src, site).toMatch(new RegExp(`\\.\\.\\.budgetFlags\\(\\s*"${site}"\\s*\\)`));
    }
  });

  it("budgetFlags renders the CLI flag pair and refuses an unknown site", () => {
    expect(budgetFlags("cron-growth-audit")).toEqual([
      "--max-budget-usd",
      String(CLAUDE_BUDGET_USD["cron-growth-audit"]),
    ]);
    expect(() => budgetFlags("cron-does-not-exist")).toThrow(/no budget/);
  });
});
