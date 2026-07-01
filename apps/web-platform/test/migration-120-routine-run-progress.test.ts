import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/120_routine_run_progress.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/120_routine_run_progress.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");

// Negative "the migration must NOT contain X" assertions run against the DDL with
// `--` comment lines stripped — the header comments deliberately NAME forbidden
// constructs (actor_id, no_mutate, CONCURRENTLY) to explain their absence, and a
// raw-body grep would false-match them (per the grep-over-script-body learning).
const code = sql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

describe("migration 120: routine_run_progress live-state sidecar", () => {
  it("creates routine_run_progress with RLS enabled", () => {
    expect(sql).toContain("CREATE TABLE IF NOT EXISTS public.routine_run_progress");
    expect(sql).toContain("ENABLE ROW LEVEL SECURITY");
  });

  it("has exactly the minimal column set (no dropped-review columns)", () => {
    for (const col of [
      "id",
      "routine_id",
      "run_id",
      "attempt",
      "started_at",
      "last_heartbeat_at",
    ]) {
      expect(sql).toMatch(new RegExp(`\\b${col}\\b`));
    }
    // Dropped during review: per-step indexing (P2-5), constant current_step
    // (S-F4), redundant heartbeat_count (S-F6), resumed_from_heartbeat (S-F3).
    expect(sql).not.toMatch(/\bcurrent_step\b/);
    expect(sql).not.toMatch(/\btotal_steps\b/);
    expect(sql).not.toMatch(/\bcurrent_step_index\b/);
    expect(sql).not.toMatch(/\bheartbeat_count\b/);
    expect(sql).not.toMatch(/\bresumed_from_heartbeat\b/);
  });

  it("is ATTRIBUTION-FREE: no actor columns, no FK to public.users (no PII surface)", () => {
    expect(code).not.toMatch(/\bactor_id\b/);
    expect(code).not.toMatch(/\bdelegating_principal\b/);
    expect(code).not.toMatch(/REFERENCES\s+public\.users/i);
  });

  it("is NOT WORM: no no_mutate trigger, no CREATE TRIGGER (mutable heartbeat state)", () => {
    expect(code).not.toMatch(/no_mutate/i);
    expect(code).not.toMatch(/CREATE TRIGGER/i);
    expect(code).not.toMatch(/anonymise_routine_run_progress/i);
  });

  it("run_id is NOT NULL UNIQUE (backs ON CONFLICT + point lookups)", () => {
    expect(sql).toMatch(/run_id\s+text\s+NOT NULL UNIQUE/i);
  });

  it("SELECT-only RLS mirroring routine_runs; writes are service-role (no write policy)", () => {
    expect(sql).toMatch(
      /CREATE POLICY routine_run_progress_authenticated_select[\s\S]*FOR SELECT USING \(auth\.uid\(\) IS NOT NULL\)/,
    );
    // service_role writes (BYPASSRLS) — no INSERT/UPDATE/DELETE policy exists
    expect(sql).not.toMatch(/FOR (INSERT|UPDATE|DELETE|ALL)/i);
    expect(sql).toMatch(
      /REVOKE INSERT, UPDATE, DELETE ON public\.routine_run_progress FROM anon, authenticated/,
    );
  });

  it("indexes last_heartbeat_at for the staleness scan", () => {
    expect(sql).toMatch(/CREATE INDEX[\s\S]*last_heartbeat_at/i);
  });

  it("no CREATE INDEX CONCURRENTLY (Supabase wraps migrations in a transaction)", () => {
    expect(code).not.toMatch(/CONCURRENTLY/i);
  });

  it("carries LAWFUL_BASIS and RETENTION annotations", () => {
    expect(sql).toMatch(/--\s*LAWFUL_BASIS:/);
    expect(sql).toMatch(/--\s*RETENTION:/);
  });

  it("down migration drops the table", () => {
    expect(downSql).toMatch(/DROP TABLE IF EXISTS public\.routine_run_progress/);
  });
});
