import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 067_action_sends_leader_loop.sql (#4379, PR-B).
//
// Adds 6 nullable columns to public.action_sends for the leader-prompt
// loop: reversal_handles (JSONB ARRAY — multi-tool classes per AC9),
// current_turn (smallint), current_turn_started_at (timestamptz),
// cancellation_requested_at (timestamptz), prompt_version (text), and
// undone_at (timestamptz).
//
// NO TRIGGER RESHAPE: mig 064's WORM trigger uses
// `BEFORE UPDATE OF <pre-064 immutable columns>` form. UPDATEs touching
// only the 6 new columns are admitted by default. The plan's
// Reality-Check Findings row 2 documents this drift from the spec's
// (incorrect) statement that the admit-list needs extending.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/067_action_sends_leader_loop.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/067_action_sends_leader_loop.down.sql",
);

const NEW_COLUMNS = [
  "reversal_handles",
  "current_turn",
  "current_turn_started_at",
  "cancellation_requested_at",
  "prompt_version",
  "undone_at",
] as const;

describe("migration 067_action_sends_leader_loop", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");
  const downExecutable = down.replace(/--[^\n]*/g, "");

  it("adds reversal_handles as nullable jsonb (PLURAL — array shape per AC9)", () => {
    // Note: the column type is jsonb (single column), but its contents are
    // a JSONB array. ADR: reversal_handles holds [{kind,...}, ...] so
    // multi-tool classes (pr_review_pending, triage.p0p1_issue, cve_alert)
    // can emit multiple per-artifact reversal records.
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?reversal_handles\s+jsonb/i,
    );
    expect(executable).not.toMatch(/reversal_handles\s+jsonb\s+NOT\s+NULL/i);
    // Guard against the spec's stale singular naming.
    expect(executable).not.toMatch(/\breversal_handle\s+jsonb/i);
  });

  it("adds current_turn as nullable smallint", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?current_turn\s+smallint/i,
    );
    expect(executable).not.toMatch(/current_turn\s+smallint\s+NOT\s+NULL/i);
  });

  it("adds current_turn_started_at as nullable timestamptz", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?current_turn_started_at\s+timestamptz/i,
    );
    expect(executable).not.toMatch(
      /current_turn_started_at\s+timestamptz\s+NOT\s+NULL/i,
    );
  });

  it("adds cancellation_requested_at as nullable timestamptz", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?cancellation_requested_at\s+timestamptz/i,
    );
    expect(executable).not.toMatch(
      /cancellation_requested_at\s+timestamptz\s+NOT\s+NULL/i,
    );
  });

  it("adds prompt_version as nullable text", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?prompt_version\s+text/i,
    );
    expect(executable).not.toMatch(/prompt_version\s+text\s+NOT\s+NULL/i);
  });

  it("adds undone_at as nullable timestamptz", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?undone_at\s+timestamptz/i,
    );
    expect(executable).not.toMatch(/undone_at\s+timestamptz\s+NOT\s+NULL/i);
  });

  it("does NOT reshape the action_sends_no_update trigger (no DROP TRIGGER)", () => {
    // Plan Reality-Check Findings row 2: mig 064's trigger uses
    // BEFORE UPDATE OF <pre-064 columns> form; UPDATEs touching only the
    // new columns are admitted by default. Mig 067 must NOT alter the
    // trigger — doing so would risk breaking the existing admit-list for
    // mig-064's three columns.
    expect(executable).not.toMatch(
      /DROP\s+TRIGGER\s+IF\s+EXISTS\s+action_sends_no_update/i,
    );
    expect(executable).not.toMatch(
      /CREATE\s+TRIGGER\s+action_sends_no_update/i,
    );
  });

  it("does NOT touch the DELETE-rejection trigger", () => {
    expect(executable).not.toMatch(
      /DROP\s+TRIGGER\s+IF\s+EXISTS\s+action_sends_no_delete/i,
    );
    expect(executable).not.toMatch(
      /CREATE\s+TRIGGER\s+action_sends_no_delete/i,
    );
  });

  it("includes COMMENTs on each of the 6 new columns explaining the writer contract", () => {
    for (const col of NEW_COLUMNS) {
      expect(sql).toMatch(
        new RegExp(`COMMENT\\s+ON\\s+COLUMN\\s+public\\.action_sends\\.${col}`, "i"),
      );
    }
  });

  it("comments document the reversal_handles plural-array shape", () => {
    // Specifically calls out the plural shape so future readers grep the
    // schema dump and understand multi-tool classes emit multiple handles.
    const reversalCommentMatch = sql.match(
      /COMMENT\s+ON\s+COLUMN\s+public\.action_sends\.reversal_handles\s+IS\s+'([\s\S]*?)';/i,
    );
    expect(reversalCommentMatch).not.toBeNull();
    const commentBody = (reversalCommentMatch![1] ?? "").toLowerCase();
    // Mention of "array" or "multiple" so readers know the shape.
    expect(commentBody).toMatch(/array|multi|\[/);
  });

  it("down migration drops all 6 new columns", () => {
    for (const col of NEW_COLUMNS) {
      expect(downExecutable).toMatch(
        new RegExp(`DROP\\s+COLUMN\\s+(IF\\s+EXISTS\\s+)?${col}\\b`, "i"),
      );
    }
  });

  it("down migration does NOT touch the WORM trigger", () => {
    // Symmetric to the up-migration: the trigger was not changed, so the
    // down doesn't restore anything either.
    expect(downExecutable).not.toMatch(
      /DROP\s+TRIGGER\s+IF\s+EXISTS\s+action_sends_no_update/i,
    );
    expect(downExecutable).not.toMatch(
      /CREATE\s+TRIGGER\s+action_sends_no_update/i,
    );
  });

  it("migration is forward-only (no outer BEGIN/COMMIT per Kieran P1-4)", () => {
    // Supabase runner already wraps each migration in a transaction.
    expect(executable).not.toMatch(/^\s*BEGIN\s*;/im);
    expect(executable).not.toMatch(/^\s*COMMIT\s*;/im);
  });
});
