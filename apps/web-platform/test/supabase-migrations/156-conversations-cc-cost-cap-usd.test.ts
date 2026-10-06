import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 156_conversations_cc_cost_cap_usd.sql.
//
// File-parse test, not a live-DB test: it pins the SQL contract for the
// resumable per-conversation cost cap (feat-cc-cap-raise-resume / #9565) —
// a nullable numeric column plus the gdpr-gate lawful-basis annotation —
// that `updateConversationFor({ cc_cost_cap_usd })` and the ws-handler
// chat-case SELECT rely on. Runtime verification against dev Supabase is
// a separate apply step, not this file's concern.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/156_conversations_cc_cost_cap_usd.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/156_conversations_cc_cost_cap_usd.down.sql",
);

describe("migration 156_conversations_cc_cost_cap_usd", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");

  it("adds cc_cost_cap_usd as a nullable numeric column on conversations", () => {
    const re =
      /ALTER\s+TABLE\s+(?:public\.)?conversations[^;]*ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?cc_cost_cap_usd\s+numeric\b(?![^;]*NOT\s+NULL)/is;
    expect(sql).toMatch(re);
  });

  it("carries a lawful-basis annotation (gdpr-gate GDPR-Art-6)", () => {
    expect(sql).toMatch(/LAWFUL_BASIS:\s*GDPR?\s*Art\.\s*6/);
  });

  it("documents the column via COMMENT ON COLUMN", () => {
    expect(sql).toMatch(
      /COMMENT\s+ON\s+COLUMN\s+(?:public\.)?conversations\.cc_cost_cap_usd/i,
    );
  });

  it("down migration drops the column", () => {
    expect(down).toMatch(
      /DROP\s+COLUMN\s+(?:IF\s+EXISTS\s+)?cc_cost_cap_usd/i,
    );
  });
});

describe("migration 157_conversations_cc_cost_cap_usd_check", () => {
  // Split from 156: 156 was applied to shared dev before the CHECK was
  // added (dev-ledger-parity arm A1 — applied bodies are immutable).
  const sql157 = readFileSync(
    path.join(
      __dirname,
      "../../supabase/migrations/157_conversations_cc_cost_cap_usd_check.sql",
    ),
    "utf8",
  );
  const down157 = readFileSync(
    path.join(
      __dirname,
      "../../supabase/migrations/157_conversations_cc_cost_cap_usd_check.down.sql",
    ),
    "utf8",
  );

  it("adds a positive-value CHECK constraint on cc_cost_cap_usd", () => {
    expect(sql157).toMatch(
      /ADD\s+CONSTRAINT\s+cc_cost_cap_usd_positive\s+CHECK/i,
    );
    expect(sql157).toMatch(/cc_cost_cap_usd\s*>\s*0/);
  });

  it("down migration drops the constraint", () => {
    expect(down157).toMatch(
      /DROP\s+CONSTRAINT\s+(?:IF\s+EXISTS\s+)?cc_cost_cap_usd_positive/i,
    );
  });
});
