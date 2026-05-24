import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 064_action_sends_acknowledgment.sql (#4124, PR-A).
//
// Adds three new columns (acknowledged_at, artifact_url, failure_reason) to
// public.action_sends. The Inngest function `agent-on-spawn-requested` is
// the sole writer of these columns via service-role-client UPDATE.
//
// WORM-TRIGGER COMPAT: migration 051 installed BEFORE UPDATE FOR EACH
// STATEMENT trigger `action_sends_no_update` that rejects ALL UPDATEs.
// Migration 064 must reshape the trigger to `BEFORE UPDATE OF <immutable
// columns>` so UPDATEs touching ONLY the three new columns are admitted,
// while UPDATEs touching any pre-064 column continue to be rejected.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_action_sends_acknowledgment.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_action_sends_acknowledgment.down.sql",
);

const PRE_064_IMMUTABLE_COLUMNS = [
  "id",
  "user_id",
  "message_id",
  "action_class",
  "tier_at_send",
  "template_hash",
  "per_send_body_sha256",
  "recipient_id_hash",
  "clicked_at",
  "confirmed_typed",
  "approval_signature_sha256",
  "grant_id",
];

describe("migration 064_action_sends_acknowledgment", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");
  const downExecutable = down.replace(/--[^\n]*/g, "");

  it("adds acknowledged_at as nullable timestamptz", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?acknowledged_at\s+timestamptz/i,
    );
    expect(executable).not.toMatch(/acknowledged_at\s+timestamptz\s+NOT\s+NULL/i);
  });

  it("adds artifact_url as nullable text", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?artifact_url\s+text/i,
    );
    expect(executable).not.toMatch(/artifact_url\s+text\s+NOT\s+NULL/i);
  });

  it("adds failure_reason as nullable text", () => {
    expect(executable).toMatch(
      /ADD\s+COLUMN\s+(IF\s+NOT\s+EXISTS\s+)?failure_reason\s+text/i,
    );
    expect(executable).not.toMatch(/failure_reason\s+text\s+NOT\s+NULL/i);
  });

  it("reshapes the WORM UPDATE trigger to allow UPDATE on the three new columns", () => {
    // Trigger must DROP the existing pure-reject UPDATE trigger and re-create
    // it with a column list scoping it to the pre-064 immutable columns only.
    expect(executable).toMatch(
      /DROP\s+TRIGGER\s+IF\s+EXISTS\s+action_sends_no_update\s+ON\s+public\.action_sends/i,
    );
    expect(executable).toMatch(
      /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?BEFORE\s+UPDATE\s+OF/i,
    );
  });

  it("the recreated trigger column list covers every pre-064 immutable column", () => {
    const m = executable.match(
      /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?BEFORE\s+UPDATE\s+OF\s+([\s\S]*?)\s+ON\s+public\.action_sends/i,
    );
    expect(m).not.toBeNull();
    const colList = (m![1] ?? "").toLowerCase();
    for (const col of PRE_064_IMMUTABLE_COLUMNS) {
      expect(colList).toContain(col);
    }
  });

  it("the recreated trigger column list does NOT include any of the new columns", () => {
    const m = executable.match(
      /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?BEFORE\s+UPDATE\s+OF\s+([\s\S]*?)\s+ON\s+public\.action_sends/i,
    );
    expect(m).not.toBeNull();
    const colList = (m![1] ?? "").toLowerCase();
    expect(colList).not.toContain("acknowledged_at");
    expect(colList).not.toContain("artifact_url");
    expect(colList).not.toContain("failure_reason");
  });

  it("leaves the DELETE-rejection trigger intact (no reference to action_sends_no_delete dropping)", () => {
    expect(executable).not.toMatch(
      /DROP\s+TRIGGER\s+IF\s+EXISTS\s+action_sends_no_delete/i,
    );
  });

  it("includes COMMENTs on the three new columns explaining the writer contract", () => {
    expect(sql).toMatch(
      /COMMENT\s+ON\s+COLUMN\s+public\.action_sends\.acknowledged_at/i,
    );
    expect(sql).toMatch(
      /COMMENT\s+ON\s+COLUMN\s+public\.action_sends\.artifact_url/i,
    );
    expect(sql).toMatch(
      /COMMENT\s+ON\s+COLUMN\s+public\.action_sends\.failure_reason/i,
    );
  });

  it("down migration drops the three new columns and restores the pure-reject UPDATE trigger", () => {
    expect(downExecutable).toMatch(/DROP\s+COLUMN\s+(IF\s+EXISTS\s+)?acknowledged_at/i);
    expect(downExecutable).toMatch(/DROP\s+COLUMN\s+(IF\s+EXISTS\s+)?artifact_url/i);
    expect(downExecutable).toMatch(/DROP\s+COLUMN\s+(IF\s+EXISTS\s+)?failure_reason/i);
    // The down must put back a column-list-less UPDATE-rejecting trigger so
    // the WORM invariant is restored verbatim.
    expect(downExecutable).toMatch(
      /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?BEFORE\s+UPDATE\s+ON\s+public\.action_sends/i,
    );
  });
});
