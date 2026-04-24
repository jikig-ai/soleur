import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 032_conversation_workflow_state.sql.
//
// This is a file-parse test, not a live-DB test: it asserts the migration SQL
// contains the required column definitions and CHECK constraint enum. Runtime
// verification against dev Supabase is a separate Stage 1.4 action that hits
// the REST API per wg-when-a-pr-includes-database-migrations.
//
// Plan: 2026-04-23-feat-cc-route-via-soleur-go-plan.md Stage 1.
// The allowed workflow-name enum must match conversation-routing.ts exactly;
// if you change one without the other, the runtime CHECK will reject writes.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/032_conversation_workflow_state.sql",
);

// The full allowed set, including the '__unrouted__' sentinel used by
// conversation-routing.ts when the runner is pending but no workflow picked.
const ALLOWED_WORKFLOWS = [
  "__unrouted__",
  "one-shot",
  "brainstorm",
  "plan",
  "work",
  "review",
  "drain-labeled-backlog",
] as const;

describe("migration 032_conversation_workflow_state", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  it("adds active_workflow text NULL column to conversations", () => {
    // Match either `ADD COLUMN active_workflow text` or the `IF NOT EXISTS`
    // variant; nullable (no NOT NULL) because legacy rows must remain valid.
    const re = /ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?active_workflow\s+text\b(?![^,;]*NOT\s+NULL)/i;
    expect(sql).toMatch(re);
  });

  it("adds workflow_ended_at timestamptz NULL column to conversations", () => {
    const re = /ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?workflow_ended_at\s+timestamptz\b(?![^,;]*NOT\s+NULL)/i;
    expect(sql).toMatch(re);
  });

  it("targets the conversations table", () => {
    expect(sql).toMatch(/ALTER\s+TABLE\s+(?:public\.)?conversations\b/i);
  });

  it("declares a CHECK constraint enumerating every allowed workflow", () => {
    // The plan specifies `CHECK (active_workflow IS NULL OR active_workflow IN (...))`.
    // We don't pin the exact syntax (IS NULL OR / NULL / comment variants) —
    // we assert that every allowed value appears as a quoted literal inside
    // a CHECK clause.
    const checkMatch = sql.match(/CHECK\s*\([^)]*active_workflow[^)]*\)/is);
    expect(checkMatch, "migration must declare a CHECK constraint referencing active_workflow").not.toBeNull();
    const checkBody = checkMatch![0];
    for (const name of ALLOWED_WORKFLOWS) {
      // Match 'one-shot' or "one-shot" (either quote style).
      const lit = new RegExp(`['"]${name.replace(/[-[\]/{}()*+?.\\^$|]/g, "\\$&")}['"]`);
      expect(checkBody, `CHECK clause must include '${name}'`).toMatch(lit);
    }
  });

  it("does NOT use CONCURRENTLY (Supabase migration-runner transaction rejects 25001)", () => {
    // cq-supabase-migration-concurrently-forbidden.
    // Strip `-- line comments` first so the rule text in the header can mention
    // the word without tripping the check; we only care about executable SQL.
    const executable = sql.replace(/--[^\n]*/g, "");
    expect(executable).not.toMatch(/\bCONCURRENTLY\b/i);
  });
});
