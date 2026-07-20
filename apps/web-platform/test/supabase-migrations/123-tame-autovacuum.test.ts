import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 123_tame_autovacuum_on_tiny_hot_tables (residual
// Supabase Disk IO fix).
//
// File-parse test, not a live-DB test. It pins the SQL contract for the third
// remediation in the prod Disk IO Budget line (#3358 → #5736 → this): after the
// June 2026 webhook-dedup fix crushed statement WAL to ~17 MB/day, the residual
// IOPS drain is autovacuum THRASH — three tiny (0–16 row) public hot-update
// tables were being fully vacuumed 49–142×/week because the default trigger
// (threshold 50 + 20% scale) fires after ~50 dead tuples. This migration raises
// the per-table dead-tuple threshold ~20× and pins fillfactor for HOT updates.
//
// The test guards three invariants:
//   1. Each of the three owned tables gets the exact autovacuum + fillfactor
//      reloptions (byte-pinned so a future edit cannot silently drop one).
//   2. The migration touches ZERO Supabase-managed schemas (auth.* / realtime.*
//      / cron.*) — the owned-tables-only scope boundary (auth churn is #5739).
//   3. The .down.sql RESETs exactly the params the up-migration SETs, per table.
//
// Plan: 2026-07-07-fix-supabase-autovacuum-thrash-disk-io-plan.md.
// Related (out-of-scope) auth-churn tracker: #5739.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const TARGET_TABLES = [
  "user_concurrency_slots",
  "mint_rate_window",
  "runtime_mint_intent",
] as const;

describe("migration 123_tame_autovacuum_on_tiny_hot_tables (up)", () => {
  const executable = stripComments(
    readFileSync(
      path.join(MIG_DIR, "123_tame_autovacuum_on_tiny_hot_tables.sql"),
      "utf8",
    ),
  );

  for (const table of TARGET_TABLES) {
    describe(`public.${table}`, () => {
      // Isolate this table's ALTER ... SET (...) block so per-param assertions
      // cannot be satisfied by a param set on a *different* table's block.
      const block = (() => {
        const re = new RegExp(
          `ALTER\\s+TABLE\\s+public\\.${table}\\s+SET\\s*\\(([^)]*)\\)`,
          "i",
        );
        const m = executable.match(re);
        return m ? m[1] : "";
      })();

      it("has an ALTER TABLE ... SET (...) block", () => {
        expect(block).not.toBe("");
      });

      it("sets autovacuum_vacuum_threshold to a value in [500, 2000]", () => {
        const m = block.match(/autovacuum_vacuum_threshold\s*=\s*(\d+)/i);
        expect(m).not.toBeNull();
        const v = Number(m![1]);
        expect(v).toBeGreaterThanOrEqual(500);
        expect(v).toBeLessThanOrEqual(2000);
      });

      it("zeroes autovacuum_vacuum_scale_factor (exactly 0, not 0.2)", () => {
        // Negative lookahead is load-bearing: `\b` would match `0.2` (the
        // default this migration exists to eliminate), making the assertion
        // vacuous against exactly the regression it guards.
        expect(block).toMatch(/autovacuum_vacuum_scale_factor\s*=\s*0(?![.\d])/i);
      });

      it("sets autovacuum_analyze_threshold to a value in [500, 2000]", () => {
        const m = block.match(/autovacuum_analyze_threshold\s*=\s*(\d+)/i);
        expect(m).not.toBeNull();
        const v = Number(m![1]);
        expect(v).toBeGreaterThanOrEqual(500);
        expect(v).toBeLessThanOrEqual(2000);
      });

      it("zeroes autovacuum_analyze_scale_factor (exactly 0, not 0.1)", () => {
        expect(block).toMatch(/autovacuum_analyze_scale_factor\s*=\s*0(?![.\d])/i);
      });

      it("pins fillfactor = 70", () => {
        expect(block).toMatch(/fillfactor\s*=\s*70\b/i);
      });
    });
  }

  it("alters EXACTLY the three target public tables and no others", () => {
    // Positive scope-completeness guard: the auth.*/realtime.*/cron.* negative
    // check below only defends the Supabase-managed direction. This asserts no
    // stray `ALTER TABLE public.<other> SET (...)` (e.g. a large table like
    // public.users) slips in — which would waste disk (fillfactor) or defer
    // vacuum on a table where that is unsafe.
    const altered = [
      ...executable.matchAll(/ALTER\s+TABLE\s+public\.(\w+)\s+SET/gi),
    ].map((m) => m[1].toLowerCase());
    expect(altered.sort()).toEqual([...TARGET_TABLES].sort());
  });

  it("touches ZERO Supabase-managed tables (auth.* / realtime.* / cron.*)", () => {
    expect(executable).not.toMatch(/ALTER\s+TABLE\s+auth\./i);
    expect(executable).not.toMatch(/ALTER\s+TABLE\s+realtime\./i);
    expect(executable).not.toMatch(/ALTER\s+TABLE\s+cron\./i);
  });

  it("does not run VACUUM FULL / CLUSTER (non-transactional, forbidden)", () => {
    expect(executable).not.toMatch(/VACUUM\s+FULL/i);
    expect(executable).not.toMatch(/\bCLUSTER\b/i);
  });
});

describe("migration 123_tame_autovacuum_on_tiny_hot_tables (down)", () => {
  const executable = stripComments(
    readFileSync(
      path.join(MIG_DIR, "123_tame_autovacuum_on_tiny_hot_tables.down.sql"),
      "utf8",
    ),
  );

  for (const table of TARGET_TABLES) {
    it(`RESETs the five params on public.${table}`, () => {
      const re = new RegExp(
        `ALTER\\s+TABLE\\s+public\\.${table}\\s+RESET\\s*\\(([^)]*)\\)`,
        "i",
      );
      const m = executable.match(re);
      expect(m).not.toBeNull();
      const block = m![1];
      expect(block).toMatch(/autovacuum_vacuum_threshold/i);
      expect(block).toMatch(/autovacuum_vacuum_scale_factor/i);
      expect(block).toMatch(/autovacuum_analyze_threshold/i);
      expect(block).toMatch(/autovacuum_analyze_scale_factor/i);
      expect(block).toMatch(/fillfactor/i);
    });
  }
});
