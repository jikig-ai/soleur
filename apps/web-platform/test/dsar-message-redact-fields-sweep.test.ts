/**
 * DSAR Art. 15(4) MESSAGE_REDACT_FIELDS migration-sweep sentinel.
 *
 * Plan: knowledge-base/project/plans/2026-05-22-feat-dsar-author-redaction-
 *       art-15-4-plan.md
 * Issue: #4319
 * Review concur: code-quality-analyst P1 #6 + pattern-recognition-specialist
 *                P2 #c1 + data-integrity-guardian P1 #b (review #4351).
 *
 * Enforces hr-write-boundary-sentinel-sweep-all-write-sites at CI time:
 * every column added to `public.messages` via `ALTER TABLE ... ADD COLUMN`
 * in supabase/migrations/ must be classified as either
 * MESSAGE_REDACT_FIELDS (nulled on a foreign-author row) or
 * MESSAGE_NON_REDACT_ALLOWLIST (structural, safe to surface). Unknown
 * columns trip CI so a reviewer must consciously decide the
 * classification before the migration can merge.
 *
 * The sentinel parses migration SQL directly rather than introspecting
 * the live schema so it works in any environment without DB creds and
 * fails-loud at PR time.
 */
import { describe, expect, test } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import {
  MESSAGE_NON_REDACT_ALLOWLIST,
  MESSAGE_REDACT_FIELDS,
} from "../server/dsar-export";

const MIGRATIONS_DIR = join(__dirname, "..", "supabase", "migrations");

// Match either:
//   ALTER TABLE public.messages
//     ADD COLUMN IF NOT EXISTS <name> <type>,
//     ADD COLUMN <name2> <type>,
// or the canonical initial-create block in 001:
//   create table public.messages (
//     <name> <type> not null,
//     ...
//   );
const ALTER_BLOCK_RE =
  /ALTER\s+TABLE\s+public\.messages\b[^;]*?;/gis;
const ADD_COLUMN_RE =
  /ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<name>[a-z_][a-z0-9_]*)\b/gi;
const CREATE_TABLE_RE =
  /create\s+table\s+(?:if\s+not\s+exists\s+)?public\.messages\s*\(([^;]+)\);/is;
const CREATE_COLUMN_RE =
  /^\s*(?<name>[a-z_][a-z0-9_]*)\s+(?:uuid|text|jsonb|json|integer|timestamptz|boolean|smallint|bigint)/i;

function collectMessageColumns(): Set<string> {
  const cols = new Set<string>();
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
    .sort();

  for (const f of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, f), "utf-8");

    // (a) Initial create-table — only present in 001.
    const create = sql.match(CREATE_TABLE_RE);
    if (create) {
      for (const line of create[1].split(",")) {
        const m = line.match(CREATE_COLUMN_RE);
        if (m?.groups?.name) cols.add(m.groups.name);
      }
    }

    // (b) ALTER TABLE … ADD COLUMN (possibly multi-column).
    for (const block of sql.matchAll(ALTER_BLOCK_RE)) {
      for (const add of block[0].matchAll(ADD_COLUMN_RE)) {
        if (add.groups?.name) cols.add(add.groups.name);
      }
    }
  }
  return cols;
}

describe("DSAR Art. 15(4) MESSAGE_REDACT_FIELDS migration sweep", () => {
  test("every `public.messages` column is classified as redact or allowlist", () => {
    const observed = collectMessageColumns();
    const classified = new Set<string>([
      ...MESSAGE_REDACT_FIELDS,
      ...MESSAGE_NON_REDACT_ALLOWLIST,
    ]);

    const unclassified = [...observed]
      .filter((c) => !classified.has(c))
      .sort();

    expect(
      unclassified,
      `New columns on public.messages must be classified in either ` +
        `MESSAGE_REDACT_FIELDS (foreign-author content/namespace fields) ` +
        `or MESSAGE_NON_REDACT_ALLOWLIST (structural fields safe to surface ` +
        `on a foreign-author row) in apps/web-platform/server/dsar-export.ts ` +
        `before the migration that adds them can merge. See review #4351 ` +
        `disposition + hr-write-boundary-sentinel-sweep-all-write-sites.`,
    ).toEqual([]);
  });

  test("MESSAGE_REDACT_FIELDS and MESSAGE_NON_REDACT_ALLOWLIST are disjoint", () => {
    const redact = new Set<string>(MESSAGE_REDACT_FIELDS);
    const overlap = MESSAGE_NON_REDACT_ALLOWLIST.filter((c) => redact.has(c));
    expect(overlap).toEqual([]);
  });

  test("sweep observed at least the initial-schema columns", () => {
    // Guards the parser: if the migration walker breaks (e.g., the
    // ALTER_BLOCK_RE regex stops matching), the unclassified list above
    // would be empty (false-pass). Anchoring to known column ensures
    // the walker actually ran.
    const observed = collectMessageColumns();
    expect(observed.has("content"), "001 content column observed").toBe(true);
    expect(observed.has("tool_calls"), "001 tool_calls observed").toBe(true);
    expect(
      observed.has("workspace_id"),
      "059 workspace_id observed",
    ).toBe(true);
  });
});
