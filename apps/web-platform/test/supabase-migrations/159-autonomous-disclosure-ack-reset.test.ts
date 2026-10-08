import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration 159 — CPO3-R2 / #9776: supersede the autonomous-mode first-run
// consent ack after the disclosure copy was re-locked (2026-10-08).
//
// SHARP EDGES:
//   - The UPDATE is scoped to `bash_autonomous AND ack_at IS NOT NULL` and moves
//     ack_at into ack_superseded_at in ONE statement.
//   - It must NEVER write the bash_autonomous toggle (099 GDPR sentinel stays
//     valid): the toggle appears only in the WHERE clause, never in SET.

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

const raw = readFileSync(
  path.join(MIGRATIONS_DIR, "159_autonomous_disclosure_ack_reset.sql"),
  "utf-8",
);
const downSql = readFileSync(
  path.join(MIGRATIONS_DIR, "159_autonomous_disclosure_ack_reset.down.sql"),
  "utf-8",
);
const verifySql = readFileSync(
  path.join(VERIFY_DIR, "159_autonomous_disclosure_ack_reset.sql"),
  "utf-8",
);

// Strip `--` line comments so assertions target executable SQL only.
const sql = raw
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

const updates = sql.match(/UPDATE\s+public\.workspaces[\s\S]*?;/gi) ?? [];

describe("migration 159: autonomous disclosure ack reset", () => {
  it("adds the nullable autonomous_disclosure_ack_superseded_at timestamptz column", () => {
    expect(sql).toMatch(
      /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+autonomous_disclosure_ack_superseded_at\s+timestamptz\s*;/i,
    );
    expect(sql).not.toMatch(
      /autonomous_disclosure_ack_superseded_at\s+timestamptz[^;]*(DEFAULT|NOT\s+NULL)/i,
    );
  });

  it("runs exactly ONE UPDATE on workspaces", () => {
    expect(updates).toHaveLength(1);
  });

  it("the UPDATE moves ack_at into ack_superseded_at and NULLs ack_at in one statement", () => {
    const u = updates[0];
    expect(u).toMatch(
      /SET\s+autonomous_disclosure_ack_superseded_at\s*=\s*COALESCE\(\s*autonomous_disclosure_ack_superseded_at\s*,\s*autonomous_disclosure_ack_at\s*\)\s*,\s*autonomous_disclosure_ack_at\s*=\s*NULL/i,
    );
  });

  it("keeps the FIRST superseded timestamp on a re-run (COALESCE, Art. 7(1) evidence)", () => {
    // Without COALESCE a second run would overwrite the original consent time
    // with a later (possibly new-copy) ack.
    expect(updates[0]).toMatch(/COALESCE\(\s*autonomous_disclosure_ack_superseded_at/i);
  });

  it("sets a lock_timeout so the ADD COLUMN cannot queue behind a long transaction", () => {
    expect(sql).toMatch(/SET\s+LOCAL\s+lock_timeout\s*=\s*'5s'/i);
  });

  it("the UPDATE WHERE clause is exactly `bash_autonomous AND ack_at IS NOT NULL`", () => {
    const where = updates[0].match(/WHERE([\s\S]*?);/i)?.[1] ?? "";
    expect(where.replace(/\s+/g, " ").trim()).toBe(
      "bash_autonomous AND autonomous_disclosure_ack_at IS NOT NULL",
    );
  });

  it("does NOT write the bash_autonomous toggle column (099 GDPR sentinel stays valid)", () => {
    const setClause =
      updates[0].match(/SET([\s\S]*?)WHERE/i)?.[1] ?? "";
    expect(setClause).not.toMatch(/\bbash_autonomous\b/i);
    expect(sql).not.toMatch(/set_workspace_bash_autonomous/i);
    expect(sql).not.toMatch(/SET\s+DEFAULT/i);
  });

  it("creates no function (plain UPDATE; no SECURITY DEFINER surface)", () => {
    expect(sql).not.toMatch(/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i);
  });

  it("carries a lawful-basis annotation (gdpr-gate GDPR-Art-6)", () => {
    expect(raw).toMatch(/LAWFUL_BASIS:\s*GDPR?\s*Art\.\s*6/);
  });

  it("down migration drops only the audit column and does not restore the live ack", () => {
    expect(downSql).toMatch(
      /DROP\s+COLUMN\s+IF\s+EXISTS\s+autonomous_disclosure_ack_superseded_at/i,
    );
    expect(downSql).not.toMatch(/UPDATE\s/i);
    expect(downSql).not.toMatch(/bash_autonomous/i);
  });

  it("verify SQL emits check_name/bad rows and is read-only", () => {
    expect(verifySql).toContain("ack_superseded_column_exists");
    expect(verifySql).toContain("autonomous_disclosure_ack_superseded_at");
    expect(verifySql).toContain("no_autonomous_ack_predates_relock");
    expect(verifySql).toContain("ack_not_older_than_superseded");
    expect(verifySql).not.toMatch(/\b(UPDATE|DELETE|INSERT|ALTER)\b/i);
  });
});
